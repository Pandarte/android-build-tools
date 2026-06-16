# 🔨 android-build-tools

**Compiler des APK Android en local sur ARM — natif Termux d'abord, proot + qemu en secours. Sans PC ni build cloud.**

> [🇬🇧 English](README.md) &nbsp;•&nbsp; 🇫🇷 Français


Cette boîte à outils compile **n'importe quel projet Android/Gradle** (Android
natif, Capacitor, React Native, Flutter) directement sur un téléphone ARM. Elle
fournit aussi un petit serveur HTTP qui sert de back-end à l'application
[APKforge](https://github.com/Pandarte/forge).

<p align="left">
  <img alt="Plateforme" src="https://img.shields.io/badge/plateforme-Termux%20%2F%20Android%20ARM-3DDC84">
  <img alt="Méthode" src="https://img.shields.io/badge/aapt2-x86%20via%20qemu-orange">
  <img alt="Shell" src="https://img.shields.io/badge/shell-bash-4EAA25">
  <img alt="Serveur" src="https://img.shields.io/badge/serveur-python3-3776AB">
</p>

---

## Deux chaînes : le natif d'abord, le proot en secours

Cette boîte à outils propose **deux** façons de compiler. La chaîne **native**
est celle par défaut ; la chaîne **proot + qemu** est un secours, installé et
utilisé seulement en cas de besoin.

| Chaîne | Scripts | aapt2 | Vitesse | Rôle |
|--------|---------|-------|---------|------|
| **Termux-native** | `setup-termux-native.sh`, `build-termux-native.sh` | aapt2 ARM de Termux (natif) | rapide (natif) | **par défaut** — chaque build démarre ici |
| **proot + qemu** | `bootstrap-debian-build.sh`, `setup-aapt2-qemu.sh`, `android-builder.sh`, `build-android-local.sh` | aapt2 x86 de Google via qemu (proot Debian) | plus lente (émulée) | **secours** — seulement si le natif échoue pour une raison de chaîne |

Comment le serveur arbitre (`buildserver.py`) :

1. Chaque build est tenté **nativement** d'abord (aapt2 ARM natif, sans qemu).
2. S'il réussit → terminé. Rien d'autre n'est touché.
3. S'il échoue, le serveur regarde **pourquoi**. Une erreur de projet (erreur
   Kotlin, symbole manquant…) est rapportée telle quelle — le proot n'y
   changerait rien, donc pas de bascule.
4. Si l'échec est lié à la **chaîne** (p. ex. `failed to load include path
   .../android.jar` parce que l'aapt2 Termux est trop ancien pour le compileSdk
   du projet), le serveur bascule sur la chaîne proot + qemu. Si aucun proot
   n'est encore installé, il **installe Debian à la demande**
   (`bootstrap-debian-build.sh`) puis réessaie dedans.

Pourquoi un secours ? Gradle a besoin d'`aapt2` pour lire l'`android.jar` de
l'API ciblée. L'aapt2 fourni par Termux est un **binaire ARM natif** (rapide,
sans émulation) mais construit sur une base Android plus ancienne : il ne lit
l'`android.jar` que jusqu'à l'API 34 environ. Les projets en **compileSdk 35+**
(p. ex. `androidx.activity` ≥ 1.10 ou Material 3 Expressive) ne peuvent pas être
lus par l'aapt2 Termux. Pour ceux-là, la seule option sur ARM est l'aapt2 x86
récent de Google passé par qemu — d'où la chaîne proot.

**Effet net :** les projets simples ou anciens compilent vite, en natif, sans
jamais toucher de proot. Les projets en SDK récent démarrent en natif, butent
sur le mur de l'aapt2, et le serveur provisionne puis utilise le secours
Debian + qemu de façon transparente. Le jour où Termux met à jour son aapt2 vers
une base Android plus récente, la chaîne native couvrira aussi les SDK récents
et le proot pourra être abandonné totalement.

## Le problème résolu

Gradle a besoin de l'outil **aapt2** pour compiler les ressources Android. Sur un
téléphone ARM, on se heurte à trois murs :

1. L'aapt2 fourni par Termux est **trop vieux** : il ne lit pas l'`android.jar`
   des API récentes (35, 36) → erreur `LoadedArsc.cpp ... entry offsets overlap`.
2. L'aapt2 de Debian/Ubuntu (`apt install aapt`) tourne sur ARM mais est lui
   aussi trop ancien (2.19) → même erreur sur les jar récents.
3. L'aapt2 **récent** de Google n'existe **que pour x86** (pas de build
   `linux-aarch64`) → `Exec format error` sur ARM.

**La solution** : exécuter l'aapt2 **x86 récent** via **qemu** (émulation x86 sur
ARM). Avec deux subtilités :

- `binfmt_misc` (exécution x86 transparente) est **absent** sur Android non-root :
  on ne peut pas simplement « lancer » le binaire x86, il faut appeler qemu
  explicitement.
- Gradle **refuse un script shell** comme aapt2 (il exige un vrai binaire ELF).
  On contourne avec un **shim** : un minuscule binaire ELF natif ARM qui ne fait
  que relancer `qemu + aapt2-x86`. Ce shim est ensuite **injecté dans le .jar
  aapt2 que Gradle conserve en cache**, ce qui évite la validation stricte de
  l'option `aapt2FromMavenOverride`.

Chaîne complète :

```
Gradle ──▶ (cache) aapt2 = SHIM (ELF ARM) ──▶ qemu-x86_64 ──▶ aapt2 x86 récent ──▶ lit android.jar
```

## Installation

Tout se pilote depuis **Termux** (aucun proot nécessaire en usage normal).

**Chaîne native (par défaut) :**

```bash
bash ~/android-build-tools/setup-termux-native.sh
```

Ceci installe le JDK, le SDK Android et l'**aapt2 ARM natif**, et configure
Gradle pour l'utiliser. Idempotent. Après ça, tu peux compiler tout projet dont
le compileSdk est supporté par l'aapt2 Termux (≈ API 34 et en dessous).

**Secours Debian (optionnel, à la demande) :**

Tu n'as normalement pas à l'installer toi-même — le serveur le provisionne
automatiquement la première fois qu'un build natif échoue pour une raison de
chaîne. Pour le mettre en place à l'avance malgré tout :

```bash
bash ~/android-build-tools/bootstrap-debian-build.sh
```

Ceci installe un proot Debian **minimal** et y lance `setup-aapt2-qemu.sh`
(qemu, gcc, JDK, libs x86 multiarch, aapt2 x86, le shim, et une seule plateforme
SDK). Rien de superflu ; le proot reste au repos tant que les builds natifs
réussissent.

(Adapter `android-36` / `build-tools;36.0.0` au compileSdk du projet visé.)

## Utilisation

### Compiler depuis une URL git (tout-en-un)

`android-builder.sh` clone un dépôt, **détecte son type** (Flutter / Capacitor /
React Native / Android natif), extrait ses besoins (compileSdk, AGP…), installe
les plateformes SDK manquantes, prépare (`npm install` / `cap sync` / `pub get`)
puis compile via la chaîne aapt2 + qemu.

```bash
# dans le proot Debian de secours (le serveur y entre automatiquement) :
proot-distro login debian
bash ~/android-build-tools/android-builder.sh https://github.com/utilisateur/projet
```

Options :

```bash
  --branch <nom>     # compiler une branche précise
  --subdir <chemin>  # le projet est dans un sous-dossier (monorepo)
  --task <tâche>     # défaut : assembleDebug ; ex : assembleRelease
