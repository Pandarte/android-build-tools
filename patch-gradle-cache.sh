#!/bin/bash
# =============================================================================
# patch-gradle-cache.sh
# Remplace l'aapt2 x86 par le shim ARM dans le(s) jar aapt2 du cache Gradle.
# Idempotent. Appelable seul ou source par d'autres scripts.
# Si le jar n'est pas encore en cache, tente un pre-telechargement.
# =============================================================================

set -uo pipefail
# Charge les messages bilingues (EN par defaut, FR si ABT_LANG=fr).
_ABT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$_ABT_DIR/lib-i18n.sh" ] && source "$_ABT_DIR/lib-i18n.sh"


SHIM_BIN="$HOME/aapt2-shim"
AAPT2_VERSION="${AAPT2_VERSION:-8.13.0-13719691}"
GRADLEW="${1:-}"   # optionnel : un gradlew a utiliser pour le pre-telechargement

[ -x "$SHIM_BIN" ] || { printf "$(t shim_missing)\n" "$SHIM_BIN"; exit 1; }
command -v zip  >/dev/null || apt-get install -y zip  >/dev/null 2>&1
command -v unzip >/dev/null || apt-get install -y unzip >/dev/null 2>&1

SHIM_SIZE="$(stat -c%s "$SHIM_BIN")"

do_patch() {
    local jars patched=0
    jars=$(find "$HOME/.gradle" -name 'aapt2-*-linux.jar' 2>/dev/null || true)
    [ -z "$jars" ] && return 1
    for jar in $jars; do
        local size
        size=$(unzip -l "$jar" 2>/dev/null | awk '/[ \/]aapt2$/ {print $1; exit}')
        if [ "$size" = "$SHIM_SIZE" ]; then patched=$((patched+1)); continue; fi
        [ -f "$jar.x86.bak" ] || cp "$jar" "$jar.x86.bak"
        local w; w=$(mktemp -d)
        ( cd "$w" && unzip -oq "$jar" && cp "$SHIM_BIN" aapt2 && chmod +x aapt2 \
          && rm -f "$jar" && zip -rq "$jar" . )
        rm -rf "$w"
        chmod 444 "$jar"
        printf "$(t patched_jar)\n" "$jar"
        patched=$((patched+1))
    done
    [ "$patched" -gt 0 ]
}

if do_patch; then
    echo "$(t cache_ok)"
    exit 0
fi

# pas en cache -> pre-telechargement
echo "$(t jar_absent_predl)"
PF=$(mktemp -d)
cat > "$PF/build.gradle" <<EOF
configurations { aapt2 }
repositories { google(); mavenCentral() }
dependencies { aapt2 'com.android.tools.build:aapt2:${AAPT2_VERSION}:linux@jar' }
task fetch(type: Copy) { from configurations.aapt2; into 'out' }
EOF
echo "rootProject.name='prefetch'" > "$PF/settings.gradle"

if [ -n "$GRADLEW" ] && [ -x "$GRADLEW" ]; then
    "$GRADLEW" -p "$PF" fetch --no-daemon || true
elif command -v gradle >/dev/null; then
    gradle -p "$PF" fetch --no-daemon || true
else
    echo "$(t no_gradlew_predl)"
    rm -rf "$PF"; exit 1
fi
rm -rf "$PF"

do_patch && echo "$(t cache_patched_predl)" || {
    echo "$(t jar_missing_predl)"
    exit 1
}
