#!/data/data/com.termux/files/usr/bin/bash

# 🇹🇿 Termux MTU Scanner & DNS Optimizer 🇹🇿
# Usage: bash -c "$(curl -fsSL https://raw.githubusercontent.com/athumani2580/DNS/main/slowdns/ednscheck.sh)"

# Colors for Termux
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
PURPLE='\033[1;35m'
WHITE='\033[1;37m'
NC='\033[0m'

# Banner with 🇹🇿
print_banner() {
    clear
    echo ""
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${CYAN}   ████████╗███████╗██████╗ ███╗   ███╗██╗   ██╗██╗  ██╗${PURPLE}   ║${NC}"
    echo -e "${PURPLE}║${CYAN}   ╚══██╔══╝██╔════╝██╔══██╗████╗ ████║██║   ██║╚██╗██╔╝${PURPLE}   ║${NC}"
    echo -e "${PURPLE}║${CYAN}      ██║   █████╗  ██████╔╝██╔████╔██║██║   ██║ ╚███╔╝ ${PURPLE}   ║${NC}"
    echo -e "${PURPLE}║${CYAN}      ██║   ██╔══╝  ██╔══██╗██║╚██╔╝██║██║   ██║ ██╔██╗ ${PURPLE}   ║${NC}"
    echo -e "${PURPLE}║${CYAN}      ██║   ███████╗██║  ██║██║ ╚═╝ ██║╚██████╔╝██╔╝ ██╗${PURPLE}   ║${NC}"
    echo -e "${PURPLE}║${CYAN}      ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═╝${PURPLE}   ║${NC}"
    echo -e "${PURPLE}║                                                            ║${NC}"
    echo -e "${PURPLE}║${WHITE}       🇹🇿  T E R M U X   M T U   S C A N N E R  🇹🇿       ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${YELLOW}         Complete Network Analysis & DNS Optimizer         ${PURPLE}║${NC}"
    echo -e "${PURPLE}║                                                            ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Check if running in Termux
check_termux() {
    if [ ! -d "/data/data/com.termux" ]; then
        echo -e "${RED}Error: This script is designed for Termux only!${NC}"
        echo "Please run this in Termux app."
        exit 1
    fi
}

# Check and install required packages
check_dependencies() {
    echo -e "${BLUE}[*]${NC} Checking dependencies..."
    
    # Check for curl
    if ! command -v curl &> /dev/null; then
        echo -e "${YELLOW}[!]${NC} curl not found. Installing..."
        pkg install curl -y > /dev/null 2>&1
        echo -e "${GREEN}[✓]${NC} curl installed"
    fi
    
    # Check for ping
    if ! command -v ping &> /dev/null; then
        echo -e "${YELLOW}[!]${NC} ping not found. Installing..."
        pkg install iputils-ping -y > /dev/null 2>&1
        echo -e "${GREEN}[✓]${NC} ping installed"
    fi
    
    # Check for netstat/ss
    if ! command -v ss &> /dev/null && ! command -v netstat &> /dev/null; then
        echo -e "${YELLOW}[!]${NC} network tools not found. Installing..."
        pkg install net-tools -y > /dev/null 2>&1
        echo -e "${GREEN}[✓]${NC} network tools installed"
    fi
    
    echo -e "${GREEN}[✓]${NC} All dependencies are installed"
}

# Comprehensive Network Information
show_network_info() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}    🇹🇿  C O M P L E T E   N E T W O R K   I N F O  🇹🇿${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Get IP addresses
    echo -e "${PURPLE}[ PUBLIC IP ]${NC}"
    public_ip=$(curl -s ifconfig.me)
    if [ -n "$public_ip" ]; then
        echo -e "  ${GREEN}${public_ip}${NC}"
    else
        echo -e "  ${RED}Not available${NC}"
    fi
    
    # Get local IP
    echo -e "${PURPLE}[ LOCAL IP ]${NC}"
    local_ip=$(ip route get 1 2>/dev/null | awk '{print $7; exit}')
    if [ -n "$local_ip" ]; then
        echo -e "  ${GREEN}${local_ip}${NC}"
    else
        echo -e "  ${YELLOW}No local IP detected${NC}"
    fi
    
    # Get default interface
    echo -e "${PURPLE}[ NETWORK INTERFACE ]${NC}"
    interface=$(ip route | grep default | awk '{print $5}' | head -1)
    if [ -n "$interface" ]; then
        echo -e "  ${GREEN}${interface}${NC}"
        
        # Get interface status
        if ip link show $interface | grep -q "state UP"; then
            echo -e "  ${GREEN}Status: UP${NC}"
        else
            echo -e "  ${RED}Status: DOWN${NC}"
        fi
    else
        echo -e "  ${RED}No interface found${NC}"
    fi
    
    # Check internet connectivity
    echo -e "${PURPLE}[ INTERNET CONNECTIVITY ]${NC}"
    if ping -c 1 -W 2 8.8.8.8 &> /dev/null; then
        echo -e "  ${GREEN}✓ Connected to Internet${NC}"
        
        # Test DNS servers
        echo -e "${PURPLE}[ DNS SERVERS TEST ]${NC}"
        dns_servers=(
            "Google DNS:8.8.8.8"
            "Cloudflare:1.1.1.1"
            "OpenDNS:208.67.222.222"
            "Quad9:9.9.9.9"
        )
        
        for dns in "${dns_servers[@]}"; do
            name="${dns%:*}"
            ip="${dns#*:}"
            echo -ne "  ${name}: "
            if ping -c 1 -W 1 $ip &> /dev/null; then
                echo -e "${GREEN}✓ Reachable${NC}"
            else
                echo -e "${RED}✗ Unreachable${NC}"
            fi
        done
        
        # Check current DNS
        echo -e "${PURPLE}[ CURRENT DNS CONFIG ]${NC}"
        if [ -f /etc/resolv.conf ]; then
            grep -E "^nameserver" /etc/resolv.conf | head -3 | while read line; do
                echo -e "  ${YELLOW}${line}${NC}"
            done
        else
            echo -e "  ${YELLOW}/etc/resolv.conf not found${NC}"
        fi
        
    else
        echo -e "  ${RED}✗ No Internet Connection${NC}"
    fi
    
    # Check for SlowDNS services
    echo -e "${PURPLE}[ SLOWDNS SERVICES SCAN ]${NC}"
    
    # Common SlowDNS ports
    slowdns_ports=(53 5300 5353 8053 443 8443 8080)
    found_ports=()
    
    for port in "${slowdns_ports[@]}"; do
        # Check if port is listening
        if command -v ss &> /dev/null; then
            if ss -tulpn 2>/dev/null | grep -q ":$port"; then
                found_ports+=($port)
                service_info=$(ss -tulpn 2>/dev/null | grep ":$port" | head -1)
                echo -e "  ${GREEN}✓ Port ${port} - IN USE${NC}"
                echo -e "    ${YELLOW}${service_info}${NC}"
            else
                echo -e "  ${BLUE}• Port ${port} - Available${NC}"
            fi
        elif command -v netstat &> /dev/null; then
            if netstat -tulpn 2>/dev/null | grep -q ":$port"; then
                found_ports+=($port)
                service_info=$(netstat -tulpn 2>/dev/null | grep ":$port" | head -1)
                echo -e "  ${GREEN}✓ Port ${port} - IN USE${NC}"
                echo -e "    ${YELLOW}${service_info}${NC}"
            else
                echo -e "  ${BLUE}• Port ${port} - Available${NC}"
            fi
        fi
    done
    
    # Summary
    echo ""
    echo -e "${PURPLE}[ SUMMARY ]${NC}"
    if [ ${#found_ports[@]} -gt 0 ]; then
        echo -e "  ${GREEN}Found ${#found_ports[@]} DNS-related services${NC}"
        echo -e "  ${YELLOW}Ports in use: ${found_ports[*]}${NC}"
    else
        echo -e "  ${YELLOW}No DNS/SlowDNS services detected${NC}"
    fi
    
    # Check for EDNS support
    echo -e "${PURPLE}[ EDNS SUPPORT TEST ]${NC}"
    if command -v dig &> /dev/null; then
        if dig +edns +nocookie google.com @8.8.8.8 2>/dev/null | grep -q "EDNS:"; then
            echo -e "  ${GREEN}✓ EDNS is supported${NC}"
        else
            echo -e "  ${YELLOW}⚠ EDNS may not be supported${NC}"
        fi
    else
        echo -e "  ${BLUE}Install 'dig' for EDNS testing: pkg install dnsutils${NC}"
    fi
}

# Comprehensive MTU Scanner (512 to 4096)
scan_all_mtu() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}    🇹🇿  C O M P R E H E N S I V E   M T U   S C A N  🇹🇿${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${YELLOW}Scanning MTU from 512 to 4096 (this will take 2-3 minutes)...${NC}"
    echo -e "${BLUE}This tests which packet sizes work without fragmentation${NC}"
    echo ""
    
    # Test servers
    local servers=("8.8.8.8" "1.1.1.1" "208.67.222.222")
    local working_mtus=()
    local max_working_mtu=0
    local last_working=0
    local test_count=0
    
    # Test in ranges for efficiency
    echo -e "${PURPLE}[ Testing Small Packets: 512-1500 ]${NC}"
    for mtu in {512..1500..32}; do
        test_mtu $mtu
    done
    
    echo -e "${PURPLE}[ Testing Medium Packets: 1500-3000 ]${NC}"
    for mtu in {1500..3000..64}; do
        test_mtu $mtu
    done
    
    echo -e "${PURPLE}[ Testing Large Packets: 3000-4096 ]${NC}"
    for mtu in {3000..4096..128}; do
        test_mtu $mtu
    done
    
    # Fill in gaps around the maximum working MTU
    if [ $max_working_mtu -gt 0 ]; then
        echo -e "${PURPLE}[ Fine-tuning around maximum: $((max_working_mtu-128))-$((max_working_mtu+128)) ]${NC}"
        for mtu in $(seq $((max_working_mtu-128)) 8 $((max_working_mtu+128))); do
            if [ $mtu -ge 512 ] && [ $mtu -le 4096 ]; then
                test_mtu $mtu
            fi
        done
    fi
    
    display_results
}

# Test individual MTU
test_mtu() {
    local mtu=$1
    local payload_size=$(($mtu - 28))
    local success=0
    
    # Skip if too small
    if [ $payload_size -lt 0 ]; then
        return
    fi
    
    # Show progress every 10 tests
    if [ $((test_count % 10)) -eq 0 ]; then
        echo -ne "  Testing: ${mtu} bytes\r"
    fi
    ((test_count++))
    
    # Test with multiple servers
    for server in "${servers[@]}"; do
        if timeout 2 ping -M do -s $payload_size -c 1 -W 1 $server 2>/dev/null | grep -qv "Frag needed\|100% packet loss"; then
            ((success++))
        fi
    done
    
    # Consider successful if at least 2 servers respond
    if [ $success -ge 2 ]; then
        working_mtus+=($mtu)
        if [ $mtu -gt $max_working_mtu ]; then
            max_working_mtu=$mtu
            last_working=$mtu
        fi
    fi
}

# Display scan results
display_results() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}    🇹🇿  S C A N   R E S U L T S  🇹🇿${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ ${#working_mtus[@]} -eq 0 ]; then
        echo -e "${RED}No working MTU sizes found!${NC}"
        echo "This could be due to:"
        echo "  1. Network blocking ICMP"
        echo "  2. Strict firewall rules"
        echo "  3. No internet connection"
        echo ""
        echo -e "${YELLOW}Recommendation: Use standard MTU 512${NC}"
        return
    fi
    
    # Sort and get unique MTUs
    IFS=$'\n' unique_mtus=($(printf "%s\n" "${working_mtus[@]}" | sort -n | uniq))
    unset IFS
    
    # Group MTUs by range
    echo -e "${GREEN}WORKING MTU RANGES:${NC}"
    
    local range_start=${unique_mtus[0]}
    local range_end=${unique_mtus[0]}
    local ranges=()
    
    for ((i=1; i<${#unique_mtus[@]}; i++)); do
        if [ $((${unique_mtus[i]} - range_end)) -le 16 ]; then
            range_end=${unique_mtus[i]}
        else
            ranges+=("$range_start-$range_end")
            range_start=${unique_mtus[i]}
            range_end=${unique_mtus[i]}
        fi
    done
    ranges+=("$range_start-$range_end")
    
    # Display ranges
    for range in "${ranges[@]}"; do
        start=${range%-*}
        end=${range#*-}
        if [ $start -eq $end ]; then
            echo -e "  ${GREEN}✓${NC} $start bytes"
        else
            echo -e "  ${GREEN}✓${NC} $range bytes"
        fi
    done
    
    # Maximum MTU
    local absolute_max=${unique_mtus[-1]}
    echo ""
    echo -e "${GREEN}MAXIMUM WORKING MTU: ${YELLOW}$absolute_max bytes${NC}"
    
    # Calculate optimal DNS MTU
    calculate_optimal_mtu $absolute_max
}

# Calculate optimal MTU for DNS
calculate_optimal_mtu() {
    local max_mtu=$1
    
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}    🇹🇿  O P T I M A L   D N S   C O N F I G  🇹🇿${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Recommended MTU based on maximum
    local recommended_mtu=512
    
    if [ $max_mtu -ge 4096 ]; then
        recommended_mtu=4096
        echo -e "${PURPLE}🎯 RECOMMENDED: MTU 4096 (MAXIMUM PERFORMANCE)${NC}"
        echo "   Speed: 8x faster than 512 MTU"
        echo "   Use: For TCP-based DNS tunnels"
        echo "   Note: Requires TCP fallback support"
        
    elif [ $max_mtu -ge 2048 ]; then
        recommended_mtu=2048
        echo -e "${GREEN}🎯 RECOMMENDED: MTU 2048 (ULTRA HIGH SPEED)${NC}"
        echo "   Speed: 4x faster than 512 MTU"
        echo "   Use: High-speed networks with jumbo frames"
        
    elif [ $max_mtu -ge 1452 ]; then
        recommended_mtu=1452
        echo -e "${GREEN}🎯 RECOMMENDED: MTU 1452 (MAXIMUM UDP)${NC}"
        echo "   Speed: 2.8-3x faster than 512 MTU"
        echo "   Use: Standard networks without jumbo frames"
        
    elif [ $max_mtu -ge 1232 ]; then
        recommended_mtu=1232
        echo -e "${GREEN}🎯 RECOMMENDED: MTU 1232 (OPTIMAL BALANCE)${NC}"
        echo "   Speed: 2.3-2.5x faster than 512 MTU"
        echo "   Use: Modern DNS standard"
        
    elif [ $max_mtu -ge 1024 ]; then
        recommended_mtu=1024
        echo -e "${YELLOW}🎯 RECOMMENDED: MTU 1024 (GOOD IMPROVEMENT)${NC}"
        echo "   Speed: 2x faster than 512 MTU"
        echo "   Use: Conservative networks"
        
    else
        recommended_mtu=512
        echo -e "${YELLOW}🎯 RECOMMENDED: MTU 512 (STANDARD)${NC}"
        echo "   Speed: Baseline"
        echo "   Use: Maximum compatibility"
    fi
    
    # Show configuration
    echo ""
    echo -e "${WHITE}CONFIGURATION FOR SLOWDNS:${NC}"
    echo "  ExecStart=/etc/slowdns/sldns-server -udp :5300 -mtu $recommended_mtu ..."
    
    echo ""
    echo -e "${WHITE}CONFIGURATION FOR EDNS PROXY:${NC}"
    echo "  EXTERNAL_EDNS_SIZE = 512"
    echo "  INTERNAL_EDNS_SIZE = $recommended_mtu"
    
    # Performance comparison
    echo ""
    echo -e "${WHITE}PERFORMANCE COMPARISON:${NC}"
    if [ $recommended_mtu -eq 512 ]; then
        echo "  Speed: 1x (Baseline)"
    else
        local speed_multiplier=$(echo "scale=1; $recommended_mtu/512" | bc)
        echo "  Speed: ${speed_multiplier}x faster than 512 MTU"
        echo "  Efficiency: $((100 - (51200/$recommended_mtu)))% less overhead"
    fi
}

# Quick MTU test
quick_mtu_test() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}    🇹🇿  Q U I C K   M T U   T E S T  🇹🇿${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    local test_mtus=(512 1024 1232 1452 2048 4096)
    
    for mtu in "${test_mtus[@]}"; do
        local payload_size=$(($mtu - 28))
        echo -ne "  Testing MTU ${mtu}: "
        
        local success=0
        for server in "8.8.8.8" "1.1.1.1"; do
            if timeout 2 ping -M do -s $payload_size -c 1 -W 1 $server 2>/dev/null | grep -qv "Frag needed\|100% packet loss"; then
                ((success++))
            fi
        done
        
        if [ $success -ge 1 ]; then
            echo -e "${GREEN}✓ WORKING${NC}"
        else
            echo -e "${RED}✗ FRAGMENTS${NC}"
        fi
    done
}

# Main menu
show_menu() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}    🇹🇿  M A I N   M E N U  🇹🇿${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${GREEN}1.${NC} 🇹🇿 Complete Network Information"
    echo -e "${GREEN}2.${NC} 🇹🇿 Full MTU Scan (512 to 4096)"
    echo -e "${GREEN}3.${NC} 🇹🇿 Quick MTU Test"
    echo -e "${GREEN}4.${NC} 🇹🇿 Test Specific MTU"
    echo -e "${GREEN}5.${NC} 🇹🇿 Optimize DNS Settings"
    echo -e "${GREEN}6.${NC} 🇹🇿 Exit"
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Test specific MTU
test_specific_mtu() {
    echo ""
    echo -e "${YELLOW}Enter MTU size to test (512-4096):${NC}"
    read -p "MTU: " custom_mtu
    
    if ! [[ "$custom_mtu" =~ ^[0-9]+$ ]] || [ $custom_mtu -lt 512 ] || [ $custom_mtu -gt 4096 ]; then
        echo -e "${RED}Invalid MTU! Must be between 512 and 4096${NC}"
        return
    fi
    
    echo ""
    echo -ne "${BLUE}[*]${NC} Testing MTU ${WHITE}$custom_mtu${NC}: "
    
    local payload_size=$(($custom_mtu - 28))
    local success=0
    
    for server in "8.8.8.8" "1.1.1.1"; do
        if timeout 2 ping -M do -s $payload_size -c 1 -W 1 $server 2>/dev/null | grep -qv "Frag needed\|100% packet loss"; then
            ((success++))
        fi
    done
    
    if [ $success -ge 1 ]; then
        echo -e "${GREEN}✓ WORKING${NC}"
        
        # Recommend optimal DNS MTU
        local dns_mtu=$custom_mtu
        if [ $dns_mtu -gt 1452 ]; then
            echo -e "${YELLOW}Note: For DNS, consider using 1452 max for UDP${NC}"
        fi
        
        echo ""
        echo -e "${WHITE}Recommended SlowDNS config:${NC}"
        echo "  -mtu $dns_mtu"
        
    else
        echo -e "${RED}✗ FRAGMENTS${NC}"
        echo -e "${YELLOW}Try a smaller MTU value${NC}"
    fi
}

# Optimize DNS settings
optimize_dns() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}    🇹🇿  D N S   O P T I M I Z A T I O N  🇹🇿${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${YELLOW}Testing optimal DNS configuration...${NC}"
    echo ""
    
    # Test different DNS servers
    dns_servers=(
        "8.8.8.8:Google DNS"
        "1.1.1.1:Cloudflare"
        "208.67.222.222:OpenDNS"
        "9.9.9.9:Quad9"
        "94.140.14.14:AdGuard"
    )
    
    echo -e "${PURPLE}[ DNS RESPONSE TIME TEST ]${NC}"
    best_server=""
    best_time=999
    
    for dns_entry in "${dns_servers[@]}"; do
        ip="${dns_entry%:*}"
        name="${dns_entry#*:}"
        
        echo -ne "  ${name}: "
        
        # Measure response time
        start_time=$(date +%s%3N)
        if timeout 2 ping -c 1 -W 1 $ip &> /dev/null; then
            end_time=$(date +%s%3N)
            response_time=$((end_time - start_time))
            
            if [ $response_time -lt $best_time ]; then
                best_time=$response_time
                best_server="$name ($ip)"
            fi
            
            echo -e "${GREEN}${response_time}ms${NC}"
        else
            echo -e "${RED}TIMEOUT${NC}"
        fi
    done
    
    echo ""
    echo -e "${PURPLE}[ RECOMMENDATIONS ]${NC}"
    echo -e "  ${GREEN}Fastest DNS: ${best_server}${NC}"
    echo -e "  ${YELLOW}Response time: ${best_time}ms${NC}"
    
    echo ""
    echo -e "${WHITE}To apply these settings in Termux:${NC}"
    echo "  echo 'nameserver 8.8.8.8' > /data/data/com.termux/files/usr/etc/resolv.conf"
    echo "  echo 'nameserver 1.1.1.1' >> /data/data/com.termux/files/usr/etc/resolv.conf"
}

# Main execution
main() {
    print_banner
    check_termux
    check_dependencies
    
    while true; do
        show_menu
        read -p "Select option (1-6): " choice
        
        case $choice in
            1)
                show_network_info
                ;;
            2)
                scan_all_mtu
                ;;
            3)
                quick_mtu_test
                ;;
            4)
                test_specific_mtu
                ;;
            5)
                optimize_dns
                ;;
            6)
                echo ""
                echo -e "${GREEN}🇹🇿 Asante kwa kutumia Termux MTU Scanner! 🇹🇿${NC}"
                echo ""
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option! Please select 1-6${NC}"
                ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
        clear
        print_banner
    done
}

# Handle Ctrl+C
trap 'echo -e "\n${RED}Script interrupted. Kwaheri! 🇹🇿${NC}"; exit 1' INT

# Run main function
main
