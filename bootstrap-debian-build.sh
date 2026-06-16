#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# bootstrap-debian-build.sh  --  FALLBACK proot Debian (chaine qemu)
# A lancer dans TERMUX (pas dans le proot).
#
# Installe le filet de securite : un proot Debian MINIMAL + la chaine aapt2+qemu,
# au cas ou la compilation native Termux echoue. N'installe rien de superflu.
#
# A n'utiliser qu'une fois (ou pour reconstruire). Idempotent.
# La chaine NATIVE reste la voie par defaut ; ceci n'est qu'un secours.
# =============================================================================
set -e

echo "############################################################"
echo "#  APKforge - fallback Debian minimal (chaine aapt2+qemu)   #"
echo "############################################################"

HOME_DIR="/data/data/com.termux/files/home"
TOOLS="$HOME_DIR/android-build-tools"
DISTRO="debian"
ROOTFS="$PREFIX/var/lib/proot-distro/containers/$DISTRO"

# --- 1. proot-distro + Debian ------------------------------------------------
echo "== [1/3] proot-distro + Debian minimal =="
yes | pkg install -y proot-distro || true

if [ -d "$ROOTFS" ]; then
    echo "  Debian deja installe."
else
    proot-distro install "$DISTRO"
fi

# --- 2. Depot des outils dans le proot ---------------------------------------
echo "== [2/3] Copie des outils dans le proot =="
# On copie android-build-tools (deja clone cote Termux par forge-install.sh)
# dans le HOME root du proot, pour que setup-aapt2-qemu.sh et lib-i18n.sh
# soient cote a cote.
if [ ! -d "$TOOLS" ]; then
    echo "  ERREUR: $TOOLS introuvable cote Termux."
    echo "  Lance d'abord forge-install.sh (il clone android-build-tools)."
    exit 1
fi
PROOT_HOME="$ROOTFS/root"
mkdir -p "$PROOT_HOME/android-build-tools"
cp -a "$TOOLS/." "$PROOT_HOME/android-build-tools/"

# --- 3. Installation de la chaine DANS le proot ------------------------------
echo "== [3/3] Installation de la chaine aapt2+qemu (dans Debian) =="
# setup-aapt2-qemu.sh installe : qemu-user, toolchain du shim, JDK,
# libs amd64 minimales, aapt2 x86, et le SDK (android-36 uniquement).
# DEBIAN_FRONTEND pour eviter les prompts ; ABT_LANG=fr pour les messages.
proot-distro login "$DISTRO" -- env DEBIAN_FRONTEND=noninteractive ABT_LANG=fr \
    bash /root/android-build-tools/setup-aapt2-qemu.sh

echo
echo "============================================================"
echo "Fallback Debian pret. La chaine native reste prioritaire ;"
echo "le serveur basculera sur ce proot seulement si le natif"
echo "echoue pour une raison liee a la chaine."
echo "Relance APKforge : 'proot_ready' doit maintenant etre True."
echo "============================================================"
