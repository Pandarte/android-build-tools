#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# setup-termux-native.sh
#
# Installe une chaine de compilation Android 100% NATIVE dans Termux :
#   - PAS de proot, PAS d'Ubuntu, PAS de qemu, PAS de shim.
#   - JDK ARM natif (Bionic) + Android SDK (cmdline-tools + build-tools ARM).
#   - aapt2 ARM natif fourni par le build-tools, pointe directement a Gradle
#     via android.aapt2FromMavenOverride.
#
# C'est la voie rapide : aapt2 tourne en natif, plus aucune emulation.
# L'ancienne chaine proot reste disponible en secours (setup-aapt2-qemu.sh).
#
# Usage (depuis Termux, PAS depuis le proot) :
#   bash ~/android-build-tools/setup-termux-native.sh
# =============================================================================
set -uo pipefail

# Charge les messages bilingues si presents (EN par defaut, FR si ABT_LANG=fr).
_ABT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$_ABT_DIR/lib-i18n.sh" ] && source "$_ABT_DIR/lib-i18n.sh"
# Repli si lib-i18n absent : t() renvoie son argument.
type -t t >/dev/null 2>&1 || t() { printf '%s' "$1"; }

PREFIX="/data/data/com.termux/files/usr"
HOME_DIR="/data/data/com.termux/files/home"
ANDROID_HOME="$HOME_DIR/android-sdk"
CMDLINE_VERSION="11076708"   # command line tools (linux) ; fonctionne via le JDK
PLATFORM="android-36"
BUILD_TOOLS="36.0.0"
GRADLE_PROPS="$HOME_DIR/.gradle/gradle.properties"

echo "=== [1/6] Refus du contexte proot ==="
# Ce script DOIT tourner dans Termux natif. Si on est dans un proot, stop.
if [ -n "${PROOT_L2S:-}" ] || grep -qi 'proot' /proc/self/status 2>/dev/null; then
    echo "ERREUR / ERROR: lance ce script depuis Termux, PAS depuis le proot."
    exit 1
fi

echo "=== [2/6] Paquets Termux (jdk, wget, unzip) ==="
pkg update -y && pkg install -y wget unzip openjdk-21 || {
    echo "ERREUR / ERROR: installation des paquets Termux a echoue."; exit 1; }

# JAVA_HOME pour Termux (openjdk est dans \$PREFIX/lib/jvm ou expose par pkg).
export JAVA_HOME="$PREFIX/opt/openjdk"
[ -d "$JAVA_HOME" ] || JAVA_HOME="$(dirname "$(dirname "$(command -v java)")")"

echo "=== [3/6] Android SDK (cmdline-tools) ==="
if [ ! -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
    mkdir -p "$ANDROID_HOME/cmdline-tools"
    cd "$HOME_DIR"
    wget -q -O cmdline-tools.zip \
        "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_VERSION}_latest.zip" || {
        echo "ERREUR / ERROR: telechargement cmdline-tools echoue."; exit 1; }
    unzip -q cmdline-tools.zip -d "$ANDROID_HOME/cmdline-tools"
    mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
    rm -f cmdline-tools.zip
fi
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

echo "=== [4/6] Licences + plateforme + build-tools ==="
# sdkmanager tourne avec le JDK Termux ; sur ARM il fournit l'aapt2 ARM natif.
yes | sdkmanager --sdk_root="$ANDROID_HOME" --licenses >/dev/null 2>&1 || true
sdkmanager --sdk_root="$ANDROID_HOME" \
    "platform-tools" "platforms;$PLATFORM" "build-tools;$BUILD_TOOLS" || {
    echo "ERREUR / ERROR: sdkmanager a echoue (build-tools $BUILD_TOOLS indisponible ?)."
    echo "  Essaie une version plus basse, ex: build-tools;34.0.0"
    exit 1; }

AAPT2="$ANDROID_HOME/build-tools/$BUILD_TOOLS/aapt2"

echo "=== [5/6] Verification aapt2 ARM natif ==="
if [ ! -x "$AAPT2" ]; then
    echo "ERREUR / ERROR: aapt2 introuvable a $AAPT2"; exit 1
fi
ARCH_INFO="$(file "$AAPT2" 2>/dev/null || true)"
echo "  $ARCH_INFO"
if echo "$ARCH_INFO" | grep -qiE 'x86-64|x86_64|Intel'; then
    echo "AVERTISSEMENT / WARNING: l'aapt2 fourni est x86, pas ARM."
    echo "  Le build natif echouera. Reste sur la chaine proot (qemu) pour l'instant,"
    echo "  ou installe une build-tools dont l'aapt2 est aarch64."
    # On continue quand meme pour ecrire la config, l'utilisateur decidera.
fi

echo "=== [6/6] Config Gradle (aapt2FromMavenOverride) ==="
mkdir -p "$(dirname "$GRADLE_PROPS")"
# Retire une ancienne ligne d'override puis ajoute la bonne.
if [ -f "$GRADLE_PROPS" ]; then
    sed -i '/android.aapt2FromMavenOverride/d' "$GRADLE_PROPS"
fi
echo "android.aapt2FromMavenOverride=$AAPT2" >> "$GRADLE_PROPS"
# Gradle/AGP recents : autorise l'override sans verification stricte si besoin.
grep -q 'android.aapt2FromMavenIgnore' "$GRADLE_PROPS" 2>/dev/null || \
    echo "android.aapt2FromMavenIgnore=true" >> "$GRADLE_PROPS"

echo
echo "============================================================"
echo " Chaine Termux-native prete. / Termux-native chain ready."
echo "   JAVA_HOME      = $JAVA_HOME"
echo "   ANDROID_HOME   = $ANDROID_HOME"
echo "   aapt2 (ARM)    = $AAPT2"
echo "   gradle.props   = $GRADLE_PROPS"
echo " Pour builder : bash ~/android-build-tools/build-termux-native.sh <url-git>"
echo "============================================================"
