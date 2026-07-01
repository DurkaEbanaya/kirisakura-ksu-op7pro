#!/bin/bash
# Build OemFix LSPosed module without Gradle
# Requirements: JDK 17, Android SDK build-tools 36.0.0, android-34 platform
set -e

SCRIPT_DIR="${0%/*}"
BUILD_DIR="$SCRIPT_DIR/build"
OBJ_DIR="$BUILD_DIR/obj"
APK_DIR="$BUILD_DIR/apk"
COMPILED_DIR="$BUILD_DIR/compiled"

ANDROID_JAR="${ANDROID_JAR:-/usr/local/share/android-commandlinetools/platforms/android-34/android.jar}"
BUILD_TOOLS="${BUILD_TOOLS:-/usr/local/share/android-commandlinetools/build-tools/36.0.0}"
JAVA_HOME="${JAVA_HOME:-/usr/local/opt/openjdk@17}"
KEYSTORE="${KEYSTORE:-../../vpnhide/lsposed/release.keystore}"
KS_ALIAS="${KS_ALIAS:-release}"
KS_PASS="${KS_PASS:-vpnhide123}"

export PATH="$JAVA_HOME/bin:$PATH"

echo "=== Compiling Java sources ==="
rm -rf "$OBJ_DIR"
mkdir -p "$OBJ_DIR"
javac -source 11 -target 11 -d "$OBJ_DIR" \
    -cp "$SCRIPT_DIR/stubs:$ANDROID_JAR" \
    $SCRIPT_DIR/stubs/de/robv/android/xposed/*.java \
    $SCRIPT_DIR/stubs/de/robv/android/xposed/callbacks/*.java \
    $SCRIPT_DIR/src/com/durka/oemfix/*.java

echo "=== Converting to DEX ==="
rm -f "$BUILD_DIR/classes.dex"
"$BUILD_TOOLS/d8" --min-api 30 --output "$BUILD_DIR" \
    "$OBJ_DIR"/com/durka/oemfix/FixEntry*.class

echo "=== Compiling resources ==="
rm -rf "$COMPILED_DIR"
mkdir -p "$COMPILED_DIR"
"$BUILD_TOOLS/aapt2" compile --dir "$APK_DIR/res" -o "$COMPILED_DIR"

echo "=== Linking APK ==="
rm -f "$BUILD_DIR/oemfix-unsigned.apk"
"$BUILD_TOOLS/aapt2" link \
    --manifest "$APK_DIR/AndroidManifest.xml" \
    -o "$BUILD_DIR/oemfix-unsigned.apk" \
    -I "$ANDROID_JAR" \
    --min-sdk-version 30 --target-sdk-version 34 \
    "$COMPILED_DIR"/*.flat

echo "=== Adding DEX and assets ==="
( cd "$BUILD_DIR" && zip -j oemfix-unsigned.apk classes.dex )
( cd "$APK_DIR" && zip "$BUILD_DIR/oemfix-unsigned.apk" assets/xposed_init )

echo "=== Zipalign ==="
"$BUILD_TOOLS/zipalign" -f 4 \
    "$BUILD_DIR/oemfix-unsigned.apk" \
    "$BUILD_DIR/oemfix-aligned.apk"

echo "=== Signing ==="
"$BUILD_TOOLS/apksigner" sign \
    --ks "$KEYSTORE" --ks-key-alias "$KS_ALIAS" \
    --ks-pass "pass:$KS_PASS" --key-pass "pass:$KS_PASS" \
    --out "$BUILD_DIR/oemfix-signed.apk" \
    "$BUILD_DIR/oemfix-aligned.apk"

echo "=== Verifying ==="
"$BUILD_TOOLS/apksigner" verify "$BUILD_DIR/oemfix-signed.apk"

echo ""
echo "Built: $BUILD_DIR/oemfix-signed.apk"
ls -la "$BUILD_DIR/oemfix-signed.apk"
