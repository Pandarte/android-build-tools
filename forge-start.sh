#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# forge-start.sh  --  DEMARRAGE RAPIDE (chaine native + proot en secours)
# A coller et lancer dans TERMUX.
#
# Le serveur tourne DESORMAIS directement dans Termux (pas dans le proot),
# car il pilote les DEUX chaines :
#   - NATIVE : build-termux-native.sh (aapt2 ARM, sans qemu) -> par defaut
#   - PROOT  : android-builder.sh dans Debian (qemu)         -> secours auto
#
# Le buildserver choisit native d'abord et bascule sur proot si l'echec vient
# de la chaine (pas du projet).
# =============================================================================
set -u

echo "=== APKforge - demarrage rapide ==="

HOME_DIR="/data/data/com.termux/files/home"
TOOLS="$HOME_DIR/android-build-tools"
SERVER_DIR="$HOME_DIR/buildserver"
SERVER="$SERVER_DIR/buildserver.py"
NATIVE_AAPT2="$HOME_DIR/android-sdk/build-tools/35.0.0/aapt2"
DEBIAN_ROOT="$PREFIX/var/lib/proot-distro/containers/debian"

# --- Verifie qu'au moins une chaine est presente -----------------------------
native_ready=0
proot_ready=0
[ -x "$NATIVE_AAPT2" ] && [ -f "$TOOLS/build-termux-native.sh" ] && native_ready=1
[ -d "$DEBIAN_ROOT" ]  && [ -f "$TOOLS/android-builder.sh" ]     && proot_ready=1

echo "-- chaines disponibles --"
[ "$native_ready" = 1 ] && echo "  [x] native (sans qemu)" || echo "  [ ] native"
[ "$proot_ready"  = 1 ] && echo "  [x] proot Debian (qemu)" || echo "  [ ] proot"

if [ "$native_ready" = 0 ] && [ "$proot_ready" = 0 ]; then
    echo "ERREUR: aucune chaine installee."
    echo "  Native : bash $TOOLS/setup-termux-native.sh"
    echo "  Proot  : bash $HOME_DIR/bootstrap-debian-build.sh"
    exit 1
fi

# --- Repare/installe la chaine native si elle manque mais est souhaitee -------
if [ "$native_ready" = 0 ] && [ -f "$TOOLS/setup-termux-native.sh" ]; then
    echo "-- chaine native absente : installation --"
    bash "$TOOLS/setup-termux-native.sh" || \
        echo "  (echec setup native ; on continuera avec le proot si dispo)"
fi

# --- S'assure que le buildserver est en place --------------------------------
mkdir -p "$SERVER_DIR"
if [ ! -f "$SERVER" ] && [ -f "$TOOLS/buildserver.py" ]; then
    cp "$TOOLS/buildserver.py" "$SERVER"
fi
if [ ! -f "$SERVER" ]; then
    echo "ERREUR: serveur introuvable a $SERVER"
    echo "  Recopie : cp $TOOLS/buildserver.py $SERVER"
    exit 1
fi

# --- Environnement natif pour le serveur (ANDROID_HOME, java du PATH) ---------
export ANDROID_HOME="$HOME_DIR/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

echo "-- demarrage du serveur (Termux) --"
echo "Laisse Termux ouvert. Retourne dans APKforge et appuie sur 'Reessayer'."
echo
exec python3 "$SERVER"
