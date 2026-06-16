#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# stamp-version.sh  --  Horodatage du versioning avant build
#
# Reecrit versionName et versionCode du module Android pour rendre CHAQUE
# build APKforge unique et installable par-dessus le precedent :
#   - versionName : "<officiel> (build AAAAMMJJHHMM)"   (cosmetique + tracable)
#   - versionCode : timestamp tronque, strictement croissant (Android exige
#                   un versionCode plus grand pour ecraser une install).
#
# Generique : detecte le build.gradle(.kts) du module et patche en place sur
# la COPIE clonee (pas le repo d'origine). Idempotent par build (relancer
# regenere un nouvel horodatage).
#
# Usage : bash stamp-version.sh <chemin-projet> [sous-module]
# =============================================================================
set -uo pipefail

PROJECT_DIR="${1:?Usage: stamp-version.sh <chemin-projet> [sous-module]}"
SUBMODULE="${2:-app}"

# Horodatage du build (heure locale).
STAMP="$(date +%Y%m%d%H%M)"          # AAAAMMJJHHMM, ex 202606160945
# versionCode : minutes ecoulees depuis 2020. Strictement croissant dans le
# temps, et tient largement dans un int signe (~3.4M en 2026, max ~2.1 milliards).
EPOCH_2020=1577836800                # 2020-01-01 00:00 UTC
NOW="$(date +%s)"
VCODE=$(( (NOW - EPOCH_2020) / 60 ))

# Trouve le fichier build du module.
GRADLE_FILE=""
for f in "$PROJECT_DIR/$SUBMODULE/build.gradle" "$PROJECT_DIR/$SUBMODULE/build.gradle.kts"; do
    [ -f "$f" ] && GRADLE_FILE="$f" && break
done
if [ -z "$GRADLE_FILE" ]; then
    echo "[stamp] build.gradle introuvable dans $PROJECT_DIR/$SUBMODULE ; on saute."
    exit 0   # non bloquant : on laisse le build se faire sans horodatage
fi

echo "[stamp] horodatage du versioning : $GRADLE_FILE"
echo "[stamp]   versionName += (build $STAMP) ; versionCode = $VCODE"

STAMP="$STAMP" VCODE="$VCODE" python3 - "$GRADLE_FILE" << 'PY'
import os, re, sys

path = sys.argv[1]
stamp = os.environ["STAMP"]
vcode = os.environ["VCODE"]
src = open(path, encoding="utf-8").read()
orig = src

# --- versionName : on capture la valeur officielle puis on y accole le build ---
# Gere : versionName "1.2"      (Groovy)
#        versionName = "1.2"    (Kotlin DSL)
#        versionName APP_VERSION_NAME / def APP_VERSION_NAME = "1.2"
def stamp_name(m):
    prefix, q, val = m.group(1), m.group(2), m.group(3)
    # evite de re-horodater si deja fait
    if "(build " in val:
        return m.group(0)
    return f'{prefix}{q}{val} (build {stamp}){q}'

# versionName "..."  /  versionName = "..."
src = re.sub(r'(versionName\s*=?\s*)(["\'])([^"\']*)\2',
             stamp_name, src, count=1)

# Si le projet utilise une constante def APP_VERSION_NAME = "..."
src = re.sub(r'(def\s+APP_VERSION_NAME\s*=\s*)(["\'])([^"\']*)\2',
             stamp_name, src, count=1)

# --- versionCode : on force la valeur horodatee --------------------------------
# versionCode 9  /  versionCode = 9
src = re.sub(r'(versionCode\s*=?\s*)\d+',
             lambda m: f'{m.group(1)}{vcode}', src, count=1)
# def APP_VERSION_CODE = 9
src = re.sub(r'(def\s+APP_VERSION_CODE\s*=\s*)\d+',
             lambda m: f'{m.group(1)}{vcode}', src, count=1)

if src == orig:
    print("[stamp] aucun motif versionName/versionCode reconnu ; fichier inchange.")
else:
    open(path, "w", encoding="utf-8").write(src)
    print("[stamp] versioning horodate applique.")
PY
