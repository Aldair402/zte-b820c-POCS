#!/usr/bin/env bash
# build.sh — build HalEnvset.jar from HalEnvset.java.
#
# Requirements
#   * JDK (javac)
#   * d8 — r8.jar from
#       https://dl.google.com/dl/android/maven2/com/android/tools/r8/<ver>/r8-<ver>.jar
#   * platform stubs for android.os.HwBinder / android.os.IHwBinder / android.os.Process
#       - either $ANDROID_HOME/platforms/android-31/android.jar
#       - or a local stub package (a few empty-signature classes are enough to compile)
#   * hal.jar — the HIDL interface classes (ISystemControl + callbacks + asInterface).
#       Generated with hidl-gen from ISystemControl.hal, or extracted from the vendor image
#       (/vendor/framework/droidlogic.software.core.jar on this device).
#
# Layout used during the research: HalEnvset.jar + hal.jar pushed to /data/local/tmp.
set -euo pipefail

D8="${D8:-r8.jar}"
HALJAR="${HALJAR:-hal.jar}"
ANDROID_JAR="${ANDROID_JAR:-android.jar}"     # platform stubs (for HwBinder et al.)
OUT="${OUT:-HalEnvset.jar}"
MIN_API="${MIN_API:-30}"

javac -cp "$HALJAR:$ANDROID_JAR" -d classes HalEnvset.java

java -cp "$D8" com.android.tools.r8.D8 \
     --min-api "$MIN_API" \
     --classpath "$HALJAR" --classpath "$ANDROID_JAR" \
     --output out classes/vendor/amlogic/hardware/systemcontrol/V1_0/HalEnvset*.class

( cd out && jar cf "../$OUT" . )
echo "built: $OUT"
echo
cat <<EOF
deploy:
  adb push $OUT   /data/local/tmp/
  adb push $HALJAR /data/local/tmp/

run (adb shell, or the /RunCmd channel as uid 1000):
  CLASSPATH=/data/local/tmp/$OUT:/data/local/tmp/$HALJAR \\
    /system/bin/app_process /system/bin HalEnvset envget ubootenv.var.bootcmd
  CLASSPATH=… app_process /system/bin HalEnvset envset ubootenv.var.test 1
EOF
