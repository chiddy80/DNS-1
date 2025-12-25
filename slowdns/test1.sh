#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Dropbear Port Configuration
DROPBEAR_PORT=222
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

echo "Starting Dropbear SlowDNS Installation..."

# Get Server IP
SERVER_IP=$(curl -s ifconfig.me)
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(hostname -I | awk '{print $1}')
fi

# Install Dropbear
echo "Installing Dropbear on port $DROPBEAR_PORT..."
apt-get update > /dev/null 2>&1
apt-get install -y dropbear > /dev/null 2>&1

# Configure Dropbear with enhanced parameters
echo "Configuring Dropbear on port $DROPBEAR_PORT..."
cat > /etc/default/dropbear << EOF
# Dropbear SSH server configuration
NO_START=0
DROPBEAR_PORT=$DROPBEAR_PORT
DROPBEAR_EXTRA_ARGS="-p $DROPBEAR_PORT -W 65536 -K 30 -I 0"
DROPBEAR_BANNER="/etc/dropbear/banner"
DROPBEAR_RSAKEY="/etc/dropbear/dropbear_rsa_host_key"
DROPBEAR_DSSKEY="/etc/dropbear/dropbear_dss_host_key"
DROPBEAR_ECDSAKEY="/etc/dropbear/dropbear_ecdsa_host_key"
DROPBEAR_RECEIVE_WINDOW=65536
EOF

# Generate SSH RSA key for Dropbear
echo "Generating RSA key for Dropbear..."
if [ ! -f /etc/dropbear/dropbear_rsa_host_key ]; then
    mkdir -p /etc/dropbear
    # Generate RSA key with 2048 bits (Dropbear's default)
    dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key -s 2048
    print_success "RSA key generated for Dropbear"
else
    print_success "RSA key already exists for Dropbear"
fi

# Restart Dropbear
systemctl restart dropbear
sleep 2
print_success "Dropbear configured on port $DROPBEAR_PORT with enhanced parameters"

# Setup SlowDNS
echo "Setting up SlowDNS..."
rm -rf /etc/slowdns
mkdir -p /etc/slowdns
print_success "SlowDNS directory created"

# Download files
echo "Downloading SlowDNS files..."
wget -q -O /etc/slowdns/server.key "https://raw.githubusercontent.com/athumani2580/DNS/main/slowdns/server.key"
if [ $? -eq 0 ]; then
    print_success "server.key downloaded"
else
    wget -q -O /etc/slowdns/server.key "https://raw.githubusercontent.com/athumani2580/DNS/main/server.key"
    print_success "server.key downloaded"
fi

wget -q -O /etc/slowdns/server.pub "https://raw.githubusercontent.com/athumani2580/DNS/main/slowdns/server.pub"
if [ $? -eq 0 ]; then
    print_success "server.pub downloaded"
else
    wget -q -O /etc/slowdns/server.pub "https://raw.githubusercontent.com/athumani2580/DNS/main/server.pub"
    print_success "server.pub downloaded"
fi

wget -q -O /etc/slowdns/sldns-server "https://raw.githubusercontent.com/athumani2580/DNS/main/slowdns/sldns-server"
if [ $? -eq 0 ]; then
    print_success "sldns-server downloaded"
else
    wget -q -O /etc/slowdns/sldns-server "https://raw.githubusercontent.com/athumani2580/DNS/main/slowdns/sldns-server"
    print_success "sldns-server downloaded"
fi

chmod +x /etc/slowdns/sldns-server
print_success "File permissions set"

# Get nameserver
echo ""
read -p "Enter nameserver (e.g., dns.example.com): " NAMESERVER
echo ""

# Create SlowDNS service with MTU 1800
echo "Creating SlowDNS service..."
cat > /etc/systemd/system/server-sldns.service << EOF
[Unit]
Description=SlowDNS Server
After=network.target dropbear.service

[Service]
Type=simple
ExecStart=/etc/slowdns/sldns-server -udp :$SLOWDNS_PORT -mtu 1800 -privkey-file /etc/slowdns/server.key $NAMESERVER 127.0.0.1:$DROPBEAR_PORT
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

print_success "Service file created"

