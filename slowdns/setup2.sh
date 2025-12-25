#!/bin/bash

# Colors for errors only
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
EXTERNAL_EDNS_SIZE=512
INTERNAL_EDNS_SIZE=2048
EDNS_PROXY_PORT=53
SLOWDNS_PORT=5300

# Functions
print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Check root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Please run as root: sudo bash $0"
        exit 1
    fi
}

# Check if SlowDNS is running
check_slowdns() {
    if ss -ulpn | grep -q ":$SLOWDNS_PORT"; then
        print_success "SlowDNS found running on port $SLOWDNS_PORT"
        return 0
    else
        print_error "SlowDNS not found on port $SLOWDNS_PORT"
        print_error "This EDNS Proxy requires SlowDNS to be running first."
        print_error "Please install and start SlowDNS before running this script."
        exit 1
    fi
}

# Stop DNS services
safe_stop_dns() {
    # Stop systemd-resolved if running
    if systemctl is-active --quiet systemd-resolved; then
        systemctl stop systemd-resolved 2>/dev/null || print_error "Failed to stop systemd-resolved"
        sleep 1
    fi
    
    # Disable systemd-resolved from starting on boot
    systemctl disable systemd-resolved 2>/dev/null || true
    
    # Check what's on port 53
    local port_users=$(ss -tulpn | grep ':53 ' | head -5)
    if [ -n "$port_users" ]; then
        print_warning "Port 53 is currently in use by:"
        echo "$port_users"
        
        # Stop common DNS services
        for service in dnsmasq bind9 named; do
            if systemctl list-units --type=service | grep -q "$service"; then
                systemctl stop $service 2>/dev/null || true
            fi
        done
        
        sleep 2
        
        # If still in use, free the port
        if ss -tulpn | grep -q ':53 '; then
            fuser -k 53/udp 2>/dev/null || true
            fuser -k 53/tcp 2>/dev/null || true
            sleep 2
        fi
    fi
}

# Start main script
check_root
print_success "Starting EDNS Proxy Installation..."

# Check prerequisites
check_slowdns

# Install Python3 if not present
if ! command -v python3 &> /dev/null; then
    apt-get update > /dev/null 2>&1
    apt-get install -y python3 > /dev/null 2>&1 || print_error "Failed to install Python3"
fi

# Create EDNS Proxy Python script
cat > /usr/local/bin/edns-proxy.py << 'EOF'
#!/usr/bin/env python3
"""
EDNS Proxy for SlowDNS
- Listens on UDP :53 (public)
- Forwards to 127.0.0.1:5300 (SlowDNS server) with bigger EDNS size
- Outside sees 512, inside server sees 2048
"""
import socket
import threading
import struct

# Public listen
LISTEN_HOST = "0.0.0.0"
LISTEN_PORT = 53

# Internal SlowDNS server address
UPSTREAM_HOST = "127.0.0.1"
UPSTREAM_PORT = 5300

# EDNS sizes
EXTERNAL_EDNS_SIZE = 512   # what we show to clients
INTERNAL_EDNS_SIZE = 2048  # what we tell SlowDNS internally

def patch_edns_udp_size(data: bytes, new_size: int) -> bytes:
    """Parse DNS message and patch EDNS (OPT RR) UDP payload size."""
    if len(data) < 12:
        return data
    
    try:
        qdcount, ancount, nscount, arcount = struct.unpack("!HHHH", data[4:12])
    except struct.error:
        return data
    
    offset = 12
    
    def skip_name(buf, off):
        """Skip DNS name (supporting compression)."""
        while True:
            if off >= len(buf):
                return len(buf)
            l = buf[off]
            off += 1
            if l == 0:
                break
            if l & 0xC0 == 0xC0:
                if off >= len(buf):
                    return len(buf)
                off += 1
                break
            off += l
        return off
    
    # Skip Questions
    for _ in range(qdcount):
        offset = skip_name(data, offset)
        if offset + 4 > len(data):
            return data
        offset += 4
    
    def skip_rrs(count, buf, off):
        """Skip Resource Records."""
        for _ in range(count):
            off = skip_name(buf, off)
            if off + 10 > len(buf):
                return len(buf)
            rtype, rclass, ttl, rdlen = struct.unpack("!HHIH", buf[off:off+10])
            off += 10
            if off + rdlen > len(buf):
                return len(buf)
            off += rdlen
        return off
    
    # Skip Answer + Authority
    offset = skip_rrs(ancount, data, offset)
    offset = skip_rrs(nscount, data, offset)
    
    # Additional section → EDNS OPT RR is here
    new_data = bytearray(data)
    for _ in range(arcount):
        rr_name_start = offset
        offset = skip_name(data, offset)
        if offset + 10 > len(data):
            return data
        rtype = struct.unpack("!H", data[offset:offset+2])[0]
        if rtype == 41:  # OPT RR (EDNS)
            # UDP payload size is 2 bytes after TYPE
            size_bytes = struct.pack("!H", new_size)
            new_data[offset+2:offset+4] = size_bytes
            return bytes(new_data)
        # Skip CLASS(2) + TTL(4) + RDLEN(2) + RDATA
        _, _, rdlen = struct.unpack("!H I H", data[offset+2:offset+10])
        offset += 10 + rdlen
    
    return data

