#!/bin/sh
# ==============================================================================
# Setup Firewall & SIP Traffic Policies for Jio Voice
# Ensures LAN softphones & JioJoin app can communicate with Jio IMS P-CSCF
# ==============================================================================

set -e

echo "[*] Configuring firewall rules for Jio Voice..."

# 1. Create Voice Firewall Zone
if ! uci -q get firewall.voice_zone >/dev/null 2>&1; then
    echo "[*] Creating voice firewall zone..."
    uci set firewall.voice_zone=zone
    uci set firewall.voice_zone.name="voice"
    uci set firewall.voice_zone.network="voice"
    uci set firewall.voice_zone.input="REJECT"
    uci set firewall.voice_zone.output="ACCEPT"
    uci set firewall.voice_zone.forward="REJECT"
    uci set firewall.voice_zone.masq="1"
    uci set firewall.voice_zone.mtu_fix="1"
fi

# 2. Allow LAN -> Voice Zone forwarding
if ! uci -q get firewall.lan_to_voice >/dev/null 2>&1; then
    echo "[*] Creating forwarding rule: lan -> voice..."
    uci set firewall.lan_to_voice=forwarding
    uci set firewall.lan_to_voice.src="lan"
    uci set firewall.lan_to_voice.dest="voice"
fi

# 3. Allow SIP and RTP incoming from voice interface back to established LAN clients
if ! uci -q get firewall.voice_sip_allow >/dev/null 2>&1; then
    uci set firewall.voice_sip_allow=rule
    uci set firewall.voice_sip_allow.name="Allow-Jio-SIP"
    uci set firewall.voice_sip_allow.src="voice"
    uci set firewall.voice_sip_allow.dest="lan"
    uci set firewall.voice_sip_allow.proto="udp tcp"
    uci set firewall.voice_sip_allow.dest_port="5060 5061 5068"
    uci set firewall.voice_sip_allow.target="ACCEPT"
fi

# 4. Install nftables QoS priority rules if fw4 is active
if [ -d /etc/nftables.d ]; then
    echo "[*] Installing nftables DSCP marking rules into /etc/nftables.d/40-jio-voice.nft..."
    SCRIPT_DIR=$(dirname "$0")
    if [ -f "$SCRIPT_DIR/../configs/40-jio-voice.nft" ]; then
        cp "$SCRIPT_DIR/../configs/40-jio-voice.nft" /etc/nftables.d/40-jio-voice.nft
    fi
fi

# 5. Commit and reload firewall
uci commit firewall
echo "[+] Firewall UCI settings committed. Reloading firewall..."
/etc/init.d/firewall reload

echo "[SUCCESS] Firewall rules applied."
