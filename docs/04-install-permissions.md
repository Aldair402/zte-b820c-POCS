# 04 — Sideloading blocked by appop default (`REQUEST_INSTALL_PACKAGES`)

## 4.1 Symptom

Installing any APK not obtained from the preinstalled store fails. The package installer returns
`INSTALL_FAILED_USER_RESTRICTED` or the *Install* button never becomes usable, and the per-app
*Allow from this source* toggle is unavailable in Settings.

## 4.2 Cause

The framework consults the **appop** `REQUEST_INSTALL_PACKAGES` per application. On this build the
default is **deny** for user-installed apps, while the global kill-switch is already enabled:

```console
$ cmd appops get com.esaba.downloader REQUEST_INSTALL_PACKAGES
REQUEST_INSTALL_PACKAGES: deny; rejectTime=+6d2h55m43s508ms ago
$ settings get secure install_non_market_apps
1
```

The OEM UI never exposes the per-app toggle, so the state cannot be changed by hand.

## 4.3 PoC

```sh
for P in com.esaba.downloader com.yablio.sendfilestotv com.termux \
         com.android.vending com.spocky.projengmenu; do
  cmd appops set "$P" REQUEST_INSTALL_PACKAGES allow
  cmd appops get "$P" REQUEST_INSTALL_PACKAGES
done
# -> REQUEST_INSTALL_PACKAGES: allow
```

After this, the system installer accepts sideloads and `pm install` works.

## 4.4 Command-line installation

```sh
# uid 1000 path (via /RunCmd): APK must be readable by the installer; /sdcard works,
# /data/local/tmp does not (SELinux: apk_data_file label).
pm install -r /sdcard/Download/app.apk

# uid 2000 path (adb shell): both /sdcard and /data/local/tmp work
adb install -r /data/local/tmp/app.apk
```

## 4.5 Related settings

| Setting | Default here | Notes |
|---------|--------------|-------|
| `secure install_non_market_apps` | `1` | global switch on; per-app appop is what blocks |
| `global package_verifier_enable` | `null` | verifier toggles not writable by uid 1000 (`SecurityException`) |
| `global verifier_verify_adb_installs` | `null` | same |
| `global package_verifier_user_consent` | `1` | Play Protect consent retained |

## 4.6 Applicable app variants

The SoC is arm64 but Android userspace is **32-bit** (`armv8l`), so `armeabi-v7a` APKs must be used.
Verified installs on the test unit: TizenTube Cobalt `cobalt-arm.apk` (requires the stock YouTube TV
app), SmartTube `armeabi-v7a`, Aniyomi `armeabi-v7a`.

## 4.7 Fix

- Ship the ROM with the documented pre-Android-8 behavior (`install_non_market_apps`) or expose the
  per-app toggle in Settings instead of forcing `deny` through appops.
- Do not pre-set `REQUEST_INSTALL_PACKAGES` to `deny` for packages the user installs.

## 4.8 Apps that install their own add-ons (Aniyomi extensions)

The same appop also breaks in-app add-on installers. Aniyomi's extensions are separate APKs that the
application installs itself, so the application — not the user — needs `REQUEST_INSTALL_PACKAGES`.
With the ROM default (`deny`) the extension list stays empty and the install fails without a useful
message.

Package IDs (verified against `aniyomiorg/aniyomi` `app/build.gradle.kts` and the release APK):

```
release  xyz.jmir.tachiyomi.mi
debug    xyz.jmir.tachiyomi.mi.debug
```

Note the internal namespace is `eu.kanade.tachiyomi` while the `applicationId` is not — checking the
wrong ID makes the fix look like it did nothing.

`scripts/app_perms.sh` applies the full set (appops + runtime grants + battery whitelist):

```sh
sh app_perms.sh                      # autodetects
sh app_perms.sh xyz.jmir.tachiyomi.mi
```

| Setting | Fixes |
|---------|-------|
| appop `REQUEST_INSTALL_PACKAGES` | extension installation |
| appop `MANAGE_EXTERNAL_STORAGE` | direct writes to `/sdcard/Aniyomi` without the SAF picker |
| appop `LEGACY_STORAGE` | pre-scoped-storage paths |
| `READ/WRITE_EXTERNAL_STORAGE` | library scanning, downloads |
| `dumpsys deviceidle whitelist +<pkg>` | long downloads killed by the power manager |
