# Compiler des APK Android en local sur ARM (Termux + proot + qemu)

Cette boîte à outils permet de compiler **n'importe quel projet Android/Gradle**
(Capacitor, Android natif, etc.) directement sur un téléphone ARM, sans PC et
sans build cloud.

## Le problème qu'elle résout

Gradle a besoin de l'outil **aapt2** pour compiler les ressources Android.
Sur un téléphone ARM, on est coincé entre trois murs :

1. L'aapt2 fourni par Termux est **trop vieux** : il ne lit pas le `android.jar`
   des API récentes (35, 36) -> erreur `LoadedArsc.cpp ... entry offsets overlap`.
2. L'aapt2 fourni par Debian/Ubuntu (`apt install aapt`) tourne sur ARM mais est
   lui aussi trop vieux (2.19) -> même erreur sur les jar récents.
3. L'aapt2 **récent** de Google n'existe **que pour x86** (Google ne publie pas
   de build `linux-aarch64`) -> `Exec format error` sur ARM.

**La solution** : faire tourner l'aapt2 **x86 récent** via **qemu** (émulation
x86 sur ARM). Deux subtilités :

- `binfmt_misc` (exécution x86 transparente) est **absent** sur Android non-root,
  donc on ne peut pas juste "lancer" le binaire x86 ; il faut appeler qemu
  explicitement.
- Gradle **refuse un script shell** comme aapt2 (il exige un vrai binaire ELF).
  On contourne avec un **shim** : un minuscule binaire ELF natif ARM qui ne fait
  que relancer `qemu + aapt2-x86`. Ce shim est ensuite **injecté dans le .jar
  aapt2 que Gradle garde en cache**, ce qui évite la validation stricte de
  l'option `aapt2FromMavenOverride`.

Chaîne complète :
```
Gradle  ->  (son cache) aapt2 = SHIM (ELF ARM)  ->  qemu-x86_64  ->  aapt2 x86 récent  ->  lit android.jar
```

## Installation (une seule fois)

Depuis Termux :
```bash
proot-distro login ubuntu          # entrer dans Ubuntu
bash ~/android-build-tools/setup-aapt2-qemu.sh
```

Le setup installe qemu, gcc, le JDK, les libs x86 multiarch, télécharge l'aapt2
x86 et compile le shim. Idempotent (peut être relancé sans risque).

Il faut aussi le **SDK Android** dans Ubuntu (si pas déjà fait) :
```bash
export ANDROID_HOME="$HOME/android-sdk"
mkdir -p "$ANDROID_HOME/cmdline-tools"
cd /tmp
wget -O cmd.zip https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
unzip -q cmd.zip -d "$ANDROID_HOME/cmdline-tools"
mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
yes | sdkmanager --licenses
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"
```
(adapte `android-36` / `build-tools;36.0.0` au compileSdk de ton projet.)

## Compiler depuis une URL git (tout-en-un)

`android-builder.sh` clone un repo, **détecte son type** (Flutter / Capacitor /
React Native / Android natif), extrait ses besoins (compileSdk, AGP…), installe
les plateformes SDK manquantes, prépare (`npm install` / `cap sync` / `pub get`),
puis build via la chaîne aapt2+qemu.

```bash
proot-distro login ubuntu
bash ~/android-build-tools/android-builder.sh https://github.com/Pandarte/souffle-app
```

Options :
```bash
  --branch <nom>    # builder une branche precise
  --subdir <chemin> # le projet est dans un sous-dossier (monorepo)
  --task <tache>    # defaut assembleDebug ; ex: assembleRelease
```

Comportement en cas de souci (selon ton choix) : l'outil **tente tout
automatiquement**. Si le **build** échoue, il s'arrête, affiche un **diagnostic
des causes connues**, et te laisse décider du correctif (plutôt que de deviner).

Les repos clonés vont dans `~/android-builds/<nom>`.

### Pré-requis par type de projet
- **Capacitor / React Native** : `nodejs` + `npm` (le setup les installe pas ;
  fais `apt install -y nodejs npm` une fois).
