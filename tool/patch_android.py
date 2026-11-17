#!/usr/bin/env python3
import os
import re

run = os.environ.get("GITHUB_RUN_NUMBER", "1")
has_keystore = os.environ.get("HAS_KEYSTORE") == "true"

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
            s += '\ndependencies {\n    coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:2.1.4"\n}\n'
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
    ):
        if p not in m:
            perms += f'    <uses-permission android:name="{p}"/>\n'
    if perms:
        m = m.replace("<application", perms + "    <application", 1)
        with open(manifest, "w") as f:
            f.write(m)
        print("Manifest permissions OK")
