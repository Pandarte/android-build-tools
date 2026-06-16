#!/bin/bash
# =============================================================================
# setup-aapt2-qemu.sh
# Installe la chaîne complète permettant de compiler des projets Android/Gradle
# en local sur un appareil ARM (Termux -> proot Ubuntu ou Debian), en faisant tourner
# l'aapt2 x86 de Google via qemu.
#
# A LANCER UNE SEULE FOIS (ou pour reconstruire sur un système propre).
# Idempotent : on peut le relancer sans casser quoi que ce soit.
#
# Prérequis : être DANS un proot Ubuntu ou Debian, en root.
# =============================================================================

set -e
# Charge les messages bilingues (EN par defaut, FR si ABT_LANG=fr).
_ABT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$_ABT_DIR/lib-i18n.sh" ] && source "$_ABT_DIR/lib-i18n.sh"


TOOLS_DIR="$HOME/android-build-tools"
AAPT2_VERSION="8.13.0-13719691"   # version de l'aapt2 x86 ; doit correspondre
                                   # a l'AGP du projet (ici AGP 8.13). Voir NOTE.
AAPT2_DIR="$HOME/aapt2-x86"
SHIM_SRC="$HOME/aapt2-shim.c"
SHIM_BIN="$HOME/aapt2-shim"

echo "$(t setup_step1)"
if [ ! -f /etc/os-release ] || ! grep -qiE "ubuntu|debian" /etc/os-release; then
    echo "$(t proot_only)"
    exit 1
fi
mkdir -p "$TOOLS_DIR"

echo "$(t setup_pkgs)"
apt-get update -y
apt-get install -y --no-install-recommends \
    qemu-user build-essential gcc libc6-dev file wget unzip zip ca-certificates \
    openjdk-21-jdk-headless

echo "$(t setup_step3)"
dpkg --add-architecture amd64
apt-get update -y
# libs minimales dont l'aapt2 x86 a besoin pour se charger sous qemu
apt-get install -y libc6:amd64 libstdc++6:amd64 zlib1g:amd64

printf "$(t setup_dl_aapt2)\n" "$AAPT2_VERSION"
mkdir -p "$AAPT2_DIR"
if [ ! -f "$AAPT2_DIR/aapt2" ]; then
    cd /tmp
    rm -f aapt2.jar
    # NOTE: l'URL correcte contient bien /dl/  (sinon 404).
    # classifier 'linux' = x86_64 (Google ne fournit PAS de linux-aarch64).
    wget -O aapt2.jar \
      "https://dl.google.com/dl/android/maven2/com/android/tools/build/aapt2/${AAPT2_VERSION}/aapt2-${AAPT2_VERSION}-linux.jar"
    rm -rf aapt2-x86-extract
    unzip -o aapt2.jar -d aapt2-x86-extract
    cp aapt2-x86-extract/aapt2 "$AAPT2_DIR/aapt2"
    chmod +x "$AAPT2_DIR/aapt2"
fi
echo "aapt2 x86 : $(file "$AAPT2_DIR/aapt2" 2>/dev/null | cut -d, -f1-2 || echo "$(t bin_downloaded)")"

echo "$(t setup_compile_shim)"
cat > "$SHIM_SRC" <<EOF
/* Shim ELF natif ARM. Gradle exige un vrai binaire ELF (il refuse un script
 * shell). Ce binaire ne fait que relancer l'aapt2 x86 via qemu, en passant
 * tous les arguments. */
#include <unistd.h>
int main(int argc, char **argv) {
    char *qemu = "/usr/bin/qemu-x86_64";
    char *real = "$AAPT2_DIR/aapt2";
    char *new_argv[argc + 2];
    new_argv[0] = qemu;
    new_argv[1] = real;
    for (int i = 1; i < argc; i++) new_argv[i + 1] = argv[i];
    new_argv[argc + 1] = 0;
    execv(qemu, new_argv);
    return 127;
}
EOF
gcc "$SHIM_SRC" -o "$SHIM_BIN"
chmod +x "$SHIM_BIN"

echo "$(t setup_test_shim)"
# Note: aapt2 ecrit sa version sur stderr selon les versions -> on capture 2>&1.
SHIM_OUT="$("$SHIM_BIN" version 2>&1 || true)"
if echo "$SHIM_OUT" | grep -q "Android Asset Packaging Tool"; then
    echo "OK -> $SHIM_OUT"
else
    echo "$(t shim_bad_version)"
    echo "Sortie: $(echo "$SHIM_OUT" | head -3)"
    exit 1
fi

echo
echo "============================================================"
echo "$(t chain_installed)"
echo "   aapt2 x86 : $AAPT2_DIR/aapt2"
echo "   shim ARM  : $SHIM_BIN"
echo
echo "$(t use_build_local)"
echo "$(t use_build_local2)"
echo "============================================================"
