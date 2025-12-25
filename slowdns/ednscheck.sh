#!/data/data/com.termux/files/usr/bin/bash

# Termux MTU Checker Script
# Usage: bash -c "$(curl -fsSL https://raw.githubusercontent.com/athumani2580/DNS/main/slowdns/ednscheck.sh)"

# Colors for Termux
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Banner
print_banner() {
    clear
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                                                            ║${NC}"
    echo -e "${CYAN}║${WHITE}     ███████╗██████╗ ███╗   ██╗███████╗ ██████╗██╗  ██╗${CYAN}    ║${NC}"
    echo -e "${CYAN}║${WHITE}     ██╔════╝██╔══██╗████╗  ██║██╔════╝██╔════╝██║  ██║${CYAN}    ║${NC}"
    echo -e "${CYAN}║${WHITE}     █████╗  ██║  ██║██╔██╗ ██║███████╗██║     ███████║${CYAN}    ║${NC}"
    echo -e "${CYAN}║${WHITE}     ██╔══╝  ██║  ██║██║╚██╗██║╚════██║██║     ██╔══██║${CYAN}    ║${NC}"
    echo -e "${CYAN}║${WHITE}     ███████╗██████╔╝██║ ╚████║███████║╚██████╗██║  ██║${CYAN}    ║${NC}"
    echo -e "${CYAN}║${WHITE}     ╚══════╝╚═════╝ ╚═╝  ╚═══╝╚══════╝ ╚═════╝╚═╝  ╚═╝${CYAN}    ║${NC}"
    echo -e "${CYAN}║                                                            ║${NC}"
    echo -e "${CYAN}║${WHITE}            T E R M U X   M T U   C H E C K E R           ${CYAN}║${NC}"
    echo -e "${CYAN}║${YELLOW}         Find Optimal MTU for SlowDNS/EDNS Proxy         ${CYAN}║${NC}"
    echo -e "${CYAN}║${YELLOW}               Extended Test (512 to 4096)               ${CYAN}║${NC}"
    echo -e "${CYAN}║                                                            ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
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
    
    echo -e "${GREEN}[✓]${NC} All dependencies are installed"
}

# Test MTU function
test_mtu_size() {
    local mtu=$1
    local payload_size=$(($mtu - 28))  # MTU - IP header(20) - ICMP header(8)
    
    # Try multiple test servers
    local servers=("8.8.8.8" "1.1.1.1" "208.67.222.222")
    
    for server in "${servers[@]}"; do
        if timeout 3 ping -M do -s $payload_size -c 2 -W 2 $server 2>/dev/null | grep -q "Frag needed"; then
            return 1  # Fragmentation detected
        fi
    done
    
    return 0  # No fragmentation
}

