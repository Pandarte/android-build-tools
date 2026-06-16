# 🔨 android-build-tools

**Build Android APKs locally on ARM — native Termux first, proot + qemu fallback. No PC, no cloud build.**

> 🇬🇧 English &nbsp;•&nbsp; [🇫🇷 Français](README.fr.md)

This toolkit builds **any Android/Gradle project** (native Android, Capacitor,
React Native, Flutter) directly on an ARM phone. It also ships a small HTTP
server that acts as the back-end for the
[APKforge](https://github.com/Pandarte/APKforge) app.

<p align="left">
  <img alt="Platform" src="https://img.shields.io/badge/platform-Termux%20%2F%20Android%20ARM-3DDC84">
  <img alt="Method" src="https://img.shields.io/badge/aapt2-native%20ARM%20%2B%20qemu%20fallback-orange">
  <img alt="Shell" src="https://img.shields.io/badge/shell-bash-4EAA25">
  <img alt="Server" src="https://img.shields.io/badge/server-python3-3776AB">
</p>

---

## Two build chains: native first, proot as a fallback

This toolkit ships **two** ways to build. The **native** chain is the default;
the **proot + qemu** chain is a fallback, installed and used only when needed.

| Chain | Scripts | aapt2 | Speed | Role |
|-------|---------|-------|-------|------|
| **Termux-native** | `setup-termux-native.sh`, `build-termux-native.sh` | Termux ARM aapt2 (native) | fast (native) | **default** — every build starts here |
| **proot + qemu** | `bootstrap-debian-build.sh`, `setup-aapt2-qemu.sh`, `android-builder.sh`, `build-android-local.sh` | Google x86 via qemu (in a Debian proot) | slower (emulated) | **fallback** — only if native fails for a toolchain reason |

How the server arbitrates (`buildserver.py`):

1. Every build runs **natively** first (native ARM aapt2, no qemu).
2. If it succeeds → done. Nothing else touched.
3. If it fails, the server checks **why**. A project error (Kotlin error, missing
   symbol…) is reported as-is — the proot wouldn't fix it, so no fallback.
4. If the failure is tied to the **toolchain** (e.g. `failed to load include
   path .../android.jar` because the Termux aapt2 is too old for the project's
   compileSdk), the server falls back to the proot + qemu chain. If no proot is
   installed yet, it **installs Debian on demand** (`bootstrap-debian-build.sh`)
   and retries there.

Why a fallback at all? Gradle needs `aapt2` to read the target API's
`android.jar`. The aapt2 packaged by Termux is a **native ARM binary** (fast, no
emulation) but is built on an older Android base, so it can only read
`android.jar` up to roughly API 34. Projects requiring **compileSdk 35+** (e.g.
`androidx.activity` ≥ 1.10 or Material 3 Expressive) can't be read by the Termux
aapt2. For those, the only option on ARM is Google's recent x86 aapt2 run through
qemu — hence the proot chain.

**Net effect:** simple/older projects build fast and natively, and never touch
a proot. Recent-SDK projects start native, hit the aapt2 wall, and the server
transparently provisions and uses the Debian + qemu fallback. The day Termux
updates its aapt2 to a newer Android base, the native chain will cover recent
SDKs too and the proot can be retired entirely.

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

Everything is driven from **Termux** (no proot needed for normal use).

**Native chain (default):**

```bash
bash ~/android-build-tools/setup-termux-native.sh
```

This installs the JDK, the Android SDK and the **native ARM aapt2**, and points
Gradle at it. It is idempotent. After this you can build any project whose
compileSdk the Termux aapt2 supports (≈ API 34 and below).

**Debian fallback (optional, on demand):**

You normally don't install this yourself — the server provisions it
automatically the first time a native build fails for a toolchain reason. To set
it up ahead of time anyway:

```bash
bash ~/android-build-tools/bootstrap-debian-build.sh
```

This installs a **minimal** Debian proot and runs `setup-aapt2-qemu.sh` inside
it (qemu, gcc, JDK, x86 multiarch libs, x86 aapt2, the shim, and a single SDK
platform). Nothing superfluous; the proot stays idle while native builds
succeed.

## Usage

### Build from a git URL (all-in-one)

`android-builder.sh` clones a repository, **detects its type** (Flutter /
Capacitor / React Native / native Android), extracts its needs (compileSdk,
AGP…), installs missing SDK platforms, prepares it (`npm install` / `cap sync` /
`pub get`), then builds it through the aapt2 + qemu chain.

```bash
# inside the Debian fallback proot (the server enters it automatically):
proot-distro login debian
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
- **Flutter**: the Flutter SDK must be installed inside the Debian proot
  ([official guide](https://docs.flutter.dev/get-started/install/linux)). The
  tool detects it and warns if it's missing.
- **Native Android**: nothing beyond the chain and the Android SDK.

### Build a project already on disk

```bash
proot-distro login debian
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
# inside the project folder, on the Debian side:
npm install
npx cap sync android
bash ~/android-build-tools/build-android-local.sh ./android
```

### Build server (APKforge back-end)

`buildserver.py` exposes the chain via a small local HTTP API
(`127.0.0.1:8765`), driven by the
[APKforge](https://github.com/Pandarte/APKforge) app.

```bash
python3 ~/buildserver/buildserver.py        # or: bash start-build-server.sh
```

The server runs **in Termux**. It drives the native chain directly and, only on
a toolchain-related native failure, provisions and uses the Debian + qemu
fallback (see *Two build chains* above).

### Termux-native build (default path)

This is the default chain the server uses for every build. Run it by hand from
Termux — no proot, no qemu, full native speed:

```bash
bash ~/android-build-tools/setup-termux-native.sh                 # one time
bash ~/android-build-tools/build-termux-native.sh <git-url|path>  # build
```

`setup-termux-native.sh` installs the JDK, the Android SDK and the **Termux
native ARM aapt2** (`pkg install aapt2`), and points Gradle at it via
`android.aapt2FromMavenOverride`. It verifies the binary actually runs (no
`Exec format error`). If the build later fails with `failed to load include path
.../android.jar`, the project's compileSdk is too recent for the Termux aapt2 —
use the proot+qemu chain instead.

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
| `setup-termux-native.sh` | sets up the native chain (default: JDK, SDK, native aapt2) |
| `bootstrap-debian-build.sh` | installs the minimal Debian fallback proot + the qemu chain |
| `setup-aapt2-qemu.sh`    | installs the qemu chain inside the proot (x86 aapt2, shim) |
| `android-builder.sh`     | clones from a git URL, detects, prepares and builds         |
| `build-android-local.sh` | patches the Gradle cache and builds a local project         |
| `detect-project.sh`      | detects the project type (Flutter/Capacitor/RN/native)      |
| `patch-gradle-cache.sh`  | injects the shim into the cached aapt2 jar                   |
| `setup-node.sh`          | installs Node.js / npm for web projects                     |
| `build-termux-native.sh` | builds natively in Termux (no proot/qemu)                   |
| `lib-i18n.sh`            | bilingual log messages (EN default, FR via `ABT_LANG`)      |
| `buildserver.py`         | local HTTP API, back-end for the APKforge app               |
| `start-build-server.sh`  | starts the build server                                     |

## Performance and limits

The **native** path (Termux ARM aapt2) is the norm and runs at full speed. The
**fallback** is a multi-layer stack (Termux → proot → qemu → shim → Gradle
cache): it works, but qemu emulates every aapt2 instruction, so it's slower and
more fragile. It only kicks in when the project's compileSdk outruns the Termux
aapt2. For fast, reliable CI, GitHub Actions remains the reference option; this
toolkit exists to build **100% locally**, including offline.

## Related projects

- [APKforge](https://github.com/Pandarte/APKforge) — the Android interface that
  drives this chain through the HTTP server.
