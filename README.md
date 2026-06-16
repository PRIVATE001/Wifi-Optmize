# Wifi-Optmize
<div align="center">

<img src="https://raw.githubusercontent.com/microsoft/fluentui-system-icons/main/assets/Globe/SVG/ic_fluent_globe_48_filled.svg" width="80" alt="Network Tuner Logo"/>

# FTTH Network Tuner

**A precise, battle-tested PowerShell CLI tool for Windows network optimization.**  
No snake oil. No magic. Just documented, verified, reversible improvements.

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?style=for-the-badge&logo=powershell&logoColor=white)](https://github.com/PowerShell/PowerShell)
[![Windows](https://img.shields.io/badge/Windows-10%2F11-0078D4?style=for-the-badge&logo=windows&logoColor=white)](https://www.microsoft.com/windows)
[![Version](https://img.shields.io/badge/Version-5.0--Final-brightgreen?style=for-the-badge)](https://github.com)
[![License](https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge)](LICENSE)
[![Stars](https://img.shields.io/github/stars/yourusername/ftth-network-tuner?style=for-the-badge&color=gold)](https://github.com)
[![PRs Welcome](https://img.shields.io/badge/PRs-Welcome-blue?style=for-the-badge)](https://github.com)

<br/>

> *Every tweak has a source. Every change has a backup. Every option has an explanation.*

<br/>

[**Quick Start**](#-quick-start) • [**Features**](#-features) • [**Menu Guide**](#-menu-guide) • [**Technical Docs**](#-technical-notes) • [**Changelog**](#-changelog)

---

</div>

## 📸 Preview

```
========================================================================
  FTTH Network Tuner  v4.0
  FTTH / High-Speed Network Optimizer for Windows — Realistic Edition
========================================================================

  [1]  Optimize  —  Benchmark DNS, apply best provider, tune TCP stack
  [2]  Rollback  —  Restore your exact pre-optimization settings
  [3]  Repair    —  Reset IP/Winsock stack (for connectivity issues)
  [4]  Status    —  View current adapter, TCP, and DNS state
  [5]  Exit

========================================================================
  Log folder: C:\Users\You\Desktop\NetworkTuner_Logs

  Select option (1-5):
```

```
  DNS Benchmark Results — Sorted by Latency (TCP/53)
  ------------------------------------------------------------------------
  Provider                       IPv4 Latency       IPv6 Latency       Status
  ------------------------------------------------------------------------
  Cloudflare (Privacy)           8.3 ms             12.1 ms            <-- FASTEST
  Google                         14.7 ms             N/A
  Quad9 (Secure)                 19.2 ms            21.0 ms
  AdGuard                        31.5 ms             N/A
  OpenDNS                        Unreachable         N/A
  ------------------------------------------------------------------------
```

---

## ✨ Features

<table>
<tr>
<td width="50%">

### 🔍 Real DNS Benchmarking
Measures **TCP/53 latency** — not ICMP ping. More accurate because many ISPs block ICMP while leaving DNS port open. Tests 6 built-in providers + any custom one you add.

</td>
<td width="50%">

### 🔒 Exact Backup & Rollback
Saves **your personal current state** to a JSON file before touching anything. Rollback restores your exact original values — not generic Windows defaults.

</td>
</tr>
<tr>
<td>

### ⚡ TCP Stack Optimization
Applies documented, verified `netsh` commands: CUBIC congestion control, Auto-Tuning, RSS, Heuristics. Only changes what isn't already correct.

</td>
<td>

### 🔐 DNS-over-HTTPS (DoH)
Optionally registers your chosen provider for encrypted DNS queries using Windows 11's native DoH support — no third-party software needed.

</td>
</tr>
<tr>
<td>

### 🎛️ Optional Advanced Tweaks
NetworkThrottlingIndex, Nagle's Algorithm, NIC Power Management — each explained clearly before you confirm. All opt-in, none automatic.

</td>
<td>

### 📊 Live Status View
Instantly see your current adapter info, TCP global settings, DNS servers, and backup status — all in one clean read.

</td>
</tr>
<tr>
<td>

### 🔧 Network Stack Repair
One-command reset of IP stack + Winsock. For actual connectivity problems — not a speed hack. Clearly separated from optimization.

</td>
<td>

### 📁 Full Session Logging
Every action is timestamped and saved to `Desktop\NetworkTuner_Logs\`. Each session gets its own log file. Nothing is silently lost.

</td>
</tr>
</table>

---

## 🌐 DNS Providers

| # | Provider | Primary IPv4 | Secondary IPv4 | DoH | Notes |
|---|---|---|---|---|---|
| 1 | 🟠 Cloudflare (Privacy) | `1.1.1.1` | `1.0.0.1` | ✅ | Zero logs, fastest globally |
| 2 | 🔵 Google | `8.8.8.8` | `8.8.4.4` | ✅ | Maximum reliability |
| 3 | 🟣 Quad9 (Secure) | `9.9.9.9` | `149.112.112.112` | ✅ | Blocks malicious domains |
| 4 | 🟢 AdGuard | `94.140.14.14` | `94.140.15.15` | ✅ | Blocks ads + trackers |
| 5 | 🟠 Cloudflare (Malware) | `1.1.1.2` | `1.0.0.2` | — | Malware-blocking variant |
| 6 | 🔷 OpenDNS | `208.67.222.222` | `208.67.220.220` | — | Cisco, configurable filtering |
| + | ⚪ Custom | *your input* | *your input* | — | Add any server to benchmark |

> **Why TCP/53 and not ping?** See [Technical Notes](#-technical-notes) below.

---

## ⚙️ Requirements

| Requirement | Minimum |
|---|---|
| **OS** | Windows 10 v1903+ or Windows 11 (any version) |
| **PowerShell** | 5.1+ (built into all supported Windows versions) |
| **Privileges** | Administrator (auto-elevates if not already) |
| **Connection** | Any active network adapter (Ethernet or Wi-Fi) |
| **Dependencies** | None — zero external packages |

---

## 🚀 Quick Start

### Option A — One Click (Easiest)

1. Download [`Net.ps1`](Net.ps1)
2. **Right-click** the file → **Run with PowerShell**
3. Click **Yes** if Windows asks for admin permission

### Option B — PowerShell Terminal

```powershell
# Allow script execution and run:
powershell -ExecutionPolicy Bypass -File ".\Net.ps1"
```

### Option C — Clone & Run

```bash
git clone https://github.com/yourusername/ftth-network-tuner.git
cd ftth-network-tuner
```

```powershell
# Then in PowerShell (as Admin):
.\Net.ps1
```

> ⚠️ **Always review scripts before running them as Administrator.**

---

## 📖 Menu Guide

### `[1]` Optimize — The Main Event

The full optimization pipeline runs in 4 clear steps:

```
Step 1 of 4 — Select Network Adapter
Step 2 of 4 — Backup Current Settings
Step 3 of 4 — DNS Latency Benchmark (TCP/53)
Step 4 of 4 — TCP Stack + Advanced Tweaks
```

**Automatic TCP changes** *(only applied if not already correct)*:

| Setting | Value Applied | Reason |
|---|---|---|
| Congestion Control Provider | `cubic` | Modern algorithm, better throughput |
| Auto-Tuning Level | `normal` | Optimal window scaling |
| Receive-Side Scaling (RSS) | `enabled` | Distributes NIC processing across CPU cores |
| Window-Scaling Heuristics | `disabled` | Conflicts with Auto-Tuning on Windows 8.1+ |

**Optional tweaks** *(you confirm each one)*:

<details>
<summary><b>🔧 NetworkThrottlingIndex</b> — Click to expand</summary>

Removes the MMCSS (Multimedia Class Scheduler) cap on network packet processing. By default, Windows throttles non-multimedia network throughput to prioritize audio/video rendering. Disabling this is beneficial when running heavy network workloads alongside media software.

**Requires:** Restart  
**Risk:** Low  
**Who benefits:** Power users running streaming software + heavy downloads simultaneously

</details>

<details>
<summary><b>🔧 Nagle's Algorithm (per-adapter)</b> — Click to expand</summary>

Nagle's algorithm buffers small TCP packets to improve bulk throughput efficiency. Disabling it reduces per-packet latency at the cost of slightly higher overhead. Useful for latency-sensitive TCP applications (SSH, some games, real-time dashboards).

**Important:** Has **zero effect** on UDP traffic. Most modern online games use UDP — this won't help them.

**Requires:** Restart  
**Risk:** Low-medium (per-adapter, reversible)  
**Who benefits:** SSH users, TCP-based real-time applications

</details>

<details>
<summary><b>🔧 Adapter Power Management</b> — Click to expand</summary>

Prevents Windows from putting the NIC to sleep during idle periods. When the adapter wakes up from power-save mode, there's a brief reconnection delay that manifests as micro-stutters or packet loss spikes.

**Requires:** No restart  
**Risk:** Very low (slight increase in power usage)  
**Who benefits:** Laptop users, anyone experiencing random brief connection drops

</details>

---

### `[2]` Rollback

Restores **your exact pre-optimization state** from the JSON backup.

- DNS servers (your original ones, or DHCP if you had none set)
- TCP parameters (congestion, auto-tuning, RSS, heuristics)
- Registry keys (NetworkThrottlingIndex, Nagle keys — removed if they didn't exist before)

If no backup exists, you can optionally apply approximate Windows defaults.

---

### `[3]` Repair — Network Stack Reset

```
netsh int ip reset      → Resets the TCP/IP stack
netsh winsock reset     → Resets the Winsock catalog
ipconfig /flushdns      → Clears the DNS resolver cache
```

> **Use this only for actual connectivity problems** — not as a speed optimization. Requires a system restart. VPN/security software may need reconfiguration after reboot.

---

### `[4]` Status — Current State Snapshot

Displays live information without making any changes:

- Adapter: name, speed, MAC, IPv4, current DNS
- TCP global: congestion, auto-tuning, ECN, RSS, heuristics
- Backup: availability and timestamp

---

## 📂 Output Files

All files are saved to: `%USERPROFILE%\Desktop\NetworkTuner_Logs\`

```
NetworkTuner_Logs/
├── Session_20260616_143022.log     ← Timestamped session log
├── Session_20260615_091511.log     ← Previous session
└── Last_Known_State.json           ← Your latest backup
```

### Backup JSON Structure

```json
{
  "Timestamp":           "2026-06-16T14:30:22.000",
  "ToolVersion":         "4.0",
  "AdapterName":         "Ethernet",
  "AdapterGuid":         "{4D36E972-E325-11CE-BFC1-08002BE10318}",
  "AdapterSpeed":        "1 Gbps",
  "DnsV4":               ["192.168.1.1"],
  "DnsV6":               [],
  "Congestion":          "cubic",
  "AutoTuning":          "normal",
  "Ecn":                 "disabled",
  "Rss":                 "enabled",
  "Heuristics":          "disabled",
  "ThrottleIndexWasSet": false,
  "ThrottleIndexValue":  null,
  "NagleKeysExisted":    false,
  "TCPNoDelayValue":     null,
  "TcpAckFreqValue":     null
}
```

---

## 🔬 Technical Notes

<details>
<summary><b>Why TCP/53 instead of ICMP ping for DNS benchmarking?</b></summary>

ICMP (ping) is frequently rate-limited or blocked entirely by ISPs and corporate firewalls as a security measure, while DNS port 53 must remain open for the network to function. Benchmarking via a real TCP handshake to port 53 gives a realistic picture of:
- Whether the provider is actually reachable from your network
- The actual round-trip time your DNS resolver will experience
- Consistency across multiple attempts (3 samples, averaged)

</details>

<details>
<summary><b>Why is Nagle's Algorithm opt-in with a warning?</b></summary>

Nagle's algorithm was designed to improve throughput efficiency for bulk TCP transfers by coalescing small packets. Network engineers generally recommend disabling it **at the application level** when fine-grained control is needed, rather than system-wide. Disabling it globally can reduce bulk transfer efficiency. Additionally, the claim that "disabling Nagle helps gaming" is only valid for TCP-based games — the vast majority of modern online games use UDP, where Nagle is irrelevant.

</details>

<details>
<summary><b>Why is ECN (Explicit Congestion Notification) not auto-enabled?</b></summary>

ECN is a valid network congestion signaling mechanism defined in RFC 3168. However, a significant portion of ISP equipment, home routers, and middleboxes either ignore ECN flags or incorrectly handle ECN-marked packets by dropping them — leading to connection failures or severe throughput degradation. Without knowing your specific network path, auto-enabling ECN is more likely to cause problems than solve them. It is intentionally excluded from automatic changes.

</details>

<details>
<summary><b>Why are DCA and NetDMA not touched?</b></summary>

Direct Cache Access (DCA) and Network Direct Memory Access (NetDMA) were hardware-level performance features supported in Windows Vista through Windows 7. They were removed or disabled in Windows 8.1 and later. Any registry keys related to these features on Windows 10/11 are non-functional — changing them has no measurable effect and is intentionally skipped to avoid confusion.

</details>

<details>
<summary><b>What does "realistic" mean in this context?</b></summary>

This tool does not promise to "double your internet speed" or use unverified registry hacks sourced from gaming forums. If your connection speed is limited by your ISP plan, no software can change that. What this tool can realistically improve:

- **DNS resolution latency** — choosing the fastest provider for your location
- **TCP receive window behavior** — better auto-scaling for high-bandwidth links
- **CPU load distribution** — via RSS, when processing high packet rates
- **Micro-stutter elimination** — via NIC power management

</details>

---

## 🗂️ Project Structure

```
ftth-network-tuner/
├── Net.ps1          ← The entire tool (single file, zero dependencies)
└── README.md        ← This file
```

The tool is intentionally a **single PowerShell file** with no external dependencies. This means:
- Nothing to install
- Nothing to configure before running
- Easy to audit (everything is visible in one file)
- Easy to share (copy one file)

---

## 🤝 Contributing

Contributions are welcome! Here are some ways to help:

- 🐛 **Report bugs** — Open an issue with your Windows version, adapter type, and what went wrong
- 🌐 **Suggest DNS providers** — If you know a reliable, privacy-respecting provider worth benchmarking
- 🔧 **Propose tweaks** — New TCP/registry tweaks are welcome *with sources and documented technical basis*
- 🌍 **Translations** — Help make the tool available in more languages

### Guidelines for New Tweaks

> Any proposed optimization must include:
> 1. A documented technical source (Microsoft Learn, RFC, Sysinternals, peer-reviewed research)
> 2. A clear explanation of what it does and who benefits
> 3. A clear explanation of potential downsides or incompatibilities
> 4. Whether it requires a restart
> 5. It must be opt-in if there is any real risk of regression

---

## 📜 Changelog

### v5.0 Final — 2026-06-16
> Production release. All known bugs fixed. All community-sourced best practices applied.

**Bug fixes (from full code audit):**
- **FIXED:** `Test-DnsTcpLatencyParallel` was completely sequential (dead parallel code) — replaced with a real `RunspacePool` implementation using up to 16 concurrent runspaces. All providers are benchmarked simultaneously instead of one-by-one. Benchmarking 8 providers now takes ~800ms instead of ~6 seconds.
- **FIXED:** `$a.FullDuplex` property does not exist on `Get-NetAdapter` objects — silently showed "Half-Duplex" for all adapters. Removed entirely.
- **FIXED:** `$MyInvocation.PSCommandPath` inside a function always returns `$null` (refers to function, not script). Removed broken fallback.
- **FIXED:** `Show-AdapterInfo` displayed `$ip4` as raw array when adapter had multiple IPs. Now uses `-join ", "`.
- **FIXED:** DoH registration `catch {}` block was silent — failures are now logged with reason.
- **FIXED:** `Apply-TcpOptimizations` skipped changes when `Get-TcpGlobalState` returned `$null` (non-English Windows, atypical netsh output). Now applies changes even when current state is unknown.
- **FIXED:** `Restore-GenericDefaults` did not remove Nagle registry keys. Keys are now cleaned up in generic restore.
- **FIXED:** `$Script:Colors.Highlight = "Blue"` was nearly invisible on dark terminals. Changed to `DarkCyan`.
- **FIXED:** `Write-Banner` and `Write-SectionHeader` did not write to session log — log had no structural context. Both now call `Write-Log`.
- **FIXED:** `netsh int ip reset` called without a log file path (required on some Windows builds). Now passes a timestamped log path.
- **FIXED:** `Show-CurrentState` forced adapter selection even for a read-only status view. Now shows **all** active adapters automatically.
- **FIXED:** Custom DNS `Sec4` was set to the same IP as `Pri4` — single IP was applied twice. Now `Sec4 = $null` for custom entries.
- **FIXED:** `Write-Line -NoNewline` + `Write-Host` pattern in StackRepair was visually inconsistent. Replaced with clean separate lines.
- **FIXED:** All `netsh` output captured via `2>&1` — ErrorRecord objects now filtered with `Where-Object { $_ -is [string] }` to prevent false regex matches.

**New features:**
- **NEW:** `Set-StrictMode -Version Latest` — catches undefined variables and uninitialized arrays at runtime
- **NEW:** DNS latency now uses 4 attempts with **trimmed average** (drops lowest outlier) — more accurate than 3-sample plain average
- **NEW:** TCP Chimney Offload state backed up, optimized, and restored (deprecated on Win10/11, was missing before)
- **NEW:** QoS baseline policy creation to prevent arbitrary traffic shaping
- **NEW:** Interrupt Moderation detection and configuration
- **NEW:** Tweak 4/4: LSO + Checksum Offload + RSC enable (NIC-accelerated TCP — major CPU reduction on FTTH)
- **NEW:** Power management now tries WMI fallback if PowerShell cmdlet fails
- **NEW:** Expanded power management keys: EEE, SelectiveSuspend, WakeOnMagicPacket, WakeOnPattern
- **NEW:** DNS verification step after applying DNS (Resolve-DnsName confirm)
- **NEW:** DHCP release before stack repair
- **NEW:** NetBIOS cache flush in stack repair
- **NEW:** IPv6 stack reset in stack repair (`netsh int ipv6 reset`)
- **NEW:** Optional immediate reboot prompt after stack repair
- **NEW:** Status view shows TCP health check with "recommended" annotation for non-optimal values
- **NEW:** Session log includes OS version and PowerShell version in header
- **NEW:** `[Net.ServicePointManager]::SecurityProtocol = TLS12` at startup for secure future cmdlets
- **NEW:** 8 built-in DNS providers (added Comodo + Level3)
- **NEW:** `SystemResponsiveness = 10` applied alongside NetworkThrottlingIndex for complete MMCSS tuning
- **NEW:** Main menu shows last backup timestamp when available

### v4.0 — 2026-06-16
- Full rewrite: clean English CLI, no inline comments
- Persistent interactive menu loop
- Status view, 6 DNS providers, color-coded latency table
- Timestamped session logs, exact JSON backup

### v3.0 — 2026-01-01
- Replaced ICMP ping with TCP/53 latency measurement for DNS benchmarking
- Real exit-code verification for all `netsh` commands (no silent failures)
- Exact JSON backup of personal state (not generic defaults)
- DoH registration for supported providers via native Windows API
- Optional tweaks: NetworkThrottlingIndex, Nagle's Algorithm, NIC power management
- IPv6 DNS support in benchmark and application

### v2.x — 2025
- Initial public release
- Basic DNS selection and TCP tuning
- Arabic UI

---

## ⚖️ License

```
MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software to use, copy, modify, merge, publish, distribute, and/or
sell copies of the software, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
```

---

<div align="center">

**Made with ❤️ for the networking community**

*If this tool helped you, consider giving it a ⭐ — it helps others find it.*

[![Share on Twitter](https://img.shields.io/badge/Share-Twitter-1DA1F2?style=for-the-badge&logo=twitter&logoColor=white)](https://twitter.com/intent/tweet?text=Check%20out%20FTTH%20Network%20Tuner%20-%20a%20precise%20PowerShell%20CLI%20for%20Windows%20network%20optimization!&hashtags=PowerShell,Windows,Networking)
[![Share on Reddit](https://img.shields.io/badge/Share-Reddit-FF4500?style=for-the-badge&logo=reddit&logoColor=white)](https://reddit.com/submit?title=FTTH%20Network%20Tuner%20-%20Realistic%20Windows%20Network%20Optimizer)

</div>

