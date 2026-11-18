# 📞 JioFiber Voice on OpenWrt (LAN & Wi-Fi Gateway)

<div align="center">

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![OpenWrt](https://img.shields.io/badge/OpenWrt-23.05%20%7C%2024.10%20%7C%20Master-00a8e8?logo=openwrt&logoColor=white)](https://openwrt.org)
[![Tested Hardware](https://img.shields.io/badge/Hardware-MT7986%20%7C%20x86%20%7C%20GL.iNet-brightgreen)](#hardware-compatibility)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

**Ditch the locked JioFiber router. Keep your home landline number running on your own high-performance OpenWrt router over Wi-Fi.**

[Why I Built This](#-why-i-built-this-a-note-from-the-author) • [Quick Start](#-quick-start-1-line-install) • [How It Works](#-how-it-works) • [JioJoin Setup](#-using-official-jiojoin-app) • [SIP Softphone](#-using-standard-sip-phones) • [FAQ](#-frequently-asked-questions)

</div>

---

## 💡 Why I Built This (A Note from the Author)

When I flashed OpenWrt onto my Jio router hardware, I searched everywhere across GitHub, BroadbandForum, Reddit, and YouTube to find instructions on how to use the included Jio landline number on my own router.

**There was not a single repository, guide, or working announcement on the entire internet.** Nobody had publicly solved it or shared how to make it work.

We spent hundreds of hours of intense reverse-engineering:
- Extracting and analyzing stock SquashFS root filesystems.
- Sniffing DHCPv6 Option 21 (SIP P-CSCF discovery) on Voice VLAN 406.
- Decoding the SSDP device descriptor beacons required by the official JioJoin mobile app.
- Mapping DSCP voice priority tags (CS5 for SIP signaling, EF 0xb8 for RTP audio media).

**We are releasing this entire project 100% free and open-source.** Nobody should have to suffer through weeks of broken SIP packets and silent audio just to use a phone service they already pay for. If this project helps you, please consider giving the repository a ⭐ star!

— **Mus'ab ([@musabtvt](https://github.com/musabtvt))**

---

> [!TIP]
> **Using an AI Coding Assistant? (Claude Code, Gemini CLI, Cursor, Windsurf)**  
> Copy and paste this prompt directly into your agent terminal to auto-configure your router:  
> ```text
> "Connect to my OpenWrt router at 192.168.1.1 via SSH. Inspect the WAN physical interface, backup existing network/firewall UCI configs to /tmp/jio_backup.tar.gz, clone https://github.com/musabtvt/openwrt-jiofiber-voice-lan, run ./install.sh in non-interactive mode for Voice VLAN 406, and verify that the Jio voice interface receives an IP address."
> ```

---

## ⚡ Quick Start (1-Line Install)

SSH into your OpenWrt router and run:

```bash
wget -O - https://raw.githubusercontent.com/musabtvt/openwrt-jiofiber-voice-lan/main/install.sh | sh
```

### What This Script Does:
1. 🛡️ **Safety Backup**: Creates an instant archive of your network, firewall, and DHCP configs in `/etc/jio-voice/backups/`.
2. 🔍 **Auto-Detection**: Identifies your physical WAN interface (`eth1`, `eth0`, `sfp`).
3. 🌐 **VLAN 406 Provisioning**: Configures the dedicated 802.1q voice interface (`ethX.406`) with DHCPv6.
4. 📱 **JioJoin Beacon**: Starts a lightweight background daemon so the official JioJoin app instantly pairs on Wi-Fi.

To restore previous settings at any time:
```bash
/etc/jio-voice/backup_restore.sh --restore
```

---

## 📊 Stock Jio Router vs. OpenWrt Voice Gateway

| Feature | Stock Locked Jio Router | OpenWrt Voice Gateway |
| :--- | :---: | :---: |
| **Wi-Fi 6/7 Performance** | ❌ Heavily throttled / basic | ✅ Full Filogic MT7986 / Custom AP speeds |
| **Custom DNS (AdGuard / Pi-hole)** | ❌ Blocked by Jio TR-069 | ✅ Full DoH / DoT / Ad-blocking |
| **Official JioJoin App on Phone** | ✅ Works on Wi-Fi | ✅ Works on Wi-Fi |
| **Standard SIP Softphones (MicroSIP)** | ❌ Blocked | ✅ Fully Supported |
| **Hardware VoIP Desk Phones** | ❌ Not allowed | ✅ Supported via local SIP proxy |
| **Zero Server / Zero Cloud Cost** | ✅ Included | ✅ 100% Free & Local |

---

## 🛠️ How It Works

```
 ┌─────────────────────────────────────────────────────────────┐
 │                      HOME WI-FI NETWORK                     │
 │                                                             │
 │   [Smartphone with JioJoin]     [PC with MicroSIP/Linphone] │
 │              │                              │               │
 │              ▼                              ▼               │
 │       192.168.1.x:Wi-Fi              192.168.1.x:Ethernet   │
 └──────────────────────┬──────────────────────┬───────────────┘
                        │                      │
 ┌──────────────────────▼──────────────────────▼───────────────┐
 │                   YOUR OPENWRT ROUTER                       │
 │                                                             │
 │   • UPnP/SSDP Beacon Service (Port 1900 / 80)               │
 │   • nftables Transparent Voice Routing                      │
 │   • Dedicated Voice Interface: eth0.406 (VLAN 406)          │
 └──────────────────────────────┬──────────────────────────────┘
                                │
                    464xlat / IPv6 IMS Slice
                                │
 ┌──────────────────────────────▼──────────────────────────────┐
 │              RELIANCE JIO IMS CORE NETWORK                  │
 │              (P-CSCF / Call State Control)                  │
 └─────────────────────────────────────────────────────────────┘
```

---

## 📱 Using Official JioJoin App

> [!IMPORTANT]
> **JioFiber FTTH vs. Jio AirFiber 5G:**  
> This repository uses **VLAN 406**, which is the dedicated IMS voice slice on **JioFiber FTTH (Optical Fiber / GPON)**.  
> If you are on **Jio AirFiber 5G (Outdoor Unit / MT7986)**, your voice traffic is carried inside the 5G broadband bearer on **VLAN 1015**. Please refer to our [Hardware Compatibility Guide](docs/HARDWARE_COMPATIBILITY.md) and [jio-airfiber-openwrt-5g-wan](https://github.com/musabtvt/jio-airfiber-openwrt-5g-wan).

1. Connect your smartphone to your OpenWrt router's Wi-Fi network.
2. Open the **JioJoin** app (Google Play / Apple App Store).
3. Tap **Configure JioFiber Device**. The app will detect your OpenWrt router via our beacon daemon.
4. Enter the OTP sent to your registered Jio mobile number.
5. Your home landline is now live and ringing on your smartphone!

---

## 💻 Using Standard SIP Phones (MicroSIP / Linphone / VoIP Desk Phone)

See our comprehensive [Softphone Configuration Guide](docs/SOFTPHONE_SETUP_GUIDE.md) for step-by-step instructions for:
- Windows (MicroSIP)
- iOS / Android / Linux (Linphone)
- Grandstream / Yealink hardware IP phones

---

## ❓ Frequently Asked Questions

<details>
<summary><b>Does this modify my bootloader or void my router's hardware?</b></summary>
No. This script purely configures standard OpenWrt UCI network and firewall files. It never flashes firmware or touches boot partitions.
</details>

<details>
<summary><b>What if my router doesn't get a DHCPv6 lease on VLAN 406?</b></summary>
Ensure your physical WAN port is connected directly to the Jio ONT or ODU. Check our <a href="docs/TROUBLESHOOTING.md">Troubleshooting Guide</a> for commands to check <code>logread | grep odhcp6c</code>.
</details>

<details>
<summary><b>How do I completely uninstall and remove this?</b></summary>
Simply run <code>/etc/jio-voice/backup_restore.sh --restore</code>. Your router configuration will be returned to the exact state before installation.
</details>

---

## 📄 License

Distributed under the MIT License. See [LICENSE](LICENSE) for details.
