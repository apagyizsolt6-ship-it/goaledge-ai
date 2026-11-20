#!/usr/bin/env python3
"""Patch android build files after flutter create."""
import os
import re

run = os.environ.get("GITHUB_RUN_NUMBER", "1")
has_keystore = os.environ.get("HAS_KEYSTORE") == "true"

# ---------------------------------------------------------------------------
# settings.gradle(.kts)
# ---------------------------------------------------------------------------
for settings_path in ("android/settings.gradle.kts", "android/settings.gradle"):
    if not os.path.exists(settings_path):
        continue
    with open(settings_path, "r") as f:
        s = f.read()

    if "pluginManagement" in s and "google()" not in s:
        s = re.sub(
            r"pluginManagement\s*\{[^}]*repositories\s*\{[^}]*\}",
            """pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }""",
            s,
            count=1,
            flags=re.DOTALL,
        )
        if "google()" not in s:
            s = s.replace(
                "pluginManagement {",
                """pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
""",
                1,
            )

    with open(settings_path, "w") as f:
        f.write(s)
    print(f"Patched {settings_path} repositories")

# ---------------------------------------------------------------------------
# Root build.gradle(.kts)
# ---------------------------------------------------------------------------
for root_path in ("android/build.gradle.kts", "android/build.gradle"):
    if not os.path.exists(root_path):
        continue
    with open(root_path, "r") as f:
        s = f.read()
    s = re.sub(r'(kotlin\s*=\s*")\d+\.\d+\.\d+(")', r"\g<1>2.1.0\2", s)
    s = re.sub(
        r'(id\("org\.jetbrains\.kotlin\.android"\)\s+version\s+")\d+\.\d+\.\d+(")',
        r"\g<1>2.1.0\2",
        s,
    )
    with open(root_path, "w") as f:
        f.write(s)
    print(f"Patched {root_path}")

