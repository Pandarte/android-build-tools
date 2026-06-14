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

PROJECT_DIR="${1:?Usage: build-android-local.sh /chemin/projet [tache]}"
GRADLE_TASK="${2:-assembleDebug}"

SHIM_BIN="$HOME/aapt2-shim"
AAPT2_DIR="$HOME/aapt2-x86"
ANDROID_SDK="$HOME/android-sdk"

# --- 1. verifications de la chaine -------------------------------------------
if [ ! -x "$SHIM_BIN" ] || [ ! -x "$AAPT2_DIR/aapt2" ]; then
    echo "ERREUR: chaine aapt2+qemu absente. Lance d'abord :"
    echo "    bash ~/android-build-tools/setup-aapt2-qemu.sh"
    exit 1
fi
if [ ! -f "$PROJECT_DIR/gradlew" ]; then
    echo "ERREUR: pas de gradlew dans $PROJECT_DIR"
    echo "(pour un projet Capacitor, vise le sous-dossier 'android')"
    exit 1
fi

# --- 2. environnement (Java + SDK) -------------------------------------------
export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(which java)")")")"
export ANDROID_HOME="$ANDROID_SDK"
export PATH="$ANDROID_SDK/cmdline-tools/latest/bin:$ANDROID_SDK/platform-tools:$PATH"

if [ -d "$ANDROID_SDK" ]; then
    echo "sdk.dir=$ANDROID_SDK" > "$PROJECT_DIR/local.properties"
else
    echo "ATTENTION: SDK Android introuvable a $ANDROID_SDK"
    echo "Installe-le avec sdkmanager, ou ajuste ANDROID_SDK dans ce script."
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

echo "=== Patch du cache Gradle (1re tentative) ==="
if ! patch_gradle_cache; then
    echo "Jar aapt2 pas encore en cache. Pre-telechargement..."
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
    patch_gradle_cache || echo "AVERTISSEMENT: jar toujours pas trouve, le build le revelera."
fi

# --- 5. build ----------------------------------------------------------------
echo "=== Build : $GRADLE_TASK dans $PROJECT_DIR ==="
echo "(patience sur processDebugResources : aapt2 tourne via qemu, c'est plus lent)"
cd "$PROJECT_DIR"
chmod +x gradlew

# Si Gradle a restaure le jar entre-temps, on re-patche et on relance une fois.
if ! ./gradlew "$GRADLE_TASK" --no-daemon; then
    echo "=== Echec : re-patch du cache puis nouvelle tentative ==="
    patch_gradle_cache || true
    ./gradlew "$GRADLE_TASK" --no-daemon
fi

# --- 6. localisation de l'APK ------------------------------------------------
echo
echo "=== APK(s) produit(s) ==="
find "$PROJECT_DIR" -path '*outputs/apk*' -name '*.apk' -printf '%p  (%s octets)\n' 2>/dev/null || \
    echo "Aucun .apk trouve (la tache '$GRADLE_TASK' n'en produit peut-etre pas)."
echo
echo "Pour copier vers les Telechargements Termux :"
echo "  cp <chemin.apk> /data/data/com.termux/files/home/storage/downloads/"
