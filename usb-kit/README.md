# Kit USB — preparar el pendrive para arrancar Armbian

Todo lo necesario para que el pendrive arranque Linux en esta caja (`ZTE B820C-A15`, Amlogic **U212**).

## Contenido

| Archivo | Qué es |
|---|---|
| `armbian_first_run.txt` | Configuración previa **sin teclado**: WiFi + IP fija (editar SSID/clave) |
| `LEEME-KIT-ARMBIAN.txt` | Guía en español paso a paso |
| `rescue.flag` | **Botón de pánico**: con este archivo en el pendrive, la caja arranca Android |
| `firmware/mediatek/*.bin` | Firmware del WiFi **MT7663** (copiar a la partición FAT como `mediatek/`) |

> ⚠️ Los `.bin` del firmware **no se incluyen en el repo** (son de `linux-firmware`, con su propia
> licencia). Descárgalos así y ponlos en `firmware/mediatek/`:
> ```sh
> base=https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mediatek
> curl -LO $base/mt7663pr2h.bin
> curl -LO $base/mt7663pr2h_rebb.bin
> curl -LO $base/mt7663_n9_v3.bin
> ```

## Preparar el pendrive (resumen)

1. Graba la imagen Armbian (Ej.: `Armbian_26.11.0_amlogic_s905x2_bookworm_6.12.109_server_*.img.gz`)
   con **balenaEtcher** o **Rufus** (modo DD).
2. En la partición **FAT32** (la que tiene `uEnv.txt`):
   - `uEnv.txt` → `FDT=/dtb/amlogic/meson-g12a-u200.dtb`
   - copia `u-boot.usb` a **`u-boot.ext`**
   - copia `armbian_first_run.txt` (editando `FR_net_wifi_ssid` / `FR_net_wifi_key`)
   - copia `firmware/mediatek/` como carpeta `mediatek/`
   - *(opcional)* `rescue.flag` para desactivar el arranque USB cuando lo necesites
3. Mete el pendrive en la caja y enciende. Primera vez: 1–3 min.

## Entrar sin teclado

- **SSH desde el PC:** `ssh root@<ip>` (si usaste el `armbian_first_run.txt`, la IP fija es
  `192.168.100.66`), contraseña inicial `1234`.
- Mira la IP en la TV (consola de Armbian) o en el router.
- Si el WiFi (MT7663 SDIO) no levanta: prueba las DTBs alternativas o un **adaptador USB-Ethernet**.

## Volver a Android

- Quita el pendrive y reinicia → Android.
- O pon `rescue.flag` en el pendrive.
- O ejecuta `scripts/disable_usb_boot.sh` desde Android (restaura el entorno de U-Boot de fábrica).
