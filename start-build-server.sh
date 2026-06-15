#!/bin/bash
# =============================================================================
# start-build-server.sh
# Lance le serveur de build et le maintient actif. A appeler depuis Termux
# (le serveur doit tourner dans l'environnement ou vit la chaine : si la
# chaine est dans le proot Ubuntu, ce script doit etre execute DANS le proot).
#
# Pour un demarrage automatique persistant, voir le service Termux plus bas.
# =============================================================================

set -u
# Charge les messages bilingues (EN par defaut, FR si ABT_LANG=fr).
_ABT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$_ABT_DIR/lib-i18n.sh" ] && source "$_ABT_DIR/lib-i18n.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
PORT="${BUILD_SERVER_PORT:-8765}"

command -v python3 >/dev/null || { echo "python3 requis"; exit 1; }

printf "$(t server_start)\n" "$PORT"
echo "(Ctrl-C pour arreter)"
exec python3 "$HERE/buildserver.py"

# -----------------------------------------------------------------------------
# DEMARRAGE AUTOMATIQUE (optionnel) via termux-services :
#
#   pkg install termux-services
#   mkdir -p $PREFIX/var/service/build-server
#   cat > $PREFIX/var/service/build-server/run <<'RUN'
#   #!/data/data/com.termux/files/usr/bin/sh
#   exec proot-distro login ubuntu -- bash /root/buildserver/start-build-server.sh
#   RUN
#   chmod +x $PREFIX/var/service/build-server/run
#   sv-enable build-server
#
# Note : adapte le chemin (/root/buildserver) a l'endroit ou tu places ces
# fichiers DANS le proot. Si la chaine est en Termux natif (pas proot),
# retire le 'proot-distro login ubuntu --'.
# -----------------------------------------------------------------------------