- **Flutter** : le SDK Flutter doit être installé dans Ubuntu
  (https://docs.flutter.dev/get-started/install/linux). L'outil le détecte et
  te prévient s'il manque.
- **Android natif** : rien de plus que la chaîne + le SDK Android.

## Compiler un projet déjà sur disque

```bash
proot-distro login ubuntu
bash ~/android-build-tools/build-android-local.sh ~/mon-projet/android
```

- Pour un projet **Capacitor**, vise le sous-dossier `android`.
- Pour un projet **Android natif**, vise la racine (là où est `gradlew`).
- Tâche par défaut : `assembleDebug`. Pour une autre :
  ```bash
  bash ~/android-build-tools/build-android-local.sh ~/mon-projet/android assembleRelease
  ```

Le script patche le cache Gradle automatiquement, build, et affiche le chemin
de l'APK. Pour le récupérer côté téléphone :
```bash
cp <chemin.apk> /data/data/com.termux/files/home/storage/downloads/
```
(nécessite `termux-setup-storage` exécuté une fois côté Termux.)

## Workflow Capacitor complet (rappel)

Si tu pars d'une app web et veux la transformer en APK :
```bash
# dans le dossier du projet, côté Ubuntu :
npm install
npx cap sync android
bash ~/android-build-tools/build-android-local.sh ./android
```

## Dépannage

**`Custom AAPT2 location does not point to an AAPT2 executable`**
Tu as un `aapt2FromMavenOverride` qui pointe sur le shim. NE PAS utiliser
l'override : le script passe par le patch du cache. Vérifie :
```bash
grep aapt2 ~/.gradle/gradle.properties   # ne doit RIEN afficher
```

**`failed to load include path .../android.jar` ou `LoadedArsc.cpp`**
Le cache Gradle a été restauré avec l'aapt2 x86 d'origine (le shim a été
écrasé). Relance simplement le build : le script re-patche automatiquement.
Pour patcher à la main :
```bash
CACHE_JAR=$(find ~/.gradle -name 'aapt2-*-linux.jar' | head -1)
# ... voir la fonction patch_gradle_cache dans build-android-local.sh
```

**`SDK location not found`**
Variable d'environnement perdue (nouveau shell). Le script recrée
`local.properties`, mais vérifie que `~/android-sdk` existe.

**`No cached version available for offline mode`**
Ne lance PAS avec `--offline` au premier build d'un projet : Gradle doit
télécharger ses dépendances. Le script ne met pas `--offline` ; si tu l'ajoutes
manuellement, retire-le pour le premier build.

**`checkDebugAarMetadata ... requires compileSdk 36`**
Une dépendance exige un compileSdk plus récent. Avec cette chaîne, tu peux
simplement **monter le compileSdk** (le shim lit tous les jar). Mets le projet
au niveau demandé et installe la plateforme correspondante :
```bash
sdkmanager "platforms;android-36"
# puis ajuste compileSdkVersion/targetSdkVersion dans variables.gradle (Capacitor)
# ou build.gradle (Android natif)
```

**Version d'aapt2 / AGP différente**
Le setup télécharge l'aapt2 `8.13.0-13719691` (= AGP 8.13). Si un projet utilise
un AGP très différent, Gradle voudra une autre version d'aapt2. Le shim lit
n'importe quel jar, mais le **nom de version** du jar de cache doit correspondre.
Le plus simple : aligner l'AGP du projet sur 8.13, ou éditer `AAPT2_VERSION`
dans `setup-aapt2-qemu.sh` et le `:linux@jar` dans `build-android-local.sh`,
puis relancer le setup.

## Composants (où est quoi)

| Élément              | Chemin                          | Rôle                            |
|----------------------|---------------------------------|---------------------------------|
| aapt2 x86 récent     | `~/aapt2-x86/aapt2`             | le vrai outil, exécuté via qemu |
| shim ELF ARM         | `~/aapt2-shim`                  | pont Gradle -> qemu             |
| source du shim       | `~/aapt2-shim.c`               | pour recompiler si besoin       |
| script d'install     | `~/android-build-tools/setup-aapt2-qemu.sh`   | reconstruit tout |
| script de build      | `~/android-build-tools/build-android-local.sh`| patche + compile |
| backup jar d'origine | `~/.gradle/.../aapt2-*-linux.jar.x86.bak`     | pour revenir en arrière |

## Limite honnête

C'est un montage à plusieurs couches (Termux -> proot -> qemu -> shim ->
cache Gradle). Ça marche, mais c'est plus lent qu'un build natif (qemu émule
chaque instruction d'aapt2) et plus fragile qu'un build cloud. Pour un usage
"sûr et rapide", GitHub Actions reste l'option de référence. Cette chaîne, c'est
pour la satisfaction (réelle) de compiler **100% en local**, et pour les cas
sans connexion.
