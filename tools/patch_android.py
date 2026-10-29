#!/usr/bin/env python3
"""Adds what flutter_local_notifications needs to the generated android/ folder.

Run by tools/setup_android.sh right after `flutter create`. Safe to run twice.
Exits with an error if the generated files do not look as expected, so a
Flutter template change fails loudly instead of producing a silent APK that
never notifies.
"""
import pathlib
import re
import sys

ANDROID = pathlib.Path(__file__).resolve().parent.parent / "android"
MANIFEST = ANDROID / "app/src/main/AndroidManifest.xml"

PERMISSIONS = """\
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
    <uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" android:maxSdkVersion="32"/>
"""

RECEIVERS = """\
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
"""


def fail(message: str) -> None:
    sys.exit(f"patch_android.py: {message}")


def patch_manifest() -> None:
    text = MANIFEST.read_text()
    if "ScheduledNotificationReceiver" not in text:
        if "<application" not in text or "</application>" not in text:
            fail("AndroidManifest.xml has no <application> element")
        text = text.replace("<application", PERMISSIONS + "    <application", 1)
        text = text.replace("</application>", RECEIVERS + "    </application>", 1)
    text = re.sub(r'android:label="[^"]*"', 'android:label="Micro Reader"', text, count=1)
    MANIFEST.write_text(text)
    for needle in ("ScheduledNotificationReceiver", "POST_NOTIFICATIONS", 'android:label="Micro Reader"'):
        if needle not in text:
            fail(f"manifest patch failed: {needle} missing afterwards")


def patch_gradle() -> None:
    kts = ANDROID / "app/build.gradle.kts"
    groovy = ANDROID / "app/build.gradle"
    if kts.exists():
        text = kts.read_text()
        if "isCoreLibraryDesugaringEnabled" not in text:
            text, n = re.subn(
                r"compileOptions\s*\{",
                "compileOptions {\n        isCoreLibraryDesugaringEnabled = true",
                text,
                count=1,
            )
            if n != 1:
                fail("no compileOptions block in build.gradle.kts")
            text += (
                "\ndependencies {\n"
                '    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n'
                "}\n"
            )
        kts.write_text(text)
        marker = "isCoreLibraryDesugaringEnabled"
        target = kts
    elif groovy.exists():
        text = groovy.read_text()
        if "coreLibraryDesugaringEnabled" not in text:
            text, n = re.subn(
                r"compileOptions\s*\{",
                "compileOptions {\n        coreLibraryDesugaringEnabled true",
                text,
                count=1,
            )
            if n != 1:
                fail("no compileOptions block in build.gradle")
            text += (
                "\ndependencies {\n"
                "    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n"
                "}\n"
            )
        groovy.write_text(text)
        marker = "coreLibraryDesugaringEnabled"
        target = groovy
    else:
        fail("neither app/build.gradle.kts nor app/build.gradle found")
    if marker not in target.read_text():
        fail("gradle patch failed")


ROOT_KTS_SNIPPET = """\
// Added by tools/patch_android.py: some plugins are compiled against an older
// Android API than flutter_plugin_android_lifecycle requires. Compile them
// against a newer one. Must come before any subproject is evaluated.
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android")
        if (androidExt != null && project.name != "app") {
            androidExt.withGroovyBuilder { "compileSdkVersion"(36) }
        }
    }
}

"""

ROOT_GROOVY_SNIPPET = """\
// Added by tools/patch_android.py: see build.gradle.kts variant for why.
subprojects {
    afterEvaluate { p ->
        if (p.name != 'app' && p.hasProperty('android')) {
            p.android { compileSdkVersion 36 }
        }
    }
}

"""


def patch_root_gradle() -> None:
    kts = ANDROID / "build.gradle.kts"
    groovy = ANDROID / "build.gradle"
    if kts.exists():
        target, snippet = kts, ROOT_KTS_SNIPPET
    elif groovy.exists():
        target, snippet = groovy, ROOT_GROOVY_SNIPPET
    else:
        fail("neither android/build.gradle.kts nor android/build.gradle found")
    text = target.read_text()
    if "compileSdkVersion" not in text:
        target.write_text(snippet + text)
    if "compileSdkVersion" not in target.read_text():
        fail("root gradle patch failed")


if __name__ == "__main__":
    if not MANIFEST.exists():
        fail(f"{MANIFEST} not found. Run tools/setup_android.sh instead.")
    patch_manifest()
    patch_gradle()
    patch_root_gradle()
    print("android/ patched for notifications.")
