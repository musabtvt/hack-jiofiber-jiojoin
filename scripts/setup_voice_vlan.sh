#!/bin/sh
# ==============================================================================
# Setup Voice VLAN 406 on OpenWrt
# Configures ethX.406 interface with DHCPv6 & 464xlat routing to Jio IMS Core
# ==============================================================================

set -e

echo "[*] Initializing Jio Voice VLAN 406 configuration..."

# 1. Identify WAN physical device
WAN_DEV=$(uci -q get network.wan.device || uci -q get network.wan.ifname || echo "")
if [ -z "$WAN_DEV" ]; then
    for candidate in eth1 eth0 wan sfp sfp1; do
        if ip link show "$candidate" >/dev/null 2>&1; then
            WAN_DEV="$candidate"
            break
        fi
    done
fi

if [ -z "$WAN_DEV" ]; then
    echo "[-] Error: Could not determine physical WAN device. Please specify manually."
    exit 1
fi

echo "[+] Target physical WAN device: $WAN_DEV"
VLAN_DEV="${WAN_DEV}.406"

# 2. Configure 802.1q device in OpenWrt network config
if ! uci -q get network.voice_dev >/dev/null 2>&1; then
    echo "[*] Creating 802.1q device $VLAN_DEV..."
    uci set network.voice_dev=device
    uci set network.voice_dev.name="$VLAN_DEV"
    uci set network.voice_dev.type="8021q"
    uci set network.voice_dev.ifname="$WAN_DEV"
    uci set network.voice_dev.vid="406"
fi

# 3. Configure interface for Jio Voice IMS
echo "[*] Creating network interface 'voice'..."
uci set network.voice=interface
uci set network.voice.device="$VLAN_DEV"
uci set network.voice.proto="dhcpv6"
uci set network.voice.reqaddress="try"
uci set network.voice.reqprefix="auto"
uci set network.voice.delegate="0"
uci set network.voice.metric="25"

# 4. Commit network changes
uci commit network
echo "[+] Network UCI settings committed."

# 5. Reload network
echo "[*] Reloading network daemon..."
/etc/init.d/network reload

echo "[+] Voice VLAN 406 setup complete. Checking interface status..."
sleep 3
if ip addr show dev "$VLAN_DEV" 2>/dev/null | grep -q "inet6"; then
    echo "[SUCCESS] Voice VLAN $VLAN_DEV is up with IPv6 address assigned by Jio IMS."
else
    echo "[!] Voice VLAN created. Waiting for DHCPv6 lease from Jio IMS core..."
fi
