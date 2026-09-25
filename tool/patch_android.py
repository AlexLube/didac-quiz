"""Ajusta el proyecto Android que genera `flutter create` (se ejecuta en CI).

- Nombre visible "Didac-Quiz" e identificador com.didacquiz.app
- Permiso de Internet
- ID de aplicación de AdMob (por defecto, el de pruebas de Google)
- Enlace de vuelta para el inicio de sesión con Google/Apple
- minSdk 23 (requisito de los anuncios)
"""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

APP = Path(sys.argv[1] if len(sys.argv) > 1 else "app")
ADMOB_APP_ID = os.environ.get("ADMOB_APP_ID") or "ca-app-pub-3940256099942544~3347511713"

manifest = APP / "android/app/src/main/AndroidManifest.xml"
m = manifest.read_text(encoding="utf-8")

if "android.permission.INTERNET" not in m:
    m = m.replace("<application", '<uses-permission android:name="android.permission.INTERNET"/>\n    <application', 1)

m = re.sub(r'android:label="[^"]*"', 'android:label="Didac-Quiz"', m, count=1)

if "com.google.android.gms.ads.APPLICATION_ID" not in m:
    m = re.sub(
        r"(<application[^>]*>)",
        r'\1\n        <meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" '
        f'android:value="{ADMOB_APP_ID}"/>',
        m,
        count=1,
    )

if "login-callback" not in m:
    deep_link = """
            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="com.didacquiz.app" android:host="login-callback"/>
            </intent-filter>
        </activity>"""
    m = m.replace("</activity>", deep_link, 1)

manifest.write_text(m, encoding="utf-8")

for name in ("build.gradle.kts", "build.gradle"):
    gradle = APP / "android/app" / name
    if not gradle.exists():
        continue
    g = gradle.read_text(encoding="utf-8")
    g = re.sub(r'applicationId\s*=?\s*"[^"]+"', 'applicationId = "com.didacquiz.app"', g)
    g = re.sub(r"minSdk(Version)?\s*=?\s*flutter\.minSdkVersion", "minSdk = 23", g)
    gradle.write_text(g, encoding="utf-8")
    print(f"Ajustado {gradle}")

print("AndroidManifest ajustado")
