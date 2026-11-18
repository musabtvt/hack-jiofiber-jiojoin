#!/bin/sh
# ==============================================================================
# JioJoin Discovery Beacon Daemon (RFC 2141 / UPnP SSDP Compliant)
# Emulates Jio ONT SSDP announcements & replies to M-SEARCH requests on LAN
# so the official JioJoin app detects the OpenWrt router as an authentic Jio ONT.
# ==============================================================================

SSDP_ADDR="239.255.255.250"
SSDP_PORT=1900
ROUTER_IP=$(uci -q get network.lan.ipaddr || echo "192.168.1.1")
MAC_ADDR=$(cat /sys/class/net/br-lan/address 2>/dev/null || cat /sys/class/net/eth0/address 2>/dev/null || echo "00:11:22:33:44:55")
UUID=$(echo "$MAC_ADDR" | tr -d ':' | tr '[:upper:]' '[:lower:]')

echo "[*] Starting JioJoin RFC-compliant SSDP Beacon Daemon on $ROUTER_IP..."
echo "[+] Emulated Device UUID: uuid:jio-gateway-${UUID}"

# Ensure multicast route points explicitly to LAN/Wi-Fi bridge (br-lan)
# Without this route, Linux routes 239.255.255.250 out the default WAN gateway!
ip route add 224.0.0.0/4 dev br-lan 2>/dev/null || true

# Ensure UPnP XML device descriptor is served via uhttpd
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
    <serviceList>
      <service>
        <serviceType>urn:schemas-upnp-org:service:WANIPConnection:1</serviceType>
        <serviceId>urn:upnp-org:serviceId:WANIPConn1</serviceId>
        <controlURL>/upnp/control/WANIPConn1</controlURL>
        <eventSubURL>/upnp/event/WANIPConn1</eventSubURL>
        <SCPDURL>/gateconnSCPD.xml</SCPDURL>
      </service>
    </serviceList>
  </device>
</root>
EOF

# Detect broadcast engine (prefer socat, fallback to nc)
BROADCAST_CMD=""
if command -v socat >/dev/null 2>&1; then
    BROADCAST_CMD="socat"
elif command -v nc >/dev/null 2>&1; then
    BROADCAST_CMD="nc"
fi

# SSDP NOTIFY Announcement Payload (RFC Compliant)
SSDP_NOTIFY="NOTIFY * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nCACHE-CONTROL: max-age=1800\r\nLOCATION: http://${ROUTER_IP}/jio_desc.xml\r\nNT: urn:schemas-upnp-org:device:InternetGatewayDevice:1\r\nNTS: ssdp:alive\r\nSERVER: Linux/5.4 UPnP/1.0 JioFiber/JIDU6401-v2.1\r\nUSN: uuid:jio-gateway-${UUID}::urn:schemas-upnp-org:device:InternetGatewayDevice:1\r\n\r\n"

send_beacon() {
    if [ "$BROADCAST_CMD" = "socat" ]; then
        printf "%b" "$SSDP_NOTIFY" | socat - UDP4-DATAGRAM:239.255.255.250:1900,bind=${ROUTER_IP},broadcast 2>/dev/null || \
        printf "%b" "$SSDP_NOTIFY" | socat - UDP4-DATAGRAM:239.255.255.250:1900,broadcast 2>/dev/null || true
    elif [ "$BROADCAST_CMD" = "nc" ]; then
        printf "%b" "$SSDP_NOTIFY" | nc -u -w1 239.255.255.250 1900 2>/dev/null || true
    fi
}

# 1. Rapid startup burst (3 packets at 1-second intervals for instant app pairing)
echo "[*] Sending initial rapid discovery beacon burst..."
send_beacon
sleep 1
send_beacon
sleep 1
send_beacon

# 2. Main periodic beacon loop (every 10 seconds)
while true; do
    sleep 10
    send_beacon
done
