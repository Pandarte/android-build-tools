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

# --- Auto-mise a jour du depot (silencieuse) ---------------------------------
# Au demarrage, on verifie si android-build-tools est a jour. Si une version
# distante existe ET que l'arbre local est propre (aucune modif non commitee),
# on pull (fast-forward) puis on RE-EXEC ce script a jour. Le re-exec est
# indispensable : bash lit le fichier au fil de l'execution, donc le modifier en
# cours de route corromprait le run. Le garde APKFORGE_SELF_UPDATED evite toute
# boucle (on ne tente la MAJ qu'une fois par lancement).
if [ -z "${APKFORGE_SELF_UPDATED:-}" ] && command -v git >/dev/null 2>&1 \
   && [ -d "$TOOLS/.git" ]; then
    did_update=0
    if cd "$TOOLS" 2>/dev/null; then
        # Fetch leger et borne dans le temps (ne bloque pas si reseau lent/absent).
        if timeout 15 git fetch --quiet origin 2>/dev/null; then
            branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
            local_rev="$(git rev-parse HEAD 2>/dev/null || echo '')"
            remote_rev="$(git rev-parse "origin/$branch" 2>/dev/null || echo '')"

            if [ -n "$branch" ] && [ -n "$remote_rev" ] \
               && [ "$local_rev" != "$remote_rev" ]; then
                # En retard sur le distant. On ne pull QUE si l'arbre est propre.
                if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
                    if git merge --ff-only --quiet "origin/$branch" 2>/dev/null; then
                        did_update=1
                    fi
                else
                    echo "-- MAJ dispo, mais modifs locales non commitees : pull ignore --" >&2
                fi
            fi
        fi
        cd "$HOME_DIR" 2>/dev/null || true
    fi

    if [ "$did_update" = 1 ]; then
        echo "-- depot mis a jour -> relance du script --"
        export APKFORGE_SELF_UPDATED=1
        exec bash "$TOOLS/forge-start.sh" "$@"
    fi
fi


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
