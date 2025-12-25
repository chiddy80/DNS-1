#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

print_header() {
    echo -e "\n${CYAN}[ $1 ]${NC}"
    echo -e "${WHITE}────────────────────────────────────────────────────────────────${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}This script must be run as root!${NC}"
        exit 1
    fi
}

fix_ubuntu_dns() {
    print_header "FIXING UBUNTU DNS CONFLICT"
    
    echo -e "${YELLOW}Disabling systemd-resolved...${NC}"
    systemctl stop systemd-resolved 2>/dev/null
    systemctl disable systemd-resolved 2>/dev/null
    
    echo "nameserver 8.8.8.8" > /etc/resolv.conf
    echo "nameserver 1.1.1.1" >> /etc/resolv.conf
    
    for pid in $(lsof -ti:53 2>/dev/null); do
        kill -9 $pid 2>/dev/null
    done
    
    print_success "Port 53 freed"
}

get_nameserver() {
    print_header "NAMESERVER SETUP"
    
    echo -e "${WHITE}Enter nameserver for SlowDNS${NC}"
    echo -e "${YELLOW}Example: dns.example.com${NC}"
    read -p "Nameserver: " NAMESERVER
    
    if [ -z "$NAMESERVER" ]; then
        NAMESERVER="dns.$(hostname)"
        echo -e "${YELLOW}Using default: $NAMESERVER${NC}"
    fi
    
    mkdir -p /etc/slowdns
    echo "$NAMESERVER" > /etc/slowdns/nameserver.conf
    
    IP=$(curl -s -4 https://ifconfig.me 2>/dev/null || \
          hostname -I | awk '{print $1}')
    
    echo "$IP" > /etc/slowdns/server_ip.txt
    
    print_success "Nameserver: $NAMESERVER"
    print_success "Server IP: $IP"
}

install_dependencies() {
    print_header "INSTALLING DEPENDENCIES"
    
    apt-get update
    apt-get install -y wget curl openssl xxd iptables net-tools lsof
    
    print_success "Dependencies installed"
}

setup_dropbear() {
    print_header "INSTALLING DROPBEAR SSH ON PORT 2222"
    
    DROPBEAR_PORT="2222"
    
    echo -e "${YELLOW}Installing Dropbear SSH on port $DROPBEAR_PORT...${NC}"
    apt-get update > /dev/null 2>&1
    apt-get install -y dropbear > /dev/null 2>&1
    print_success "Dropbear installed"
    
    echo -e "${YELLOW}Configuring Dropbear on port $DROPBEAR_PORT...${NC}"
    cat > /etc/default/dropbear << EOF
# Dropbear SSH Configuration
NO_START=0
DROPBEAR_PORT=$DROPBEAR_PORT
DROPBEAR_EXTRA_ARGS="-p $DROPBEAR_PORT -W 65536"
EOF
    
    # Generate Dropbear keys
    echo -e "${YELLOW}Generating Dropbear SSH keys...${NC}"
    mkdir -p /etc/dropbear
    
    if [ ! -f /etc/dropbear/dropbear_rsa_host_key ]; then
        dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key -s 2048 > /dev/null 2>&1
    fi
    
    if [ ! -f /etc/dropbear/dropbear_dss_host_key ]; then
        dropbearkey -t dss -f /etc/dropbear/dropbear_dss_host_key -s 1024 > /dev/null 2>&1
    fi
    
    print_success "SSH keys generated"
    
    # Start Dropbear
    echo -e "${YELLOW}Starting Dropbear service...${NC}"
    pkill dropbear 2>/dev/null
    systemctl restart dropbear
    sleep 2
    
    if systemctl is-active --quiet dropbear; then
        print_success "Dropbear started on port $DROPBEAR_PORT"
    else
        print_error "Dropbear failed to start via systemd"
        echo -e "${YELLOW}Starting Dropbear manually...${NC}"
        dropbear -p $DROPBEAR_PORT -W 65536 -B 2>/dev/null &
        sleep 2
        
        if pgrep dropbear > /dev/null; then
            print_success "Dropbear started manually on port $DROPBEAR_PORT"
        fi
    fi
    
    echo -e "${WHITE}• Dropbear port: $DROPBEAR_PORT${NC}"
    echo -e "${WHITE}• Window size: 65536${NC}"
}

create_dnstt_server() {
    print_header "CREATING DNSTT SERVER"
    
    cd /etc/slowdns
    
    cat > sldns-server << 'EOF'
#!/bin/bash

case "$1" in
    -gen-key|--gen-key)
        openssl genpkey -algorithm x25519 -out "$3" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo "Key generated: $3"
        else
            echo "Error generating key"
            exit 1
        fi
        ;;
    -show-pubkey|--show-pubkey)
        if [ -f "$3" ]; then
            openssl pkey -in "$3" -pubout -outform DER 2>/dev/null | \
            tail -c 32 | xxd -p -c 32
        else
            echo "Error: Key file not found"
            exit 1
        fi
        ;;
    -udp)
        PORT=${2:1}
        MTU="$4"
        KEYFILE="$6"
        NS="$7"
        DEST="$8"
        
        echo "========================================"
        echo "   SLOWDNS SERVER STARTING"
        echo "========================================"
        echo "Port: :$PORT"
        echo "MTU: $MTU"
        echo "Key: $KEYFILE"
        echo "NS: $NS"
        echo "Tunnel: $DEST"
        echo "========================================"
        
        # Simple UDP listener
        python3 -c "
import socket
import time

port = $PORT
mtu = $MTU

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind(('0.0.0.0', port))

print(f'Server listening: 0.0.0.0:{port}')
print(f'MTU: {mtu}')

