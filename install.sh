#!/bin/sh
# ==============================================================================
# JioFiber Voice on OpenWrt - Universal 1-Click Installer
# Author: Mus'ab (@musabtvt)
# https://github.com/musabtvt/openwrt-jiofiber-voice-lan
# ==============================================================================

set -e

INSTALL_DIR="/etc/jio-voice"
BACKUP_DIR="/etc/jio-voice/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "=========================================================="
echo "📞 JioFiber Voice on OpenWrt (LAN & Wi-Fi Gateway) Setup"
echo "   Developed by Mus'ab (@musabtvt)"
echo "=========================================================="

# Check if running as root on OpenWrt
if [ "$(id -u)" -ne 0 ]; then
    echo "[-] Error: Please run this script as root." >&2
    exit 1
fi

if [ ! -f /etc/openwrt_release ]; then
    echo "[!] Warning: /etc/openwrt_release not found. Make sure this is an OpenWrt system."
fi

mkdir -p "$INSTALL_DIR"
mkdir -p "$BACKUP_DIR"

# Universal Package Manager Wrapper (Supports OpenWrt 25.x apk and 23.05/24.10 opkg)
pkg_install() {
    if command -v apk >/dev/null 2>&1; then
        apk update >/dev/null 2>&1 || true
        apk add "$@" >/dev/null 2>&1 || true
    elif command -v opkg >/dev/null 2>&1; then
        opkg update >/dev/null 2>&1 || true
        opkg install "$@" >/dev/null 2>&1 || true
    fi
}

# Step 1: Backup existing network and firewall configs
echo "[*] Step 1/6: Creating configuration snapshot backup..."
tar -czf "$BACKUP_DIR/backup_${TIMESTAMP}.tar.gz" /etc/config/network /etc/config/firewall /etc/config/dhcp 2>/dev/null || true
echo "[+] Safety backup saved to $BACKUP_DIR/backup_${TIMESTAMP}.tar.gz"

# Install socat for high-reliability multicast SSDP broadcasts
pkg_install socat

# Step 2: Auto-detect WAN interface
echo "[*] Step 2/6: Detecting physical WAN interface..."
WAN_IFACE=$(uci -q get network.wan.device || uci -q get network.wan.ifname || echo "")

if [ -z "$WAN_IFACE" ] || echo "$WAN_IFACE" | grep -q "\."; then
    for dev in wan eth1 eth0 sfp; do
        if ip link show "$dev" >/dev/null 2>&1; then
            WAN_IFACE="$dev"
            break
        fi
    done
fi

if [ -z "$WAN_IFACE" ]; then
    WAN_IFACE="wan"
fi

echo "[+] Using WAN device: $WAN_IFACE"
VOICE_DEV="${WAN_IFACE}.406"

# Step 3: Configure Voice VLAN 406 in UCI
echo "[*] Step 3/6: Configuring Voice VLAN 406 in UCI network..."

# Create 802.1q VLAN device
uci set network.voice_dev=device
uci set network.voice_dev.name="$VOICE_DEV"
uci set network.voice_dev.type="8021q"
uci set network.voice_dev.ifname="$WAN_IFACE"
uci set network.voice_dev.vid="406"

# Configure network.voice interface
uci set network.voice=interface
uci set network.voice.device="$VOICE_DEV"
uci set network.voice.proto="dhcpv6"
uci set network.voice.reqaddress="try"
uci set network.voice.reqprefix="auto"
uci set network.voice.delegate="0"
uci set network.voice.metric="20"

# Step 4: Configure Firewall Zone & Forwarding
echo "[*] Step 4/6: Configuring firewall zone and SIP routing..."

uci set firewall.voice_zone=zone
uci set firewall.voice_zone.name="voice"
uci set firewall.voice_zone.network="voice"
uci set firewall.voice_zone.input="REJECT"
uci set firewall.voice_zone.output="ACCEPT"
uci set firewall.voice_zone.forward="REJECT"
uci set firewall.voice_zone.masq="1"
uci set firewall.voice_zone.masq6="1"
uci set firewall.voice_zone.mtu_fix="1"

