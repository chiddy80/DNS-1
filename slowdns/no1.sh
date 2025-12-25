#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Port Configuration
SSHD_PORT=22 # OpenSSH on standard port 22
SLOWDNS_PORT=5300 # SlowDNS runs on port 5300
DNS_PORT=53 # Standard DNS port

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

# Show port information
echo "=== PORT CONFIGURATION ==="
echo ""
echo -e "${GREEN}Port 22${NC} : SSH Server"
echo -e "${GREEN}Port 53${NC} : DNS Server (Standard DNS port)"
echo -e "${GREEN}Port 5300${NC} : SlowDNS Server"
echo ""
echo "=========================="
echo ""

print_success "Starting OpenSSH SlowDNS Installation..."

# Get Server IP
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}' || echo "Unknown")

# Disable UFW
print_success "Disabling UFW..."
sudo ufw disable 2>/dev/null || true
if systemctl is-active --quiet ufw 2>/dev/null; then
    sudo systemctl stop ufw 2>/dev/null || true
fi
systemctl disable ufw 2>/dev/null || true

# Configure OpenSSH
print_success "Configuring OpenSSH on port $SSHD_PORT..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup 2>/dev/null || true

iptables -A INPUT -p icmp -j ACCEPT
iptables -A OUTPUT -j ACCEPT
iptables -A INPUT -m state --state INVALID -j DROP
iptables -A INPUT -p tcp --dport $SSHD_PORT -m state --state NEW -m recent --set
iptables -A INPUT -p tcp --dport $SSHD_PORT -m state --state NEW -m recent --update --seconds 60 --hitcount 4 -j DROP

echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6
sysctl -w net.core.rmem_max=134217728 > /dev/null 2>&1
sysctl -w net.core.wmem_max=134217728 > /dev/null 2>&1

exit 0
END

chmod +x /etc/rc.local
systemctl enable rc-local > /dev/null 2>&1 || true
systemctl start rc-local.service > /dev/null 2>&1 || true

# Disable IPv6
print_success "Disabling IPv6..."
echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || true
sysctl -w net.ipv6.conf.all.disable_ipv6=1 > /dev/null 2>&1 || true
echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf 2>/dev/null || true
echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf 2>/dev/null || true
sysctl -p > /dev/null 2>&1 || true

# Start SlowDNS service
print_success "Starting SlowDNS service..."
pkill sldns-server 2>/dev/null || true
systemctl daemon-reload
systemctl enable server-sldns > /dev/null 2>&1 || true
systemctl start server-sldns 2>/dev/null || true
sleep 3

if systemctl is-active --quiet server-sldns 2>/dev/null; then
    print_success "SlowDNS service started"
    
    # Test DNS functionality
    print_success "Testing SlowDNS on port $SLOWDNS_PORT..."
    sleep 2
    if timeout 3 bash -c "echo > /dev/udp/127.0.0.1/$SLOWDNS_PORT" 2>/dev/null; then
        print_success "SlowDNS is listening on port $SLOWDNS_PORT"
    else
        print_warning "SlowDNS not responding on port $SLOWDNS_PORT"
    fi
else
    print_error "SlowDNS service failed to start"
    
    # Try direct start as fallback with MTU 1800
    pkill sldns-server 2>/dev/null || true
    /etc/slowdns/sldns-server -udp :$SLOWDNS_PORT -mtu 1800 -privkey-file /etc/slowdns/server.key $NAMESERVER 127.0.0.1:$SSHD_PORT &
    sleep 2
    
    if pgrep -x "sldns-server" > /dev/null; then
        print_success "SlowDNS started directly"
    else
        print_error "Failed to start SlowDNS"
    fi
fi

# Clean up
print_success "Cleaning up packages..."
sudo apt-get remove -y libpam-pwquality 2>/dev/null || true

# Test connections
echo ""
echo -e "${GREEN}=== PORT TESTING ===${NC}"

# Test SSH port 22
print_success "Testing SSH connection on port $SSHD_PORT..."
if timeout 5 bash -c "echo > /dev/tcp/127.0.0.1/$SSHD_PORT" 2>/dev/null; then
    print_success "SSH port $SSHD_PORT is accessible"
else
    print_error "SSH port $SSHD_PORT is not accessible"
fi

# Test SlowDNS port 5300
print_success "Testing SlowDNS on port $SLOWDNS_PORT..."
if timeout 3 bash -c "echo > /dev/udp/127.0.0.1/$SLOWDNS_PORT" 2>/dev/null; then
    print_success "SlowDNS port $SLOWDNS_PORT is accessible"
else
    print_warning "SlowDNS port $SLOWDNS_PORT may not be responding"
fi

# Check port 53 status
print_success "Checking DNS port $DNS_PORT..."
if ss -tulpn | grep -q ":$DNS_PORT"; then
    print_warning "Port $DNS_PORT is in use by another service"
    echo "Current services on port 53:"
    ss -tulpn | grep ":53" | sed 's/^/ /'
else
    print_success "Port $DNS_PORT is available for EDNS Proxy"
fi

# Show final status
echo ""
echo -e "${GREEN}=== INSTALLATION COMPLETED ===${NC}"
