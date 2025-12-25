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
        if ping -M do -s $payload_size -c 2 -W 2 $server 2>/dev/null | grep -q "Frag needed"; then
            return 1  # Fragmentation detected
        fi
    done
    
    return 0  # No fragmentation
}

# Main test function
run_mtu_test() {
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}    T E S T I N G   M T U   S I Z E S${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Test common DNS MTU sizes
    local mtu_sizes=(512 768 1024 1232 1400 1452 1472 1500)
    local working_mtus=()
    
    echo -e "${YELLOW}Testing MTU sizes (this may take a moment)...${NC}"
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
    
    if [ $max_mtu -ge 1452 ]; then
        echo -e "${GREEN}➤ RECOMMENDED: Use MTU 1452${NC}"
        echo "   Speed: 2.8-3x faster than 512 MTU"
        echo "   Status: Maximum performance"
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
        echo "   Speed: 1.8-2x faster than 512 MTU"
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

# Quick test function
quick_test() {
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}    Q U I C K   T E S T${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Test only key MTU sizes
    local quick_mtus=(512 1024 1232 1452)
    
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
    echo -e "${GREEN}1.${NC} Run full MTU test"
    echo -e "${GREEN}2.${NC} Run quick test (512, 1024, 1232, 1452)"
    echo -e "${GREEN}3.${NC} Test specific MTU size"
    echo -e "${GREEN}4.${NC} Show current network info"
    echo -e "${GREEN}5.${NC} Exit"
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Test specific MTU
test_specific_mtu() {
    echo ""
    echo -e "${YELLOW}Enter MTU size to test (68-1500):${NC}"
    read -p "MTU: " custom_mtu
    
    # Validate input
    if ! [[ "$custom_mtu" =~ ^[0-9]+$ ]] || [ $custom_mtu -lt 68 ] || [ $custom_mtu -gt 1500 ]; then
        echo -e "${RED}Invalid MTU! Must be between 68 and 1500${NC}"
        return
    fi
    
    echo ""
    echo -ne "${BLUE}[*]${NC} Testing MTU ${WHITE}$custom_mtu${NC}: "
    
    if test_mtu_size $custom_mtu; then
        echo -e "${GREEN}✓ WORKING${NC}"
        
        # Calculate recommended DNS MTU
        local dns_mtu=$((custom_mtu - 48))  # Leave room for headers
        if [ $dns_mtu -lt 512 ]; then
            dns_mtu=512
        fi
        
        echo ""
        echo -e "${YELLOW}Recommended DNS MTU: $dns_mtu${NC}"
    else
        echo -e "${RED}✗ FRAGMENTS${NC}"
    fi
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
        read -p "Select option (1-5): " choice
        
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
                echo ""
                echo -e "${GREEN}Thank you for using Termux MTU Checker!${NC}"
                echo ""
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option! Please select 1-5${NC}"
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