def handle_request(server_sock: socket.socket, data: bytes, client_addr):
    """Handle DNS request and response."""
    upstream_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    upstream_sock.settimeout(5.0)
    
    try:
        upstream_data = patch_edns_udp_size(data, INTERNAL_EDNS_SIZE)
        upstream_sock.sendto(upstream_data, (UPSTREAM_HOST, UPSTREAM_PORT))
        resp, _ = upstream_sock.recvfrom(4096)
        resp_patched = patch_edns_udp_size(resp, EXTERNAL_EDNS_SIZE)
        server_sock.sendto(resp_patched, client_addr)
    except socket.timeout:
        pass
    except Exception as e:
        print(f"Error: {e}")
    finally:
        upstream_sock.close()

def main():
    server_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    server_sock.bind((LISTEN_HOST, LISTEN_PORT))
    
    print(f"[EDNS Proxy] Listening on {LISTEN_HOST}:{LISTEN_PORT}, "
          f"upstream {UPSTREAM_HOST}:{UPSTREAM_PORT}, "
          f"external EDNS={EXTERNAL_EDNS_SIZE}, internal EDNS={INTERNAL_EDNS_SIZE}")
    
    while True:
        data, client_addr = server_sock.recvfrom(4096)
        t = threading.Thread(
            target=handle_request,
            args=(server_sock, data, client_addr),
            daemon=True,
        )
        t.start()

if __name__ == "__main__":
    main()
EOF

chmod +x /usr/local/bin/edns-proxy.py || print_error "Failed to set permissions on edns-proxy.py"

# Create systemd service for EDNS Proxy
cat > /etc/systemd/system/edns-proxy.service << EOF
[Unit]
Description=EDNS Proxy (Port 53, 512↔2048)
After=network.target
Wants=slowdns-server.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/edns-proxy.py
Restart=always
RestartSec=3
User=root
LimitNOFILE=65536
Environment="PYTHONUNBUFFERED=1"
StandardOutput=append:/var/log/edns-proxy.log
StandardError=append:/var/log/edns-proxy.error

[Install]
WantedBy=multi-user.target
EOF

# Stop DNS services
safe_stop_dns

# Update firewall
iptables -F 2>/dev/null || print_error "Failed to flush iptables"
iptables -t nat -F 2>/dev/null || print_error "Failed to flush nat table"
iptables -A INPUT -p udp --dport $EDNS_PROXY_PORT -j ACCEPT || print_error "Failed to add UDP rule"
iptables -A INPUT -p tcp --dport $EDNS_PROXY_PORT -j ACCEPT || print_error "Failed to add TCP rule"
iptables -t nat -A PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 53 || print_error "Failed to add PREROUTING rule"
iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports 53 || print_error "Failed to add OUTPUT rule"

# Start EDNS Proxy service
systemctl daemon-reload || print_error "Failed to reload systemd daemon"
systemctl enable edns-proxy.service > /dev/null 2>&1 || print_error "Failed to enable edns-proxy service"
systemctl start edns-proxy.service || print_error "Failed to start edns-proxy service"

sleep 3

# Test EDNS Proxy
if ss -ulpn | grep -q ":$EDNS_PROXY_PORT"; then
    print_success "EDNS Proxy listening on port $EDNS_PROXY_PORT"
    
    # Test DNS query
    if timeout 3 dig @127.0.0.1 google.com +short > /dev/null 2>&1; then
        print_success "DNS query successful"
    else
        print_warning "DNS query test failed"
    fi
else
    print_error "EDNS Proxy not listening on port 53"
    
    # Try to start manually
    nohup /usr/bin/python3 /usr/local/bin/edns-proxy.py > /tmp/edns-debug.log 2>&1 &
    sleep 3
    
    if ss -ulpn | grep -q ":$EDNS_PROXY_PORT"; then
        print_success "EDNS Proxy started manually"
    else
        print_error "Failed to start EDNS Proxy"
    fi
fi

# Create status script
cat > /usr/local/bin/edns-status << 'EOF'
#!/bin/bash
echo "=== EDNS Proxy Status ==="
echo ""
echo "Service Status:"
systemctl status edns-proxy --no-pager | grep "Active:" | sed 's/^/ /'
echo ""
echo "Port Status:"
echo " Port 53 (EDNS Proxy):"
ss -ulpn | grep ":53" | sed 's/^/ /'
echo " Port 5300 (SlowDNS):"
ss -ulpn | grep ":5300" | sed 's/^/ /'
EOF

chmod +x /usr/local/bin/edns-status || print_error "Failed to create status script"

# Create test command
cat > /usr/local/bin/test-edns << 'EOF'
#!/bin/bash
echo "Testing EDNS Proxy..."
echo "Running: dig @127.0.0.1 google.com"
dig @127.0.0.1 google.com +short
EOF

chmod +x /usr/local/bin/test-edns || print_error "Failed to create test command"

print_success "EDNS Proxy Installation Completed!"
echo ""
print_warning "Quick Test Commands:"
echo " edns-status # Check EDNS Proxy status"
echo " test-edns   # Test DNS resolution"
echo " dig @127.0.0.1 google.com # Manual DNS test"