```

Si le build échoue, l'outil s'arrête et affiche un **diagnostic des causes
connues** plutôt que de tenter une correction à l'aveugle. Les dépôts clonés
sont placés dans `~/android-builds/<nom>`.

**Prérequis par type de projet :**

- **Capacitor / React Native** : `nodejs` + `npm` (`apt install -y nodejs npm`,
  ou via `setup-node.sh`).
- **Flutter** : le SDK Flutter doit être installé dans le proot Debian
  ([guide officiel](https://docs.flutter.dev/get-started/install/linux)).
  L'outil le détecte et prévient s'il manque.
- **Android natif** : rien de plus que la chaîne et le SDK Android.

### Compiler un projet déjà sur disque

```bash
proot-distro login debian
bash ~/android-build-tools/build-android-local.sh ~/mon-projet/android
```

- Projet **Capacitor** : viser le sous-dossier `android`.
- Projet **Android natif** : viser la racine (là où se trouve `gradlew`).
- Tâche par défaut : `assembleDebug`. Pour une autre :
  ```bash
  bash ~/android-build-tools/build-android-local.sh ~/mon-projet/android assembleRelease
  ```

Le script patche le cache Gradle automatiquement, compile, et affiche le chemin
de l'APK. Pour le récupérer côté téléphone :

```bash
cp <chemin.apk> /data/data/com.termux/files/home/storage/downloads/
```

(nécessite `termux-setup-storage` exécuté une fois côté Termux.)

### Workflow Capacitor complet

Pour transformer une app web en APK :

```bash
# dans le dossier du projet, côté Debian :
npm install
npx cap sync android
bash ~/android-build-tools/build-android-local.sh ./android
```

### Serveur de build (back-end d'APKforge)

`buildserver.py` expose la chaîne via une petite API HTTP locale
(`127.0.0.1:8765`), pilotée par l'application
[APKforge](https://github.com/Pandarte/forge).

```bash
python3 ~/buildserver/buildserver.py        # ou : bash start-build-server.sh
```

Le serveur tourne **dans Termux**. Il pilote directement la chaîne native et,
uniquement sur un échec natif lié à la chaîne, provisionne puis utilise le
secours Debian + qemu (voir *Deux chaînes* plus haut).

### Build Termux-natif (voie par défaut)

Pour les projets en compileSdk 34 ou moins, on compile en natif dans Termux —
pas de proot, pas de qemu, pleine vitesse native. À lancer **depuis Termux**
(pas dans le proot) :

```bash
bash ~/android-build-tools/setup-termux-native.sh                 # une fois
bash ~/android-build-tools/build-termux-native.sh <url-git|chemin>  # build
```

`setup-termux-native.sh` installe le JDK, le SDK Android et l'**aapt2 ARM natif
de Termux** (`pkg install aapt2`), et pointe Gradle dessus via
`android.aapt2FromMavenOverride`. Il vérifie que le binaire s'exécute vraiment
(pas d'`Exec format error`). Si le build échoue ensuite avec `failed to load
include path .../android.jar`, c'est que le compileSdk du projet est trop récent
pour l'aapt2 Termux — utilise alors la chaîne proot+qemu.

## Dépannage

**`Custom AAPT2 location does not point to an AAPT2 executable`**
Un `aapt2FromMavenOverride` pointe sur le shim. Ne pas utiliser l'override : le
script passe par le patch du cache. Vérifier :
```bash
grep aapt2 ~/.gradle/gradle.properties   # ne doit RIEN afficher
```

**`failed to load include path .../android.jar` ou `LoadedArsc.cpp`**
Le cache Gradle a été restauré avec l'aapt2 x86 d'origine (shim écrasé). Relancer
le build : le script re-patche automatiquement. Pour patcher à la main, voir la
fonction `patch_gradle_cache` dans `build-android-local.sh`.

**`SDK location not found`**
Variable d'environnement perdue (nouveau shell). Le script recrée
`local.properties` ; vérifier que `~/android-sdk` existe.

**`No cached version available for offline mode`**
Ne pas lancer avec `--offline` au premier build d'un projet : Gradle doit
télécharger ses dépendances. Le script ne met pas `--offline` ; si on l'ajoute
manuellement, le retirer pour le premier build.

**`checkDebugAarMetadata ... requires compileSdk 36`**
Une dépendance exige un compileSdk plus récent. Avec cette chaîne, on peut
simplement **monter le compileSdk** (le shim lit tous les jar) :
```bash
sdkmanager "platforms;android-36"
# puis ajuster compileSdk/targetSdk dans variables.gradle (Capacitor)
# ou build.gradle (Android natif)
```

**Version d'aapt2 / AGP différente**
Le setup télécharge l'aapt2 `8.13.0-13719691` (= AGP 8.13). Si un projet utilise
un AGP très différent, Gradle voudra une autre version d'aapt2. Le shim lit
n'importe quel jar, mais le **nom de version** du jar de cache doit correspondre.
Le plus simple : aligner l'AGP du projet sur 8.13, ou éditer `AAPT2_VERSION` dans
`setup-aapt2-qemu.sh` et le `:linux@jar` dans `build-android-local.sh`, puis
relancer le setup.

## Composants

| Élément              | Chemin                                          | Rôle                              |
|----------------------|-------------------------------------------------|-----------------------------------|
| aapt2 x86 récent     | `~/aapt2-x86/aapt2`                             | le vrai outil, exécuté via qemu   |
| shim ELF ARM         | `~/aapt2-shim`                                  | pont Gradle → qemu                |
| source du shim       | `~/aapt2-shim.c`                               | pour recompiler si besoin         |
| backup jar d'origine | `~/.gradle/.../aapt2-*-linux.jar.x86.bak`       | pour revenir en arrière           |

## Scripts du dépôt

| Script                   | Rôle                                                        |
|--------------------------|-------------------------------------------------------------|
| `setup-aapt2-qemu.sh`    | installe la chaîne complète (qemu, aapt2 x86, shim)         |
| `android-builder.sh`     | clone depuis une URL git, détecte, prépare et compile       |
| `build-android-local.sh` | patche le cache Gradle et compile un projet local           |
| `detect-project.sh`      | détecte le type de projet (Flutter/Capacitor/RN/natif)      |
| `patch-gradle-cache.sh`  | injecte le shim dans le jar aapt2 du cache Gradle           |
| `setup-node.sh`          | installe Node.js / npm pour les projets web                 |
| `setup-termux-native.sh` | installe la chaîne native (défaut : JDK, SDK, aapt2 natif) |
| `bootstrap-debian-build.sh` | installe le proot Debian minimal de secours + la chaîne qemu |
| `build-termux-native.sh` | compile en natif dans Termux (sans proot/qemu)              |
| `lib-i18n.sh`            | messages de logs bilingues (EN par défaut, FR via `ABT_LANG`) |
| `buildserver.py`         | API HTTP locale, back-end de l'app APKforge                 |
| `start-build-server.sh`  | démarre le serveur de build                                 |

## Performances et limites

La voie **native** (aapt2 ARM de Termux) est la norme et tourne à pleine
vitesse. Le **secours** est un montage à plusieurs couches (Termux → proot →
qemu → shim → cache Gradle) : fonctionnel, mais qemu émule chaque instruction
d'aapt2, donc plus lent et plus fragile. Il n'intervient que lorsque le
compileSdk du projet dépasse ce que l'aapt2 Termux sait lire. Pour une CI rapide
et fiable, GitHub Actions reste l'option de référence ; cette boîte à outils
existe pour compiler **100 % en local**, y compris hors connexion.

## Projets liés

- [APKforge](https://github.com/Pandarte/forge) — l'interface Android qui pilote
  cette chaîne via le serveur HTTP.
