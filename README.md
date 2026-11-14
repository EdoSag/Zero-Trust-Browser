# Zero-Trust Browser

A private web browser for Android, part of the Zero-Trust apps. On the phone
it is **ZT Browser**.

- **Trackers and ads blocked** on every site: about 50,000 known hosts from
  EasyList and EasyPrivacy, checked for every request the page makes.
  **Cookie banners and empty ad boxes hidden** (EasyList Cookie List and
  EasyList element hiding). Protection can be turned off per site from the
  shield in the address bar. The list updates weekly without an app update,
  signed (see below).
- **Fingerprinting protection**: canvas, audio and WebGL readouts get noise
  that differs per site and per app start; CPU and memory report common
  values; the battery API is gone.
- **Per-site JavaScript switch** and **per-site camera / microphone /
  location**: sites ask, you answer once (remembered and synced) or only
  this time; private tabs always ask.
- **Links without tracking tags**: `utm_…`, `fbclid`, `gclid` and some 70
  others are removed from links you open, copy or share; redirect pages
  that only report the click (`google.com/url?q=…`, `l.facebook.com`…) and
  Google AMP copies are skipped, so the real page opens directly.
- **Privacy report**: trackers and ads blocked this week, per day and per
  site, over all your devices. Kept like history (end-to-end encrypted);
  private tabs add to the total without the site's name.
- **HTTPS-only**: sites open over an encrypted connection; a site that only
  works without one asks first.
- **Private tabs** with their own cookies, storage and cache (a separate
  WebView profile), deleted when the last private tab closes or the app
  locks. Never saved to history or synced.
- **Bookmarks, history, settings and open tabs** are end-to-end encrypted in
  the shared Zero-Trust account and synced between devices through
  Zero-Trust-Core. The server only sees sealed rows with random ids.
- **Reader view** (Mozilla Readability) and a **reading list** whose pages
  are saved to read offline as end-to-end encrypted attachments.
- **Tabs**: groups, search, close tabs unused for N days; background tabs
  unload when memory runs low and come back with their history.
- **Downloads page** (open, share, delete), including files pages make
  themselves (`blob:` and `data:` links).
- **Import bookmarks** from Chrome, Firefox, Edge or Safari (.html export).
- **QR code scanner** (ZXing, offline) and voice search in the address bar;
  share a page as a QR code.
- Print or save as PDF; add a site to the home screen.
- The fire button: close all tabs and clear cookies, site data, cache and
  (optionally) recent history in one go.
- Dark pages (when the phone is in dark mode) and a text size setting.
- Password managers (Bitwarden, Proton Pass, 1Password...) fill forms
  through Android autofill; ZT Browser never stores passwords.
- Always on: third-party cookies blocked, Global Privacy Control sent,
  pop-ups only after a tap (they open as tabs), web engine usage
  statistics off.
- **Start page shortcuts**: pin sites, reorder them, and a "Most visited"
  row from your history.
- **Search suggestions** (off until you turn them on; addresses and
  private tabs are never sent) and **your own search engines**.
- **User scripts** in the Tampermonkey / Greasemonkey format (Greasy Fork
  scripts work), the answer to "no extensions": add from a link, a file or
  by pasting; tap a `.user.js` link to install. Before installing you see
  which sites the script runs on, where it can send data and what else it
  can do. Updates only after you review them; off in private tabs unless
  you allow it. Scripts sync end-to-end encrypted; what they store stays
  on the phone, encrypted. See "User scripts" below for the supported
  `GM_*` functions.
- **English and Hebrew**, with a right-to-left layout. The sign-in and
  unlock screens come from Zero-Trust-Core and are English for now.
- Can be the default browser; "Share to" and "Search in ZT Browser" for
  selected text.

## How it is built

The page engine is Android System WebView (Chromium, updated through Google
Play), shown in Flutter through a platform view. The native side lives in
`android/app/src/main/kotlin/dev/sagron/zerotrustbrowser/`:

| File | What |
|---|---|
| `ZtTab.kt` | One tab: a WebView with the privacy settings above, blocking, HTTPS upgrade, per-site JavaScript, permissions, pop-ups, downloads, reader extraction, long-press menu, find in page |
| `Blocker.kt` | Host-name blocking and element-hiding rules from `assets/blocklist/blocklist.txt` (hash-set lookups), or a newer signed download |
| `PageScripts.kt` | The script every page gets first (Global Privacy Control, fingerprinting noise, hiding CSS), reader view, blob downloads |
| `Downloads.kt` | The Downloads page's list, data:/blob: files saved to Downloads |
| `MainActivity.kt` | Tab registry and memory (unloading), the `zt_browser/engine` channel, file uploads, fullscreen video, downloads, permissions, print, shortcuts, QR, voice, autofill status, default-browser role |

Tabs outlive the Flutter widget showing them, so switching tabs or locking
the app keeps pages as they were. The Dart side (`lib/`) is the UI, the tab
list and the encrypted data (`lib/data/`), on the same account, lock,
settings and look as every Zero-Trust app.