# ---------------------------------------------------------------------------
# app/build.gradle(.kts) – critical: FORCE release signing when keystore present
# ---------------------------------------------------------------------------
for path in ("android/app/build.gradle.kts", "android/app/build.gradle"):
    if not os.path.exists(path):
        continue
    with open(path, "r") as f:
        s = f.read()

    s = re.sub(r'applicationId\s*=\s*"[^"]+"', 'applicationId = "com.goaledge.goaledge_ai"', s)
    s = re.sub(r'applicationId\s+"[^"]+"', 'applicationId "com.goaledge.goaledge_ai"', s)
    s = re.sub(r"versionCode\s*=\s*flutter\.versionCode", f"versionCode = {run}", s)
    s = re.sub(r"versionCode\s+flutter\.versionCode", f"versionCode {run}", s)
    s = re.sub(r"versionCode\s+\d+", f"versionCode {run}", s)

    is_kts = path.endswith(".kts")

    # Desugaring
    if is_kts:
        if "isCoreLibraryDesugaringEnabled" not in s:
            s = re.sub(
                r"(sourceCompatibility\s*=\s*JavaVersion\.VERSION_\d+)",
                r"isCoreLibraryDesugaringEnabled = true\n        \1",
                s,
                count=1,
            )
        if "desugar_jdk_libs" not in s:
            s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    else:
        if "coreLibraryDesugaringEnabled" not in s:
            s = re.sub(
                r"(sourceCompatibility\s+JavaVersion\.VERSION_\d+)",
                r"coreLibraryDesugaringEnabled true\n        \1",
                s,
                count=1,
            )
        if "desugar_jdk_libs" not in s:
            s += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"

    if has_keystore:
        if is_kts:
            # Remove any existing release signingConfig assignment (often points to debug)
            s = re.sub(
                r"signingConfig\s*=\s*signingConfigs\.getByName\(\"debug\"\)",
                'signingConfig = signingConfigs.getByName("release")',
                s,
            )
            s = re.sub(
                r"signingConfig\s*=\s*signingConfigs\.getByName\(\"release\"\)",
                'signingConfig = signingConfigs.getByName("release")',
                s,
            )

            # Inject release signingConfigs if missing
            if 'create("release")' not in s and "create(\"release\")" not in s:
                block = """
    val kp = java.util.Properties()
    val kpFile = rootProject.file("key.properties")
    if (kpFile.exists()) {
        kp.load(java.io.FileInputStream(kpFile))
    }
    signingConfigs {
        create("release") {
            keyAlias = kp["keyAlias"] as String
            keyPassword = kp["keyPassword"] as String
            storeFile = file(kp["storeFile"] as String)
            storePassword = kp["storePassword"] as String
        }
    }
"""
                # Prefer insert before buildTypes
                if "buildTypes {" in s:
                    s = s.replace("buildTypes {", block + "\n    buildTypes {", 1)
                elif "signingConfigs {" in s:
                    # Append release config inside existing signingConfigs – harder; replace whole block start
                    s = s.replace(
                        "signingConfigs {",
                        """signingConfigs {
        create("release") {
            val kp = java.util.Properties()
            val kpFile = rootProject.file("key.properties")
            if (kpFile.exists()) kp.load(java.io.FileInputStream(kpFile))
            keyAlias = kp["keyAlias"] as String
            keyPassword = kp["keyPassword"] as String
            storeFile = file(kp["storeFile"] as String)
            storePassword = kp["storePassword"] as String
        }
""",
                        1,
                    )
                else:
                    s = s.replace(
                        "android {",
                        "android {\n" + block,
                        1,
                    )

            # Ensure release buildType uses release signing
            if 'signingConfigs.getByName("release")' not in s:
                s = re.sub(
                    r"(release\s*\{)",
                    r'\1\n            signingConfig = signingConfigs.getByName("release")',
                    s,
                    count=1,
                )
            else:
                # Force any debug assignment inside release to release
                pass
        else:
            # Groovy
            s = re.sub(
                r"signingConfig\s+signingConfigs\.debug",
                "signingConfig signingConfigs.release",
                s,
            )
            if "signingConfigs.release" not in s or "storeFile" not in s:
                block = """
    def kp = new Properties()
    def kpFile = rootProject.file('key.properties')
    if (kpFile.exists()) {
        kp.load(new FileInputStream(kpFile))
    }
    signingConfigs {
        release {
            keyAlias kp['keyAlias']
            keyPassword kp['keyPassword']
            storeFile file(kp['storeFile'])
            storePassword kp['storePassword']
        }
    }
"""
                if "buildTypes {" in s and "signingConfigs {" not in s:
                    s = s.replace("buildTypes {", block + "\n    buildTypes {", 1)
            if "signingConfig signingConfigs.release" not in s:
                s = re.sub(
                    r"(release\s*\{)",
                    r"\1\n            signingConfig signingConfigs.release",
                    s,
                    count=1,
                )

    with open(path, "w") as f:
        f.write(s)
    print(f"Patched {path} versionCode={run} keystore={has_keystore}")

# ---------------------------------------------------------------------------
# Manifest
# ---------------------------------------------------------------------------
manifest = "android/app/src/main/AndroidManifest.xml"
if os.path.exists(manifest):
    with open(manifest, "r") as f:
        m = f.read()
    perms = ""
    for p in (
        "android.permission.INTERNET",
        "android.permission.ACCESS_NETWORK_STATE",
        "android.permission.POST_NOTIFICATIONS",
        "android.permission.VIBRATE",
        "android.permission.REQUEST_INSTALL_PACKAGES",
    ):
        if p not in m:
            perms += f'    <uses-permission android:name="{p}"/>\n'
    if perms:
        m = m.replace("<application", perms + "    <application", 1)
        with open(manifest, "w") as f:
            f.write(m)
        print("Manifest permissions OK")

if has_keystore:
    app_gradle = None
    for p in ("android/app/build.gradle.kts", "android/app/build.gradle"):
        if os.path.exists(p):
            app_gradle = p
            break
    if app_gradle:
        with open(app_gradle, "r") as f:
            content = f.read()
        ok = (
            "signingConfigs" in content
            and ("getByName(\"release\")" in content or "signingConfigs.release" in content)
        )
        if not ok:
            raise SystemExit(
                "HAS_KEYSTORE=true but release signingConfig was not applied. Aborting.\n"
                + content[:2000]
            )
        print("Keystore signing block verified (release)")
        # Print snippet around release for CI log
        for i, line in enumerate(content.splitlines()):
            if "release" in line.lower() or "signing" in line.lower():
                print(f"  gradle:{i+1}: {line}")
