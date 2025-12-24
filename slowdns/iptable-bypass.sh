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

# Port Configuration
SSH_PORT=22
DNS_PORT=53
SLOWDNS_PORT=5300

# Title Function
print_title() {
    clear
    echo ""
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    echo -e "${WHITE}   I P T A B L E S   C O N F I G U R A T I O N${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW}   Port Rules for SlowDNS + EDNS Proxy${NC}"
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

# Check root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}Please run as root: sudo bash $0${NC}"
        exit 1
    fi
}

# Show title
clear
check_root
print_title

print "Starting iptables configuration..."
echo ""

print "Flushing existing iptables rules..."
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X

# Set default policies
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
print_success "All iptables rules flushed"

print "Setting up essential rules..."
echo ""

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
print_success "Loopback interface allowed"

# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
print_success "Established connections allowed"

print "Opening ports for services..."
echo ""

# SSH (Required for SlowDNS backend)
iptables -A INPUT -p tcp --dport $SSH_PORT -j ACCEPT
print_success "SSH port $SSH_PORT opened"

# EDNS Proxy (Listens on Port 53 for client requests)
iptables -A INPUT -p udp --dport $DNS_PORT -j ACCEPT
iptables -A INPUT -p tcp --dport $DNS_PORT -j ACCEPT
print_success "EDNS Proxy port $DNS_PORT opened"

# SlowDNS Server (Receives requests from EDNS Proxy Python script)
iptables -A INPUT -p udp --dport $SLOWDNS_PORT -j ACCEPT
print_success "SlowDNS port $SLOWDNS_PORT opened"

print "Allowing internal service communication..."
echo ""

# Allow EDNS Proxy (Python) to connect to SlowDNS
iptables -A OUTPUT -p udp --dport $SLOWDNS_PORT -j ACCEPT
print_success "EDNS Proxy → SlowDNS communication allowed"

# Allow localhost communication
iptables -A INPUT -s 127.0.0.1 -d 127.0.0.1 -j ACCEPT
iptables -A OUTPUT -s 127.0.0.1 -d 127.0.0.1 -j ACCEPT
print_success "Localhost communication allowed"

print "Adding permissive rules..."
echo ""

# Allow ICMP
iptables -A INPUT -p icmp -j ACCEPT
print_success "ICMP allowed"

# Allow all outbound traffic
iptables -A OUTPUT -j ACCEPT
print_success "All outbound traffic allowed"

print "Adding basic security rules..."
echo ""

# Drop invalid packets
iptables -A INPUT -m state --state INVALID -j DROP
print_success "Invalid packets dropped"

# Limit SSH connections
iptables -A INPUT -p tcp --dport $SSH_PORT -m state --state NEW -m recent --set
iptables -A INPUT -p tcp --dport $SSH_PORT -m state --state NEW -m recent --update --seconds 60 --hitcount 4 -j DROP
print_success "SSH brute force protection"

print "Saving iptables rules..."
echo ""

# Save rules
if command -v iptables-save > /dev/null; then
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    print_success "Rules saved to /etc/iptables/rules.v4"
fi

echo ""
echo -e "${GREEN}────────────────────────────────────────────────────────────────${NC}"
print_success "IPTABLES CONFIGURATION COMPLETED"
echo -e "${GREEN}────────────────────────────────────────────────────────────────${NC}"
echo ""
