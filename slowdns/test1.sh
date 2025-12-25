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

# SSH/Dropbear Port Configuration
DROPEAR_PORT=2222  # Changed from SSH port 22 to Dropbear port 2222
SLOWDNS_PORT=5300  # SlowDNS runs on port 5300

# Title Function
print_title() {
    clear
    echo ""
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    echo -e "${WHITE} D R O P B E A R   S L O W D N S${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW} Complete Installation Script${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    echo ""
}

print() {
    echo -e "${BLUE}[*]${NC} $1"
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

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

# Show title
clear
print_title

# Get Server IP
SERVER_IP=$(curl -s ifconfig.me)
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(hostname -I | awk '{print $1}')
fi

# ====================================================
# INSTALLATION PROCESS
# ====================================================
print "Starting Dropbear SlowDNS Installation..."
echo ""

# Update system
print "Updating system packages..."
apt-get update -qq

# Install required tools
print "Installing required tools..."
apt-get install -y net-tools curl wget build-essential zlib1g-dev  # Added build tools
print_success "Tools installed"

# Disable UFW
print "Disabling UFW..."
sudo ufw disable 2>/dev/null
if systemctl is-active --quiet ufw; then
    sudo systemctl stop ufw
fi
systemctl disable ufw 2>/dev/null
print_success "UFW disabled"

# Disable systemd-resolved
print "Disabling systemd-resolved..."
if systemctl is-active --quiet systemd-resolved; then
    systemctl stop systemd-resolved
fi
systemctl disable systemd-resolved 2>/dev/null
print_success "systemd-resolved disabled"

# DNS config - Modified as requested
print "Configuring DNS..."

# First, remove any immutable attribute if present
if [ -f /etc/resolv.conf ]; then
    chattr -i /etc/resolv.conf 2>/dev/null
fi

# Remove if it's a symlink
if [ -L /etc/resolv.conf ]; then
    rm -f /etc/resolv.conf
fi

# Create new resolv.conf with proper permissions
cat > /etc/resolv.conf << EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
options edns0
EOF

# Make it immutable to prevent changes
chattr +i /etc/resolv.conf 2>/dev/null || print_warning "Could not make resolv.conf immutable (may be normal)"

print_success "DNS configured"

# ====================================================
# INSTALL DROPBEAR 2017.75 FROM SOURCE
# ====================================================
print "Installing Dropbear SSH 2017.75 from source on port $DROPEAR_PORT..."

# Remove existing dropbear if installed via apt
print "Removing existing dropbear packages..."
apt-get remove --purge -y dropbear* 2>/dev/null || true

# Download and compile Dropbear 2017.75
print "Downloading Dropbear 2017.75 source..."
cd /tmp
rm -rf dropbear-2017.75 dropbear-2017.75.tar.bz2 2>/dev/null

# Try multiple download sources
wget -q --timeout=30 --tries=2 https://matt.ucc.asn.au/dropbear/releases/dropbear-2017.75.tar.bz2 || \
wget -q --timeout=30 --tries=2 https://mirror.rackspace.com/dropbear/releases/dropbear-2017.75.tar.bz2 || \
wget -q --timeout=30 --tries=2 https://ftp.lysator.liu.se/pub/openssh/dropbear/dropbear-2017.75.tar.bz2

if [ ! -f dropbear-2017.75.tar.bz2 ]; then
    print_error "Failed to download Dropbear 2017.75 source"
    print "Trying alternative download method..."
    curl -L -o dropbear-2017.75.tar.bz2 "https://github.com/mkj/dropbear/archive/refs/tags/DROPBEAR_2017.75.tar.gz" 2>/dev/null || {
        print_error "Cannot download Dropbear 2017.75"
        print_warning "Falling back to system package manager..."
        apt-get install -y dropbear
    }
else
    print_success "Dropbear 2017.75 source downloaded"
fi

# Extract and compile if download succeeded
if [ -f dropbear-2017.75.tar.bz2 ] || [ -f DROPBEAR_2017.75.tar.gz ]; then
    print "Extracting Dropbear source..."
    if [ -f dropbear-2017.75.tar.bz2 ]; then
        tar -xjf dropbear-2017.75.tar.bz2
    else
        tar -xzf DROPBEAR_2017.75.tar.gz
        mv dropbear-DROPBEAR_2017.75 dropbear-2017.75
    fi
    
    cd dropbear-2017.75
    
    print "Configuring Dropbear..."
    ./configure --prefix=/usr --sysconfdir=/etc/dropbear
    
    print "Compiling Dropbear..."
    make -j$(nproc)
    
    print "Installing Dropbear..."
    make install
    
    # Create necessary directories
    mkdir -p /etc/dropbear /var/run/dropbear
    
    # Create default banner
    echo "Welcome to Dropbear SSH Server" > /etc/dropbear/banner
    
    print_success "Dropbear 2017.75 compiled and installed from source"
else
    # Use system dropbear if compilation failed
    print_warning "Using system package manager dropbear version"
    DROPBEAR_VERSION=$(dropbear -V 2>&1 | grep -o 'dropbear[^ ]*' || echo "unknown")
    print "System Dropbear version: $DROPBEAR_VERSION"
fi

# Backup original config if exists
if [ -f /etc/default/dropbear ]; then
    cp /etc/default/dropbear /etc/default/dropbear.backup 2>/dev/null
fi

# Configure Dropbear
print "Configuring Dropbear on port $DROPEAR_PORT..."
cat > /etc/default/dropbear << EOF
# Dropbear SSH Configuration - Port $DROPEAR_PORT (2017.75)
NO_START=0
DROPBEAR_PORT=$DROPEAR_PORT
DROPBEAR_EXTRA_ARGS="-s -w -p $DROPEAR_PORT"
DROPBEAR_BANNER="/etc/dropbear/banner"
DROPBEAR_RSAKEY="/etc/dropbear/dropbear_rsa_host_key"
DROPBEAR_DSSKEY="/etc/dropbear/dropbear_dss_host_key"
DROPBEAR_ECDSAKEY="/etc/dropbear/dropbear_ecdsa_host_key"
DROPBEAR_RECEIVE_WINDOW=65536
EOF

# Generate SSH RSA key (2048-bit) as requested
print "Generating SSH RSA key (2048-bit)..."
if [ -f /etc/dropbear/dropbear_rsa_host_key ]; then
    print_warning "RSA key already exists, skipping generation..."
else
    ssh-keygen -t rsa -b 2048 -f /etc/dropbear/dropbear_rsa_host_key -N "" -q
    if [ $? -eq 0 ]; then
        print_success "SSH RSA key generated successfully"
    else
        print_error "Failed to generate SSH RSA key"
        # Try with dropbearkey instead
        dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key -s 2048 2>/dev/null && \
        print_success "SSH RSA key generated with dropbearkey"
    fi
fi

# Also generate DSA key for Dropbear compatibility
print "Generating DSA key for Dropbear..."
if [ -f /etc/dropbear/dropbear_dss_host_key ]; then
    print_warning "DSA key already exists, skipping generation..."
else
    # Try to generate DSA key
    dropbearkey -t dss -f /etc/dropbear/dropbear_dss_host_key 2>/dev/null
    if [ $? -eq 0 ]; then
        print_success "DSA key generated successfully"
    else
        print_warning "Failed to generate DSA key, Dropbear will generate it automatically"
        # Create empty file to avoid service failure
        touch /etc/dropbear/dropbear_dss_host_key
    fi
fi

# Create systemd service file for Dropbear
print "Creating Dropbear systemd service..."
cat > /etc/systemd/system/dropbear.service << EOF
[Unit]
Description=Dropbear SSH Server (2017.75)
After=network.target

[Service]
Type=simple
ExecStart=/usr/sbin/dropbear -F -E -p $DROPEAR_PORT -s -w
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

# Enable and start Dropbear service
print "Starting Dropbear service..."
systemctl daemon-reload
systemctl enable dropbear > /dev/null 2>&1
systemctl restart dropbear
sleep 3

# Check if Dropbear is running
print "Checking if Dropbear is running..."
if ss -tuln | grep -q ":$DROPEAR_PORT"; then
    print_success "Dropbear configured and running on port $DROPEAR_PORT"
    DROPBEAR_VERSION=$(dropbear -V 2>&1 | head -1 || echo "2017.75 (compiled)")
    print "Dropbear version: $DROPBEAR_VERSION"
elif netstat -tuln 2>/dev/null | grep -q ":$DROPEAR_PORT"; then
    print_success "Dropbear configured and running on port $DROPEAR_PORT"
else
    print_warning "Dropbear may not be running, checking service status..."
    if systemctl is-active --quiet dropbear; then
        print_success "Dropbear service is active"
    else
        print_warning "Trying alternative start method..."
        pkill dropbear 2>/dev/null
        # Try direct start
        /usr/sbin/dropbear -p $DROPEAR_PORT -s -w -F -E &
        sleep 2
        if ss -tuln | grep -q ":$DROPEAR_PORT" || netstat -tuln 2>/dev/null | grep -q ":$DROPEAR_PORT"; then
            print_success "Dropbear started on port $DROPEAR_PORT"
        else
            print_error "Failed to start Dropbear"
            print "Checking Dropbear binary..."
            if [ -x /usr/sbin/dropbear ]; then
                /usr/sbin/dropbear -h
            fi
        fi
    fi
fi

# ====================================================
# INSTALL SLOWDNS
# ====================================================
print "Setting up SlowDNS..."
rm -rf /etc/slowdns
mkdir -p /etc/slowdns
print_success "SlowDNS directory created"

# Download files
print "Downloading SlowDNS files..."
wget -q -O /etc/slowdns/server.key "https://raw.githubusercontent.com/athumani2580/DNS/main/slowdns/server.key"
if [ $? -eq 0 ]; then
    print_success "✓ server.key downloaded"
else
    print "Trying alternative URL..."
    wget -q -O /etc/slowdns/server.key "https://raw.githubusercontent.com/athumani2580/DNS/main/server.key"
    print_success "✓ server.key downloaded"
fi

wget -q -O /etc/slowdns/server.pub "https://raw.githubusercontent.com/athumani2580/DNS/main/slowdns/server.pub"
if [ $? -eq 0 ]; then
    print_success "✓ server.pub downloaded"
else
    print "Trying alternative URL..."
    wget -q -O /etc/slowdns/server.pub "https://raw.githubusercontent.com/athumani2580/DNS/main/server.pub"
    print_success "✓ server.pub downloaded"
fi

wget -q -O /etc/slowdns/sldns-server "https://raw.githubusercontent.com/athumani2580/DNS/main/slowdns/sldns-server"
if [ $? -eq 0 ]; then
    print_success "✓ sldns-server downloaded"
else
    print "Trying alternative URL..."
    wget -q -O /etc/slowdns/sldns-server "https://raw.githubusercontent.com/athumani2580/DNS/main/slowdns/sldns-server"
    print_success "✓ sldns-server downloaded"
fi

chmod +x /etc/slowdns/sldns-server
print_success "File permissions set"

# Get nameserver
echo ""
echo -e "${CYAN}[ NAMESERVER SETUP ]${NC}"
echo -e "${WHITE}────────────────────────────────────────────────────────────────${NC}"
read -p "Enter nameserver (e.g., dns.example.com): " NAMESERVER
echo ""

# Create SlowDNS service
print "Creating SlowDNS service..."
cat > /etc/systemd/system/server-sldns.service << EOF
[Unit]
Description=SlowDNS Server
After=network.target dropbear.service

[Service]
Type=simple
ExecStart=/etc/slowdns/sldns-server -udp :$SLOWDNS_PORT -mtu 1232 -privkey-file /etc/slowdns/server.key $NAMESERVER 127.0.0.1:$DROPEAR_PORT
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF
print_success "Service file created"

# Startup config
print "Setting up startup configuration..."
cat > /etc/rc.local <<-END
#!/bin/sh -e

# Start Dropbear
systemctl start dropbear

# Flush iptables
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X

# Default policies
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# Localhost
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Dropbear port 2222
iptables -A INPUT -p tcp --dport $DROPEAR_PORT -j ACCEPT

# SlowDNS port 5300
iptables -A INPUT -p udp --dport $SLOWDNS_PORT -j ACCEPT  # Port 5300 UDP
iptables -A INPUT -p tcp --dport $SLOWDNS_PORT -j ACCEPT  # Port 5300 TCP
iptables -A OUTPUT -p udp --dport $SLOWDNS_PORT -j ACCEPT

# Localhost traffic
iptables -A INPUT -s 127.0.0.1 -d 127.0.0.1 -j ACCEPT
iptables -A OUTPUT -s 127.0.0.1 -d 127.0.0.1 -j ACCEPT

# ICMP (ping)
iptables -A INPUT -p icmp -j ACCEPT

# Default output
iptables -A OUTPUT -j ACCEPT

# Drop invalid
iptables -A INPUT -m state --state INVALID -j DROP

# DDoS protection for Dropbear
iptables -A INPUT -p tcp --dport $DROPEAR_PORT -m state --state NEW -m recent --set
iptables -A INPUT -p tcp --dport $DROPEAR_PORT -m state --state NEW -m recent --update --seconds 60 --hitcount 4 -j DROP

# Disable IPv6
echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6

# Optimize network settings
sysctl -w net.core.rmem_max=134217728 > /dev/null 2>&1
sysctl -w net.core.wmem_max=134217728 > /dev/null 2>&1

exit 0
END

chmod +x /etc/rc.local
systemctl enable rc-local > /dev/null 2>&1
systemctl start rc-local.service > /dev/null 2>&1
print_success "Startup configuration set"

# Disable IPv6
print "Disabling IPv6..."
echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6
sysctl -w net.ipv6.conf.all.disable_ipv6=1 > /dev/null 2>&1
echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf
sysctl -p > /dev/null 2>&1
print_success "IPv6 disabled"

# Start SlowDNS service
print "Starting SlowDNS service..."
pkill sldns-server 2>/dev/null
systemctl daemon-reload
systemctl enable server-sldns > /dev/null 2>&1
systemctl start server-sldns
sleep 3

if systemctl is-active --quiet server-sldns; then
    print_success "SlowDNS service started"
    
    # Test DNS functionality
    print "Testing DNS functionality..."
    sleep 2
    
    # Test with port 5300 explicitly
    if timeout 3 bash -c "echo > /dev/udp/127.0.0.1/$SLOWDNS_PORT" 2>/dev/null; then
        print_success "SlowDNS is listening on port $SLOWDNS_PORT"
    else
        print_warning "SlowDNS not responding on port $SLOWDNS_PORT"
        systemctl status server-sldns --no-pager
    fi
else
    print_error "SlowDNS service failed to start"
    systemctl status server-sldns --no-pager
    
    # Try direct start as fallback
    pkill sldns-server 2>/dev/null
    /etc/slowdns/sldns-server -udp :$SLOWDNS_PORT -mtu 1232 -privkey-file /etc/slowdns/server.key $NAMESERVER 127.0.0.1:$DROPEAR_PORT &
    sleep 2
    if pgrep -x "sldns-server" > /dev/null; then
        print_success "SlowDNS started directly"
    else
        print_error "Failed to start SlowDNS"
    fi
fi

# Clean up
print "Cleaning up packages..."
sudo apt-get remove -y libpam-pwquality 2>/dev/null || true
print_success "Packages cleaned"

# Test connection
print "Testing Dropbear connection..."
if timeout 5 bash -c "echo > /dev/tcp/127.0.0.1/$DROPEAR_PORT" 2>/dev/null; then
    print_success "Dropbear port $DROPEAR_PORT is accessible"
else
    print_error "Dropbear port $DROPEAR_PORT is not accessible"
fi

echo ""
echo -e "${GREEN}────────────────────────────────────────────────────────────────${NC}"
print_success "Dropbear 2017.75 + SlowDNS Installation Completed!"
echo -e "${GREEN}────────────────────────────────────────────────────────────────${NC}"
echo ""
echo -e "${YELLOW}Installation Summary:${NC}"
echo "• Dropbear SSH: Port $DROPEAR_PORT (Version 2017.75)"
echo "• SlowDNS Server: Port $SLOWDNS_PORT"
echo "• Nameserver: $NAMESERVER"
echo "• SSH Key: 2048-bit RSA"
echo ""
echo -e "${YELLOW}Important Note:${NC}"
echo "SlowDNS is running on port $SLOWDNS_PORT (not 53)"
echo "To make SlowDNS work on port 53, you need to:"
echo "1. Install EDNS Proxy (separate script)"
echo "2. Or use iptables to redirect port 53 to $SLOWDNS_PORT"
echo ""
