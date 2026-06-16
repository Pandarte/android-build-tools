#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# setup-termux-native.sh
#
# Installe une chaine de compilation Android 100% NATIVE dans Termux :
#   - PAS de proot, PAS d'Ubuntu/Debian, PAS de qemu, PAS de shim.
#   - JDK ARM natif (Bionic) + Android SDK aarch64 (build-tools + platforms).
#   - aapt2 ARM natif (build-tools 35.0.0 de lzhiyong/termux-ndk), pointe
#     directement a Gradle via android.aapt2FromMavenOverride.
#
# C'est la voie rapide : aapt2 tourne en natif, plus aucune emulation.
# L'ancienne chaine proot+qemu reste disponible en secours
# (bootstrap-debian-build.sh / setup-aapt2-qemu.sh).
#
# IMPORTANT : le SDK officiel de Google installe un aapt2 *x86* sur ARM
# (Exec format error). On utilise donc le SDK aarch64 precompile de
# lzhiyong/termux-ndk, qui fournit un vrai aapt2 ARM + les plateformes
# android-35 ET android-36.
#
# Usage (depuis Termux, PAS depuis le proot) :
#   bash ~/android-build-tools/setup-termux-native.sh
# =============================================================================
set -uo pipefail

PREFIX="/data/data/com.termux/files/usr"
HOME_DIR="/data/data/com.termux/files/home"
ANDROID_HOME="$HOME_DIR/android-sdk"
BUILD_TOOLS="35.0.0"   # version fournie par le SDK aarch64 lzhiyong
AAPT2="$ANDROID_HOME/build-tools/$BUILD_TOOLS/aapt2"
GRADLE_PROPS="$HOME_DIR/.gradle/gradle.properties"
SDK_ARCHIVE_URL="https://github.com/lzhiyong/termux-ndk/releases/download/android-sdk/android-sdk-aarch64.7z"
SDK_ARCHIVE="$HOME_DIR/android-sdk-aarch64.7z"

# --- Patch des binaires build-tools x86 -> ARM -------------------------------
# Certains projets (ex. Kvaesitso) demandent une version de build-tools que
# seul le SDK *Google* fournit (installe par setup-aapt2-qemu.sh). Ce SDK pose
# des binaires x86_64 qui plantent sur ARM ("Syntax error: word unexpected").
# On remplace les binaires reellement invoques par AGP par leurs equivalents
# ARM64 natifs (lzhiyong/android-sdk-tools, lies statiquement).
#
# Liste ciblee : on NE patche QUE ce qui est utile et invoque en pratique.
#   - aidl        : compilation des interfaces AIDL (.aidl)
#   - zipalign    : alignement de l'APK (quasi tous les builds)
#   - aapt        : ancien AAPT, encore appele par des projets/plugins legacy
#   - split-select: APK splits (ABI/density)
# Ignores volontairement : aapt2 (override ARM separe), d8/apksigner/lld
# (scripts JVM, pas natifs), bcc_compat/llvm-rs-cc/dexdump (RenderScript mort
# ou outils de debug jamais dans la chaine de build).
BT_PATCH_TOOLS="aidl zipalign aapt split-select"
BT_ARM_RELEASE="35.0.2"
BT_ARM_ASSET="android-sdk-tools-static-aarch64.zip"
BT_ARM_URL="https://github.com/lzhiyong/android-sdk-tools/releases/download/$BT_ARM_RELEASE/$BT_ARM_ASSET"

# Detecte si un fichier est un ELF ARM aarch64 SANS dependre de `file`
# (souvent absent sur Termux). Lit le magic ELF puis e_machine (0xB7=AArch64).
is_arm64() {
    local f="$1"
    [ -f "$f" ] || return 1
    local magic mach
    magic="$(head -c4 "$f" | od -An -tx1 | tr -d ' \n')"
    [ "$magic" = "7f454c46" ] || return 1
    mach="$(dd if="$f" bs=1 skip=18 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')"
    [ "$mach" = "b7" ]
}

echo "=== [1/6] Refus du contexte proot ==="
# Ce script DOIT tourner dans Termux natif. Si on est dans un proot, stop.
if [ -n "${PROOT_L2S:-}" ] || grep -qi 'proot' /proc/self/status 2>/dev/null; then
    echo "ERREUR: lance ce script depuis Termux, PAS depuis le proot."
    exit 1
fi

echo "=== [2/6] Paquets Termux (jdk, wget, p7zip) ==="
pkg update -y && pkg install -y wget p7zip openjdk-21 || {
    echo "ERREUR: installation des paquets Termux a echoue."; exit 1; }

echo "=== [3/6] SDK aarch64 (aapt2 ARM natif + platforms) ==="
if [ -x "$AAPT2" ]; then
    echo "  SDK aarch64 deja present, on saute le telechargement."
else
    cd "$HOME_DIR"
    if [ ! -f "$SDK_ARCHIVE" ]; then
        echo "  Telechargement du SDK aarch64 (~291 Mo)..."
        wget -O "$SDK_ARCHIVE" "$SDK_ARCHIVE_URL" || {
            echo "ERREUR: telechargement du SDK aarch64 echoue."; exit 1; }
    fi
    echo "  Extraction..."
    7z x -y "$SDK_ARCHIVE" >/dev/null || {
        echo "ERREUR: extraction du SDK aarch64 echouee."; exit 1; }
    # On peut supprimer l'archive pour gagner de la place (commenter si on veut la garder).
    rm -f "$SDK_ARCHIVE"
