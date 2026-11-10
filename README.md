# Zero-Trust Browser

A private web browser for Android, part of the Zero-Trust apps. On the phone
it is **ZT Browser**.

- **Trackers and ads blocked** on every site: about 50,000 known hosts from
  EasyList and EasyPrivacy, checked for every request the page makes.
  Protection can be turned off per site from the shield in the address bar.
- **HTTPS-only**: sites open over an encrypted connection; a site that only
  works without one asks first.
- **Private tabs** with their own cookies, storage and cache (a separate
  WebView profile), deleted when the last private tab closes or the app
  locks. Never saved to history or synced.
- **Bookmarks, history, settings and open tabs** are end-to-end encrypted in
  the shared Zero-Trust account and synced between devices through
  Zero-Trust-Core. The server only sees sealed rows with random ids.
- Always on: third-party cookies blocked, Global Privacy Control sent,
  camera / microphone / location requests from sites refused, pop-ups only
  after a tap (they open as tabs), web engine usage statistics off.
- Can be the default browser; "Share to" and "Search in ZT Browser" for
  selected text.

## How it is built

The page engine is Android System WebView (Chromium, updated through Google
Play), shown in Flutter through a platform view. The native side lives in
`android/app/src/main/kotlin/dev/sagron/zerotrustbrowser/`:

| File | What |
|---|---|
| `ZtTab.kt` | One tab: a WebView with the privacy settings above, blocking, HTTPS upgrade, pop-ups, downloads, long-press menu, find in page |
| `Blocker.kt` | Host-name blocking from `assets/blocklist/domains.txt` (hash-set lookups) |
| `MainActivity.kt` | Tab registry, the `zt_browser/engine` channel, file uploads, fullscreen video, downloads, links from other apps, default-browser role |

Tabs outlive the Flutter widget showing them, so switching tabs or locking
the app keeps pages as they were. The Dart side (`lib/`) is the UI, the tab
list and the encrypted data (`lib/data/`), on the same account, lock,
settings and look as every Zero-Trust app.

Requires Android 10 (API 29). Private tabs need Android System WebView with
multi-profile support (version 123 or newer); on older WebView versions they
still keep no history and no cache, but share cookies with normal tabs.

## Updating the blocklists

```bash
git clone --depth 1 https://github.com/easylist/easylist.git /tmp/easylist
python3 tool/update_blocklist.py /tmp/easylist
```

## Builds

Every push to `main` builds a signed APK and publishes it as a GitHub
Release (`.github/workflows/android-apk.yml`). The repository needs the
`ANDROID_KEYSTORE_BASE64` and `ANDROID_KEYSTORE_PASSWORD` secrets, the same
keystore as the other Zero-Trust apps.

## Credits and licences

- Blocklists: [EasyList and EasyPrivacy](https://easylist.to) by The EasyList
  authors, used under [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/)
  (see `assets/blocklist/LICENSE`).
- Web engine: Android System WebView, part of the Android platform.
