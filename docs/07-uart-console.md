# 07 — UART console (UART_AO, 115200 8N1)

The board exposes a debug UART. Timing, baud rate and port are not guesses: they are present in the
kernel command line captured from Android (`/proc/device-tree/chosen/bootargs`):

```
console=ttyS0,115200 no_console_suspend earlyprintk=aml-uart,0xff803000
```

- `ttyS0` → **UART_AO** (always-on domain), amlogic `uart_ao` at **0xff803000**
- **115200 8N1**, no flow control
- U-Boot itself uses the same port, so the console shows `Hit any key to stop autoboot: 1`

## 7.1 Locating the pads

Typical U212/G12A layout: 4 pads in a row near the SoC (or next to the eMMC), silkscreen
`G/T/R/V` (GND, TX, RX, 3V3) or unmarked.

Identification with a multimeter (device powered off, then on):

1. **GND** — continuity with the USB shield / HDMI shell.
2. **3V3** — reads a stable ~3.3 V and is *not* a signal source; do **not** connect power.
3. **TX** (board → adapter) — idles at ~3.3 V and shows bursts during boot.
4. **RX** (adapter → board) — idles high; used to send.

If the meter reads ~1.8 V, the UART is 1.8 V; use a level shifter (3.3 V adapters can damage it).

## 7.2 Adapter and wiring

- USB-TTL adapter with a **3.3 V** setting (CP2102, CH340, FT232, PL2303).
- Adapter **GND → board GND** (mandatory), adapter **RX → board TX**, adapter **TX → board RX**.
- Leave the adapter's VCC unconnected.

## 7.3 Terminal

```sh
picocom -b 115200 /dev/ttyUSB0        # or: screen /dev/ttyUSB0 115200, minicom, PuTTY on Windows
```

Expected output at power-on: BL2/BL31, then

```
U-Boot 2015.01-g65bcffe-dirty (…)
Hit any key to stop autoboot:  1
```

## 7.4 Increasing the interrupt window from Android

`bootdelay=1` is short. It is a normal U-Boot variable and persists through `setBootEnv`:

```sh
poc/04_hal_envset/hal.sh envset ubootenv.var.bootdelay 5
```

Power-cycle, then press a key during the countdown to land in the U-Boot prompt.

## 7.5 What the prompt gives you

```
printenv / setenv / saveenv          # full environment control
usb start ; fatload usb 0 ${loadaddr} aml_autoscript ; autoscr ${loadaddr}
mmcinfo ; fatload mmc 0 …            # SD path
imgread kernel ${boot_part} ${loadaddr} ; bootm ${loadaddr}     # boot Android kernel
run recovery_from_udisk              # factory USB recovery path
```

With the console, the USB-only hook of §06 becomes optional: `autoscr` can be issued interactively, and
`aml_autoscript` can `setenv bootcmd …` + `saveenv` so the choice is persistent without touching Android.

## 7.6 Relation to the software chain

| Path | Requires opening the case? | Persistence |
|------|----------------------------|-------------|
| `setBootEnv` hook (§06) | no | env partition, killed by `rescue.flag` |
| UART prompt `setenv bootcmd` | yes (pads), plus a USB-TTL adapter | env partition, no kill-switch |
| `bootdelay` tweak | no | env partition |

Recommendation for defenders: the UART is a hardware-level trust boundary; disabling the U-Boot console
(`CONFIG_AUTOBOOT_KEYED`, `bootdelay=-1`, signed `bootcmd`) is the correct mitigation if console access
must not be possible.

## Capture from a retail unit

`izzi.txt` in the repository root is a full `picocom -b 115200 /dev/ttyUSB0` capture taken from an
unmodified B820C-A15. It covers the complete bootloader stage. Extract of what it contains:

| Line | Content |
|------|---------|
| bootloader init | `U-Boot 2015.01-g65bcffe-dirty (Jan 03 2025 - 23:43:06)`, `DRAM: 2 GiB` |
| storage | partition table with 16 entries, `enable dynamic_partition`, `mmc env offset: 0x45c00000` |
| board id | `saradc get val`, `board_version[19]`, `checkhw - name: g12a_u212_mtk` |
| verified boot | `CONFIG_AVB2: avb2`, `avb2: 1`, `avb verification: locked = 1, result = 0` |
| kernel handoff | `## Booting Android Image at 0x03080000`, `Starting kernel ...`, `uboot time: 5795261 us` |
| console shell | a `#` prompt after the kernel starts, with the recovery ramdisk root visible (`init.recovery.amlogic.rc`, `sideload`, `debug_ramdisk`) |

Two bootloader errors reproduced in that capture:

```
Usage:
itest [.b, .w, .l, .s] [*]value1 <op> [*]value2
Unknown command 'wipeisb' - try 'help'
```

Neither command exists in this U-Boot build; a vendor script (or a hook) calls them and continues.

Also visible: a 8 GT / 7456 MB device reported as `Prod: 8GTF4R`, `Type: Removable Hard Disk`,
`Filesystem: FAT12 "KEYBOX PART"` — the internal eMMC, including its FAT12 config partition.
