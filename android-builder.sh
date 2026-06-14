#!/bin/bash
# =============================================================================
# android-builder.sh
# Compile un projet Android en local a partir de son URL git, sur ARM,
# via la chaine aapt2+qemu.
#
# Usage :
#   android-builder.sh <url-git> [--branch <nom>] [--subdir <chemin>] [--task <tache>]
#
# Exemples :
#   android-builder.sh https://github.com/Pandarte/souffle-app
#   android-builder.sh https://github.com/x/y --branch dev --task assembleRelease
#   android-builder.sh https://github.com/x/monorepo --subdir apps/mobile
#
# Strategie (selon ton choix) : large couverture (Flutter / Capacitor /
# React Native / Android natif), tentative AUTOMATIQUE, et en cas d'echec
# de build -> diagnostic + on te demande quoi faire.
# =============================================================================

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/detect-project.sh"

# --- chargement de node/npm --------------------------------------------------
# Quand ce script est lance via 'proot-distro login ubuntu -- ...', le .bashrc
# n'est PAS charge : node/npm installes par nvm ne sont pas dans le PATH.
# Strategie en 3 temps (du plus fiable au secours) :
#   1) /usr/local/bin (symlinks crees a l'install) est deja dans le PATH systeme
#   2) on charge nvm explicitement
#   3) en dernier recours on ajoute a la main le bin de la version nvm la + recente
export PATH="/usr/local/bin:$PATH"
if [ -s "$HOME/.nvm/nvm.sh" ]; then
    export NVM_DIR="$HOME/.nvm"
    # shellcheck disable=SC1091
    . "$NVM_DIR/nvm.sh" >/dev/null 2>&1 || true
fi
if ! command -v node >/dev/null 2>&1; then
    NODE_BIN="$(ls -d "$HOME"/.nvm/versions/node/*/bin 2>/dev/null | sort -V | tail -1)"
    [ -n "${NODE_BIN:-}" ] && export PATH="$NODE_BIN:$PATH"
fi

# --- parse args --------------------------------------------------------------
URL="${1:?Usage: android-builder.sh <url-git> [--branch b] [--subdir d] [--task t]}"
shift || true
BRANCH=""; SUBDIR=""; TASK="assembleDebug"
while [ $# -gt 0 ]; do
    case "$1" in
        --branch) BRANCH="$2"; shift 2;;
        --subdir) SUBDIR="$2"; shift 2;;
        --task)   TASK="$2"; shift 2;;
        *) echo "Option inconnue: $1"; exit 1;;
    esac
done

WORK="$HOME/android-builds"
mkdir -p "$WORK"
NAME="$(basename "$URL" .git)"
DEST="$WORK/$NAME"
ANDROID_SDK="$HOME/android-sdk"
SHIM_BIN="$HOME/aapt2-shim"

# --- 0. pre-checks -----------------------------------------------------------
if [ ! -x "$SHIM_BIN" ]; then
    echo "ERREUR: chaine aapt2+qemu absente. Lance d'abord :"
    echo "    bash $HERE/setup-aapt2-qemu.sh"
    exit 1
fi
command -v git >/dev/null || { apt-get update -y && apt-get install -y git; }

export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(which java)")")")"
export ANDROID_HOME="$ANDROID_SDK"
export PATH="$ANDROID_SDK/cmdline-tools/latest/bin:$ANDROID_SDK/platform-tools:$PATH"

# --- 1. clone ----------------------------------------------------------------
echo "=== [1] Clone de $URL ==="
if [ -d "$DEST/.git" ]; then
    echo "Deja clone, mise a jour..."
    git -C "$DEST" pull --ff-only || echo "(pull ignore)"
else
    if [ -n "$BRANCH" ]; then
        git clone --depth 1 --branch "$BRANCH" "$URL" "$DEST"
    else
        git clone --depth 1 "$URL" "$DEST"
    fi
fi
ROOT="$DEST"
[ -n "$SUBDIR" ] && ROOT="$DEST/$SUBDIR"
[ -d "$ROOT" ] || { echo "ERREUR: sous-dossier $SUBDIR introuvable"; exit 1; }

# --- 2. detection ------------------------------------------------------------
echo "=== [2] Detection du type de projet ==="
TYPE="$(detect_project_type "$ROOT")"
echo "Type detecte : $TYPE"
if [ "$TYPE" = "unknown" ]; then
    echo "AVERTISSEMENT: type non reconnu. On tente un build Gradle generique."
fi

GRADLE_DIR="$(find_gradle_dir "$ROOT" "$TYPE")"
echo "Module Android : ${GRADLE_DIR:-<aucun>}"

# besoins
COMPILE_SDK="$(extract_sdk "$ROOT" compileSdk)"
TARGET_SDK="$(extract_sdk "$ROOT" targetSdk)"
MIN_SDK="$(extract_sdk "$ROOT" minSdk)"
AGP="$(extract_agp "$ROOT")"
echo "Besoins extraits : compileSdk=${COMPILE_SDK:-?} targetSdk=${TARGET_SDK:-?} minSdk=${MIN_SDK:-?} AGP=${AGP:-?}"

# avertissement version aapt2 vs AGP
SHIM_AGP="8.13"
if [ -n "$AGP" ] && [[ "$AGP" != $SHIM_AGP* ]]; then
    echo "NOTE: AGP du projet ($AGP) != version de l'aapt2 installe ($SHIM_AGP.x)."
    echo "      Si le build echoue sur aapt2, voir README (section 'Version aapt2/AGP')."
