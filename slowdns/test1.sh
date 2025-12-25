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
apt-get install -y net-tools curl wget dropbear
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
# INSTALL AND CONFIGURE DROPBEAR
# ====================================================
print "Installing and configuring Dropbear on port $DROPEAR_PORT..."

# Check if dropbear is installed
if ! command -v dropbear &> /dev/null; then
    print "Dropbear not found, installing via package manager..."
    apt-get install -y dropbear
fi

# Backup original config if exists
if [ -f /etc/default/dropbear ]; then
    cp /etc/default/dropbear /etc/default/dropbear.backup 2>/dev/null
fi

# Configure Dropbear
cat > /etc/default/dropbear << EOF
# Dropbear SSH Configuration - Port $DROPEAR_PORT
NO_START=0
DROPBEAR_PORT=$DROPEAR_PORT
DROPBEAR_EXTRA_ARGS="-s -w -p $DROPEAR_PORT"
DROPBEAR_BANNER="/etc/dropbear/banner"
DROPBEAR_RSAKEY="/etc/dropbear/dropbear_rsa_host_key"
DROPBEAR_DSSKEY="/etc/dropbear/dropbear_dss_host_key"
DROPBEAR_ECDSAKEY="/etc/dropbear/dropbear_ecdsa_host_key"
DROPBEAR_RECEIVE_WINDOW=65536
EOF

# Create banner file
mkdir -p /etc/dropbear
echo "Welcome to Dropbear SSH Server" > /etc/dropbear/banner

# Generate SSH RSA key (2048-bit) as requested
print "Generating SSH RSA key (2048-bit)..."
if [ -f /etc/dropbear/dropbear_rsa_host_key ]; then
    print_warning "RSA key already exists, skipping generation..."
else
    # Try with dropbearkey first (more reliable for dropbear)
    if command -v dropbearkey &> /dev/null; then
        dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key -s 2048 2>/dev/null
        if [ $? -eq 0 ]; then
            print_success "SSH RSA key generated successfully with dropbearkey"
        else
            # Fallback to ssh-keygen
            ssh-keygen -t rsa -b 2048 -f /etc/dropbear/dropbear_rsa_host_key -N "" -q
            if [ $? -eq 0 ]; then
                print_success "SSH RSA key generated successfully with ssh-keygen"
            else
                print_error "Failed to generate SSH RSA key"
            fi
        fi
    else
        ssh-keygen -t rsa -b 2048 -f /etc/dropbear/dropbear_rsa_host_key -N "" -q
        if [ $? -eq 0 ]; then
            print_success "SSH RSA key generated successfully"
        else
            print_error "Failed to generate SSH RSA key"
        fi
    fi
fi

# Generate DSA key for Dropbear compatibility
print "Generating DSA key for Dropbear..."
if [ -f /etc/dropbear/dropbear_dss_host_key ]; then
    print_warning "DSA key already exists, skipping generation..."
else
    # Try to generate DSA key with dropbearkey
    if command -v dropbearkey &> /dev/null; then
        dropbearkey -t dss -f /etc/dropbear/dropbear_dss_host_key 2>/dev/null
        if [ $? -eq 0 ]; then
            print_success "DSA key generated successfully"
        else
            print_warning "DSA key generation failed, will use existing or auto-generate"
            touch /etc/dropbear/dropbear_dss_host_key 2>/dev/null || true
        fi
    else
        print_warning "dropbearkey not available, DSA key will be auto-generated"
        touch /etc/dropbear/dropbear_dss_host_key 2>/dev/null || true
    fi
fi

# Ensure proper permissions
chmod 600 /etc/dropbear/dropbear_*_host_key 2>/dev/null || true

# Create directory for dropbear PID
mkdir -p /var/run/dropbear
chmod 755 /var/run/dropbear

# Restart Dropbear service
print "Restarting Dropbear service..."
systemctl daemon-reload
systemctl enable dropbear > /dev/null 2>&1
systemctl restart dropbear
sleep 3

# Check if Dropbear is running
print "Checking if Dropbear is running..."
DROPBEAR_RUNNING=false

# Check with multiple methods
if ss -tuln 2>/dev/null | grep -q ":$DROPEAR_PORT"; then
    DROPBEAR_RUNNING=true
