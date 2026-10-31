/*
 * HalEnvset.java — minimal client for the root-owned Amlogic system_control HAL.
 *
 * Interface: vendor.amlogic.hardware.systemcontrol@1.0::ISystemControl
 * Daemon   : systemcontrol (uid 0, SELinux u:r:hal_systemcontrol_default:s0)
 *
 * Relevant methods:
 *   getBootEnv(String name, getBootEnvCallback cb)   // "ubootenv.var.<name>"
 *   setBootEnv(String name, String value)            // writes the U-Boot env partition (CRC fixed)
 *
 * Build:  see build.sh (d8 + the HIDL stub classes from the vendor jar)
 * Run  :  CLASSPATH=HalEnvset.jar:/data/local/tmp/hal.jar \
 *           /system/bin/app_process /system/bin HalEnvset envget ubootenv.var.bootcmd
 *
 * Notes
 *  - Runs through app_process: no APK, no install, no root required. The caller is uid 1000
 *    (system_app) when invoked from the factory /RunCmd channel.
 *  - "UnsatisfiedLinkError: libandroidicu.so / libhwbinder.so" on stderr is noise: the HwBinder
 *    path used here is reached through the platform runtime that app_process already loaded.
 */
package vendor.amlogic.hardware.systemcontrol.V1_0;

import android.os.HwBinder;

public final class HalEnvset {

    private static final String IFACE = "vendor.amlogic.hardware.systemcontrol@1.0::ISystemControl";

    private static void p(String s) {
        System.out.println(s);
    }

    public static void main(String[] args) {
        String action = args.length > 0 ? args[0] : "info";
        try {
            ISystemControl sc = ISystemControl.asInterface(
                    HwBinder.getService(IFACE, "default"));
            if (sc == null) {
                p("SERVICE NULL");
                return;
            }
            switch (action) {
                case "envget": {
                    sc.getBootEnv(args[1], (rc, v) -> p("getBootEnv(" + args[1] + ") rc=" + rc + " val=" + v));
                    Thread.sleep(1500);
                    break;
                }
                case "envset": {
                    sc.setBootEnv(args[1], args[2]);
                    p("setBootEnv done");
                    break;
                }
                case "rs": {
                    sc.readSysfs(args[1], (rc, v) -> p("readSysfs(" + args[1] + ") rc=" + rc + " val=" + v));
                    Thread.sleep(1500);
                    break;
                }
                case "ws": {
                    p("writeSysfs rc=" + sc.writeSysfs(args[1], args[2]));
                    break;
                }
                case "setprop": {
                    p("setProperty rc=" + sc.setProperty(args[1], args[2]));
                    break;
                }
                case "ukr": {
                    sc.readUnifyKey(args[1], (rc, v) -> p("readUnifyKey(" + args[1] + ") rc=" + rc + " val=" + v));
                    Thread.sleep(1500);
                    break;
                }
                default:
                    p("usage: HalEnvset envget <var> | envset <var> <value> | rs <path> | "
                      + "ws <path> <value> | setprop <k> <v> | ukr <key>");
            }
        } catch (Throwable t) {
            p("EXCEPTION: " + t);
        }
    }
}
