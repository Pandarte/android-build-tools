#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# build-termux-native.sh
#
# Compile un projet Android en NATIF dans Termux (pas de proot/qemu).
# Necessite d'avoir lance setup-termux-native.sh une fois.
#
# Usage :
#   bash build-termux-native.sh <url-git> [--branch b] [--subdir d] [--task t]
#   bash build-termux-native.sh /chemin/projet/local         (chemin existant)
#
# Defaut : task = assembleDebug.
# =============================================================================
set -uo pipefail

_ABT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$_ABT_DIR/lib-i18n.sh" ] && source "$_ABT_DIR/lib-i18n.sh"
type -t t >/dev/null 2>&1 || t() { printf '%s' "$1"; }

HOME_DIR="/data/data/com.termux/files/home"
ANDROID_HOME="$HOME_DIR/android-sdk"
BUILDS_DIR="$HOME_DIR/android-builds"

# Environnement natif.
export ANDROID_HOME
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
export JAVA_HOME="${JAVA_HOME:-$(dirname "$(dirname "$(command -v java)")")}"
# Sortie Gradle en anglais (lisible a l'international), surchargee par --task FR sinon.
export LANG="${LANG:-en_US.UTF-8}"

SRC="${1:?Usage: build-termux-native.sh <url-git|chemin> [--branch b] [--subdir d] [--task t]}"
shift || true
BRANCH=""; SUBDIR=""; TASK="assembleDebug"
while [ $# -gt 0 ]; do
    case "$1" in
        --branch) BRANCH="$2"; shift 2;;
        --subdir) SUBDIR="$2"; shift 2;;
        --task)   TASK="$2"; shift 2;;
        *) shift;;
    esac
done

# --- 1. Resoudre le projet (URL git ou chemin local) -------------------------
if [ -d "$SRC" ]; then
    PROJECT_DIR="$SRC"
    printf "$(t local_project_step)\n" "$PROJECT_DIR"
else
    NAME="$(basename "${SRC%.git}")"
    DEST="$BUILDS_DIR/$NAME"
    mkdir -p "$BUILDS_DIR"
    if [ -d "$DEST/.git" ]; then
        echo "$(t already_cloned)"
        git -C "$DEST" checkout -q -- . 2>/dev/null || true  # annule l'horodatage precedent
        git -C "$DEST" fetch --all -q || true
        [ -n "$BRANCH" ] && git -C "$DEST" checkout -q "$BRANCH" || true
        git -C "$DEST" pull -q || true
    else
        printf "$(t clone_step)\n" "$SRC"
        if [ -n "$BRANCH" ]; then
            git clone -q --branch "$BRANCH" "$SRC" "$DEST"
        else
            git clone -q "$SRC" "$DEST"
        fi
    fi
    PROJECT_DIR="$DEST"
fi
[ -n "$SUBDIR" ] && PROJECT_DIR="$PROJECT_DIR/$SUBDIR"

# --- 1bis. Horodatage du versioning (versionName + versionCode) --------------
# Rend chaque build unique et installable par-dessus le precedent.
_STAMP_MODULE="${SUBDIR:-app}"
if [ -f "$_ABT_DIR/stamp-version.sh" ]; then
    bash "$_ABT_DIR/stamp-version.sh" "$PROJECT_DIR" "$_STAMP_MODULE" || true
fi

# --- 2. local.properties -----------------------------------------------------
if [ ! -f "$PROJECT_DIR/gradlew" ]; then
    printf "$(t no_gradlew_dir)\n" "$PROJECT_DIR"
    exit 1
fi
echo "sdk.dir=$ANDROID_HOME" > "$PROJECT_DIR/local.properties"



# --- 4. Localiser l'APK ------------------------------------------------------
echo
echo "=== $(t apk_produced) ==="
APK="$(find "$PROJECT_DIR" -path '*outputs/apk*' -name '*.apk' -print 2>/dev/null | head -n1)"
if [ -n "$APK" ]; then
    SIZE="$(stat -c%s "$APK" 2>/dev/null || echo '?')"
    echo "  $APK ($SIZE octets/bytes)"
    echo "$(t copy_to_dl)"
    echo "  cp \"$APK\" $HOME_DIR/storage/downloads/"
else
    printf "$(t no_apk)\n" "$TASK"
fi
echo "=== $(t build_success) ==="
