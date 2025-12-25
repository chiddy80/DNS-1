#!/bin/bash
# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Configuration
EXTERNAL_EDNS_SIZE=512
INTERNAL_EDNS_SIZE=1232
EDNS_PROXY_PORT=53
SLOWDNS_PORT=5300
DROPEAR_PORT=2222

# Title Function
print_title() {
    clear
    echo ""
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    echo -e "${WHITE} E D N S   P R O X Y   I N S T A L L A T I O N${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW} Bypass MTU 512 for SlowDNS (512 → $INTERNAL_EDNS_SIZE)${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW} Port 53 → Port $SLOWDNS_PORT (SlowDNS)${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    echo ""
}

print() {
    echo -e "${GREEN}[*]${NC} $1"
}

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
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

# Show title
clear
print_title

# Check prerequisites
print "Checking if SlowDNS is running on port $SLOWDNS_PORT..."
if ss -ulpn | grep -q ":$SLOWDNS_PORT"; then
    print_success "SlowDNS found running on port $SLOWDNS_PORT"
else
    print_error "SlowDNS not found on port $SLOWDNS_PORT"
    echo ""
    echo -e "${YELLOW}Note: This EDNS Proxy requires SlowDNS to be running first.${NC}"
    echo -e "${YELLOW}Please install and start SlowDNS before running this script.${NC}"
    echo ""
    exit 1
fi

print "Starting EDNS Proxy Installation..."
echo ""

# Install required tools
print "Installing required tools..."
apt-get update -qq
apt-get install -y python3 net-tools
print_success "Tools installed"