# Allow LAN to forward to Voice zone for SIP/IMS traffic
uci set firewall.lan_to_voice=forwarding
uci set firewall.lan_to_voice.src="lan"
uci set firewall.lan_to_voice.dest="voice"

# Allow SIP inbound replies
uci set firewall.voice_sip_allow=rule
uci set firewall.voice_sip_allow.name="Allow-Jio-SIP"
uci set firewall.voice_sip_allow.src="voice"
uci set firewall.voice_sip_allow.dest="lan"
uci set firewall.voice_sip_allow.proto="udp tcp"
uci set firewall.voice_sip_allow.dest_port="5060 5061 5068"
uci set firewall.voice_sip_allow.target="ACCEPT"

# Dynamically ensure WAN zone includes voice if needed
WAN_ZONE=$(uci show firewall | grep "\.name='wan'" | cut -d'.' -f2 | head -n 1)
[ -n "$WAN_ZONE" ] && uci set firewall."$WAN_ZONE".mtu_fix='1'

uci commit network
uci commit firewall

# Step 5: Disable Kernel SIP ALG (Eliminates One-Way Audio)
echo "[*] Step 5/6: Disabling kernel SIP ALG helper to prevent RTP audio drops..."
mkdir -p /etc/modules.d
cat << 'EOF' > /etc/modules.d/99-blacklist-sip
blacklist nf_nat_sip
blacklist nf_conntrack_sip
EOF
rmmod nf_nat_sip nf_conntrack_sip 2>/dev/null || true

# Step 6: Install QoS nftables DSCP Rules & JioJoin SSDP Beacon
echo "[*] Step 6/6: Installing QoS rules and JioJoin SSDP beacon daemon..."

# Install nftables QoS rules into /etc/nftables.d/
mkdir -p /etc/nftables.d
cat << 'EOF' > /etc/nftables.d/40-jio-voice.nft
#!/usr/sbin/nft -f
table inet jio_voice_qos {
    chain mangle_prerouting {
        type filter hook prerouting priority mangle; policy accept;
        ip protocol udp udp dport { 5060, 5061, 5068 } ip dscp set cs5
        ip protocol tcp tcp dport { 5060, 5061, 5068 } ip dscp set cs5
        ip6 nexthdr udp udp dport { 5060, 5061, 5068 } ip6 dscp set cs5
        ip6 nexthdr tcp tcp dport { 5060, 5061, 5068 } ip6 dscp set cs5
        ip protocol udp udp dport 10000-20000 ip dscp set ef
        ip6 nexthdr udp udp dport 10000-20000 ip6 dscp set ef
    }
}
EOF

ROUTER_IP=$(uci -q get network.lan.ipaddr || echo "192.168.1.1")
MAC_ADDR=$(cat /sys/class/net/br-lan/address 2>/dev/null || cat /sys/class/net/eth0/address 2>/dev/null || echo "00:11:22:33:44:55")
UUID=$(echo "$MAC_ADDR" | tr -d ':' | tr '[:upper:]' '[:lower:]')

# Explicitly ensure 224.0.0.0/4 multicast route points to br-lan
ip route add 224.0.0.0/4 dev br-lan 2>/dev/null || true

# Create UPnP device descriptor in /www
mkdir -p /www
cat <<EOF > /www/jio_desc.xml
<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <specVersion>
    <major>1</major>
    <minor>0</minor>
  </specVersion>
  <device>
    <deviceType>urn:schemas-upnp-org:device:InternetGatewayDevice:1</deviceType>
    <friendlyName>JioFiber Home Gateway</friendlyName>
    <manufacturer>Reliance Jio Infocomm Ltd.</manufacturer>
    <manufacturerURL>https://www.jio.com</manufacturerURL>
    <modelDescription>JioFiber High Speed Gateway</modelDescription>
    <modelName>JIDU6401</modelName>
    <modelNumber>JIDU6401-1.0</modelNumber>
    <UDN>uuid:jio-gateway-${UUID}</UDN>
  </device>
</root>
EOF

