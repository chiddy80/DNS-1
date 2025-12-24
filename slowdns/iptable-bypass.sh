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
    echo -e "${WHITE}   I P T A B L E S   C O R R E C T   C O N F I G U R A T I O N${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW}   Activate Correct Rules for SlowDNS + EDNS Proxy${NC}"
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

print "Starting CORRECT iptables configuration..."
echo ""

echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${WHITE}   C O R R E C T   T R A F F I C   F L O W${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "Client DNS Request (Port 53)"
echo -e "        ↓"
echo -e "   EDNS Proxy (Port 53)"
echo -e "        ↓"
echo -e "Python EDNS Processing (512 → 1232 conversion)"
echo -e "        ↓"
echo -e "Forward to Port 5300 (direct Python connection)"
echo -e "        ↓"
echo -e "  SlowDNS Server (Port 5300)"
echo -e "        ↓"
echo -e "   SSH Backend (Port 22)"
echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo ""

print "Step 1: Flushing all existing iptables rules..."
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X

# Set default policies
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
print_success "All iptables rules flushed"

# ====================================================
# ESSENTIAL RULES (NO REDIRECTION NEEDED)
# ====================================================

print "Step 2: Setting up essential rules (NO DNS redirection)..."
echo ""

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
print_success "Loopback interface allowed"

# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
print_success "Established connections allowed"

# ====================================================
# OPEN PORTS FOR SERVICES
# ====================================================

print "Step 3: Opening ports for services..."
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

# ====================================================
# ALLOW INTERNAL COMMUNICATION
# ====================================================

print "Step 4: Allowing internal service communication..."
echo ""

# Allow EDNS Proxy (Python) to connect to SlowDNS
iptables -A OUTPUT -p udp --dport $SLOWDNS_PORT -j ACCEPT
print_success "EDNS Proxy → SlowDNS communication allowed"

# Allow localhost communication
iptables -A INPUT -s 127.0.0.1 -d 127.0.0.1 -j ACCEPT
iptables -A OUTPUT -s 127.0.0.1 -d 127.0.0.1 -j ACCEPT
print_success "Localhost communication allowed"

# ====================================================
# PERMISSIVE RULES FOR BYPASS
# ====================================================

print "Step 5: Adding permissive rules..."
echo ""

# Allow ICMP
iptables -A INPUT -p icmp -j ACCEPT
print_success "ICMP allowed"

# Allow all outbound traffic
iptables -A OUTPUT -j ACCEPT
print_success "All outbound traffic allowed"

# ====================================================
# SECURITY RULES (OPTIONAL)
# ====================================================

print "Step 6: Adding basic security rules..."
echo ""

# Drop invalid packets
iptables -A INPUT -m state --state INVALID -j DROP
print_success "Invalid packets dropped"

# Limit SSH connections
iptables -A INPUT -p tcp --dport $SSH_PORT -m state --state NEW -m recent --set
iptables -A INPUT -p tcp --dport $SSH_PORT -m state --state NEW -m recent --update --seconds 60 --hitcount 4 -j DROP
print_success "SSH brute force protection"

# ====================================================
# SAVE RULES
# ====================================================

print "Step 7: Saving iptables rules..."
echo ""

# Save rules
if command -v iptables-save > /dev/null; then
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    print_success "Rules saved to /etc/iptables/rules.v4"
fi

# ====================================================
# VERIFICATION
# ====================================================

print "Step 8: Verifying configuration..."
echo ""

echo -e "${YELLOW}Current Open Ports:${NC}"
iptables -L INPUT -n | grep -E "(dpt:22|dpt:53|dpt:5300)" | while read line; do
    echo "  $line"
done

echo ""
echo -e "${YELLOW}Important:${NC}"
echo "  - NO DNS redirection rules are needed"
echo "  - EDNS Proxy Python script handles 512→1232 conversion"
echo "  - Python connects directly from port 53 to port 5300"

# ====================================================
# CREATE SIMPLE MANAGEMENT SCRIPTS
# ====================================================

print "Step 9: Creating management scripts..."
echo ""

# Simple status script
cat > /usr/local/bin/show-ports << 'EOF'
#!/bin/bash
echo "=== OPEN PORTS FOR BYPASS ==="
echo ""
echo "Port 22 (SSH):"
iptables -L INPUT -n | grep "tcp dpt:22" | head -1 | sed 's/^/  /'
echo ""
echo "Port 53 (EDNS Proxy):"
iptables -L INPUT -n | grep -E "(udp|tcp) dpt:53" | sed 's/^/  /'
echo ""
echo "Port 5300 (SlowDNS):"
iptables -L INPUT -n | grep "udp dpt:5300" | head -1 | sed 's/^/  /'
echo ""
echo "Services Status:"
echo "  EDNS Proxy: $(systemctl is-active edns-proxy 2>/dev/null || echo 'Not installed')"
echo "  SlowDNS: $(systemctl is-active slowdns-server 2>/dev/null || echo 'Not installed')"
EOF

chmod +x /usr/local/bin/show-ports
print_success "Created: show-ports"

# Reset script
cat > /usr/local/bin/open-all-ports << 'EOF'
#!/bin/bash
echo "Opening all ports (ACCEPT policy)..."
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
echo "All ports are now open"
EOF

chmod +x /usr/local/bin/open-all-ports
print_success "Created: open-all-ports"

echo ""
echo -e "${GREEN}────────────────────────────────────────────────────────────────${NC}"
print_success "IPTABLES CONFIGURATION COMPLETED!"
echo -e "${GREEN}────────────────────────────────────────────────────────────────${NC}"
echo ""

echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${WHITE}   S U M M A R Y${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}✓${NC} Port 22 (SSH) - OPEN"
echo -e "${GREEN}✓${NC} Port 53 (EDNS Proxy) - OPEN"
echo -e "${GREEN}✓${NC} Port 5300 (SlowDNS) - OPEN"
echo -e "${GREEN}✓${NC} NO DNS redirection rules"
echo -e "${GREEN}✓${NC} All outbound traffic allowed"
echo ""

echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${WHITE}   T E S T   C O M M A N D S${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "Check open ports:"
echo -e "  ${GREEN}show-ports${NC}"
echo ""
echo -e "Test DNS bypass:"
echo -e "  ${GREEN}dig @$(hostname -I | awk '{print $1}') google.com${NC}"
echo ""
echo -e "Reset to open all:"
echo -e "  ${GREEN}open-all-ports${NC}"
echo ""

echo -e "${YELLOW}Remember:${NC}"
echo "  The EDNS Proxy Python script handles the 512→1232 conversion"
echo "  No iptables redirection is needed"
echo "  Python connects directly: Port 53 → Port 5300"
echo ""
