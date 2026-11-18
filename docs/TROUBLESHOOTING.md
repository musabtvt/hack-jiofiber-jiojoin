# 🔧 Troubleshooting Guide: Jio Voice on OpenWrt

Common diagnostic scenarios and solutions when configuring Reliance Jio landline voice on OpenWrt.

---

## 1. No IP Address on Voice Interface (`ethX.406`)

### Symptoms
`ifconfig` or `ip addr show eth0.406` shows no IPv6 address assigned, or DHCPv6 lease stays pending.

### Causes & Fixes
- **Physical Port Tagging**: Ensure VLAN 406 is created on the exact physical interface plugged into the Jio ONT or ODU.
  ```bash
  # Check which physical device carries the WAN link
  ip link show
  ```
- **ODU / ONT Port Mode**: Some Jio AirFiber ODUs require untagged frames for Internet and tagged frames (VLAN 406) for Voice. Ensure the 802.1q device matches:
  ```bash
  uci show network.voice_dev
  ```
- **DHCPv6 Client Missing**: Verify `odhcp6c` is installed:
  ```bash
  opkg list-installed | grep odhcp6c
  ```

---

## 2. One-Way Audio (Caller Can't Hear You or Vice Versa)

### Symptoms
SIP call establishes and rings, but when answered, one party hears silence.

### Causes & Fixes
- **NAT Traversal / ALG**: OpenWrt's SIP ALG (`kmod-nf-nathelper-extra`) can sometimes tamper with SDP headers incorrectly. Try disabling SIP ALG if one-way audio occurs:
  ```bash
  # Check if SIP ALG is active
  lsmod | grep sip
  # Disable if conflicting
  echo "blacklist nf_nat_sip" >> /etc/modules.d/99-blacklist-sip
  ```
- **RTP Port Range Blocked**: Ensure the firewall allows UDP 10000-20000 between the LAN client and the Voice zone. Check `/etc/config/firewall`.

---

## 3. JioJoin App Shows "Device Not Found"

### Symptoms
The official JioJoin mobile app fails to discover the OpenWrt router during device pairing.

### Causes & Fixes
- **Wi-Fi Client Isolation**: Verify that client isolation is disabled in your Wi-Fi settings (`/etc/config/wireless` -> `option isolate '0'`).
- **Multicast / SSDP Filtering**: JioJoin uses SSDP multicast (`239.255.255.250:1900`). Run the beacon daemon:
  ```bash
  /etc/jio-voice/jiojoin_beacon_daemon.sh &
  ```
- **Same Subnet Requirement**: Ensure the smartphone running JioJoin is connected to the OpenWrt router's primary LAN Wi-Fi network (not a guest VLAN or secondary AP with AP isolation).

---

## 4. SIP Error `403 Forbidden` or `401 Unauthorized`

### Symptoms
MicroSIP or Linphone reports registration rejected by P-CSCF.

### Causes & Fixes
- **Network Slice Check**: Jio IMS requires registration requests to originate from the dedicated voice subnet (`ethX.406`). If the softphone routes SIP packets out via the standard Internet WAN instead of Voice VLAN 406, the P-CSCF immediately rejects the request.
- Verify your routing table sends traffic to `ims.mnc861.mcc405.3gppnetwork.org` via the `voice` interface:
  ```bash
  ip -6 route get 2405:200:...
  ```
