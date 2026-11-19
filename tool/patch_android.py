#!/usr/bin/env python3
"""Patch android build files after flutter create."""
import os
import re

run = os.environ.get("GITHUB_RUN_NUMBER", "1")
has_keystore = os.environ.get("HAS_KEYSTORE") == "true"

# ---------------------------------------------------------------------------
# settings.gradle(.kts) – ensure Google + Maven Central for Kotlin / plugins
# ---------------------------------------------------------------------------
for settings_path in ("android/settings.gradle.kts", "android/settings.gradle"):
    if not os.path.exists(settings_path):
        continue
    with open(settings_path, "r") as f:
        s = f.read()

    # Ensure pluginManagement has google() + mavenCentral() + gradlePluginPortal()
    if "pluginManagement" in s:
        # Replace a minimal pluginManagement repositories block if only portal is present
        if "google()" not in s or "mavenCentral()" not in s:
            # Inject full repositories inside pluginManagement { repositories { ... } }
            def fix_repos(match):
                body = match.group(0)
                if "google()" in body and "mavenCentral()" in body:
                    return body
                # Replace entire repositories { } inside the match with a known-good set
                return re.sub(
                    r"repositories\s*\{[^}]*\}",
                    """repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }""",
                    body,
                    count=1,
                )

            s2 = re.sub(
                r"pluginManagement\s*\{.*?repositories\s*\{.*?\}\s*",
                fix_repos,
                s,
                count=1,
                flags=re.DOTALL,
            )
            if s2 != s:
                s = s2
            elif "pluginManagement" in s and "google()" not in s:
                # Fallback: prepend repositories right after pluginManagement {
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

    # dependencyResolutionManagement repositories
    if "dependencyResolutionManagement" in s:
        if "google()" not in s.split("dependencyResolutionManagement")[-1][:500]:
            s = re.sub(
                r"(dependencyResolutionManagement\s*\{[^}]*repositories\s*\{)",
                r"\1\n        google()\n        mavenCentral()\n",
                s,
                count=1,
                flags=re.DOTALL,
            )

    with open(settings_path, "w") as f:
        f.write(s)
    print(f"Patched {settings_path} repositories")

# ---------------------------------------------------------------------------
# Root build.gradle(.kts) – pin Kotlin if present / add google maven
# ---------------------------------------------------------------------------
for root_path in ("android/build.gradle.kts", "android/build.gradle"):
    if not os.path.exists(root_path):
        continue
    with open(root_path, "r") as f:
        s = f.read()

    # Prefer a stable Kotlin that resolves on Maven Central (avoid broken portal-only resolves)
    # Only rewrite if an explicit kotlin version is set high / unknown.
    s = re.sub(
        r'(kotlin\s*=\s*")\d+\.\d+\.\d+(")',
        r"\g<1>2.1.0\2",
        s,
    )
    s = re.sub(
        r'(id\("org\.jetbrains\.kotlin\.android"\)\s+version\s+")\d+\.\d+\.\d+(")',
        r"\g<1>2.1.0\2",
        s,
    )

    with open(root_path, "w") as f:
        f.write(s)
    print(f"Patched {root_path}")

# ---------------------------------------------------------------------------
# app/build.gradle(.kts)
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
        if has_keystore and "signingConfigs" not in s and "buildTypes {" in s:
            block = """
    val kp = java.util.Properties()
    val kpFile = rootProject.file("key.properties")
    if (kpFile.exists()) kp.load(java.io.FileInputStream(kpFile))
    signingConfigs {
        create("release") {
            if (kpFile.exists()) {
                keyAlias = kp["keyAlias"] as String
                keyPassword = kp["keyPassword"] as String
                storeFile = file(kp["storeFile"] as String)
                storePassword = kp["storePassword"] as String
            }
        }
    }
"""
            s = s.replace("buildTypes {", block + "\n    buildTypes {", 1)
            s = re.sub(
                r"(buildTypes\s*\{\s*release\s*\{)",
                r'\1\n            signingConfig = signingConfigs.getByName("release")',
                s,
                count=1,
            )
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
        if has_keystore and "signingConfigs" not in s and "buildTypes {" in s:
            block = """
    def kp = new Properties()
    def kpFile = rootProject.file('key.properties')
    if (kpFile.exists()) kp.load(new FileInputStream(kpFile))
    signingConfigs {
        release {
            if (kpFile.exists()) {
                keyAlias kp['keyAlias']
                keyPassword kp['keyPassword']
                storeFile file(kp['storeFile'])
                storePassword kp['storePassword']
            }
        }
    }
"""
            s = s.replace("buildTypes {", block + "\n    buildTypes {", 1)
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
# AndroidManifest permissions
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

# Fail the job early if keystore was expected but signing block missing (optional safety)
if has_keystore:
    app_gradle = None
    for p in ("android/app/build.gradle.kts", "android/app/build.gradle"):
        if os.path.exists(p):
            app_gradle = p
            break
    if app_gradle:
        with open(app_gradle, "r") as f:
            content = f.read()
        if "signingConfigs" not in content:
            raise SystemExit(
                "HAS_KEYSTORE=true but signingConfigs was not injected into app gradle. Aborting."
            )
        print("Keystore signing block verified")
