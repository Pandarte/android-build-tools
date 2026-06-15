#!/bin/bash
# =============================================================================
# build-android-local.sh
# Compile un projet Android/Gradle en local sur ARM via la chaine aapt2+qemu.
#
# Usage :
#   build-android-local.sh /chemin/vers/projet [tache_gradle]
#
#   - /chemin/vers/projet : dossier contenant gradlew (le module 'android'
#     pour un projet Capacitor, ou la racine pour un projet Android natif).
#   - tache_gradle (optionnel) : defaut = assembleDebug
#
# Exemples :
#   build-android-local.sh ~/souffle-app/android
#   build-android-local.sh ~/mon-projet/android assembleRelease
#
# Ce que fait le script :
#   1. verifie que la chaine est installee (sinon te renvoie au setup)
#   2. s'assure que le SDK Android est configure (local.properties)
#   3. PATCHE le cache Gradle : remplace l'aapt2 x86 par le shim ARM
#      -> c'est l'etape qui doit etre refaite si Gradle restaure le jar
#   4. lance le build
#   5. affiche le chemin de l'APK produit
# =============================================================================

set -e
# Charge les messages bilingues (EN par defaut, FR si ABT_LANG=fr).
_ABT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$_ABT_DIR/lib-i18n.sh" ] && source "$_ABT_DIR/lib-i18n.sh"


PROJECT_DIR="${1:?Usage: build-android-local.sh /chemin/projet [tache]}"
GRADLE_TASK="${2:-assembleDebug}"

SHIM_BIN="$HOME/aapt2-shim"
AAPT2_DIR="$HOME/aapt2-x86"
ANDROID_SDK="$HOME/android-sdk"

# --- 1. verifications de la chaine -------------------------------------------
if [ ! -x "$SHIM_BIN" ] || [ ! -x "$AAPT2_DIR/aapt2" ]; then
    echo "$(t chain_missing)"
    echo "    bash ~/android-build-tools/setup-aapt2-qemu.sh"
    exit 1
fi
if [ ! -f "$PROJECT_DIR/gradlew" ]; then
    printf "$(t no_gradlew_dir)\n" "$PROJECT_DIR"
    echo "$(t capacitor_hint)"
    exit 1
fi

# --- 2. environnement (Java + SDK) -------------------------------------------
export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(which java)")")")"
export ANDROID_HOME="$ANDROID_SDK"
export PATH="$ANDROID_SDK/cmdline-tools/latest/bin:$ANDROID_SDK/platform-tools:$PATH"

if [ -d "$ANDROID_SDK" ]; then
    echo "sdk.dir=$ANDROID_SDK" > "$PROJECT_DIR/local.properties"
else
    printf "$(t sdk_not_found_dir)\n" "$ANDROID_SDK"
    echo "$(t sdk_install_sdkman)"
fi

# --- 3. retire tout override aapt2 (on passe par le patch de cache) ----------
GRADLE_PROPS="$HOME/.gradle/gradle.properties"
mkdir -p "$HOME/.gradle"
touch "$GRADLE_PROPS"
sed -i '/aapt2FromMavenOverride/d' "$GRADLE_PROPS"

# --- 4. fonction de patch du cache Gradle ------------------------------------
patch_gradle_cache() {
    local jars
    jars=$(find "$HOME/.gradle" -name 'aapt2-*-linux.jar' 2>/dev/null || true)
    if [ -z "$jars" ]; then
        return 1   # pas encore en cache
    fi
    local patched=0
    for jar in $jars; do
        # taille de l'aapt2 contenu dans le jar
        local size
        size=$(unzip -l "$jar" 2>/dev/null | awk '/[ \/]aapt2$/ {print $1; exit}')
        if [ "$size" = "$(stat -c%s "$SHIM_BIN")" ]; then
            patched=$((patched+1))   # deja notre shim
            continue
        fi
        # backup une seule fois
        [ -f "$jar.x86.bak" ] || cp "$jar" "$jar.x86.bak"
        # re-zippe le jar avec notre shim a la place de l'aapt2
        local work
        work=$(mktemp -d)
        ( cd "$work" && unzip -oq "$jar" && cp "$SHIM_BIN" aapt2 && chmod +x aapt2 \
            && rm -f "$jar" && zip -rq "$jar" . )
        rm -rf "$work"
        chmod 444 "$jar"   # lecture seule : empeche Gradle de l'ecraser
        patched=$((patched+1))
    done
    [ "$patched" -gt 0 ]
}

echo "$(t patch_attempt1)"
if ! patch_gradle_cache; then
    echo "$(t jar_not_cached)"
    # mini-projet qui force Gradle a telecharger le jar aapt2-linux
    PREFETCH=$(mktemp -d)
    AGP_AAPT2_VER=$(basename "$AAPT2_DIR" >/dev/null; echo "8.13.0-13719691")
    cat > "$PREFETCH/build.gradle" <<EOF
configurations { aapt2 }
repositories { google(); mavenCentral() }
dependencies { aapt2 'com.android.tools.build:aapt2:${AGP_AAPT2_VER}:linux@jar' }
task fetch(type: Copy) { from configurations.aapt2; into 'out' }
EOF
    echo "rootProject.name='prefetch'" > "$PREFETCH/settings.gradle"
    "$PROJECT_DIR/gradlew" -p "$PREFETCH" fetch --no-daemon || true
    rm -rf "$PREFETCH"
    patch_gradle_cache || echo "$(t jar_still_missing)"
fi

# --- 5. build ----------------------------------------------------------------
printf "$(t build_step)\n" "$GRADLE_TASK" "$PROJECT_DIR"
echo "$(t aapt2_patience)"
cd "$PROJECT_DIR"
chmod +x gradlew

# La sortie de Gradle (warnings, erreurs) reste en anglais pour rester lisible
# a l'international, quelle que soit la langue de l'UI.
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
GRADLE_EN_OPTS="-Duser.language=en -Duser.country=US"

# Si Gradle a restaure le jar entre-temps, on re-patche et on relance une fois.
if ! ./gradlew $GRADLE_EN_OPTS "$GRADLE_TASK" --no-daemon; then
    echo "$(t build_retry)"
    patch_gradle_cache || true
    ./gradlew $GRADLE_EN_OPTS "$GRADLE_TASK" --no-daemon
fi

# --- 6. localisation de l'APK ------------------------------------------------
echo
echo "$(t apk_produced)"
find "$PROJECT_DIR" -path '*outputs/apk*' -name '*.apk' -printf '%p  (%s octets)\n' 2>/dev/null || \
    printf "$(t no_apk)\n" "$GRADLE_TASK"
echo
echo "$(t copy_to_dl)"
echo "  cp <chemin.apk> /data/data/com.termux/files/home/storage/downloads/"
