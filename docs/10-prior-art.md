# 10 — Prior art and comparable CVEs

Checked before submitting: whether the issues below are already known, and which precedents the
vendor has handled before. Two conclusions:

- The **bug class is well established in ZTE Android TV STBs** — they accept it, and as a CNA they
  have assigned CVEs to it repeatedly. Precedent supports the report rather than undermining it.
- The **specific primitives are not covered by an existing CVE** (no CVE references the Amlogic
  `system_control` HAL or `allowDebugging` through `service call` on these devices).

## 10.1 Same vendor, same product line, same class

| CVE | Score | Affected | Description (vendor wording) | Match |
|-----|-------|----------|------------------------------|-------|
| **CVE-2023-25645** | 7.7 High | ZXV10 B860H V5.0, UP T2 4K + 8 more (10 products) | "permission and access control vulnerability in some ZTE AndroidTV STBs. Due to improper permission settings, non-privileged application can perform functions that are protected with signature/privilege-level permissions" | **Issue 1 and 2 exactly** |
| **CVE-2021-21737** | 7.5 High | ZXV10 B860H V5.0 (`V83011303.0010`, `V83011303.0016`) | "permission and access control vulnerability. Due to insufficient protection of system application, attackers could … tamper with the system desktop" | OEM system app under-protected (issue 1) |
| **CVE-2019-3416** | 9.8 Critical | ZXV10 B860A, all versions up to `V81511329.1008` | "input validation vulnerability … unauthorized users can … control the user terminal system" | Same outcome: terminal takeover |
| CVE-2018-7366 | — | ZXV10 B860AV2.1 (ChinaMobile branch) | authentication bypass → unauthorized operations | Same family, access control |
| CVE-2021-21722 | 4.4 Medium | ZXV10 B860A | insufficient log verification → information leak | Same platform discipline |

Note the firmware numbering: the affected version in CVE-2021-21737 is `V83011303.0016`; this device
runs `V83511301.2070` — the same scheme, four product generations later. ZTE's own PSIRT assigned all
of the above (`Assigner: zte`).

## 10.2 Analogous findings in other vendors' devices

| Reference | Relevance |
|-----------|-----------|
| **CVE-2023-36629** (Xiaomi Redmi Note 10S, `nfc.st_ext`) | `service call` reaches vendor service transactions and bypasses a `WRITE_SECURE_SETTINGS` check — the same mechanism as issue 2 |
| **CVE-2022-22292** (Samsung, Kryptowire) | a pre-installed app running as `system` accepts attacker-controlled intents, yielding system-uid actions — issue 1's class |
| Aafer et al., *Android SmartTVs Vulnerability Discovery via Log-Guided Fuzzing*, USENIX Security '21 | 37 vulnerabilities in 11 Android TV boxes, including **corruption of critical boot environment settings through an unprotected OEM API** (and unauthorised writes to system files). The closest published precedent for issue 3 |
| Sick.Codes HK1 Box (2020) | UART/ADB reachable as `shell`, then `su` shipped in `/system/xbin` — same overall "box takeover" impact, different mechanism (no shipped `su` here) |
| Creative Electron / BootROM work on Amlogic (below) | alternative hardware path, not a software chain |

## 10.3 Alternative path: Amlogic BootROM (CVE-2021-0467)

Independent of this chain: the Amlogic BootROM's USB download protocol has a memory-corruption bug
that allows unsigned code execution in secure world, before any signature check.

- Advisory: CVE-2021-0467, rated **Critical** in the Android Security Bulletin 2021-05
  (reported by Frédéric Basse, published 2021-02-10).
- Tooling: `frederic/amlogic-usbdl`, and **`Raxone/amlogic-usbdl_s905x2`** which explicitly supports
  this SoC family (tested on a *secured* A95X Max). Its script dumps bootloader + DTB (converted to
  `.dts`), efuse/SRAM, and extracts the BL2 AES key/IV to decrypt the bootloader.
- Entry condition: the box must be in **USB download mode** — the usual method is holding the button
  in the AV hole (toothpick) while connecting a USB-A↔USB-A cable to a PC, then keeping it pressed
  ~10 s; the PC should enumerate `idVendor=1b8e idProduct=c003`, product string `GX-CHIP`.
- Mitigation: Amlogic added a **USB download password** (efuse-burned) for units manufactured after
  December 2020 / firmware from February 2021 (`sabrina-unlock` documents the mitigation). A 2025
  build may be locked — the test is read-only and harmless either way: the device either enumerates
  as `GX-CHIP` or it does not.
- Why it matters here even if unusable as an exploit: the tooling **dumps the factory DTB**, which is
  the input needed for Wi-Fi (MT7663), IR and LED/display work on a mainline kernel
  (`docs/06`/`docs/07`).
- Component ownership: BootROM code is Amlogic's, so under a vendor bounty policy this is third-party
  code affecting ZTE equipment.

## 10.4 What is *not* covered elsewhere

| Primitive | Existing CVE? |
|-----------|---------------|
| Factory service `/RunCmd` (uid 1000 RCE from any app) | not for this model; class covered by CVE-2023-25645 / CVE-2021-21737 |
| `allowDebugging` via `service call` on this firmware | no CVE; mechanism analogous to CVE-2023-36629 |
| `system_control` HAL `setBootEnv` reachable from uid 1000 | **no CVE found**; only academic precedent (USENIX '21) |
| U-Boot `preboot` persistence + USB chainload on this build | no CVE; vendor-side design |

## 10.5 Device documentation on record

- FCC ID **Q78-ZXV10B820CA15** (2019): user guide and radio test report
  (`fcc.report/FCC-ID/Q78-ZXV10B820CA15`).
- Community reports for this exact model note that **developer options were removed by a 2022
  update** (XDA thread *"How to Activate Developer Options in Izzi zte zxv10 b820c-a15"*), which is
  consistent with the appop/permission lockdown described in `docs/04`. Owners are looking for
  pre-2022 firmware — i.e. the population affected by these issues is real and unpatched by design.
- Aggregator sites offering "official firmware" for this model (e.g. gofirmware) are **not** vendors
  and their builds should not be flashed.

## 10.6 References

- CVE-2023-25645 — <https://www.opencve.io/cve/CVE-2023-25645>
- CVE-2021-21737 — <https://app.opencve.io/cve/?product=zxv10_b860h_v5.0_firmware&vendor=zte>
- CVE-2019-3416 and CVE-2018-7366 — <https://app.opencve.io/cve/?product=zxv10_b860a&vendor=zte>
- CVE-2023-36629 (service call / permission bypass) — LevelBlue SpiderLabs, *Hunting for Android
  Privilege Escalation with a 32 Line Fuzzer*
- CVE-2022-22292 (Kryptowire / Samsung intent forwarding) — Quokka advisory
- Aafer et al., USENIX Security 2021 — <https://www.usenix.org/system/files/sec21-aafer.pdf>
- CVE-2021-0467 and `amlogic-usbdl` — <https://fredericb.info/2021/02/amlogic-usbdl-unsigned-code-loader-for-amlogic-bootrom.html>
- `amlogic-usbdl_s905x2` — <https://github.com/Raxone/amlogic-usbdl_s905x2>
- `sabrina-unlock` (USB download password mitigation) — <https://github.com/oddsolutions/sabrina-unlock>
- Hardkernel `system_control` commit restricting env access
  (`ODROID-N2: ubootenv: disable access /dev/env, but read from /proc/cmdline`) — precedent that this
  HAL surface is normally restricted