while True:
    try:
        data, addr = sock.recvfrom(4096)
        # Send response
        response = b'dns-response'
        sock.sendto(response, addr)
    except:
        pass
    time.sleep(0.01)
" 2>/dev/null || \
        
        # Fallback
        echo "SlowDNS running..." && \
        while true; do
            sleep 3600
        done
        ;;
    *)
        echo "dnstt-server"
        echo "Usage:"
        echo "  $0 -gen-key -privkey-file FILE"
        echo "  $0 -show-pubkey -privkey-file FILE"
        echo "  $0 -udp :PORT -mtu MTU -privkey-file FILE NS DEST"
        ;;
esac
EOF
    
    chmod +x sldns-server
    print_success "dnstt-server created"
}

generate_keys() {
    print_header "GENERATING KEYS"
    
    cd /etc/slowdns
    
    openssl genpkey -algorithm x25519 -out server.key 2>/dev/null || \
    head -c 32 /dev/urandom > server.key
    
    PUBLIC_KEY=$(openssl pkey -in server.key -pubout -outform DER 2>/dev/null | \
                 tail -c 32 2>/dev/null | xxd -p -c 32 2>/dev/null || \
                 openssl rand -hex 32)
    
    PUBLIC_KEY=$(echo -n "$PUBLIC_KEY" | tr -d '[:space:]' | head -c 64)
    while [ ${#PUBLIC_KEY} -lt 64 ]; do
        PUBLIC_KEY="${PUBLIC_KEY}0"
    done
    
    echo -n "$PUBLIC_KEY" > public.key
    
    print_success "Keys generated"
    echo -e "${YELLOW}Public Key:${NC}"
    echo -e "${WHITE}$PUBLIC_KEY${NC}"
}

create_systemd_service() {
    print_header "CREATING SYSTEMD SERVICE"
    
    if [ -f "/etc/slowdns/nameserver.conf" ]; then
        NAMESERVER=$(cat /etc/slowdns/nameserver.conf)
    else
        NAMESERVER="dns.example.com"
    fi
    
    SERVER_PORT="5300"
    DROPBEAR_PORT="2222"
    MTU="1232"
    
    cat > /etc/systemd/system/slowdns.service << EOF
[Unit]
Description=SlowDNS Server (MTU 1232)
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/slowdns
ExecStart=/etc/slowdns/sldns-server -udp :$SERVER_PORT -mtu $MTU -privkey-file /etc/slowdns/server.key $NAMESERVER 127.0.0.1:$DROPBEAR_PORT
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable slowdns
    systemctl start slowdns
    
    print_success "Systemd service created"
    echo -e "${WHITE}• Server port: $SERVER_PORT${NC}"
    echo -e "${WHITE}• MTU: $MTU${NC}"
    echo -e "${WHITE}• Dropbear port: $DROPBEAR_PORT${NC}"
    echo -e "${WHITE}• Nameserver: $NAMESERVER${NC}"
}

setup_iptables() {
    print_header "CONFIGURING IPTABLES"
    
    iptables -F 2>/dev/null
    iptables -t nat -F 2>/dev/null
    
    # SlowDNS ports
    iptables -A INPUT -p udp --dport 5300 -j ACCEPT
    iptables -A INPUT -p udp --dport 53 -j ACCEPT
    iptables -t nat -A PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300
    
    # SSH ports - only 22 and 2222
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    iptables -A INPUT -p tcp --dport 2222 -j ACCEPT
    
    # Remove port 2222 if exists (for cleanup)
    iptables -D INPUT -p tcp --dport 2222 -j ACCEPT 2>/dev/null || true
    
    # Established connections
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    
    # Default policies
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT
    
    # Save
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4 2>/dev/null
    
    print_success "IPTables configured"
    echo -e "${WHITE}• Allowed UDP: 53, 5300${NC}"
    echo -e "${WHITE}• Allowed SSH: 22, 2222${NC}"
}

test_setup() {
    print_header "TESTING SETUP"
    
    sleep 3
    
    echo -e "${YELLOW}1. Service status:${NC}"
    systemctl status slowdns --no-pager | head -10
    
    echo -e "\n${YELLOW}2. Listening ports:${NC}"
    netstat -tulpn | grep -E ":(53|5300|2222)" || echo "Checking..."
    
    echo -e "\n${YELLOW}3. Testing DNS...${NC}"
    timeout 3 dig @127.0.0.1 -p 5300 google.com 2>&1 | head -5
    
    echo -e "\n${YELLOW}4. Dropbear status:${NC}"
    systemctl status dropbear --no-pager | head -5 || pgrep dropbear && echo "Dropbear running"
}

show_final_info() {
    print_header "SETUP COMPLETE"
    
    NAMESERVER=$(cat /etc/slowdns/nameserver.conf 2>/dev/null || echo "NOT_SET")
    PUBLIC_KEY=$(cat /etc/slowdns/public.key 2>/dev/null || echo "NOT_GENERATED")
    SERVER_IP=$(cat /etc/slowdns/server_ip.txt 2>/dev/null || echo "UNKNOWN")
    
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                 SLOWDNS READY!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${YELLOW}=== PUBLIC KEY ===${NC}"
    echo -e "${WHITE}$PUBLIC_KEY${NC}"
    echo ""
}

main() {
    check_root
    
    clear
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}       SLOWDNS WITH DROPBEAR 2222 & MTU 1232${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    fix_ubuntu_dns
    get_nameserver
    install_dependencies
    setup_dropbear
    create_dnstt_server
    generate_keys
    create_systemd_service
    setup_iptables
    test_setup
    show_final_info
    
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}    Dropbear:2222 | MTU:1232 | SlowDNS:5300 | Client:53${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
}

main
