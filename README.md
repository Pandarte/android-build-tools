# 🔨 android-build-tools

**Build Android APKs locally on ARM — Termux + proot + qemu, no PC, no cloud build.**

> 🇬🇧 English &nbsp;•&nbsp; [🇫🇷 Français](README.fr.md)

This toolkit builds **any Android/Gradle project** (native Android, Capacitor,
React Native, Flutter) directly on an ARM phone. It also ships a small HTTP
server that acts as the back-end for the
[APKforge](https://github.com/Pandarte/forge) app.

<p align="left">
  <img alt="Platform" src="https://img.shields.io/badge/platform-Termux%20%2F%20Android%20ARM-3DDC84">
  <img alt="Method" src="https://img.shields.io/badge/aapt2-x86%20via%20qemu-orange">
  <img alt="Shell" src="https://img.shields.io/badge/shell-bash-4EAA25">
  <img alt="Server" src="https://img.shields.io/badge/server-python3-3776AB">
</p>

---

## The problem it solves

Gradle needs the **aapt2** tool to compile Android resources. On an ARM phone,
you hit three walls:

1. The aapt2 shipped by Termux is **too old**: it can't read the `android.jar`
   of recent APIs (35, 36) → `LoadedArsc.cpp ... entry offsets overlap` error.
2. The aapt2 from Debian/Ubuntu (`apt install aapt`) runs on ARM but is also too
   old (2.19) → same error on recent jars.
3. Google's **recent** aapt2 only exists for **x86** (no `linux-aarch64` build)
   → `Exec format error` on ARM.

**The solution**: run the **recent x86 aapt2** through **qemu** (x86 emulation on
ARM). Two subtleties:

- `binfmt_misc` (transparent x86 execution) is **absent** on non-rooted Android,
  so you can't just "run" the x86 binary — you must call qemu explicitly.
- Gradle **refuses a shell script** as aapt2 (it requires a real ELF binary). The
  workaround is a **shim**: a tiny native ARM ELF binary that does nothing but
  re-launch `qemu + aapt2-x86`. That shim is then **injected into the aapt2 .jar
  that Gradle keeps in its cache**, which bypasses the strict validation of the
  `aapt2FromMavenOverride` option.

Full chain:

```
Gradle ──▶ (cache) aapt2 = SHIM (ARM ELF) ──▶ qemu-x86_64 ──▶ recent x86 aapt2 ──▶ reads android.jar
```

## Installation

Do this once, from Termux:

```bash
proot-distro login ubuntu          # enter Ubuntu
bash ~/android-build-tools/setup-aapt2-qemu.sh
```

The setup installs qemu, gcc, the JDK, the x86 multiarch libs, downloads the x86
aapt2 and compiles the shim. It is idempotent (safe to re-run).

You also need the **Android SDK** inside Ubuntu, if not already present:

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

(Adapt `android-36` / `build-tools;36.0.0` to the target project's compileSdk.)

## Usage

### Build from a git URL (all-in-one)

`android-builder.sh` clones a repository, **detects its type** (Flutter /
Capacitor / React Native / native Android), extracts its needs (compileSdk,
AGP…), installs missing SDK platforms, prepares it (`npm install` / `cap sync` /
`pub get`), then builds it through the aapt2 + qemu chain.

```bash
proot-distro login ubuntu
bash ~/android-build-tools/android-builder.sh https://github.com/user/project
```

Options:

```bash
  --branch <name>    # build a specific branch
  --subdir <path>    # the project is in a subfolder (monorepo)
  --task <task>      # default: assembleDebug ; e.g. assembleRelease
```

If the build fails, the tool stops and prints a **diagnosis of known causes**
rather than guessing a fix. Cloned repositories go into `~/android-builds/<name>`.

**Per-project-type prerequisites:**

- **Capacitor / React Native**: `nodejs` + `npm` (`apt install -y nodejs npm`,
  or via `setup-node.sh`).
- **Flutter**: the Flutter SDK must be installed inside Ubuntu
  ([official guide](https://docs.flutter.dev/get-started/install/linux)). The
  tool detects it and warns if it's missing.
- **Native Android**: nothing beyond the chain and the Android SDK.

### Build a project already on disk

```bash
proot-distro login ubuntu
bash ~/android-build-tools/build-android-local.sh ~/my-project/android
```

- **Capacitor** project: point at the `android` subfolder.
- **Native Android** project: point at the root (where `gradlew` lives).
- Default task: `assembleDebug`. For another:
  ```bash
  bash ~/android-build-tools/build-android-local.sh ~/my-project/android assembleRelease
  ```

The script patches the Gradle cache automatically, builds, and prints the APK
path. To pull it to the phone:

```bash
cp <path.apk> /data/data/com.termux/files/home/storage/downloads/
```

(requires `termux-setup-storage` run once on the Termux side.)

### Full Capacitor workflow

To turn a web app into an APK:

```bash
# inside the project folder, on the Ubuntu side:
npm install
npx cap sync android
bash ~/android-build-tools/build-android-local.sh ./android
```

### Build server (APKforge back-end)

`buildserver.py` exposes the chain via a small local HTTP API
(`127.0.0.1:8765`), driven by the
[APKforge](https://github.com/Pandarte/forge) app.

```bash
proot-distro login ubuntu
python3 ~/buildserver/buildserver.py        # or: bash start-build-server.sh
```

## Troubleshooting

**`Custom AAPT2 location does not point to an AAPT2 executable`**
An `aapt2FromMavenOverride` points at the shim. Don't use the override: the
script goes through the cache patch. Check:
```bash
grep aapt2 ~/.gradle/gradle.properties   # must print NOTHING
```

**`failed to load include path .../android.jar` or `LoadedArsc.cpp`**
The Gradle cache was restored with the original x86 aapt2 (shim overwritten).
Re-run the build: the script re-patches automatically. To patch by hand, see the
`patch_gradle_cache` function in `build-android-local.sh`.

**`SDK location not found`**
Environment variable lost (new shell). The script recreates `local.properties`;
make sure `~/android-sdk` exists.

**`No cached version available for offline mode`**
Don't run with `--offline` on a project's first build: Gradle must download its
dependencies. The script doesn't pass `--offline`; if you add it manually, remove
it for the first build.

**`checkDebugAarMetadata ... requires compileSdk 36`**
A dependency requires a newer compileSdk. With this chain, you can simply **raise
the compileSdk** (the shim reads all jars):
```bash
sdkmanager "platforms;android-36"
# then adjust compileSdk/targetSdk in variables.gradle (Capacitor)
# or build.gradle (native Android)
```

**Different aapt2 / AGP version**
The setup downloads aapt2 `8.13.0-13719691` (= AGP 8.13). If a project uses a
very different AGP, Gradle will want a different aapt2 version. The shim reads any
jar, but the cache jar's **version name** must match. Easiest: align the
project's AGP to 8.13, or edit `AAPT2_VERSION` in `setup-aapt2-qemu.sh` and the
`:linux@jar` in `build-android-local.sh`, then re-run the setup.

## Components

| Element              | Path                                            | Role                              |
|----------------------|-------------------------------------------------|-----------------------------------|
| recent x86 aapt2     | `~/aapt2-x86/aapt2`                             | the real tool, run via qemu       |
| ARM ELF shim         | `~/aapt2-shim`                                  | Gradle → qemu bridge              |
| shim source          | `~/aapt2-shim.c`                               | to recompile if needed            |
| original jar backup  | `~/.gradle/.../aapt2-*-linux.jar.x86.bak`       | to roll back                      |

## Repository scripts

| Script                   | Role                                                        |
|--------------------------|-------------------------------------------------------------|
| `setup-aapt2-qemu.sh`    | installs the full chain (qemu, x86 aapt2, shim)            |
| `android-builder.sh`     | clones from a git URL, detects, prepares and builds         |
| `build-android-local.sh` | patches the Gradle cache and builds a local project         |
| `detect-project.sh`      | detects the project type (Flutter/Capacitor/RN/native)      |
| `patch-gradle-cache.sh`  | injects the shim into the cached aapt2 jar                   |
| `setup-node.sh`          | installs Node.js / npm for web projects                     |
| `buildserver.py`         | local HTTP API, back-end for the APKforge app               |
| `start-build-server.sh`  | starts the build server                                     |

## Performance and limits

This is a multi-layer stack (Termux → proot → qemu → shim → Gradle cache). It
works, but it's **slower than a native build** (qemu emulates every aapt2
instruction) and more fragile than a cloud build. For fast, reliable use, GitHub
Actions remains the reference option. This chain exists to build **100% locally**,
including offline.

## Related projects

- [APKforge](https://github.com/Pandarte/forge) — the Android interface that
  drives this chain through the HTTP server.
