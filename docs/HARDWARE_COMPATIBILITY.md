# 📡 Hardware & Network Compatibility: JioFiber FTTH vs. Jio AirFiber 5G

Understanding how Reliance Jio routes fixed-line voice across different access technologies is essential for configuring OpenWrt properly.

---

## 🏗️ The Critical Distinction

| Feature | JioFiber FTTH (Optical Fiber / GPON) | Jio AirFiber 5G (Wireless ODU / MT7986) |
| :--- | :--- | :--- |
| **Physical Interface** | Optical SC/APC Fiber to SFP or Gigabit ONT Ethernet | 2.5 Gigabit Ethernet (PoE) to 5G Outdoor Unit (ODU) |
| **Public Internet VLAN** | VLAN `100` or Untagged | **802.1Q VLAN 1015** (MTU 1500) |
| **IMS Voice Transport** | **Dedicated 802.1Q VLAN 406** | **Embedded inside 5G Bearer on VLAN 1015** |
| **Voice Addressing** | Separate IPv6 prefix assigned via DHCPv6 on `eth0.406` | Shared IPv6 / 464XLAT subnet on `wan.1015` |
| **Gateway App / B2BUA** | Direct SIP to Jio P-CSCF over VLAN 406 | Handled via Jio's internal IMS bridge on port 5068 |
| **Recommended Repo** | **`openwrt-jiofiber-voice-lan` (This repo)** | **`jio-airfiber-openwrt-5g-wan`** |

---

## 🌐 1. JioFiber FTTH (GPON Fiber) Users
If you have a fiber optic cable running directly into your ONT (green optical connector):
1. Voice signaling runs on a separate, dedicated network slice tagged with **VLAN 406**.
2. Run `wget -O - .../install.sh | sh`. The script creates the `eth0.406` interface and enables DHCPv6 to fetch your SIP P-CSCF address.
3. Your softphone or JioJoin app connects to Jio's IMS network directly through the VLAN 406 interface.

---

## 📡 2. Jio AirFiber 5G (Outdoor Unit) Users
If you have a 5G AirFiber Outdoor Unit mounted on your terrace/balcony connected to the router's 2.5GbE PoE WAN port:
1. Public Internet and Voice both traverse the single 5G radio PDU session tagged with **VLAN 1015**.
2. First, configure your WAN and 464XLAT internet using [jio-airfiber-openwrt-5g-wan](https://github.com/musabtvt/jio-airfiber-openwrt-5g-wan).
3. If running Asterisk or a PBX gateway, route SIP traffic to the router's internal B2BUA bridge on port 5068 using TLS (see [jiofiber-asterisk-global-pbx](https://github.com/musabtvt/jiofiber-asterisk-global-pbx)).