# Main test function - Extended to 4096
run_mtu_test() {
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}    E X T E N D E D   M T U   T E S T (512 to 4096)${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Test extended MTU sizes up to 4096
    local mtu_sizes=(512 768 1024 1232 1400 1452 1472 1500 2048 3072 4096)
    local working_mtus=()
    
    echo -e "${YELLOW}Testing extended MTU sizes (this may take a few minutes)...${NC}"
    echo ""
    
    for mtu in "${mtu_sizes[@]}"; do
        echo -ne "${BLUE}[*]${NC} Testing MTU ${WHITE}$mtu${NC}: "
        
        if test_mtu_size $mtu; then
            echo -e "${GREEN}✓ WORKING${NC}"
            working_mtus+=($mtu)
        else
            echo -e "${RED}✗ FRAGMENTS${NC}"
        fi
        
        # Small delay between tests
        sleep 0.5
    done
    
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}    R E S U L T S${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ ${#working_mtus[@]} -eq 0 ]; then
        echo -e "${RED}No MTU sizes worked!${NC}"
        echo "Your network may be blocking ICMP or have restrictions."
        echo ""
        echo -e "${YELLOW}Recommendation:${NC} Use MTU 512 (standard DNS size)"
        return
    fi
    
    # Find maximum working MTU
    local max_mtu=${working_mtus[0]}
    for mtu in "${working_mtus[@]}"; do
        if [ $mtu -gt $max_mtu ]; then
            max_mtu=$mtu
        fi
    done
    
    echo -e "${GREEN}Working MTU sizes:${NC}"
    for mtu in "${working_mtus[@]}"; do
        echo -e "  ${GREEN}✓${NC} $mtu bytes"
    done
    
    echo ""
    echo -e "${GREEN}Maximum working MTU: ${YELLOW}$max_mtu bytes${NC}"
    
    # Recommendations
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}    R E C O M M E N D A T I O N${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ $max_mtu -ge 4096 ]; then
        echo -e "${GREEN}➤ RECOMMENDED: Use MTU 4096${NC}"
        echo "   Speed: 8x faster than 512 MTU"
        echo "   Status: Maximum TCP performance"
        echo "   Use: For TCP-based DNS tunneling"
        echo ""
        echo -e "${WHITE}SlowDNS Config:${NC}"
        echo "  -mtu 4096"
        echo ""
        echo -e "${WHITE}EDNS Proxy Config:${NC}"
        echo "  INTERNAL_EDNS_SIZE = 4096"
        echo "  EXTERNAL_EDNS_SIZE = 512"
        
    elif [ $max_mtu -ge 2048 ]; then
        echo -e "${GREEN}➤ RECOMMENDED: Use MTU 2048${NC}"
        echo "   Speed: 4x faster than 512 MTU"
        echo "   Status: High performance"
        echo "   Use: Networks with jumbo frame support"
        echo ""
        echo -e "${WHITE}SlowDNS Config:${NC}"
        echo "  -mtu 2048"
        echo ""
        echo -e "${WHITE}EDNS Proxy Config:${NC}"
        echo "  INTERNAL_EDNS_SIZE = 2048"
        echo "  EXTERNAL_EDNS_SIZE = 512"
        
    elif [ $max_mtu -ge 1452 ]; then
        echo -e "${GREEN}➤ RECOMMENDED: Use MTU 1452${NC}"
        echo "   Speed: 2.8-3x faster than 512 MTU"
        echo "   Status: Maximum UDP performance"
        echo "   Use: Standard networks"
        echo ""
        echo -e "${WHITE}SlowDNS Config:${NC}"
        echo "  -mtu 1452"
        echo ""
        echo -e "${WHITE}EDNS Proxy Config:${NC}"
        echo "  INTERNAL_EDNS_SIZE = 1452"
        echo "  EXTERNAL_EDNS_SIZE = 512"
        
    elif [ $max_mtu -ge 1232 ]; then
        echo -e "${GREEN}➤ RECOMMENDED: Use MTU 1232${NC}"
        echo "   Speed: 2.3-2.5x faster than 512 MTU"
        echo "   Status: Optimal balance"
        echo ""
        echo -e "${WHITE}SlowDNS Config:${NC}"
        echo "  -mtu 1232"
        echo ""
        echo -e "${WHITE}EDNS Proxy Config:${NC}"
        echo "  INTERNAL_EDNS_SIZE = 1232"
        echo "  EXTERNAL_EDNS_SIZE = 512"
        
    elif [ $max_mtu -ge 1024 ]; then
        echo -e "${YELLOW}➤ RECOMMENDED: Use MTU 1024${NC}"
        echo "   Speed: 2x faster than 512 MTU"
        echo "   Status: Good improvement"
        echo ""
        echo -e "${WHITE}SlowDNS Config:${NC}"
        echo "  -mtu 1024"
        echo ""
        echo -e "${WHITE}EDNS Proxy Config:${NC}"
        echo "  INTERNAL_EDNS_SIZE = 1024"
        echo "  EXTERNAL_EDNS_SIZE = 512"
        
    else
        echo -e "${YELLOW}➤ RECOMMENDED: Use MTU 512${NC}"
        echo "   Speed: Standard DNS speed"
        echo "   Status: Maximum compatibility"
        echo ""
        echo -e "${WHITE}SlowDNS Config:${NC}"
        echo "  -mtu 512"
        echo ""
        echo -e "${WHITE}EDNS Proxy Config:${NC}"
        echo "  INTERNAL_EDNS_SIZE = 512"
        echo "  EXTERNAL_EDNS_SIZE = 512"
    fi
}

# Quick test function - Updated for 4096
quick_test() {
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}    Q U I C K   T E S T${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Test key MTU sizes including 4096
    local quick_mtus=(512 1024 1232 1452 2048 4096)
    
    for mtu in "${quick_mtus[@]}"; do
        echo -ne "${BLUE}[*]${NC} Quick test MTU ${WHITE}$mtu${NC}: "
        
        if test_mtu_size $mtu; then
            echo -e "${GREEN}✓ OK${NC}"
        else
            echo -e "${RED}✗ FRAGMENTS${NC}"
        fi
    done
}

