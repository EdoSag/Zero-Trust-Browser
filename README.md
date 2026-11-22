# Zero-Trust Browser

A private web browser for Android, part of the Zero-Trust apps. On the phone
it is **ZT Browser**.

- **Trackers and ads blocked** on every site: about 50,000 known hosts from
  EasyList and EasyPrivacy, checked for every request the page makes.
  **Cookie banners and empty ad boxes hidden** (EasyList Cookie List and
  EasyList element hiding). Protection can be turned off per site from the
  shield in the address bar. The list updates weekly without an app update,
  signed (see below).
- **Shield panel** (tap the shield in the address bar): what was blocked on
  this page, address by address; allow one address, or turn blocking off
  for the site with one tap when a page doesn't work.
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
- **Swipe gestures**: swipe the address bar or the bottom bar sideways to
  switch tabs, up to see all tabs, and pull down at the top of a page to
  reload it (each can be turned off in Settings, Gestures).
- **Download manager**: its own downloader with pause, resume where it
  stopped and automatic retry when the connection drops, progress and
  Pause/Cancel in a notification, and no size limit for files pages make
  themselves (`blob:` links). "Save this file?" first (name, size, site),
  with warnings for apps, programs, disguised names and plain http.
  Downloads from private tabs stay encrypted in the app (key only in
  memory) and are deleted with the private tabs, unless saved to the phone.
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
- **Browser identity** (user agent switcher): be Firefox, Safari, Edge or
  Chrome on another system, a random browser, or a user agent string you
  write yourself, for all sites, for one site or for one tab. The
  `User-Agent` header, the Client Hints headers and what scripts read from
  `navigator` change together. With the default nothing runs at all. See
  "Browser identity" below.
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
| `DownloadEngine.kt` | The downloader: queue, pause/resume (HTTP Range), retry, writes into a hidden Downloads entry until done, private downloads into `PrivateVault` |
| `DownloadService.kt` | Foreground service and notifications for running and finished downloads |
| `PrivateVault.kt` | Private-tab downloads encrypted in 64 KiB AES-GCM chunks under a key held only in memory |
| `Downloads.kt` | The Downloads page's list (engine downloads and older ones), open, share, delete |
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

## Browser identity (B42)

Settings → Browser identity, and "Browser identity" in the page menu for
one tab or one site. The order is: the tab's own choice, then the site's
(a rule covers the site and its subdomains), then the one for all sites,
then the default. "Desktop site" gives the computer version of whichever
identity is in use.

An identity is one user agent string; everything else is worked out from
it (`lib/browser/identity.dart`) so the parts cannot disagree:

- the `User-Agent` header and `navigator.userAgent`, in every frame and
  worker (`WebSettings.setUserAgentString`);
- the `Sec-CH-UA*` Client Hints headers and `navigator.userAgentData`,
  set in the engine itself (`WebSettingsCompat.setUserAgentMetadata`), with
  the brand list in the order Chrome uses for that version;
- `navigator.platform`, `vendor`, `oscpu`, `appVersion`, `productSub` and
  `maxTouchPoints`, from a document-start script, only for identities that
  need it (`Identity.kt`).

The default is Chrome on Android at the phone's real engine version, in
the short form Chrome itself sends (`Android 10; K`). With the default and
no site rules the engine does nothing per page and injects no script.
`{chrome}` and `{android}` in a string stand for the phone's own versions,
so the list never goes out of date; Firefox and Safari versions follow the
date. "Random" picks one identity per site and keeps it until the app
restarts or you ask for new ones; private tabs get their own picks.

Limits, because the engine is Android System WebView:

- Firefox and Safari have no Client Hints. The engine cannot leave the
  three basic `Sec-CH-UA` headers out, so they name the claimed system
  and no browser, and `navigator.userAgentData` is removed.
- The `navigator` fields set by script are not changed inside web workers.
- A page reached by a form post or by a script's `history.back()` to
  another site keeps the previous site's identity until it is reloaded.
- When a link leads to a site with another identity the page load is
  started again with it, so that request carries no `Referer`.
- A site that looks closely (TLS, fonts, drawing) can still tell the
  engine is Chromium on Android.

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
