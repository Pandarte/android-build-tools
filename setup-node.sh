#!/bin/bash
# =============================================================================
# setup-node.sh  --  installe node/npm (via nvm) dans Ubuntu proot, proprement.
# A lancer DANS Ubuntu (proot-distro login ubuntu), une seule fois.
# Repare le cas du 'npm' d'apt casse (module glob introuvable).
# =============================================================================
set -e

echo "== Nettoyage d'un eventuel node/npm d'apt casse =="
apt remove -y nodejs npm libnode72 libnode108 libnode109 libnode115 libnode127 2>/dev/null || true
apt autoremove -y 2>/dev/null || true

echo "== Installation de nvm (si absent) =="
if [ ! -s "$HOME/.nvm/nvm.sh" ]; then
    apt update && apt install -y curl ca-certificates
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
fi

export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1091
. "$NVM_DIR/nvm.sh"

echo "== Installation de Node 20 LTS =="
nvm install 20
nvm use 20

echo "== Symlinks dans /usr/local/bin (PATH systeme, vus en contexte non-interactif) =="
ln -sf "$(which node)" /usr/local/bin/node
ln -sf "$(which npm)"  /usr/local/bin/npm
ln -sf "$(which npx)"  /usr/local/bin/npx

echo "== Capacitor CLI global =="
npm install -g @capacitor/cli || true

echo
echo "== Verification =="
echo "node : $(/usr/local/bin/node --version)"
echo "npm  : $(/usr/local/bin/npm --version)"
echo "npx  : $(/usr/local/bin/npx --version)"
echo
echo "OK. node/npm sont prets et visibles par android-builder.sh."