fi

echo "=== [4/6] Verification aapt2 ARM natif ==="
if [ ! -x "$AAPT2" ]; then
    echo "ERREUR: aapt2 introuvable a $AAPT2 apres extraction."; exit 1
fi
# Test fonctionnel : l'aapt2 doit repondre nativement (pas d'Exec format error).
AAPT2_VER="$("$AAPT2" version 2>&1 || true)"
if echo "$AAPT2_VER" | grep -q "Android Asset Packaging Tool"; then
    echo "  OK -> $AAPT2_VER"
else
    echo "ERREUR: aapt2 ne repond pas nativement."
    echo "  Sortie: $AAPT2_VER"
    exit 1
fi

echo "=== [5/6] Patch build-tools x86 -> ARM (aidl, zipalign, aapt, split-select) ==="
# On parcourt toutes les versions de build-tools installees (le SDK Google de
# setup-aapt2-qemu.sh peut en poser une, ex. 36.0.0, avec des binaires x86).
BT_ROOT="$ANDROID_HOME/build-tools"
_need_patch=""
if [ -d "$BT_ROOT" ]; then
    for _btdir in "$BT_ROOT"/*/; do
        for _tool in $BT_PATCH_TOOLS; do
            _tp="$_btdir$_tool"
            [ -f "$_tp" ] || continue
            if ! is_arm64 "$_tp"; then
                _need_patch="yes"
            fi
        done
    done
fi

if [ -z "$_need_patch" ]; then
    echo "  Tous les binaires cibles sont deja ARM (ou absents). Rien a patcher."
else
    _tmp_arm="$(mktemp -d)"
    echo "  Telechargement des build-tools ARM64 ($BT_ARM_RELEASE)..."
    if wget -q -O "$_tmp_arm/arm.zip" "$BT_ARM_URL"; then
        ( cd "$_tmp_arm" && 7z x -y arm.zip >/dev/null 2>&1 || unzip -q arm.zip )
        for _btdir in "$BT_ROOT"/*/; do
            for _tool in $BT_PATCH_TOOLS; do
                _tp="$_btdir$_tool"
                [ -f "$_tp" ] || continue
                is_arm64 "$_tp" && continue   # deja ARM, on saute
                _src="$(find "$_tmp_arm" -type f -name "$_tool" | head -n1)"
                if [ -z "$_src" ] || ! is_arm64 "$_src"; then
                    echo "  ! $_tool : pas de version ARM trouvee dans l'archive, ignore."
                    continue
                fi
                [ -f "$_tp.x86.bak" ] || cp -p "$_tp" "$_tp.x86.bak"
                cp "$_src" "$_tp" && chmod +x "$_tp"
                echo "  OK $_tool patche ARM dans $(basename "$_btdir")"
            done
        done
    else
        echo "  ! Telechargement des build-tools ARM echoue ($BT_ARM_URL)."
        echo "  ! Le build pourra echouer sur aidl/zipalign si un projet les invoque."
    fi
    rm -rf "$_tmp_arm"
fi

echo "=== [6/6] Config Gradle (aapt2 + memoire mobile) ==="
mkdir -p "$(dirname "$GRADLE_PROPS")"
# Retire les anciennes lignes gerees par ce script puis (re)ajoute les bonnes.
if [ -f "$GRADLE_PROPS" ]; then
    sed -i '/android.aapt2FromMavenOverride/d' "$GRADLE_PROPS"
    sed -i '/^org.gradle.jvmargs/d' "$GRADLE_PROPS"
fi
echo "android.aapt2FromMavenOverride=$AAPT2" >> "$GRADLE_PROPS"

# Limite memoire pour mobile. CE fichier est dans GRADLE_USER_HOME (~/.gradle),
# qui a PRIORITE sur le gradle.properties d'un projet : un projet qui demande
# -Xmx4096m (frequent en Kotlin Multiplatform, ex. Grit) verra donc SA valeur
# ecrasee par celle-ci. Sans ca, Android tue le process Gradle en cours de build
# ("Gradle build daemon disappeared unexpectedly"). 2 Go de heap + metaspace
# borne est un bon compromis pour un telephone ; baisse a 1536m si besoin.
GRADLE_JVMARGS="${GRADLE_JVMARGS:--Xmx2048m -XX:MaxMetaspaceSize=512m -Dfile.encoding=UTF-8}"
echo "org.gradle.jvmargs=$GRADLE_JVMARGS" >> "$GRADLE_PROPS"

# JAVA_HOME : sur Termux, le java du PATH suffit. On le calcule pour info.
JAVA_HOME_DETECTED="$(dirname "$(dirname "$(command -v java)")")"

echo
echo "============================================================"
echo " Chaine Termux-native prete (sans qemu)."
echo "   ANDROID_HOME   = $ANDROID_HOME"
echo "   aapt2 (ARM)    = $AAPT2"
echo "   platforms      = $(ls "$ANDROID_HOME/platforms" 2>/dev/null | tr '\n' ' ')"
echo "   gradle.props   = $GRADLE_PROPS"
echo "   java           = $JAVA_HOME_DETECTED"
echo " Pour builder : bash ~/android-build-tools/build-termux-native.sh <url-git>"
echo "============================================================"
