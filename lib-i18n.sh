#!/usr/bin/env bash
# lib-i18n.sh — minimal bilingual message helper for android-build-tools.
#
# Default language is English. Set ABT_LANG=fr (env var) for French, or let the
# build server propagate the APKforge UI language automatically.
#
# Usage:
#   source "$(dirname "$0")/lib-i18n.sh"
#   echo "$(t key_name)"                 # plain message
#   printf "$(t key_with_fmt)\n" "$x"    # message with a %s placeholder
#
# A key falls back to English if no French entry exists, and to the key name
# itself if the key is unknown (so nothing ever prints blank).

# Resolve language: explicit ABT_LANG wins; otherwise default to English.
case "${ABT_LANG:-en}" in
    fr*|FR*) _ABT_LANG="fr" ;;
    *)       _ABT_LANG="en" ;;
esac

t() {
    local key="$1"
    local en fr
    case "$key" in
        # --- android-builder.sh ---
        chain_missing)        en="ERROR: aapt2+qemu chain missing. Run first:";                          fr="ERREUR: chaine aapt2+qemu absente. Lance d'abord :" ;;
        run_setup_hint)       en="    bash ~/android-build-tools/setup-aapt2-qemu.sh";                    fr="    bash ~/android-build-tools/setup-aapt2-qemu.sh" ;;
        clone_step)           en="=== [1] Cloning %s ===";                                                fr="=== [1] Clone de %s ===" ;;
        already_cloned)       en="Already cloned, updating...";                                           fr="Deja clone, mise a jour..." ;;
        subdir_missing)       en="ERROR: subfolder %s not found";                                         fr="ERREUR: sous-dossier %s introuvable" ;;
        detect_step)          en="=== [2] Detecting project type ===";                                    fr="=== [2] Detection du type de projet ===" ;;
        type_detected)        en="Detected type: %s";                                                     fr="Type detecte : %s" ;;
        type_unknown)         en="WARNING: unrecognized type. Attempting a generic Gradle build.";        fr="AVERTISSEMENT: type non reconnu. On tente un build Gradle generique." ;;
        android_module)       en="Android module: %s";                                                    fr="Module Android : %s" ;;
        needs_extracted)      en="Extracted needs: compileSdk=%s targetSdk=%s minSdk=%s AGP=%s";          fr="Besoins extraits : compileSdk=%s targetSdk=%s minSdk=%s AGP=%s" ;;
        agp_note)             en="NOTE: project AGP (%s) != installed aapt2 version (%s.x).";              fr="NOTE: AGP du projet (%s) != version de l'aapt2 installe (%s.x)." ;;
        agp_note2)            en="      If the build fails on aapt2, see README (section 'aapt2/AGP version').";  fr="      Si le build echoue sur aapt2, voir README (section 'Version aapt2/AGP')." ;;
        sdk_install_step)     en="=== [3] Installing missing SDK platforms ===";                          fr="=== [3] Installation des plateformes SDK manquantes ===" ;;
        sdk_install_fail)     en="     (failed to install android-%s, continuing)";                       fr="     (echec install android-%s, on continue)" ;;
        sdk_absent)           en="WARNING: Android SDK missing (%s). See README to install it.";          fr="ATTENTION: SDK Android absent (%s). Voir README pour l'installer." ;;
        prepare_step)         en="=== [4] Preparation (%s) ===";                                          fr="=== [4] Preparation (%s) ===" ;;
        node_missing)         en="ERROR: node not found in Ubuntu.";                                      fr="ERREUR: node introuvable dans Ubuntu." ;;
        install_once)         en="  Install it (once):";                                                  fr="  Installe-le (une fois) :" ;;
        nvm_curl)             en="    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash";  fr="    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash" ;;
        cap_sync_fail)        en="(cap sync failed; building anyway)";                                    fr="(cap sync a echoue ; on tente le build quand meme)" ;;
        flutter_missing)      en="ERROR: Flutter not installed in Ubuntu.";                               fr="ERREUR: Flutter non installe dans Ubuntu." ;;
        flutter_install)      en="  Install it: https://docs.flutter.dev/get-started/install/linux";      fr="  Installe-le : https://docs.flutter.dev/get-started/install/linux" ;;
        flutter_install2)     en="  (or via 'snapd'/git clone of the Flutter SDK).";                      fr="  (ou via 'snapd'/git clone du SDK flutter)." ;;
        no_prepare)           en="No specific preparation step.";                                         fr="Pas d'etape de preparation specifique." ;;
        prepare_failed)       en=">>> Preparation failed. What do you want to do?";                       fr=">>> La preparation a echoue. Que veux-tu faire ?" ;;
        prepare_failed2)      en="    Check the error above. Common causes: no network,";                 fr="    Regarde l'erreur ci-dessus. Causes frequentes : pas de reseau," ;;
        prepare_failed3)      en="    node/flutter missing, repo postinstall script failing.";             fr="    node/flutter manquant, script postinstall du repo qui echoue." ;;
        prepare_failed4)      en="    Fix then re-run, or continue anyway (the build will tell).";        fr="    Corrige puis relance, ou continue quand meme (le build dira)." ;;
        no_gradlew)           en="ERROR: no gradle module (gradlew) found. Build impossible.";            fr="ERREUR: aucun module gradle (gradlew) trouve. Build impossible." ;;
        show_exact_error)     en=">>> Show me the exact error (the ~30 lines above)";                       fr=">>> Montre-moi l'erreur exacte (les ~30 dernieres lignes ci-dessus)" ;;
        build_success_hdr)    en="=== BUILD SUCCEEDED ===";                                                 fr="=== BUILD REUSSI ===" ;;
        copy_to_dl_label)     en="Copy to Downloads:";                                                      fr="Copie vers Telechargements :" ;;
        build_failed_hdr)     en="=== BUILD FAILED (code %s) ===";                                          fr="=== BUILD ECHOUE (code %s) ===" ;;
        diag_header)          en="Quick diagnosis of known causes:";                                        fr="Diagnostic rapide des causes connues :" ;;
        diag_arsc)            en=" - 'failed to load include path .../android.jar' or 'LoadedArsc':";        fr=" - 'failed to load include path .../android.jar' ou 'LoadedArsc' :" ;;
        diag_arsc2)           en="     the Gradle cache was restored -> re-run, the patch redoes itself.";   fr="     le cache Gradle a ete restaure -> relance, le patch se refait." ;;
        diag_compilesdk)      en=" - 'checkDebugAarMetadata ... requires compileSdk N':";                    fr=" - 'checkDebugAarMetadata ... requires compileSdk N' :" ;;
        diag_compilesdk2)     en="     raise compileSdk to N (the shim reads all jars) + sdkmanager.";       fr="     monte compileSdk a N (le shim lit tous les jar) + sdkmanager." ;;
        diag_vanilla)         en=" - 'VANILLA_ICE_CREAM' / 'cannot find symbol' API 35:";                    fr=" - 'VANILLA_ICE_CREAM' / 'cannot find symbol' API 35 :" ;;
        diag_vanilla2)        en="     the code requires compileSdk 35+ -> align compileSdk.";               fr="     le code exige compileSdk 35+ -> aligne compileSdk." ;;
        diag_sdkloc)          en=" - 'SDK location not found': SDK missing, see README.";                    fr=" - 'SDK location not found' : SDK absent, voir README." ;;
        decide_fix)           en="    and we decide on the fix together.";                                   fr="    et on decide ensemble du correctif." ;;
        capacitor_hint)       en="(for a Capacitor project, point at the 'android' subfolder)";              fr="(pour un projet Capacitor, vise le sous-dossier 'android')" ;;

        # --- build-android-local.sh ---
        build_step)           en="=== Build: %s in %s ===";                                               fr="=== Build : %s dans %s ===" ;;
        patch_attempt1)       en="=== Patching Gradle cache (1st attempt) ===";                           fr="=== Patch du cache Gradle (1re tentative) ===" ;;
        aapt2_patience)       en="(hang tight on processDebugResources: aapt2 runs via qemu, it's slower)";  fr="(patience sur processDebugResources : aapt2 tourne via qemu, c'est plus lent)" ;;
        build_retry)          en="=== Failure: re-patching cache then retrying ===";                      fr="=== Echec : re-patch du cache puis nouvelle tentative ===" ;;
        build_success)        en="=== BUILD SUCCEEDED ===";                                               fr="=== BUILD REUSSI ===" ;;
        no_apk)               en="No .apk found (task '%s' may not produce one).";                        fr="Aucun .apk trouve (la tache '%s' n'en produit peut-etre pas)." ;;
        copy_to_dl)           en="To copy to Termux Downloads:";                                          fr="Pour copier vers les Telechargements Termux :" ;;
        no_gradlew_dir)       en="ERROR: no gradlew in %s";                                               fr="ERREUR: pas de gradlew dans %s" ;;
        sdk_not_found_dir)    en="WARNING: Android SDK not found at %s";                                   fr="ATTENTION: SDK Android introuvable a %s" ;;
        sdk_install_sdkman)   en="Install it with sdkmanager, or adjust ANDROID_SDK in this script.";     fr="Installe-le avec sdkmanager, ou ajuste ANDROID_SDK dans ce script." ;;

        # --- patch-gradle-cache.sh ---
        shim_missing)         en="ERROR: shim missing (%s). Run setup-aapt2-qemu.sh";                     fr="ERREUR: shim absent (%s). Lance setup-aapt2-qemu.sh" ;;
        jar_absent_predl)     en="aapt2 jar absent from cache, pre-downloading...";                       fr="Jar aapt2 absent du cache, pre-telechargement..." ;;
        jar_not_cached)       en="aapt2 jar not cached yet. Pre-downloading...";                          fr="Jar aapt2 pas encore en cache. Pre-telechargement..." ;;
        no_gradlew_predl)     en="ERROR: no gradlew provided nor system gradle to pre-download.";         fr="ERREUR: pas de gradlew fourni ni de gradle systeme pour pre-telecharger." ;;
        cache_patched_predl)  en="Cache patched after pre-download.";                                     fr="Cache patche apres pre-telechargement." ;;
        jar_missing_predl)    en="FAILURE: aapt2 jar not found even after pre-download.";                 fr="ECHEC: jar aapt2 introuvable meme apres pre-telechargement." ;;
        jar_still_missing)    en="WARNING: jar still not found, the build will reveal it.";               fr="AVERTISSEMENT: jar toujours pas trouve, le build le revelera." ;;
        patched_jar)          en="  patched: %s";                                                         fr="  patche : %s" ;;
        cache_restored)       en="     the Gradle cache was restored -> re-run, the patch redoes itself.";  fr="     le cache Gradle a ete restaure -> relance, le patch se refait." ;;
        cache_ok)             en="Gradle cache: aapt2 = ARM shim (OK).";                                  fr="Cache Gradle : aapt2 = shim ARM (OK)." ;;

        # --- setup-aapt2-qemu.sh ---
        proot_only)           en="ERROR: this script must run INSIDE the Ubuntu proot (proot-distro login ubuntu).";  fr="ERREUR: ce script doit tourner DANS le proot Ubuntu (proot-distro login ubuntu)." ;;
        setup_pkgs)           en="=== [2/6] Installing packages (qemu, gcc, jdk, tools) ===";             fr="=== [2/6] Installation des paquets (qemu, gcc, jdk, outils) ===" ;;
        setup_dl_aapt2)       en="=== [4/6] Downloading Google's x86 aapt2 (%s) ===";                     fr="=== [4/6] Telechargement de l'aapt2 x86 de Google (%s) ===" ;;
        bin_downloaded)       en="binary downloaded";                                                     fr="binaire telecharge" ;;
        setup_compile_shim)   en="=== [5/6] Compiling the ARM ELF shim (bridge to qemu) ===";            fr="=== [5/6] Compilation du shim ELF ARM (pont vers qemu) ===" ;;
        shim_out_ok)          en="OK -> %s";                                                              fr="OK -> %s" ;;
        setup_test_shim)      en="=== [6/6] Testing the shim ===";                                        fr="=== [6/6] Test du shim ===" ;;
        shim_bad_version)     en="ERROR: the shim doesn't return the expected version.";                 fr="ERREUR: le shim ne renvoie pas la version attendue." ;;
        chain_installed)      en=" Chain installed successfully.";                                        fr=" Chaine installee avec succes." ;;
        use_build_local)      en=" To build a project, use build-android-local.sh";                       fr=" Pour builder un projet, utilise build-android-local.sh" ;;
        use_build_local2)     en=" (it patches the Gradle cache automatically).";                         fr=" (il s'occupe de patcher le cache Gradle automatiquement)." ;;

        # --- setup-node.sh ---
        node_clean)           en="== Cleaning up any broken apt node/npm ==";                            fr="== Nettoyage d'un eventuel node/npm d'apt casse ==" ;;
        node_install_nvm)     en="== Installing nvm (if absent) ==";                                      fr="== Installation de nvm (si absent) ==" ;;
        node_install_lts)     en="== Installing Node 20 LTS ==";                                          fr="== Installation de Node 20 LTS ==" ;;
        node_ready)           en="OK. node/npm are ready and visible to android-builder.sh.";             fr="OK. node/npm sont prets et visibles par android-builder.sh." ;;

        # --- start-build-server.sh / buildserver ---
        server_start)         en="Starting build server on 127.0.0.1:%s";                                fr="Demarrage du serveur de build sur 127.0.0.1:%s" ;;
        build_step5)          en="=== [5] Build ===";                                                       fr="=== [5] Build ===" ;;
        apk_produced)         en="=== Produced APK(s) ===";                                                 fr="=== APK(s) produit(s) ===" ;;
        setup_step1)          en="=== [1/6] Checking we are inside the Ubuntu proot ===";                   fr="=== [1/6] Verification qu'on est bien dans le proot Ubuntu ===" ;;
        setup_step3)          en="=== [3/6] Enabling x86 multiarch + libs for qemu ===";                    fr="=== [3/6] Activation multiarch x86 + libs pour qemu ===" ;;
        node_verify)          en="== Verification ==";                                                      fr="== Verification ==" ;;

        *) en="$key"; fr="$key" ;;
    esac
    if [ "$_ABT_LANG" = "fr" ] && [ -n "$fr" ]; then
        printf '%s' "$fr"
    else
        printf '%s' "$en"
    fi
}
