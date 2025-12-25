#!/bin/bash
echo "Testing optimal MTU for your network..."
for mtu in 512 1024 1232 1452 1500; do
    echo -n "MTU $mtu: "
    ping -M do -s $(($mtu-28)) -c 2 google.com 2>/dev/null | grep -q "Frag" && echo "Fragments" || echo "OK"
done
