#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Test MTU sizes (common DNS MTU values)
MTU_VALUES=(512 768 1024 1232 1400 1452 1472 1500)

# Title
echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}    N E T W O R K   M T U   T E S T   S C R I P T${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Testing which MTU sizes work without fragmentation...${NC}"
echo ""

# Function to test MTU
test_mtu() {
    local mtu=$1
    local data_size=$(($mtu - 28))  # MTU - IP header(20) - ICMP header(8)
    
    # Try to ping with this MTU
    echo -n "MTU $mtu: "
    
    # Test with google.com first
    if ping -M do -s $data_size -c 2 -W 1 google.com 2>/dev/null | grep -q "Frag needed"; then
        echo -e "${RED}FRAGMENTS${NC} (Packets will fragment)"
        return 1
    elif ping -M do -s $data_size -c 2 -W 1 google.com 2>/dev/null | grep -q "0 received"; then
        echo -e "${RED}FAILED${NC} (No response)"
        return 1
    else
        echo -e "${GREEN}OK${NC} (No fragmentation)"
        return 0
    fi
}

# Test all MTU values
echo -e "${BLUE}Testing MTU sizes...${NC}"
echo ""

working_mtus=()
for mtu in "${MTU_VALUES[@]}"; do
    if test_mtu $mtu; then
        working_mtus+=($mtu)
    fi
done

echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}    R E S U L T S${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo ""

if [ ${#working_mtus[@]} -eq 0 ]; then
    echo -e "${RED}No MTU sizes worked! Network may have issues.${NC}"
    echo "Try testing with smaller MTU or check network connectivity."
else
    # Sort working MTUs
    IFS=$'\n' sorted_mtus=($(sort -n <<< "${working_mtus[*]}"))
    unset IFS
    
    # Find maximum working MTU
    max_mtu=${sorted_mtus[-1]}
    
    echo -e "${GREEN}Working MTU sizes:${NC}"
    for mtu in "${sorted_mtus[@]}"; do
        echo -e "  ${GREEN}✓${NC} $mtu bytes"
    done
    
    echo ""
    echo -e "${GREEN}Maximum working MTU: ${YELLOW}$max_mtu bytes${NC}"
    
    # Recommend optimal MTU for DNS
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}    R E C O M M E N D A T I O N S${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ $max_mtu -ge 1452 ]; then
        echo -e "${GREEN}RECOMMENDED: Use MTU 1452${NC}"
        echo "  • Maximum performance for DNS tunneling"
        echo "  • 2.8-3x faster than 512 MTU"
        echo "  • Best for high-speed networks"
    elif [ $max_mtu -ge 1232 ]; then
        echo -e "${GREEN}RECOMMENDED: Use MTU 1232${NC}"
        echo "  • Optimal balance of speed and reliability"
        echo "  • 2.3-2.5x faster than 512 MTU"
        echo "  • Standard for modern DNS"
    elif [ $max_mtu -ge 1024 ]; then
        echo -e "${YELLOW}RECOMMENDED: Use MTU 1024${NC}"
        echo "  • Good improvement over 512"
        echo "  • 1.8-2x faster than 512 MTU"
        echo "  • Safe for most networks"
    else
        echo -e "${YELLOW}RECOMMENDED: Use MTU 512${NC}"
        echo "  • Maximum compatibility"
        echo "  • No fragmentation risk"
        echo "  • Standard DNS size"
    fi
    
    # Show SlowDNS configuration
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}    C O N F I G U R A T I O N${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ $max_mtu -ge 1452 ]; then
        echo "For SlowDNS service:"
        echo "  ExecStart=/etc/slowdns/sldns-server -udp :5300 -mtu 1452 ..."
        echo ""
        echo "For EDNS Proxy Python script:"
        echo "  INTERNAL_EDNS_SIZE = 1452"
        echo "  EXTERNAL_EDNS_SIZE = 512"
    elif [ $max_mtu -ge 1232 ]; then
        echo "For SlowDNS service:"
        echo "  ExecStart=/etc/slowdns/sldns-server -udp :5300 -mtu 1232 ..."
        echo ""
        echo "For EDNS Proxy Python script:"
        echo "  INTERNAL_EDNS_SIZE = 1232"
        echo "  EXTERNAL_EDNS_SIZE = 512"
    else
        echo "For SlowDNS service:"
        echo "  ExecStart=/etc/slowdns/sldns-server -udp :5300 -mtu $max_mtu ..."
        echo ""
        echo "For EDNS Proxy Python script:"
        echo "  INTERNAL_EDNS_SIZE = $max_mtu"
        echo "  EXTERNAL_EDNS_SIZE = 512"
    fi
fi

echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}    A D V A N C E D   T E S T${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo ""

# Optional: Test with traceroute to find path MTU
read -p "Run advanced path MTU discovery? (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Running path MTU discovery...${NC}"
    echo ""
    
    # Test with tracepath to find actual path MTU
    if command -v tracepath &> /dev/null; then
        echo "Path MTU discovery using tracepath:"
        tracepath -n 8.8.8.8 | grep -i pmtu | head -5
    else
        echo "tracepath not available. Install with: apt install iputils-tracepath"
    fi
    
    # Test with multiple targets
    echo ""
    echo -e "${YELLOW}Testing with different targets...${NC}"
    echo ""
    
    TARGETS=("google.com" "cloudflare.com" "1.1.1.1" "8.8.8.8")
    
    for target in "${TARGETS[@]}"; do
        echo -n "Testing $target with MTU $max_mtu: "
        if ping -M do -s $(($max_mtu - 28)) -c 2 -W 1 $target 2>/dev/null | grep -q "Frag needed"; then
            echo -e "${RED}FRAGMENTS${NC}"
        else
            echo -e "${GREEN}OK${NC}"
        fi
    done
fi

echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Test completed!${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo ""