elif netstat -tuln 2>/dev/null | grep -q ":$DROPEAR_PORT"; then
    DROPBEAR_RUNNING=true
elif systemctl is-active --quiet dropbear; then
    DROPBEAR_RUNNING=true
    print "Dropbear service is active"
fi

if $DROPBEAR_RUNNING; then
    print_success "Dropbear configured and running on port $DROPEAR_PORT"
    
    # Show Dropbear version
    DROPBEAR_VERSION=$(dropbear -V 2>&1 | head -1 || echo "unknown version")
    print "Dropbear version: $DROPBEAR_VERSION"
else
    print_warning "Dropbear service not running normally, attempting manual start..."
    
    # Kill any existing dropbear processes
    pkill dropbear 2>/dev/null
    sleep 1
    
    # Start dropbear manually
    if command -v dropbear &> /dev/null; then
        # Create directory for dropbear
        mkdir -p /etc/dropbear /var/run/dropbear
        
        # Start dropbear in background
        dropbear -p $DROPEAR_PORT -s -w -F -E &
        DROPBEAR_PID=$!
        sleep 2
        
        # Check if started successfully
        if ps -p $DROPBEAR_PID > /dev/null 2>&1; then
            print_success "Dropbear started manually on port $DROPEAR_PORT (PID: $DROPBEAR_PID)"
            
            # Save PID to file for later management
            echo $DROPBEAR_PID > /var/run/dropbear/dropbear.pid
            
            # Create a simple init script to restart on boot
            cat > /etc/init.d/dropbear-manual << EOF
#!/bin/sh
### BEGIN INIT INFO
# Provides:          dropbear-manual
# Required-Start:    \$network \$remote_fs
# Required-Stop:     \$network \$remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Dropbear SSH server (manual)
### END INIT INFO

case "\$1" in
    start)
        pkill dropbear 2>/dev/null
        dropbear -p $DROPEAR_PORT -s -w -F -E &
        echo \$! > /var/run/dropbear/dropbear.pid
        ;;
    stop)
        pkill dropbear 2>/dev/null
        rm -f /var/run/dropbear/dropbear.pid
        ;;
    restart)
        \$0 stop
        sleep 1
        \$0 start
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart}"
        exit 1
        ;;
esac
exit 0
EOF
            
            chmod +x /etc/init.d/dropbear-manual
            update-rc.d dropbear-manual defaults > /dev/null 2>&1
        else
            print_error "Failed to start Dropbear manually"
            print "Checking system logs for errors..."
            journalctl -u dropbear --no-pager | tail -20
        fi
    else
        print_error "Dropbear binary not found. Installation may have failed."
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
After=network.target

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

# Start Dropbear (try both methods)
systemctl start dropbear 2>/dev/null || true
if [ -f /etc/init.d/dropbear-manual ]; then
    /etc/init.d/dropbear-manual start
fi

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

# Test connection
print "Testing Dropbear connection..."
if timeout 5 bash -c "echo > /dev/tcp/127.0.0.1/$DROPEAR_PORT" 2>/dev/null; then
    print_success "Dropbear port $DROPEAR_PORT is accessible"
else
    print_warning "Dropbear port $DROPEAR_PORT is not accessible locally"
    print "Checking if port is open for external connections..."
    if ss -tuln | grep -q ":$DROPEAR_PORT"; then
        print_success "Dropbear is listening on port $DROPEAR_PORT"
    else
        print_error "Dropbear is not listening on any port"
    fi
fi

echo ""
echo -e "${GREEN}────────────────────────────────────────────────────────────────${NC}"
print_success "Dropbear + SlowDNS Installation Completed!"
echo -e "${GREEN}────────────────────────────────────────────────────────────────${NC}"
echo ""
echo -e "${YELLOW}Installation Summary:${NC}"
echo "• Dropbear SSH: Port $DROPEAR_PORT"
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
echo -e "${YELLOW}Testing Commands:${NC}"
echo "Check Dropbear: ss -tuln | grep :$DROPEAR_PORT"
echo "Check SlowDNS: ss -uln | grep :$SLOWDNS_PORT"
echo "Test SSH: ssh -p $DROPEAR_PORT root@localhost"
echo ""