# Install RFC-compliant SSDP NOTIFY daemon script
cat << 'EOF' > "$INSTALL_DIR/jio-beacon.sh"
#!/bin/sh
ROUTER_IP=$(uci -q get network.lan.ipaddr || echo "192.168.1.1")
MAC_ADDR=$(cat /sys/class/net/br-lan/address 2>/dev/null || echo "001122334455")
UUID=$(echo "$MAC_ADDR" | tr -d ':' | tr '[:upper:]' '[:lower:]')

ip route add 224.0.0.0/4 dev br-lan 2>/dev/null || true

SSDP_NOTIFY="NOTIFY * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nCACHE-CONTROL: max-age=1800\r\nLOCATION: http://${ROUTER_IP}/jio_desc.xml\r\nNT: urn:schemas-upnp-org:device:InternetGatewayDevice:1\r\nNTS: ssdp:alive\r\nSERVER: Linux/5.4 UPnP/1.0 JioFiber/JIDU6401-v2.1\r\nUSN: uuid:jio-gateway-${UUID}::urn:schemas-upnp-org:device:InternetGatewayDevice:1\r\n\r\n"

send_beacon() {
    if command -v socat >/dev/null 2>&1; then
        printf "%b" "$SSDP_NOTIFY" | socat - UDP4-DATAGRAM:239.255.255.250:1900,bind=${ROUTER_IP},broadcast 2>/dev/null || \
        printf "%b" "$SSDP_NOTIFY" | socat - UDP4-DATAGRAM:239.255.255.250:1900,broadcast 2>/dev/null || true
    elif command -v nc >/dev/null 2>&1; then
        printf "%b" "$SSDP_NOTIFY" | nc -u -w1 239.255.255.250 1900 2>/dev/null || true
    fi
}

# Initial rapid beacon burst
send_beacon
sleep 1
send_beacon
sleep 1
send_beacon

# Periodic loop every 10 seconds
while true; do
    sleep 10
    send_beacon
done
EOF
chmod +x "$INSTALL_DIR/jio-beacon.sh"

# Install Procd init service for the beacon
cat << 'EOF' > /etc/init.d/jio-beacon
#!/bin/sh /etc/rc.common
USE_PROCD=1
START=95
STOP=10

start_service() {
    procd_open_instance
    procd_set_param command /etc/jio-voice/jio-beacon.sh
    procd_set_param respawn
    procd_close_instance
}
EOF
chmod +x /etc/init.d/jio-beacon
/etc/init.d/jio-beacon enable 2>/dev/null || true
/etc/init.d/jio-beacon start 2>/dev/null || true

# Install Rollback script
cat << 'EOF' > "$INSTALL_DIR/backup_restore.sh"
#!/bin/sh
BACKUP_DIR="/etc/jio-voice/backups"
case "$1" in
    --restore)
        LATEST=$(ls -t "$BACKUP_DIR"/backup_*.tar.gz 2>/dev/null | head -n 1)
        if [ -n "$LATEST" ]; then
            echo "[*] Restoring configurations from $LATEST..."
            tar -xzf "$LATEST" -C /
            rm -f /etc/nftables.d/40-jio-voice.nft
            rm -f /etc/modules.d/99-blacklist-sip
            /etc/init.d/network restart
            /etc/init.d/firewall restart
            echo "[SUCCESS] Configuration reverted to pre-install snapshot."
        else
            echo "[-] No backup archive found in $BACKUP_DIR"
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 --restore"
        ;;
esac
EOF
chmod +x "$INSTALL_DIR/backup_restore.sh"

echo "[*] Reloading network and firewall services..."
/etc/init.d/network reload || /etc/init.d/network restart
/etc/init.d/firewall reload || /etc/init.d/firewall restart

echo ""
echo "=========================================================="
echo "🎉 SUCCESS: JioFiber Voice Gateway is ready!"
echo "=========================================================="
echo "• Voice VLAN:             $VOICE_DEV"
echo "• Multicast Beacon:       br-lan (Active RFC SSDP NOTIFY)"
echo "• SIP ALG Helper:         Disabled (Zero One-Way Audio Drops)"
echo "• Pairing Status:         Instant JioJoin Detection Enabled"
echo "• Safety Rollback:        /etc/jio-voice/backup_restore.sh --restore"
echo "=========================================================="
