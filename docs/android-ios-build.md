# Android- und iOS-Builds

Application ID / Bundle Identifier: `me.thedemonlord333.demonify`. App-Name: Demonify.

## App-Icons neu erzeugen (nur nach Änderung der Vorlage)

Vorlage: `Neon horned demon headphone icon.png` (Original, unverändert) → Arbeitskopien in `demonify/assets/icon/`
(`app_icon.png`, `app_icon_launcher.png` mit Rand für abgerundete Ecken, `app_icon_foreground.png` und
`app_icon_monochrome.png` für Android-Adaptive-Icons innerhalb der Sicherheitszone).

```bash
cd demonify && dart run flutter_launcher_icons
```

Hinweis: Das Werkzeug ändert dabei `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS` in
`ios/Runner.xcodeproj/project.pbxproj` fälschlich auf `AppIcon` – diese Änderung bitte verwerfen:

```bash
git checkout ios/Runner.xcodeproj/project.pbxproj
```

## Android (unter Windows)

Einmalig einen Upload-Schlüssel erzeugen (PowerShell, JDK aus Android Studio):

```bash
keytool -genkey -v -keystore %USERPROFILE%\demonify-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias demonify
```

`demonify\android\key.properties` anlegen (wird nicht versioniert):

```properties
storePassword=<PASSWORT>
keyPassword=<PASSWORT>
keyAlias=demonify
storeFile=C:\\Users\\<NAME>\\demonify-upload.jks
```

Ohne `key.properties` wird ein Release mit dem Debug-Schlüssel signiert (nur für Tests).

Befehle (im Ordner `demonify`):

```bash
flutter pub get
```

```bash
flutter analyze
```

```bash
flutter test
```

```bash
flutter build apk --release
```

```bash
flutter build appbundle --release
```

Direkt auf ein per USB verbundenes Gerät installieren:

```bash
flutter install --release
```

Eine andere API-Basis (z. B. Testserver) setzt du mit `--dart-define=DEMONIFY_API_BASE=https://…/api/v1/`.

Hintergrundwiedergabe ist konfiguriert: `MainActivity` erbt von `AudioServiceActivity`, der Dienst
`com.ryanheise.audioservice.AudioService` (foregroundServiceType `mediaPlayback`), Berechtigungen `WAKE_LOCK`,
`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `POST_NOTIFICATIONS`. Die native libmpv-Bibliothek
lädt der Gradle-Build beim ersten Build von GitHub (media_kit_libs_android_audio) – Internetzugang nötig.

## iOS (auf dem Mac mit Xcode)

1. Repository klonen, dann:

```bash
cd demonify
```

```bash
flutter pub get
```

```bash
cd ios && pod install && cd ..
```

2. `ios/Runner.xcworkspace` in Xcode öffnen → Target **Runner** → *Signing & Capabilities*:
   - Team auswählen, Bundle Identifier `me.thedemonlord333.demonify` belassen.
   - *Background Modes* ist bereits über `Info.plist` gesetzt (`UIBackgroundModes: audio`); in Xcode wird „Audio, AirPlay, and Picture in Picture“ als aktiv angezeigt.
3. Auf ein angeschlossenes iPhone:

```bash
flutter run --release
```

4. Archiv für TestFlight/Ad-hoc:

```bash
flutter build ipa --release
```

   Anschließend in Xcode *Organizer* hochladen oder mit Transporter.

Hinweise:
- Mindestversion iOS 15.0.
- media_kit lädt beim `pod install` die libmpv-XCFrameworks (Internetzugang nötig).
- Für Entwicklung gegen einen lokalen HTTP-Server ist `NSAllowsLocalNetworking` gesetzt; Produktion nutzt HTTPS.

## Was hier geprüft wurde – und was nicht

Ausgeführt: `flutter analyze` (keine Befunde), `flutter test` (Warteschlange, Equalizer, Player-Quellenwahl, Login, Layoutprüfung).
**Nicht** ausgeführt: Android-/iOS-Builds und Tests auf echten Geräten – in der Entwicklungsumgebung waren weder
Android-SDK (Download gesperrt) noch Xcode verfügbar. Bitte die Builds wie oben beschrieben lokal durchführen.
