#!/bin/bash
# =============================================================================
# detect-project.sh
# Detecte le type d'un projet Android et extrait ses besoins de build.
# Sourcé par android-builder.sh (definit des fonctions, n'execute rien seul).
# =============================================================================

_ABT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$_ABT_DIR/lib-i18n.sh" ] && [ -z "$(type -t t)" ] && source "$_ABT_DIR/lib-i18n.sh"

# Detecte le type de projet dans le dossier $1.
# Echo l'un de : flutter | capacitor | react-native | android-native | unknown
detect_project_type() {
    local dir="$1"
    if [ -f "$dir/pubspec.yaml" ] && grep -q "flutter:" "$dir/pubspec.yaml" 2>/dev/null; then
        echo "flutter"; return
    fi
    # Capacitor : config a la racine
    if ls "$dir"/capacitor.config.* >/dev/null 2>&1; then
        echo "capacitor"; return
    fi
    if [ -f "$dir/package.json" ]; then
        if grep -q '"@capacitor/' "$dir/package.json" 2>/dev/null; then
            echo "capacitor"; return
        fi
        if grep -q '"react-native"' "$dir/package.json" 2>/dev/null; then
            echo "react-native"; return
        fi
    fi
    # Android natif : un settings.gradle + un dossier app avec build.gradle
    if { [ -f "$dir/settings.gradle" ] || [ -f "$dir/settings.gradle.kts" ]; } \
       && find "$dir" -maxdepth 5 -name 'AndroidManifest.xml' 2>/dev/null | grep -q .; then
        echo "android-native"; return
    fi
    # filet : un gradlew + un build.gradle quelque part = projet gradle generique
    if [ -f "$dir/gradlew" ] && find "$dir" -maxdepth 3 \( -name 'build.gradle' -o -name 'build.gradle.kts' \) 2>/dev/null | grep -q .; then
        echo "android-native"; return
    fi
    echo "unknown"
}

# Trouve le dossier qui contient gradlew (module Android a builder) sous $1.
# Echo le chemin, ou vide si introuvable.
find_gradle_dir() {
    local dir="$1" type="$2"
    case "$type" in
        flutter)
            # Flutter gere son propre build ; le module android est la mais
            # on build via 'flutter build apk', pas gradlew directement.
            [ -d "$dir/android" ] && echo "$dir/android" || echo "$dir"
            ;;
        capacitor|react-native)
            [ -d "$dir/android" ] && echo "$dir/android"
            ;;
        android-native)
            if [ -f "$dir/gradlew" ]; then echo "$dir"
            else find "$dir" -maxdepth 3 -name gradlew -printf '%h\n' | head -1
            fi
            ;;
        *)
            # dernier recours : premier gradlew trouve
            find "$dir" -maxdepth 3 -name gradlew -printf '%h\n' | head -1
            ;;
    esac
}

# Extrait une valeur numerique de compileSdk/targetSdk/minSdk depuis les
# fichiers Gradle sous $1. $2 = compileSdk|targetSdk|minSdk. Echo le nombre.
extract_sdk() {
    local dir="$1" key="$2" val=""
    # cherche dans variables.gradle (Capacitor) puis tous les build.gradle(.kts)
    local files
    files=$(find "$dir" -maxdepth 3 \( -name 'variables.gradle' -o -name 'build.gradle' -o -name 'build.gradle.kts' \) 2>/dev/null)
    for f in $files; do
        # formes : compileSdkVersion = 34 / compileSdk 34 / compileSdk = 34
        val=$(grep -iE "${key}(Version)?[[:space:]=]+[0-9]+" "$f" 2>/dev/null \
              | grep -oE '[0-9]+' | head -1)
        [ -n "$val" ] && { echo "$val"; return; }
    done
    echo ""
}

# Extrait la version AGP (Android Gradle Plugin) sous $1. Echo ex: 8.13.0
extract_agp() {
    local dir="$1" val=""
    local files
    files=$(find "$dir" -maxdepth 3 \( -name 'build.gradle' -o -name 'build.gradle.kts' -o -name 'libs.versions.toml' -o -name 'settings.gradle' -o -name 'settings.gradle.kts' \) 2>/dev/null)
    for f in $files; do
        val=$(grep -iE "com.android.(application|tools.build:gradle|library)" "$f" 2>/dev/null \
              | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        [ -n "$val" ] && { echo "$val"; return; }
    done
    # toml : agp = "8.x.x"
    for f in $files; do
        val=$(grep -iE '(agp|androidGradlePlugin)[[:space:]]*=' "$f" 2>/dev/null \
              | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        [ -n "$val" ] && { echo "$val"; return; }
    done
    echo ""
}

# Liste les compileSdk/targetSdk uniques requis (pour installer les plateformes).
list_required_sdks() {
    local dir="$1"
    find "$dir" -maxdepth 3 \( -name 'variables.gradle' -o -name 'build.gradle' -o -name 'build.gradle.kts' \) -exec \
        grep -hioE "(compileSdk|targetSdk)(Version)?[[:space:]=]+[0-9]+" {} \; 2>/dev/null \
        | grep -oE '[0-9]+' | sort -u
}