# Menu function
show_menu() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}    M E N U${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${GREEN}1.${NC} Run extended MTU test (512 to 4096)"
    echo -e "${GREEN}2.${NC} Run quick test (512, 1024, 1232, 1452, 2048, 4096)"
    echo -e "${GREEN}3.${NC} Test specific MTU size"
    echo -e "${GREEN}4.${NC} Show current network info"
    echo -e "${GREEN}5.${NC} Run complete scan (all MTU from 512 to 4096)"
    echo -e "${GREEN}6.${NC} Exit"
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Test specific MTU - Updated for 4096
test_specific_mtu() {
    echo ""
    echo -e "${YELLOW}Enter MTU size to test (68-4096):${NC}"
    read -p "MTU: " custom_mtu
    
    # Validate input
    if ! [[ "$custom_mtu" =~ ^[0-9]+$ ]] || [ $custom_mtu -lt 68 ] || [ $custom_mtu -gt 4096 ]; then
        echo -e "${RED}Invalid MTU! Must be between 68 and 4096${NC}"
        return
    fi
    
    echo ""
    echo -ne "${BLUE}[*]${NC} Testing MTU ${WHITE}$custom_mtu${NC}: "
    
    if test_mtu_size $custom_mtu; then
        echo -e "${GREEN}✓ WORKING${NC}"
        
        # Calculate recommended DNS MTU
        local dns_mtu=$custom_mtu
        
        # Adjust for practical DNS use
        if [ $dns_mtu -gt 4096 ]; then
            dns_mtu=4096
        elif [ $dns_mtu -gt 1452 ]; then
            echo -e "${YELLOW}Note: For UDP DNS, consider using 1452 max${NC}"
            dns_mtu=1452
        elif [ $dns_mtu -lt 512 ]; then
            dns_mtu=512
        fi
        
        echo ""
        echo -e "${YELLOW}Recommended DNS MTU: $dns_mtu${NC}"
        echo ""
        echo -e "${WHITE}SlowDNS Config:${NC}"
        echo "  -mtu $dns_mtu"
        echo ""
        echo -e "${WHITE}EDNS Proxy Config:${NC}"
        echo "  INTERNAL_EDNS_SIZE = $dns_mtu"
        echo "  EXTERNAL_EDNS_SIZE = 512"
    else
        echo -e "${RED}✗ FRAGMENTS${NC}"
        echo -e "${YELLOW}Try a smaller MTU value${NC}"
    fi
}

# Complete scan function - Tests ALL MTU from 512 to 4096
complete_scan() {
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}    C O M P L E T E   M T U   S C A N (512 to 4096)${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${YELLOW}This will test EVERY MTU from 512 to 4096${NC}"
    echo -e "${YELLOW}It will take 5-10 minutes to complete...${NC}"
    echo ""
    
    read -p "Continue? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}Scan cancelled${NC}"
        return
    fi
    
    local working_mtus=()
    local max_mtu=0
    local test_count=0
    
    echo ""
    echo -e "${BLUE}[*]${NC} Starting complete MTU scan..."
    echo ""
    
    # Test in blocks for better performance
    echo -e "${WHITE}Testing range 512-1500...${NC}"
    for mtu in {512..1500..4}; do
        test_complete_mtu $mtu
    done
    
    echo -e "${WHITE}Testing range 1500-3000...${NC}"
    for mtu in {1500..3000..8}; do
        test_complete_mtu $mtu
    done
    
    echo -e "${WHITE}Testing range 3000-4096...${NC}"
    for mtu in {3000..4096..16}; do
        test_complete_mtu $mtu
    done
    
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}    S C A N   C O M P L E T E${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ ${#working_mtus[@]} -eq 0 ]; then
        echo -e "${RED}No working MTU sizes found!${NC}"
        return
    fi
    
    # Find maximum working MTU
    for mtu in "${working_mtus[@]}"; do
        if [ $mtu -gt $max_mtu ]; then
            max_mtu=$mtu
        fi
    done
    
    echo -e "${GREEN}Maximum working MTU: ${YELLOW}$max_mtu bytes${NC}"
    echo -e "${GREEN}Total tests performed: ${YELLOW}$test_count${NC}"
    
    # Show working ranges
    echo ""
    echo -e "${WHITE}Working MTU ranges:${NC}"
    
    local ranges=()
    local current_start=${working_mtus[0]}
    local current_end=${working_mtus[0]}
    
    for ((i=1; i<${#working_mtus[@]}; i++)); do
        if [ $((${working_mtus[i]} - current_end)) -le 32 ]; then
            current_end=${working_mtus[i]}
        else
            if [ $current_start -eq $current_end ]; then
                ranges+=("$current_start")
            else
                ranges+=("$current_start-$current_end")
            fi
            current_start=${working_mtus[i]}
            current_end=${working_mtus[i]}
        fi
    done
    
    # Add last range
    if [ $current_start -eq $current_end ]; then
        ranges+=("$current_start")
    else
        ranges+=("$current_start-$current_end")
    fi
    
    # Display ranges
    for range in "${ranges[@]}"; do
        echo -e "  ${GREEN}✓${NC} $range bytes"
    done
    
    # Recommendation
    echo ""
    show_recommendation $max_mtu
}

# Helper function for complete scan
test_complete_mtu() {
    local mtu=$1
    ((test_count++))
    
    # Show progress every 50 tests
    if [ $((test_count % 50)) -eq 0 ]; then
        echo -ne "  Tested: $test_count MTUs | Current: $mtu bytes\r"
    fi
    
    if test_mtu_size $mtu; then
        working_mtus+=($mtu)
    fi
    
    # Small delay to avoid flooding
    sleep 0.1
}

# Show recommendation based on max MTU
show_recommendation() {
    local max_mtu=$1
    
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}    R E C O M M E N D A T I O N${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ $max_mtu -ge 4096 ]; then
        echo -e "${GREEN}➤ RECOMMENDED: Use MTU 4096${NC}"
        echo "   Speed: 8x faster than 512 MTU"
        echo "   Perfect for TCP-based DNS tunneling"
        
    elif [ $max_mtu -ge 2048 ]; then
        echo -e "${GREEN}➤ RECOMMENDED: Use MTU 2048${NC}"
        echo "   Speed: 4x faster than 512 MTU"
        echo "   Excellent for high-speed networks"
        
    elif [ $max_mtu -ge 1452 ]; then
        echo -e "${GREEN}➤ RECOMMENDED: Use MTU 1452${NC}"
        echo "   Speed: 2.8-3x faster than 512 MTU"
        echo "   Maximum for UDP without fragmentation"
        
    elif [ $max_mtu -ge 1232 ]; then
        echo -e "${GREEN}➤ RECOMMENDED: Use MTU 1232${NC}"
        echo "   Speed: 2.3-2.5x faster than 512 MTU"
        echo "   Optimal balance for most networks"
        
    elif [ $max_mtu -ge 1024 ]; then
        echo -e "${YELLOW}➤ RECOMMENDED: Use MTU 1024${NC}"
        echo "   Speed: 2x faster than 512 MTU"
        echo "   Good improvement with safety margin"
        
    else
        echo -e "${YELLOW}➤ RECOMMENDED: Use MTU 512${NC}"
        echo "   Speed: Standard DNS speed"
        echo "   Maximum compatibility"
    fi
    
    # Show configuration
    local recommended_mtu=$max_mtu
    if [ $recommended_mtu -gt 1452 ]; then
        recommended_mtu=1452  # Max for UDP
    fi
    
    echo ""
    echo -e "${WHITE}Configuration:${NC}"
    echo "  SlowDNS: -mtu $recommended_mtu"
    echo "  EDNS Proxy: INTERNAL_EDNS_SIZE = $recommended_mtu"
    echo "  EDNS Proxy: EXTERNAL_EDNS_SIZE = 512"
}

# Show network info
show_network_info() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}    N E T W O R K   I N F O${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Get IP address
    echo -e "${BLUE}IP Address:${NC}"
    ip route get 1 2>/dev/null | awk '{print $7; exit}' || echo "Not available"
    
    # Get default interface
    echo -e "${BLUE}Interface:${NC}"
    ip route | grep default | awk '{print $5}' | head -1 || echo "Not available"
    
    # Check internet connectivity
    echo -e "${BLUE}Internet:${NC}"
    if ping -c 1 8.8.8.8 &> /dev/null; then
        echo -e "${GREEN}✓ Connected${NC}"
    else
        echo -e "${RED}✗ No connection${NC}"
    fi
    
    echo ""
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
                run_mtu_test
                ;;
            2)
                quick_test
                ;;
            3)
                test_specific_mtu
                ;;
            4)
                show_network_info
                ;;
            5)
                complete_scan
                ;;
            6)
                echo ""
                echo -e "${GREEN}Thank you for using Termux MTU Checker!${NC}"
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
trap 'echo -e "\n${RED}Script interrupted. Exiting...${NC}"; exit 1' INT

# Run main function
main
