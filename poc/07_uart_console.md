# 07 — UART console PoC

Full U-Boot console on the debug UART. No software chain required once the pads are wired.

## Parameters (derived from the device's own bootargs)

```
console=ttyS0,115200  earlyprintk=aml-uart,0xff803000
```

| Item | Value |
|------|-------|
| Controller | UART_AO (always-on), MMIO `0xff803000` |
| Settings | **115200 8N1**, no flow control |
| Adapter | USB-TTL 3.3 V (CP2102 / CH340 / FT232 / PL2303) |
| Wiring | adapter GND → board GND, adapter RX → board TX, adapter TX → board RX (VCC unconnected) |

## Procedure

1. **Identify pads** (device off, then powered): GND is continuity to the USB/HDMI shell; 3V3 reads a
   steady ~3.3 V; TX/RX idle high and burst during boot. If a pin reads ~1.8 V, use a level shifter.
2. **Extend the autoboot window** from Android before opening the case (persists in the env partition):

   ```sh
   poc/04_hal_envset/hal.sh envset ubootenv.var.bootdelay 5
   ```

3. **Attach**:

   ```sh
   picocom -b 115200 /dev/ttyUSB0        # Windows: PuTTY, serial, 115200/8-N-1
   ```

4. **Power-cycle** and press a key during `Hit any key to stop autoboot: N`.

## Console usage

```text
# inspect
printenv bootcmd
printenv preboot

# boot Linux from the USB stick, one shot
usb start
fatload usb 0 ${loadaddr} aml_autoscript
autoscr ${loadaddr}

# or persist a USB-first policy (no kill-switch: be careful)
setenv preboot 'run cachebootcheck; run bootusb'
setenv bootusb 'usb start; if fatload usb 0 ${loadaddr} aml_autoscript; then autoscr ${loadaddr}; fi'
saveenv

# boot Android kernel manually
imgread kernel ${boot_part} ${loadaddr}
bootm ${loadaddr}
```

## Notes

- The console is the only source of full boot logs; the software-only path (§06) relies on the `cstep`
  telemetry variable instead.
- UART is a hardware trust boundary. If it must not be reachable in production, set
  `CONFIG_AUTOBOOT_KEYED`, `bootdelay` 0, and sign `bootcmd`.
- Do not connect the adapter's VCC line; the pads are not a power input.