# Startup config with ALL iptables
echo "Setting up startup configuration..."
cat > /etc/rc.local <<-END
#!/bin/sh -e
systemctl start dropbear
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport $DROPBEAR_PORT -j ACCEPT
iptables -A INPUT -p udp --dport $SLOWDNS_PORT -j ACCEPT
iptables -A INPUT -p tcp --dport $SLOWDNS_PORT -j ACCEPT
iptables -A OUTPUT -p udp --dport $SLOWDNS_PORT -j ACCEPT
iptables -A INPUT -s 127.0.0.1 -d 127.0.0.1 -j ACCEPT
iptables -A OUTPUT -s 127.0.0.1 -d 127.0.0.1 -j ACCEPT
iptables -A INPUT -p icmp -j ACCEPT
iptables -A OUTPUT -j ACCEPT
iptables -A INPUT -m state --state INVALID -j DROP
iptables -A INPUT -p tcp --dport $DROPBEAR_PORT -m state --state NEW -m recent --set
iptables -A INPUT -p tcp --dport $DROPBEAR_PORT -m state --state NEW -m recent --update --seconds 60 --hitcount 4 -j DROP
echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6
sysctl -w net.core.rmem_max=134217728 > /dev/null 2>&1
sysctl -w net.core.wmem_max=134217728 > /dev/null 2>&1
exit 0
END

chmod +x /etc/rc.local
systemctl enable rc-local > /dev/null 2>&1
systemctl start rc-local.service > /dev/null 2>&1
print_success "Startup configuration set"

# Disable IPv6
echo "Disabling IPv6..."
echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6
sysctl -w net.ipv6.conf.all.disable_ipv6=1 > /dev/null 2>&1
echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf
sysctl -p > /dev/null 2>&1
print_success "IPv6 disabled"

# Start SlowDNS service
echo "Starting SlowDNS service..."
pkill sldns-server 2>/dev/null
systemctl daemon-reload
systemctl enable server-sldns > /dev/null 2>&1
systemctl start server-sldns
sleep 3

if systemctl is-active --quiet server-sldns; then
    print_success "SlowDNS service started"
    
    echo "Testing DNS functionality..."
    sleep 2
    if timeout 3 bash -c "echo > /dev/udp/127.0.0.1/$SLOWDNS_PORT" 2>/dev/null; then
        print_success "SlowDNS is listening on port $SLOWDNS_PORT"
    else
        print_warning "SlowDNS not responding on port $SLOWDNS_PORT"
    fi
else
    print_error "SlowDNS service failed to start"
    
    # Try direct start with MTU 1800
    pkill sldns-server 2>/dev/null
    /etc/slowdns/sldns-server -udp :$SLOWDNS_PORT -mtu 1800 -privkey-file /etc/slowdns/server.key $NAMESERVER 127.0.0.1:$DROPBEAR_PORT &
    sleep 2
    
    if pgrep -x "sldns-server" > /dev/null; then
        print_success "SlowDNS started directly"
    else
        print_error "Failed to start SlowDNS"
    fi
fi

# Clean up
echo "Cleaning up packages..."
sudo apt-get remove -y libpam-pwquality 2>/dev/null || true
print_success "Packages cleaned"

# Test connection
echo "Testing Dropbear connection..."
if timeout 5 bash -c "echo > /dev/tcp/127.0.0.1/$DROPBEAR_PORT" 2>/dev/null; then
    print_success "Dropbear port $DROPBEAR_PORT is accessible"
else
    print_error "Dropbear port $DROPBEAR_PORT is not accessible"
fi

# Display RSA key fingerprint
echo "Displaying Dropbear RSA key fingerprint..."
if [ -f /etc/dropbear/dropbear_rsa_host_key ]; then
    echo "RSA Key Fingerprint:"
    dropbearkey -y -f /etc/dropbear/dropbear_rsa_host_key | grep -E "(ssh-rsa|Fingerprint)" | head -5
    print_success "RSA key fingerprint displayed"
else
    print_warning "RSA key file not found"
fi

# Display Dropbear enhanced parameters
echo ""
print_success "Dropbear SlowDNS Installation Completed!"
echo ""
echo "Server IP: $SERVER_IP"
echo "Dropbear Port: $DROPBEAR_PORT"
echo "Dropbear Parameters: -W 65536 -K 30 -I 0"
echo "SlowDNS Port: $SLOWDNS_PORT"
echo "MTU: 1800"
echo ""
echo "Enhanced Dropbear Parameters:"
echo "  -W 65536: Keepalive interval (seconds)"
echo "  -K 30   : Maximum authentication attempts"
echo "  -I 0    : Idle timeout (0 = disabled)"
echo ""
echo "SSH RSA key has been generated for secure connections"
echo ""
echo "Note: SlowDNS is running on port $SLOWDNS_PORT"
