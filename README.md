# Zero-Trust Browser

A private web browser for Android and Windows that blocks trackers and ads,
with bookmarks, history and open tabs synced end-to-end encrypted. On the
phone it is called **ZT Browser**; in stores and on release pages,
**Zero-Trust Browser**. Same account, settings and look as the other
Zero-Trust apps, built on
[Zero-Trust-Core](https://github.com/EdoSag/Zero-Trust-Core). Part of the
[Zero-Trust suite](https://zerotrust.bz).

## What it does

- **Trackers and ads blocked** on every site: about 50,000 known hosts from
  EasyList and EasyPrivacy, checked for every request the page makes.
  **Cookie banners and empty ad boxes hidden** (EasyList Cookie List and
  EasyList element hiding). Protection can be turned off per site from the
  shield in the address bar. The list updates weekly without an app update,
  signed (see below).
- **Shield panel** (tap the shield in the address bar): what was blocked on
  this page, address by address; allow one address, or turn blocking off
  for the site with one tap when a page doesn't work.
- **Phishing and malware warnings**: a known dangerous site shows a full
  warning page first. The list (hashed site names, updated daily) is
  downloaded whole and checked on the phone, so the pages you open are never
  sent anywhere. Files from such sites get a warning in "Save this file?".
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
- **Fill code** from ZT Authenticator: when a page asks for a one-time
  sign-in code, a bar offers "Fill code" (also in the page menu). ZT
  Authenticator opens for that site, and the code goes straight into the
  page. Only shows when ZT Authenticator is on the phone. See
  [Fill code](#fill-code-zt-authenticator).
- **Translate pages** on the phone, with Firefox's translation engine: the
  page's text never leaves the phone. A language is downloaded the first
  time you pick it, from a signed list.
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
- **Downloads page**: search, filter by kind (images, videos, documents...),
  grouped by day, the space downloads take, select several to delete or
  take off the list, rename, try again, copy the link, and clear the list
  while keeping the files. The list itself is stored encrypted on the phone
  (Android Keystore) and never synced.
- **Download rules**: Wi-Fi only, how many downloads run at once, a folder
  of your choice (an SD card too) instead of Downloads, and deleting
  finished downloads after 7, 30 or 90 days.
- **Download vault**: keep files encrypted inside ZT Browser (move a
  download in from its menu, or add files from the phone), open them with
  the phone's lock, and move them back to Downloads. The vault is on this
  phone only: never synced and left out of Android backups.
- **Send a download** (or a file from the vault) to ZT Notes, as a new
  note, or to another of your devices: it travels as an end-to-end
  encrypted attachment (up to 20 MB) and shows up on that device's
  Downloads page under "Sent from your devices", ready to save.
- **Home screen widgets**: a search bar (search, voice, private tab, QR),
  a grid of your quick links (the start page's pinned sites, or the first
  bookmarks), and a 1x1 Fire button that deletes cookies, site data and
  private downloads at once, then closes every tab and deletes the last
  hour of history once ZT Browser is unlocked. The quick links are kept
  encrypted on the phone for the widget and cleared on sign-out.
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
- Can be the default browser; "Share to" and "Search in ZT Browser" for
  selected text.

## Privacy

Like every Zero-Trust app, it is zero-knowledge: your data is encrypted on
your device, with keys made from your password, before anything is sent.
The server stores only ciphertext and your password itself is never
sent, so neither we nor anyone who breaks into the server can read your
data. The recovery key shown at sign-up is the only way back in if you
forget the password. How the keys work:
[Zero-Trust-Core](https://github.com/EdoSag/Zero-Trust-Core#key-hierarchy) and
[zerotrust.bz/security](https://zerotrust.bz/security/).

- Bookmarks, history, settings, open tabs, user scripts and the privacy
  report are encrypted in the account. The server only sees sealed rows
  with random ids.
- Blocklists and the phishing and malware list are downloaded whole and
  checked on the phone, so the pages you open are never sent anywhere.
- Private tabs are never saved to history or synced.
- The download list, the download vault and what user scripts store stay on
  the phone, encrypted.
- Pages are translated on the phone; the page's text never leaves it.
- ZT Browser never stores passwords.

## One account, one core

One Zero-Trust account opens every app in the suite. Sign-in, unlock
(fingerprint or face, auto-lock), the recovery key, settings, the look,
sync and languages come from
[Zero-Trust-Core](https://github.com/EdoSag/Zero-Trust-Core), so they work
the same in every app. Accounts made before the core still sign in and
see their data.

## Install

Android: get the latest signed APK from this repository's
[Releases](https://github.com/EdoSag/Zero-Trust-Browser/releases/latest),
or from [zerotrust.bz/install](https://zerotrust.bz/install/#browser),
which also shows each file's SHA-256, the signing fingerprint and an
Obtainium link. GitHub Releases are the main way the apps are published.

Builds from GitHub check for a newer release themselves (Settings > About,
one anonymous request a day, can be turned off). Every Zero-Trust app is signed
with the same key, and Android only installs an update signed with it.

Windows 10 and 11: each release also has
`zero-trust-browser-windows-<version>-build<number>.zip`. Unzip it into its
own folder and start `zerotrust_browser.exe`. The app is not code-signed yet,
so Windows may warn about an unknown publisher the first time.

## Languages

English and Hebrew, with right-to-left layout. Choose under
Settings > Appearance > Language. See
[Texts and languages](#texts-and-languages) for how the texts are kept.

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
| `Downloads.kt` | The Downloads page's list (engine downloads and older ones), open, share, delete, remove from the list |
| `DownloadVault.kt` | The download vault: files encrypted in the private-download format under a vault key kept in an `EncryptedStore`; add, open, share, move to Downloads |
| `LinksWidgetProvider.kt`, `FireWidgetProvider.kt` | The quick links grid and 1x1 Fire home screen widgets (W13) |
| `EncryptedStore.kt` | Small phone-only files (the download list) encrypted with AES-GCM under an Android Keystore key |
| `MainActivity.kt` | Tab registry and memory (unloading), the `zt_browser/engine` channel, file uploads, fullscreen video, downloads, permissions, print, shortcuts, QR, voice, autofill status, default-browser role |

Tabs outlive the Flutter widget showing them, so switching tabs or locking
the app keeps pages as they were. The Dart side (`lib/`) is the UI, the tab
list and the encrypted data (`lib/data/`), on the same account, lock,
settings and look as every Zero-Trust app.

Requires Android 10 (API 29). Private tabs need Android System WebView with
multi-profile support (version 123 or newer); on older WebView versions they
still keep no history and no cache, but share cookies with normal tabs.

## Windows (desktop)

The same Flutter app runs on Windows 10 and 11, with Microsoft Edge
WebView2 as the page engine (it comes with Windows). The C++ side,
`windows/runner/browser_engine.cpp`, answers the same `zt_browser/engine`
channel as the Android code: each tab is a WebView2 window that Dart places
over its `TabView` (`setTabBounds`) and hides while a sheet, menu or other
screen is on top.

What the Windows build has today: tabs and private (InPrivate) tabs,
tracker blocking from the same blocklist (bundled, or a newer downloaded
one), HTTPS-Only, the phishing and malware warning (B-1), history,
bookmarks and sync through the shared account, pop-ups opening as tabs,
favicons, and clearing browsing data (Fire). Not yet on Windows: reader
view, translation, find in page, user scripts, browser identity, the
download manager (WebView2 saves to the Downloads folder itself) and the
download vault. These answer "not implemented" and the app treats them as
missing.

Pages and cookies of normal tabs are kept in
`%LOCALAPPDATA%\ZT Browser\WebView2`; private tabs keep nothing.

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

## Fill code (ZT Authenticator)

- `PageScripts.CODE_FIELDS` runs in the top frame of each page and tells the
  app (the `ztCode` listener, hidden from the page) whether there is a
  one-time code field: `autocomplete="one-time-code"`, a field whose name,
  label or placeholder says so (not promo, postal or phone fields), or a
  row of 4 to 8 one-character boxes. It checks again when the page changes,
  so sign-in forms that show the field later count too.
- "Fill code" opens ZT Authenticator with `startActivityForResult` (it only
  answers a caller signed with the suite key): action
  `bz.zerotrust.action.PICK_TEXT`, category
  `bz.zerotrust.category.ONE_TIME_CODE`, extras
  `bz.zerotrust.extra.FOR_PACKAGE` (this app) and
  `bz.zerotrust.extra.FOR_DOMAIN` (the tab's host, as the browser sees it,
  never what the page says).
- The browser only opens an app that is signed with its own key, so another
  app claiming the same action never learns which site is open.
- The answer (`bz.zerotrust.extra.TEXT`, 4 to 12 letters or digits) is typed
  into the page only if the tab is still on the same site, and not when
  `bz.zerotrust.extra.VALID_UNTIL` has passed. The code never reaches the
  Dart side, the clipboard or any log.

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

### Phishing and malware list (B-1)

Every day the "Safety list" workflow (`.github/workflows/safety-list.yml`)
runs `tool/update_safety_list.py` on Phishing.Database (MIT) and URLhaus
(CC0), drops whole popular sites that appear only because one of their
pages was bad (Tranco top sites and the Public Suffix List decide), signs
the result with the same key as the blocklist and uploads
`safety-list.bin.gz` and its `.sig` to the rolling `safety-list` release.
The app checks once a day. Run the workflow once by hand after merging so
the first list exists.

## Build from source

Flutter 3.47.9, the version CI pins (3.50 deprecates `material.dart` and
fails analyze).

```bash
# .env (not committed; CI writes its own). Public client values only:
# never a service-role key, because .env is bundled into the APK.
SUPABASE_URL=https://<project>.supabase.co
SUPABASE_ANON_KEY=<publishable key>

flutter pub get
dart run zt_release_checks --app browser   # shared release checks
flutter analyze && flutter test
flutter run                # Android
flutter run -d windows     # Windows
```

Never add `cryptography_flutter`: it breaks the core's key derivation and
sign-in fails.

## Branches and releases

Work happens on `Dev`: pull requests target `Dev`, never `main`. A release
is one `Dev` → `main` pull request.

Every push to `main` builds a signed APK and publishes it as a GitHub
Release (`.github/workflows/android-apk.yml`). The repository needs the
`ANDROID_KEYSTORE_BASE64` and `ANDROID_KEYSTORE_PASSWORD` secrets, the same
keystore as the other Zero-Trust apps.

Every push to `main` also builds the Windows app
(`.github/workflows/windows.yml`, called by the release workflow) and adds
it to the same GitHub Release as
`zero-trust-browser-windows-<version>-build<number>.zip`. Unzip it into its
own folder and start `zerotrust_browser.exe`. The app is not code-signed
yet, so Windows may warn about an unknown publisher the first time.

Pull requests build the Windows app too, start it once to see that it
opens, and keep the zipped app and a screenshot of its first screen on the
run's Summary page.

## Credits and licences

- Blocklists: [EasyList, EasyPrivacy and the EasyList Cookie List](https://easylist.to)
  by The EasyList authors, used under [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/)
  (see `assets/blocklist/LICENSE`).
- Phishing and malware list: [Phishing.Database](https://github.com/mitchellkrogza/Phishing.Database)
  by Mitchell Krog and Nissar Chababy (MIT) and [URLhaus](https://urlhaus.abuse.ch)
  by abuse.ch (CC0), as hashes; [Tranco](https://tranco-list.eu) and the
  [Public Suffix List](https://publicsuffix.org) are used when building it.
- Reader view: [Mozilla Readability](https://github.com/mozilla/readability)
  0.6.0, Apache License 2.0 (see `assets/reader/LICENSE`).
- QR scanner: [ZXing Android Embedded](https://github.com/journeyapps/zxing-android-embedded)
  and ZXing, Apache License 2.0.
- QR codes: [qr_flutter](https://pub.dev/packages/qr_flutter), BSD-3-Clause.
- Web engine: Android System WebView, part of the Android platform; on
  Windows, Microsoft Edge WebView2 (the SDK is BSD-3-Clause and is
  downloaded when building).

## Support and security

- Help centre: [zerotrust.bz/help](https://zerotrust.bz/help/). Questions and
  account deletion: support@zerotrust.bz.
- Security problems: please report them privately to cyber@zerotrust.bz. What
  the encryption does and doesn't protect against is on
  [zerotrust.bz/security](https://zerotrust.bz/security/).
- [Privacy policy](https://zerotrust.bz/privacy/) and
  [terms](https://zerotrust.bz/terms/).

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