fi

# --- 3. installation des plateformes SDK requises ----------------------------
echo "=== [3] Installation des plateformes SDK manquantes ==="
if [ -d "$ANDROID_SDK" ]; then
    for sdk in $(list_required_sdks "$ROOT"); do
        if [ ! -d "$ANDROID_SDK/platforms/android-$sdk" ]; then
            echo "  -> platforms;android-$sdk"
            yes | sdkmanager "platforms;android-$sdk" >/dev/null 2>&1 || \
                echo "     (echec install android-$sdk, on continue)"
        fi
    done
else
    echo "ATTENTION: SDK Android absent ($ANDROID_SDK). Voir README pour l'installer."
fi

# --- 4. preparation selon le type --------------------------------------------
echo "=== [4] Preparation ($TYPE) ==="
prepare_failed=0

# pour capacitor/react-native, node est indispensable
case "$TYPE" in
    capacitor|react-native)
        if ! command -v node >/dev/null 2>&1; then
            echo "ERREUR: node introuvable dans Ubuntu."
            echo "  Installe-le (une fois) :"
            echo "    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash"
            echo "    export NVM_DIR=\"\$HOME/.nvm\"; . \"\$NVM_DIR/nvm.sh\"; nvm install 20"
            echo "    ln -sf \"\$(which node)\" /usr/local/bin/node"
            echo "    ln -sf \"\$(which npm)\"  /usr/local/bin/npm"
            echo "    ln -sf \"\$(which npx)\"  /usr/local/bin/npx"
            prepare_failed=1
        else
            echo "node $(node --version), npm $(npm --version)"
        fi
        ;;
esac

if [ "$prepare_failed" = 0 ]; then
case "$TYPE" in
    capacitor)
        # npm install (deps locales, dont @capacitor/cli local si present),
        # puis sync des assets web vers le projet android.
        ( cd "$ROOT" && npm install ) || prepare_failed=1
        if [ "$prepare_failed" = 0 ]; then
            # essaie le cap local du projet, sinon le cap global
            ( cd "$ROOT" && npx cap sync android ) \
                || ( cd "$ROOT" && cap sync android ) \
                || echo "(cap sync a echoue ; on tente le build quand meme)"
        fi
        ;;
    react-native)
        ( cd "$ROOT" && npm install ) || prepare_failed=1
        ;;
    flutter)
        if command -v flutter >/dev/null; then
            ( cd "$ROOT" && flutter pub get ) || prepare_failed=1
        else
            echo "ERREUR: Flutter non installe dans Ubuntu."
            echo "  Installe-le : https://docs.flutter.dev/get-started/install/linux"
            echo "  (ou via 'snapd'/git clone du SDK flutter)."
            prepare_failed=1
        fi
        ;;
    android-native|unknown)
        echo "Pas d'etape de preparation specifique."
        ;;
esac
fi

if [ "$prepare_failed" = 1 ]; then
    echo
    echo ">>> La preparation a echoue. Que veux-tu faire ?"
    echo "    Regarde l'erreur ci-dessus. Causes frequentes : pas de reseau,"
    echo "    node/flutter manquant, script postinstall du repo qui echoue."
    echo "    Corrige puis relance, ou continue quand meme (le build dira)."
    exit 2
fi

# --- 5. build via la chaine locale -------------------------------------------
echo "=== [5] Build ==="
if [ "$TYPE" = "flutter" ] && command -v flutter >/dev/null; then
    # Flutter pilote Gradle lui-meme ; on patche le cache puis flutter build.
    "$HERE/patch-gradle-cache.sh" || true
    ( cd "$ROOT" && flutter build apk --debug )
    BUILD_RC=$?
else
    # Capacitor / RN / natif : on delegue a build-android-local.sh
    if [ -z "$GRADLE_DIR" ]; then
        echo "ERREUR: aucun module gradle (gradlew) trouve. Build impossible."
        exit 2
    fi
    bash "$HERE/build-android-local.sh" "$GRADLE_DIR" "$TASK"
    BUILD_RC=$?
fi

# --- 6. resultat / diagnostic ------------------------------------------------
echo
if [ "${BUILD_RC:-1}" -eq 0 ]; then
    echo "=== BUILD REUSSI ==="
    find "$ROOT" -path '*outputs*' -name '*.apk' -printf '  %p  (%s octets)\n' 2>/dev/null
    echo
    echo "Copie vers Telechargements :"
    echo "  cp <chemin.apk> /data/data/com.termux/files/home/storage/downloads/"
else
    echo "=== BUILD ECHOUE (code $BUILD_RC) ==="
    echo "Diagnostic rapide des causes connues :"
    LOG="$ROOT/build/reports/problems/problems-report.html"
    echo " - 'failed to load include path .../android.jar' ou 'LoadedArsc' :"
    echo "     le cache Gradle a ete restaure -> relance, le patch se refait."
    echo " - 'checkDebugAarMetadata ... requires compileSdk N' :"
    echo "     monte compileSdk a N (le shim lit tous les jar) + sdkmanager."
    echo " - 'VANILLA_ICE_CREAM' / 'cannot find symbol' API 35 :"
    echo "     le code exige compileSdk 35+ -> aligne compileSdk."
    echo " - 'SDK location not found' : SDK absent, voir README."
    echo
    echo ">>> Montre-moi l'erreur exacte (les ~30 dernieres lignes ci-dessus)"
    echo "    et on decide ensemble du correctif."
fi
exit "${BUILD_RC:-1}"