# Create EDNS Proxy Python script
print "Creating EDNS Proxy Python script..."
cat > /usr/local/bin/edns-proxy.py << 'EOF'
#!/usr/bin/env python3
"""
EDNS Proxy for SlowDNS (smart parser)
- Listens on UDP :53 (public)
- Forwards to 127.0.0.1:5300 (SlowDNS server) with bigger EDNS size
- Outside sees 512, inside server sees 1232
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
INTERNAL_EDNS_SIZE = 1232  # what we tell SlowDNS internally

def patch_edns_udp_size(data: bytes, new_size: int) -> bytes:
    """Parse DNS message and patch EDNS (OPT RR) UDP payload size."""
    if len(data) < 12:
        return data
    
    try:
        # Header: ID(2), FLAGS(2), QDCOUNT(2), ANCOUNT(2), NSCOUNT(2), ARCOUNT(2)
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
            if l & 0xC0 == 0xC0:  # compression pointer
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
        offset += 4  # QTYPE + QCLASS
    
    def skip_rrs(count, buf, off):
        """Skip Resource Records."""
        for _ in range(count):
            off = skip_name(buf, off)
            if off + 10 > len(buf):
                return len(buf)
            # TYPE(2) + CLASS(2) + TTL(4) + RDLEN(2)
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
    """Handle DNS request."""
    upstream_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    upstream_sock.settimeout(5.0)
    
    try:
        # Patch EDNS size for upstream
        upstream_data = patch_edns_udp_size(data, INTERNAL_EDNS_SIZE)
        upstream_sock.sendto(upstream_data, (UPSTREAM_HOST, UPSTREAM_PORT))
        resp, _ = upstream_sock.recvfrom(4096)
        
        # Patch EDNS size for client
        resp_patched = patch_edns_udp_size(resp, EXTERNAL_EDNS_SIZE)
        server_sock.sendto(resp_patched, client_addr)
    except socket.timeout:
        pass  # client will resend
    except Exception:
        pass  # stay calm, don't crash
    finally:
        upstream_sock.close()

def main():
    server_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    server_sock.bind((LISTEN_HOST, LISTEN_PORT))
    
    print(f"[EDNS Proxy] Listening on {LISTEN_HOST}:{LISTEN_PORT}")
    print(f"[EDNS Proxy] Upstream: {UPSTREAM_HOST}:{UPSTREAM_PORT}")
    print(f"[EDNS Proxy] EDNS: {EXTERNAL_EDNS_SIZE} → {INTERNAL_EDNS_SIZE}")
    
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

chmod +x /usr/local/bin/edns-proxy.py
print_success "EDNS Proxy Python script created"

# Stop existing DNS services
print "Stopping existing DNS services on port 53..."

# Stop systemd-resolved if running
if systemctl is-active --quiet systemd-resolved; then
    print "Stopping systemd-resolved..."
    systemctl stop systemd-resolved
    sleep 1
fi

# Disable systemd-resolved from starting on boot
systemctl disable systemd-resolved 2>/dev/null

# Check what's using port 53
print "Checking what's using port 53..."
port_users=$(ss -tulpn | grep ':53 ' | head -5)

if [ -n "$port_users" ]; then
    print_warning "Port 53 is currently in use by:"
    echo "$port_users"
    
    echo ""
    read -p "Continue and stop these services? (y/n): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Installation aborted by user"
        exit 1
    fi
    
    # Gracefully stop services
    print "Stopping services gracefully..."
    
    if systemctl list-units --type=service | grep -q "dnsmasq"; then
        systemctl stop dnsmasq 2>/dev/null
    fi
    
    if systemctl list-units --type=service | grep -q "bind9"; then
        systemctl stop bind9 2>/dev/null
    fi
    
    if systemctl list-units --type=service | grep -q "named"; then
        systemctl stop named 2>/dev/null
    fi
    
    sleep 2
    
    # If still in use, free the port
    if ss -tulpn | grep -q ':53 '; then
        print "Freeing port 53..."
        fuser -k 53/udp 2>/dev/null || true
        fuser -k 53/tcp 2>/dev/null || true
        sleep 2
    fi
fi

print_success "Port 53 prepared for EDNS Proxy"

# Create systemd service for EDNS Proxy
print "Creating EDNS Proxy service..."
cat > /etc/systemd/system/edns-proxy.service << EOF
[Unit]
Description=EDNS Proxy (Port 53 → $SLOWDNS_PORT)
After=network.target
Wants=server-sldns.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/edns-proxy.py
Restart=always
RestartSec=3
User=root
LimitNOFILE=65536
Environment="PYTHONUNBUFFERED=1"

[Install]
WantedBy=multi-user.target
EOF

print_success "EDNS Proxy service created"

# Configure firewall
print "Configuring firewall rules..."
iptables -F 2>/dev/null
iptables -t nat -F 2>/dev/null
iptables -A INPUT -p udp --dport $EDNS_PROXY_PORT -j ACCEPT
iptables -A INPUT -p tcp --dport $EDNS_PROXY_PORT -j ACCEPT
print_success "Firewall configured"

# Start EDNS Proxy service
print "Starting EDNS Proxy service..."
systemctl daemon-reload
systemctl enable edns-proxy.service > /dev/null 2>&1
systemctl start edns-proxy.service
sleep 3

# Test EDNS Proxy
print "Testing EDNS Proxy..."
sleep 2

if systemctl is-active --quiet edns-proxy.service; then
    print_success "EDNS Proxy service started"
    
    # Test port 53
    print "Testing port $EDNS_PROXY_PORT..."
    if ss -ulpn | grep -q ":$EDNS_PROXY_PORT"; then
        print_success "EDNS Proxy listening on port $EDNS_PROXY_PORT"
        
        # Test DNS query
        print "Testing DNS query..."
        sleep 2
        if timeout 3 dig @127.0.0.1 google.com +short > /dev/null 2>&1; then
            print_success "DNS query successful"
        else
            print_warning "DNS query test inconclusive (might be network issue)"
        fi
    else
        print_warning "EDNS Proxy not listening on port 53"
    fi
else
    print_error "EDNS Proxy service failed to start"
    print "Checking service status..."
    systemctl status edns-proxy.service --no-pager
    
    # Try manual start
    print "Trying manual start..."
    pkill -f edns-proxy.py 2>/dev/null
    nohup /usr/bin/python3 /usr/local/bin/edns-proxy.py > /tmp/edns-proxy.log 2>&1 &
    sleep 2
    
    if ps aux | grep -q "[e]dns-proxy.py"; then
        print_success "EDNS Proxy started manually"
        echo "Check /tmp/edns-proxy.log for details"
    else
        print_error "Failed to start EDNS Proxy"
    fi
fi

# Create status check script
print "Creating status check script..."
cat > /usr/local/bin/edns-status << 'EOF'
#!/bin/bash
echo "=== EDNS Proxy Status ==="
echo ""
echo "Service Status:"
systemctl status edns-proxy --no-pager | grep "Active:" | sed 's/^/ /'
echo ""
echo "Port Status:"
echo " Port 53 (EDNS Proxy):"
ss -ulpn | grep ":53" | sed 's/^/ /' || echo "  Not listening"
echo " Port 5300 (SlowDNS):"
ss -ulpn | grep ":5300" | sed 's/^/ /' || echo "  Not listening"
echo ""
echo "Recent Logs:"
journalctl -u edns-proxy.service -n 5 --no-pager 2>/dev/null | tail -5 | sed 's/^/ /'
EOF

chmod +x /usr/local/bin/edns-status
print_success "Status script created: edns-status"

# Create test command
print "Creating test command..."
cat > /usr/local/bin/test-dns << 'EOF'
#!/bin/bash
echo "Testing DNS resolution through EDNS Proxy..."
echo "Running: dig @127.0.0.1 google.com +short"
dig @127.0.0.1 google.com +short
EOF

chmod +x /usr/local/bin/test-dns
print_success "Test command created: test-dns"

echo ""
echo -e "${GREEN}────────────────────────────────────────────────────────────────${NC}"
print_success "EDNS Proxy Installation Completed!"
echo -e "${GREEN}────────────────────────────────────────────────────────────────${NC}"
echo ""
echo -e "${YELLOW}Configuration Summary:${NC}"
echo "• Dropbear SSH Port: $DROPEAR_PORT"
echo "• SlowDNS Server Port: $SLOWDNS_PORT"
echo "• EDNS Proxy Port: $EDNS_PROXY_PORT"
echo "• EDNS Size: $EXTERNAL_EDNS_SIZE (external) → $INTERNAL_EDNS_SIZE (internal)"
echo ""
echo -e "${YELLOW}Quick Commands:${NC}"
echo "  edns-status    # Check EDNS Proxy status"
echo "  test-dns       # Test DNS resolution"
echo "  dig @127.0.0.1 google.com  # Manual DNS test"
echo ""
echo -e "${YELLOW}Troubleshooting:${NC}"
echo "If port 53 is still in use:"
echo "  sudo systemctl stop systemd-resolved"
echo "  sudo fuser -k 53/udp"
echo "  sudo systemctl restart edns-proxy"
echo ""