Requires Android 10 (API 29). Private tabs need Android System WebView with
multi-profile support (version 123 or newer); on older WebView versions they
still keep no history and no cache, but share cookies with normal tabs.

## User scripts (B41)

Scripts run in the page itself, like Violentmonkey's "page" mode: the
engine adds them as document-start scripts (`UserScripts.kt`, runtime in
`assets/userscripts/runtime.js`) and each script's code is checked against
its `@match` / `@include` / `@exclude` / `@exclude-match` rules on every
page and frame. `@run-at` document-start, document-body, document-end and
document-idle (the default) are honoured, and `@noframes`; `@require` and
`@resource` files are fetched once at install and synced with the script.

Supported (both `GM_x` and `GM.x`): `GM_info`, `GM_log`, `unsafeWindow`,
`GM_addStyle`, `GM_addElement`, `GM_getValue` / `setValue` / `deleteValue`
/ `listValues` (and the `…Values` forms), `GM_addValueChangeListener`
(changes on the same page), `GM_getResourceText`, `GM_getResourceURL`,
`GM_xmlhttpRequest` (cross-site, only to `@connect` sites when the script
names any; blocked tracker hosts stay blocked; no cookies from private
tabs; no streaming or progress events), `GM_openInTab`, `GM_setClipboard`,
`GM_notification` (shown as a message in the app),
`GM_registerMenuCommand` / `GM_unregisterMenuCommand` (menu → Script
commands).

Not supported: `GM_download`, `GM_cookie`, `GM_webRequest`, `GM_getTab` /
`GM_saveTab` / `GM_getTabs`, `GM_audio`, `window.onurlchange`,
`@run-at context-menu`, `@sandbox` and `@inject-into content` (everything
runs in the page). The install screen lists any of these a script asks for.

## Texts and languages

Every text the app shows is in `tool/l10n_strings.py`, in English and
Hebrew. After changing it:

```
python3 tool/l10n_strings.py && flutter gen-l10n
```

`test/l10n_test.dart` fails when a text has no Hebrew translation.

## Updating the blocklists

The app ships with `assets/blocklist/blocklist.txt`. Every Monday the
"Blocklist" workflow (`.github/workflows/blocklist.yml`) builds a fresh one,
signs it with Ed25519 and uploads `blocklist.txt.gz` and its `.sig` to the
rolling `blocklist` release. The app checks once a week, verifies the
signature against the public key in `lib/browser/blocklist_updater.dart`,
and only then uses it. The workflow needs the `BLOCKLIST_SIGNING_KEY` secret
(the private key, PEM).

To refresh the bundled list by hand:

```bash
git clone --depth 1 https://github.com/easylist/easylist.git /tmp/easylist
python3 -I tool/update_blocklist.py /tmp/easylist
```

## Builds

Every push to `main` builds a signed APK and publishes it as a GitHub
Release (`.github/workflows/android-apk.yml`). The repository needs the
`ANDROID_KEYSTORE_BASE64` and `ANDROID_KEYSTORE_PASSWORD` secrets, the same
keystore as the other Zero-Trust apps.

## Credits and licences

- Blocklists: [EasyList, EasyPrivacy and the EasyList Cookie List](https://easylist.to)
  by The EasyList authors, used under [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/)
  (see `assets/blocklist/LICENSE`).
- Reader view: [Mozilla Readability](https://github.com/mozilla/readability)
  0.6.0, Apache License 2.0 (see `assets/reader/LICENSE`).
- QR scanner: [ZXing Android Embedded](https://github.com/journeyapps/zxing-android-embedded)
  and ZXing, Apache License 2.0.
- QR codes: [qr_flutter](https://pub.dev/packages/qr_flutter), BSD-3-Clause.
- Web engine: Android System WebView, part of the Android platform.

## License

Copyright (C) 2026 Edo Sagron (https://zerotrust.bz)

Zero-Trust is open source under the [GNU Affero General Public License v3.0](LICENSE)
(AGPL-3.0-only), the same licence Signal uses.

- You may use, study, change and share the code, including in your own projects.
- If you share a changed version, or run it for other people over a network, you must
  publish your full source code under the same licence.
- This program comes with no warranty; see the licence for details.

Third-party libraries keep their own licences; the app lists them under
Settings > Open-source licences.

The blocklist in `assets/blocklist/domains.txt` is not covered by the AGPL: it is derived from
EasyList and EasyPrivacy and stays under CC BY-SA 3.0 (see `assets/blocklist/LICENSE`).

### Name and logo

The AGPL covers the code, not the brand. "Zero-Trust", "ZT", the app names and icons are
reserved. If you publish a fork, give it a different name and icon so nobody mistakes it
for an official Zero-Trust app.

### Servers

The official apps use the Zero-Trust servers. A fork must use its own backend (for
example its own Supabase project) and must not connect to the official servers.

### Contributing

Pull requests are welcome. By sending one you agree that your contribution is licensed
under the AGPL-3.0 and that the copyright holder may also license it under other terms,
including commercially. This keeps the project able to offer paid plans and other licences.
