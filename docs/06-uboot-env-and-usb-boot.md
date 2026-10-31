# 06 — U-Boot environment abuse and USB boot

Everything below is executed from Android as uid 1000 using `ISystemControl::setBootEnv` (§05).

## 6.1 Factory environment (dumped via `envget`)

```
bootcmd             = bootsys
preboot             = run bcb_cmd; run factory_reset_poweroff_protect;run upgrade_check;run init_display;
                      run storeargs;run upgrade_key;bcb uboot-command;run switch_bootmode;
update              = usb_burning; sdc_burning; mmcinfo -> recovery_from_sdcard; usb start -> recovery_from_udisk
recovery_from_udisk = if fatload usb 0 ${loadaddr} aml_autoscript; then autoscr ${loadaddr}; fi; …
upgrade_check       = echo upgrade_step=${upgrade_step}; if itest ${upgrade_step} == 3; then run update; fi
storeboot           = … if imgread kernel ${boot_part} ${loadaddr}; then bootm ${loadaddr}; fi; …
bootdelay           = 1
upgrade_step        = 2
avb2                = 1
EnableSelinux       = enforcing
```

Notes:

- USB/SD boot support exists (`aml_autoscript` + `autoscr`) but is only reached through `update`,
  which is not triggered on a normal cold boot (`bootcmd=bootsys`).
- The factory U-Boot is **2015.01**, i.e. no `booti`. TV-box Linux images ship a modern `u-boot.ext`
  which is chain-loaded with `fatload … go` instead.

## 6.2 Persistent write surface

Per §05 §5.4: `preboot` and any custom variable persist; `bootcmd`/`EnableSelinux` do not.
The usable hook is therefore **append a step to `preboot`**.

## 6.3 Hook design (USB-only, with kill-switch)

```
preboot += run cachebootcheck;

cachebootcheck =
  setenv cstep v7_ini; saveenv;
  if test ${ubootdone} = 1; then setenv cstep v7_skip; saveenv; else
    usb start; setenv cstep v7_usb; saveenv;
    if fatload usb 0:1 ${loadaddr} rescue.flag; then setenv cstep v7_RESCUE; saveenv; else
      if fatload usb 0 0x1000000 u-boot.ext; then
          setenv cstep v7_jump0; setenv ubootdone 1; saveenv; go 0x1000000;
      else if fatload usb 0:1 0x1000000 u-boot.ext; then
          setenv cstep v7_jump1; setenv ubootdone 1; saveenv; go 0x1000000;
      else setenv cstep v7_nobootext; saveenv; fi; fi; fi; fi
```

Properties:

| Guard | Effect |
|-------|--------|
| `rescue.flag` on a FAT32 USB stick | aborts, Android boots (physical kill-switch) |
| `ubootdone=1` | single-shot: no boot loops across resets |
| `cstep=…` | per-step telemetry readable from Android (`envget utoobenv.var.cstep`) |

PoCs: [`poc/05_usb_boot_hook.sh`](../poc/05_usb_boot_hook.sh),
[`poc/06_disable_usb_boot.sh`](../poc/06_disable_usb_boot.sh).

## 6.4 Boot straight into a modern U-Boot

Because `u-boot.ext` from ophub's Armbian images is a G12A U-Boot (`strings` contains
`only support G12A chip`), loading it at `0x1000000` and `go`ing transfers control before Android's
`storeboot` runs. That U-Boot then reads `uEnv.txt` from the USB stick and boots Linux with `booti`.
Result: **no writes to eMMC partitions are required**.

## 6.5 Negative results (documented so they are not retried)

| Approach | Result |
|----------|--------|
| Boot the `cache` partition as root: `root=/dev/mmcblk0p3 rootfstype=ext4 init=/… skip_initramfs` | kernel panic before executing an external `init=` (reproduced twice; boot counter exhausted) |
| `bootcmd` override | reverted by the vendor logic on the next boot |
| `EnableSelinux=permissive` | reverted; Android user builds also ignore permissive requests from the cmdline |
| `/cache/recovery/*` as payload location | directory is wiped on each boot (OTA cleanup keeps only `last_log`/`last_install`) |
| `/cache/<root files>` as payload location | survives |
| HAL `readSysfs` for partition dumps | not usable for binary block I/O (text-only API, truncated at ~4 KB) |

## 6.6 Timing / observability

- The hook runs before `storeboot`, so `cstep` values are persisted even if the subsequent boot fails.
- A physical UART console (§07) is the only source of full log output; without it, `cstep` is the
  telemetry channel.
