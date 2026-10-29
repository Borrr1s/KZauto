# KZauto mobile app

The Android and iOS apps use Capacitor to package the existing web app. The
GitHub Pages site continues to serve the root `index.html`; mobile builds create
their own `www` output and do not change the Pages configuration.

## Requirements

- Node.js 22.12 or newer
- Android Studio and Android SDK for Android builds
- Xcode on macOS for iOS builds

## Build and open

```sh
npm ci
npm run cap:sync
npx cap open android
npx cap open ios
```

For a local Android debug APK, run `bash android/gradlew assembleDebug` on
macOS/Linux or `android/gradlew.bat assembleDebug` on Windows. The APK is
written to `android/app/build/outputs/apk/debug/app-debug.apk`.

The `Build mobile apps` GitHub Actions workflow builds an Android debug APK and
an unsigned iOS Simulator app on pushes to `apk` and on manual runs. Download
the artifacts from the workflow run. A distributable iOS IPA requires macOS,
an Apple signing certificate, and a provisioning profile.

## Native Google sign-in

The web app keeps using its existing GitHub Pages OAuth redirect. The native
app uses `kzauto://auth/callback` and returns to the app through Capacitor deep
links. Add that exact URL to the Supabase project's Auth redirect URL allowlist
before testing Google sign-in in a native build. The existing public Supabase
URL and publishable key remain in `index.html`; no service-role key or new
provider secret is added.
