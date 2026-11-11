// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_l10n.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppL10nEn extends AppL10n {
  AppL10nEn([String locale = 'en']) : super(locale);

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get clear => 'Clear';

  @override
  String get open => 'Open';

  @override
  String get share => 'Share';

  @override
  String get edit => 'Edit';

  @override
  String get remove => 'Remove';

  @override
  String get undo => 'Undo';

  @override
  String get allow => 'Allow';

  @override
  String get block => 'Block';

  @override
  String get copied => 'Copied';

  @override
  String get more => 'More';

  @override
  String get close => 'Close';

  @override
  String get reload => 'Reload';

  @override
  String get back => 'Back';

  @override
  String get forward => 'Forward';

  @override
  String get home => 'Home';

  @override
  String get menu => 'Menu';

  @override
  String get settings => 'Settings';

  @override
  String get newTab => 'New tab';

  @override
  String get newPrivateTab => 'New private tab';

  @override
  String get privateTab => 'Private tab';

  @override
  String get bookmarks => 'Bookmarks';

  @override
  String get history => 'History';

  @override
  String get readingList => 'Reading list';

  @override
  String get downloads => 'Downloads';

  @override
  String get tabs => 'Tabs';

  @override
  String get name => 'Name';

  @override
  String get address => 'Address';

  @override
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get privacyReport => 'Privacy report';

  @override
  String downloadStarted(String name) {
    return 'Downloading $name';
  }

  @override
  String get cantDownload => 'This file can\'t be downloaded';

  @override
  String savedToDownloads(String name) {
    return 'Saved $name to Downloads';
  }

  @override
  String get show => 'Show';

  @override
  String couldntSave(String name) {
    return '$name couldn\'t be saved';
  }

  @override
  String get badCertificate =>
      'This site\'s security certificate isn\'t valid, so it was not opened.';

  @override
  String get findNoMatches => 'No matches';

  @override
  String findCount(int active, int count) {
    return '$active of $count';
  }

  @override
  String get openInNewTab => 'Open in new tab';

  @override
  String get openInPrivateTab => 'Open in private tab';

  @override
  String get openImageInNewTab => 'Open image in new tab';

  @override
  String get copyLink => 'Copy link';

  @override
  String get copyImageAddress => 'Copy image address';

  @override
  String get openInAnotherAppTitle => 'Open in another app?';

  @override
  String get externalMail => 'This link writes an email in your mail app.';

  @override
  String get externalTel => 'This link calls a number with your phone app.';

  @override
  String get externalOther =>
      'This page wants to open another app on your phone.';

  @override
  String get stayHere => 'Stay here';

  @override
  String get notSecureTitle => 'Not a secure site';

  @override
  String notSecureBody(String host) {
    return '$host doesn\'t offer a secure (HTTPS) connection. If you continue, others on your network can see and change what you send and receive on this site.';
  }

  @override
  String get continueAnyway => 'Continue anyway';

  @override
  String get goBack => 'Go back';

  @override
  String permissionAsk(String host, String what) {
    return 'Allow $host to use your $what?';
  }

  @override
  String get permWhatCamera => 'camera';

  @override
  String get permWhatMicrophone => 'microphone';

  @override
  String get permWhatLocation => 'location';

  @override
  String listAnd(String first, String last) {
    return '$first and $last';
  }

  @override
  String listComma(String first, String next) {
    return '$first, $next';
  }

  @override
  String get permissionPrivateNote => 'This private tab asks every time.';

  @override
  String get permissionChangeLater =>
      'You can change this later in the site menu (the shield) or in Settings > Site permissions.';

  @override
  String get onlyThisTime => 'Only this time';

  @override
  String get readerCant => 'This page can\'t be shown in reader view';

  @override
  String get readerNeedsJs => 'Reader view needs JavaScript on for this site';

  @override
  String get addedToReadingList => 'Added to reading list';

  @override
  String get addedToReadingListOffline =>
      'Added to reading list, saved to read offline';

  @override
  String get couldntAddReading => 'Couldn\'t add to the reading list';

  @override
  String get savedCopyUnavailable =>
      'The saved copy isn\'t available. Opening the page instead.';

  @override
  String get noHomeShortcuts => 'Your home screen doesn\'t accept shortcuts';

  @override
  String get fireTitle => 'Close all tabs and clear data?';

  @override
  String get fireBody =>
      'Closes every tab, normal and private, and deletes cookies, site data and the cache on this phone. You are signed out of websites. Bookmarks, the reading list and downloads stay.';

  @override
  String get fireAlsoHistory => 'Also delete history and the privacy report';

  @override
  String get rangeLastHour => 'Last hour';

  @override
  String get rangeLast24 => 'Last 24 hours';

  @override
  String get rangeLast7Days => 'Last 7 days';

  @override
  String get rangeAll => 'All history';

  @override
  String get fireDone => 'Tabs closed and browsing data cleared';

  @override
  String get bookmarkAction => 'Bookmark';

  @override
  String get removeBookmark => 'Remove bookmark';

  @override
  String get bookmarked => 'Bookmarked';

  @override
  String get bookmarkRemoved => 'Bookmark removed';

  @override
  String get leaveReader => 'Leave reader view';

  @override
  String get readerView => 'Reader view';

  @override
  String get addToReadingList => 'Add to reading list';

  @override
  String get saveAgainReadingList => 'Save again to reading list';

  @override
  String get findInPage => 'Find in page';

  @override
  String get printOrPdf => 'Print or save as PDF';

  @override
  String get shareAsQr => 'Share as QR code';

  @override
  String get addToHomeScreen => 'Add to home screen';

  @override
  String get desktopSite => 'Desktop site';

  @override
  String get fireMenu => 'Close all tabs and clear data';

  @override
  String get pageStopped => 'This page stopped working.';

  @override
  String get previous => 'Previous';

  @override
  String get next => 'Next';

  @override
  String get siteProtection => 'Site protection';

  @override
  String get addressHint => 'Search or type an address';

  @override
  String get addressHintPrivate => 'Private tab: search or type an address';

  @override
  String get voiceSearch => 'Voice search';

  @override
  String get scanQr => 'Scan QR code';

  @override
  String get privateTooltip =>
      'Private tab: no history, cookies cleared on close';

  @override
  String searchWith(String engine) {
    return 'Search with $engine';
  }

  @override
  String get qrPrompt => 'Point at a QR code';

  @override
  String get voicePrompt => 'Search or say an address';

  @override
  String get pinToStart => 'Pin to start page';

  @override
  String get unpinFromStart => 'Unpin from start page';

  @override
  String get pinnedToStart => 'Pinned to the start page';

  @override
  String get unpinnedFromStart => 'Removed from the start page';

  @override
  String get editThisSearch => 'Edit this search';

  @override
  String get yourPasswords => 'Your passwords';

  @override
  String get passwordsTip =>
      'ZT Browser never stores passwords. Your password manager (Bitwarden, Proton Pass, 1Password...) fills sign-in forms through Android\'s autofill, in private tabs too.';

  @override
  String get chooseInAndroid => 'Choose in Android';

  @override
  String get gotIt => 'Got it';

  @override
  String get privateExplain =>
      'Pages you open here are not saved to your history. Cookies and site data are kept apart from your normal tabs and deleted when you close the last private tab or the app locks. Downloads and bookmarks you add are kept.\n\nPrivate tabs hide your browsing on this phone. Sites, your network and your internet provider can still see your visits.';

  @override
  String get startBlurb =>
      'Trackers and ads are blocked on every site. Your bookmarks and history are end-to-end encrypted in your Zero-Trust account: only your devices can read them.';

  @override
  String get shortcuts => 'Shortcuts';

  @override
  String get mostVisited => 'Most visited';

  @override
  String get addShortcut => 'Add shortcut';

  @override
  String get editShortcut => 'Edit shortcut';

  @override
  String get editShortcuts => 'Edit shortcuts';

  @override
  String get add => 'Add';

  @override
  String get pin => 'Pin';

  @override
  String get unpin => 'Unpin';

  @override
  String get dontShowHere => 'Don\'t show here';

  @override
  String get shortcutInvalid => 'Type a web address, like example.com';

  @override
  String get shortcutsEmpty =>
      'Pin the sites you open most. On any page, open the menu and tap \"Pin to start page\", or add one here.';

  @override
  String get dragToReorder => 'Hold and drag to change the order';

  @override
  String blockedThisWeek(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trackers and ads blocked this week',
      one: '1 tracker or ad blocked this week',
    );
    return '$_temp0';
  }

  @override
  String get defaultBrowser => 'Default browser';

  @override
  String get defaultBrowserOn => 'Links from other apps open in ZT Browser';

  @override
  String get defaultBrowserOff =>
      'Tap to open links from other apps in ZT Browser';

  @override
  String get searchEngine => 'Search engine';

  @override
  String get privacy => 'Privacy';

  @override
  String get blockTrackers => 'Block trackers and ads';

  @override
  String blockTrackersCount(String count) {
    return '$count known tracker and ad hosts, from EasyList and EasyPrivacy';
  }

  @override
  String get blockTrackersNoCount =>
      'Known tracker and ad hosts, from EasyList and EasyPrivacy';

  @override
  String get hideBanners => 'Hide cookie banners and ad boxes';

  @override
  String get hideBannersSub =>
      'Hides \"accept cookies\" pop-ups (without accepting anything) and the empty spaces blocked ads leave. EasyList Cookie List.';

  @override
  String get stripTracking => 'Remove tracking from links';

  @override
  String get stripTrackingSub =>
      'Removes tags like utm_source and fbclid when you open, copy or share a link, and skips Google AMP copies and pages that only report your click before sending you on.';

  @override
  String get fingerprinting => 'Fingerprinting protection';

  @override
  String get fingerprintingSub =>
      'Adds noise to what sites read to recognise your phone (canvas, audio, graphics chip, memory), different on every site and every time you open the app.';

  @override
  String get httpsOnly => 'HTTPS-only';

  @override
  String get httpsOnlySub =>
      'Open sites securely, and ask before loading one that only works without encryption';

  @override
  String get blocklistUpdates => 'Blocklist updates';

  @override
  String get blocklistUpdatesSub =>
      'Downloaded weekly from ZT Browser\'s releases on GitHub and checked against its signature. Tap to check now.';

  @override
  String blocklistUpdatesSubDated(String date) {
    return 'Downloaded weekly from ZT Browser\'s releases on GitHub and checked against its signature. List from $date. Tap to check now.';
  }

  @override
  String get sitePermissions => 'Site permissions';

  @override
  String get sitePermissionsNone =>
      'Sites ask before using your camera, microphone or location';

  @override
  String sitePermissionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sites with a remembered answer',
      one: '1 site with a remembered answer',
    );
    return '$_temp0';
  }

  @override
  String get sitesWithoutProtection => 'Sites without protection';

  @override
  String get sitesWithoutProtectionExplain =>
      'Trackers and ads are not blocked on these sites.';

  @override
  String get protect => 'Protect';

  @override
  String get javascriptOff => 'JavaScript off';

  @override
  String get javascriptOffExplain => 'JavaScript does not run on these sites.';

  @override
  String get turnOn => 'Turn on';

  @override
  String get passwordManager => 'Password manager';

  @override
  String get autofillUnsupported => 'This phone doesn\'t support autofill';

  @override
  String autofillActive(String name) {
    return '$name fills passwords in ZT Browser, in private tabs too. ZT Browser never saves passwords.';
  }

  @override
  String get autofillPick =>
      'Pick a password manager (Bitwarden, Proton Pass, 1Password...) in Android settings to fill sign-in forms. ZT Browser never saves passwords itself.';

  @override
  String get pagesSection => 'Pages';

  @override
  String get textSize => 'Text size';

  @override
  String get darkPages => 'Dark pages';

  @override
  String get darkPagesSub =>
      'When your phone is in dark mode, darken sites that have no dark design of their own';

  @override
  String get tabsAndHistory => 'Tabs and history';

  @override
  String get closeUnusedTabs => 'Close unused tabs';

  @override
  String get keepHistory => 'Keep history';

  @override
  String get clearCookies => 'Clear cookies and site data';

  @override
  String get clearCookiesSub => 'Signs you out of websites on this phone';

  @override
  String get alwaysOn => 'Always on';

  @override
  String get alwaysOnSub =>
      'Third-party cookies blocked. Global Privacy Control sent, telling sites not to sell or share your data. Camera, microphone and location only after you say yes to a site. No usage statistics sent from the web engine.';

  @override
  String get credits => 'Open-source credits';

  @override
  String get creditsSub =>
      'EasyList, EasyPrivacy and the EasyList Cookie List by The EasyList authors (easylist.to), used under CC BY-SA 3.0. Reader view: Mozilla Readability (Apache 2.0). QR scanner: ZXing (Apache 2.0).';

  @override
  String get keepHistoryExplain =>
      'Older pages are deleted from your history on all your devices.';

  @override
  String get closeTabsExplain =>
      'Tabs you haven\'t looked at for this long close by themselves. Private tabs always close when the app locks.';

  @override
  String get checkingBlocklist => 'Checking for a newer blocklist…';

  @override
  String get blocklistUpdated => 'Blocklist updated';

  @override
  String get blocklistUpToDate => 'The blocklist is up to date';

  @override
  String get blocklistFailed => 'Couldn\'t check now. Try again later.';

  @override
  String get clearCookiesTitle => 'Clear cookies and site data?';

  @override
  String get clearCookiesBody =>
      'You will be signed out of websites on this phone. Bookmarks and history stay.';

  @override
  String get cookiesCleared => 'Cookies and site data cleared';

  @override
  String get historyNone => 'Don\'t keep history';

  @override
  String get forever => 'Forever';

  @override
  String get oneWeek => '1 week';

  @override
  String get oneMonth => '1 month';

  @override
  String get threeMonths => '3 months';

  @override
  String get oneYear => '1 year';

  @override
  String nDays(int count) {
    return '$count days';
  }

  @override
  String get never => 'Never';

  @override
  String get afterDay => 'After a day';

  @override
  String get afterWeek => 'After a week';

  @override
  String get afterTwoWeeks => 'After 2 weeks';

  @override
  String get afterMonth => 'After a month';

  @override
  String afterDays(int count) {
    return 'After $count days';
  }

  @override
  String get searchSuggestions => 'Search suggestions';

  @override
  String get searchSuggestionsOff =>
      'Off: nothing you type is sent anywhere until you search.';

  @override
  String searchSuggestionsOn(String engine) {
    return 'What you type in the address bar is sent to $engine as you type. Never addresses, and never in private tabs.';
  }

  @override
  String searchSuggestionsNone(String engine) {
    return '$engine doesn\'t offer suggestions.';
  }

  @override
  String get searchSuggestionsAskTitle => 'Turn on search suggestions?';

  @override
  String searchSuggestionsAskBody(String engine) {
    return 'As you type in the address bar, the letters are sent to $engine so it can suggest searches. That tells it what you type even if you never search for it. Addresses and private tabs are never sent.';
  }

  @override
  String get addSearchEngine => 'Add search engine';

  @override
  String get engineAddress => 'Search address, with %s where the words go';

  @override
  String get engineInvalid => 'Type a name and a web address that contains %s';

  @override
  String removeEngine(String name) {
    return 'Remove $name';
  }

  @override
  String get startPageSection => 'Start page';

  @override
  String get showMostVisited => 'Show most visited sites';

  @override
  String get showMostVisitedSub => 'From your history, on the start page';

  @override
  String get privacyReportSub =>
      'Counts the trackers and ads blocked on each site. Kept like your history: end-to-end encrypted in your account.';

  @override
  String reportWeek(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trackers and ads blocked in the last 7 days',
      one: '1 tracker or ad blocked in the last 7 days',
      zero: 'Nothing blocked in the last 7 days',
    );
    return '$_temp0';
  }

  @override
  String reportMonth(int days, int count) {
    return 'Last $days days: $count';
  }

  @override
  String get reportTopSites => 'Where most was blocked this week';

  @override
  String get reportEmpty =>
      'Nothing counted yet. Browse a little and come back.';

  @override
  String get reportOff =>
      'The privacy report is off. Trackers are still blocked; they just aren\'t counted.';

  @override
  String get reportClear => 'Clear report';

  @override
  String get reportCleared => 'Privacy report cleared';

  @override
  String get reportNote =>
      'Counted on your devices and kept end-to-end encrypted in your account, like your history. Private tabs add to the total without the name of the site.';

  @override
  String get reportNoSites => 'Site names are not kept while history is off.';

  @override
  String reportCountOnSite(int count) {
    return '$count blocked';
  }

  @override
  String get newGroup => 'New group';

  @override
  String get removeFromGroup => 'Remove from group';

  @override
  String get groupName => 'Group name';

  @override
  String get newTabInGroup => 'New tab in this group';

  @override
  String get renameGroup => 'Rename group';

  @override
  String get ungroupTabs => 'Ungroup tabs';

  @override
  String closeNTabs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Close $count tabs',
      one: 'Close 1 tab',
    );
    return '$_temp0';
  }

  @override
  String get searchTabs => 'Search tabs';

  @override
  String get stopSearching => 'Stop searching';

  @override
  String get closeAllPrivateTabs => 'Close all private tabs';

  @override
  String get closeAllTabs => 'Close all tabs';

  @override
  String tabsCount(int count) {
    return 'Tabs ($count)';
  }

  @override
  String privateCount(int count) {
    return 'Private ($count)';
  }

  @override
  String get otherDevices => 'Other devices';

  @override
  String get noOpenTabs => 'No open tabs';

  @override
  String get privateTabsExplain =>
      'Private tabs keep no history, and their cookies are deleted when the last one closes or the app locks.';

  @override
  String get noTabsMatch => 'No tabs match.';

  @override
  String get notInGroup => 'Not in a group';

  @override
  String nTabs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tabs',
      one: '1 tab',
    );
    return '$_temp0';
  }

  @override
  String get groupOptions => 'Group options';

  @override
  String get closeTab => 'Close tab';

  @override
  String get otherDevicesEmpty =>
      'Tabs open in ZT Browser on your other devices show here, end-to-end encrypted. Private tabs are never shared.';

  @override
  String get editBookmark => 'Edit bookmark';

  @override
  String get importBookmarks => 'Import bookmarks';

  @override
  String get importExplain =>
      'Pick the bookmarks file you exported from your other browser:\n\n• Chrome or Edge: Bookmarks > Bookmark manager > ⋮ > Export bookmarks (on a computer).\n• Firefox: Bookmarks > Manage bookmarks > Import and Backup > Export bookmarks to HTML.\n\nThe file stays on this phone; the bookmarks are end-to-end encrypted in your account.';

  @override
  String get pickFile => 'Pick file';

  @override
  String get noBookmarksInFile => 'No bookmarks found in that file';

  @override
  String allAlreadySaved(int count) {
    return 'All $count bookmarks were already saved';
  }

  @override
  String importedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Imported $count bookmarks',
      one: 'Imported 1 bookmark',
    );
    return '$_temp0';
  }

  @override
  String get searchBookmarks => 'Search bookmarks';

  @override
  String get noBookmarksYet =>
      'No bookmarks yet. Tap the star in the menu to save a page. Bookmarks are end-to-end encrypted and on all your devices.';

  @override
  String get noBookmarksMatch => 'No bookmarks match.';

  @override
  String daysAgo(int count) {
    return '$count days ago';
  }

  @override
  String get clearHistory => 'Clear history';

  @override
  String get historyCleared => 'History cleared on all your devices';

  @override
  String get searchHistory => 'Search history';

  @override
  String get historyOff =>
      'History is off. Turn it on in Settings, under Keep history.';

  @override
  String get historyEmpty =>
      'Pages you visit show here, end-to-end encrypted. Private tabs are never saved.';

  @override
  String get nothingMatches => 'Nothing matches.';

  @override
  String sizeBytes(int count) {
    return '$count bytes';
  }

  @override
  String get fileFallbackName => 'File';

  @override
  String get noAppOpens => 'No app on this phone opens this kind of file';

  @override
  String get cancelDownloadTitle => 'Cancel download?';

  @override
  String get deleteFileTitle => 'Delete file?';

  @override
  String stopsDownloading(String name) {
    return '$name stops downloading.';
  }

  @override
  String deletedFromPhone(String name) {
    return '$name is deleted from this phone.';
  }

  @override
  String get keep => 'Keep';

  @override
  String get cancelDownload => 'Cancel download';

  @override
  String get downloadsEmpty =>
      'Files you download show here. They are saved in your phone\'s Downloads folder.';

  @override
  String progressOf(String done, String total) {
    return '$done of $total';
  }

  @override
  String get downloadingEllipsis => 'Downloading…';

  @override
  String get waitingConnection => 'Waiting for a connection';

  @override
  String get couldntDownload => 'Couldn\'t download';

  @override
  String get cantShare => 'This file can\'t be shared';

  @override
  String get readingListError => 'The reading list couldn\'t load.';

  @override
  String get readingListEmpty =>
      'Save pages from the menu with \"Add to reading list\". Articles are kept to read offline, end-to-end encrypted in your account.';

  @override
  String get savedOffline => 'Saved offline';

  @override
  String get openSavedCopy => 'Open saved copy';

  @override
  String get markUnread => 'Mark unread';

  @override
  String get markRead => 'Mark read';

  @override
  String get savedCopy => 'Saved copy';

  @override
  String get permCamera => 'Camera';

  @override
  String get permMicrophone => 'Microphone';

  @override
  String get permLocation => 'Location';

  @override
  String permOnHost(String kind, String host) {
    return '$kind on $host';
  }

  @override
  String get askNextTime => 'Ask next time';

  @override
  String get sitePermsEmpty =>
      'When a site asks for your camera, microphone or location, ZT Browser asks you first. Answers you choose to remember show here.';

  @override
  String permAllowedChip(String kind) {
    return '$kind: allowed';
  }

  @override
  String permBlockedChip(String kind) {
    return '$kind: blocked';
  }

  @override
  String get forget => 'Forget';

  @override
  String get allowed => 'Allowed';

  @override
  String get blocked => 'Blocked';

  @override
  String get connectionSecure => 'Connection is secure';

  @override
  String get connectionNotSecure => 'Connection is not secure';

  @override
  String get connectionSecureSub =>
      'What you send and see on this site is encrypted on the way.';

  @override
  String get connectionNotSecureSub =>
      'Others on your network can see and change this page. Don\'t enter passwords or card numbers here.';

  @override
  String blockedOnPage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trackers and ads blocked',
      one: '1 tracker or ad blocked',
    );
    return '$_temp0';
  }

  @override
  String get blockedOnPageSub => 'On this page, from EasyList and EasyPrivacy.';

  @override
  String protectionOn(String site) {
    return 'Protection on $site';
  }

  @override
  String get protectionSub =>
      'Turn off only if the site doesn\'t work. It reloads.';

  @override
  String get trackerBlockingOff => 'Tracker blocking is off';

  @override
  String get turnOnInSettings => 'Turn it on in Settings.';

  @override
  String javascriptOn(String site) {
    return 'JavaScript on $site';
  }

  @override
  String get javascriptSub =>
      'Off makes many sites simpler and harder to track you on, but some stop working. It reloads.';

  @override
  String get unlock => 'Unlock';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get play => 'Play';

  @override
  String get pause => 'Pause';

  @override
  String get stop => 'Stop';

  @override
  String get justNow => 'just now';

  @override
  String hoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours ago',
      one: '1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String get sendToDevice => 'Send to your devices';

  @override
  String get sendLinkToDevice => 'Send link to your devices';

  @override
  String get sendToDeviceNone =>
      'No other devices yet. Sign in to ZT Browser with the same account on another phone or tablet, and it shows up here.';

  @override
  String lastActive(String when) {
    return 'Last active $when';
  }

  @override
  String sentToDevice(String name) {
    return 'Sent to $name';
  }

  @override
  String get couldntSend => 'Couldn\'t send. Try again.';

  @override
  String get sentToThisDevice => 'Sent to this device';

  @override
  String sentFrom(String name) {
    return 'From $name';
  }

  @override
  String sentFromSnack(String name, String title) {
    return '$name sent: $title';
  }

  @override
  String get newFolder => 'New folder';

  @override
  String get folderName => 'Folder name';

  @override
  String get renameFolder => 'Rename folder';

  @override
  String get deleteFolder => 'Delete folder';

  @override
  String deleteFolderKeeps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Its $count bookmarks move to the top level',
      one: 'Its bookmark moves to the top level',
    );
    return '$_temp0';
  }

  @override
  String get topLevel => 'Top level (no folder)';

  @override
  String get folderEmpty => 'This folder is empty.';

  @override
  String nBookmarks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bookmarks',
      one: '1 bookmark',
      zero: 'No bookmarks',
    );
    return '$_temp0';
  }

  @override
  String get folderOptions => 'Folder options';

  @override
  String get moveToFolder => 'Move to folder';

  @override
  String get autoClearCookies => 'Clear cookies when tabs close';

  @override
  String get autoClearCookiesSub =>
      'When the last tab of a site closes, its cookies and site data are deleted, so it can\'t recognise you next time. Sites you keep signed in are skipped.';

  @override
  String get keptSignedIn => 'Kept signed in';

  @override
  String get keptSignedInExplain =>
      'These sites keep their cookies when their tabs close.';

  @override
  String keepSignedInOn(String site) {
    return 'Keep me signed in to $site';
  }

  @override
  String get keepSignedInSub => 'Its cookies stay when its tabs close.';

  @override
  String get saveToZtNotes => 'Save to ZT Notes';

  @override
  String get saveToZtNotesSub => 'The selected text, or the page\'s link';

  @override
  String get readLaterInZtTasks => 'Read later in ZT Tasks';

  @override
  String get callWithZtPhone => 'Call with ZT Phone';

  @override
  String get saveToZtContacts => 'Save to ZT Contacts';

  @override
  String get openWithOtherApp => 'Open with another app';

  @override
  String get copyNumber => 'Copy number';

  @override
  String get appCouldntOpen => 'That app couldn\'t open this.';

  @override
  String get backgroundPlay => 'Keep playing in the background';

  @override
  String get backgroundPlaySub =>
      'Audio and videos keep playing when you leave the app, with play and pause in the notification. A full-screen video shrinks to a small window.';

  @override
  String get mediaChannel => 'Playing media';

  @override
  String get readAloud => 'Read aloud';

  @override
  String get stopReadingAloud => 'Stop reading aloud';

  @override
  String get readingAloud => 'Reading aloud';

  @override
  String readAloudProgress(int part, int count) {
    return 'Reading aloud · $part of $count';
  }

  @override
  String get readAloudSpeed => 'Reading speed';

  @override
  String get readAloudCant => 'This page has no article to read aloud.';

  @override
  String get readAloudNoVoice =>
      'No offline voice for this page\'s language. Add one in Android Settings > Text-to-speech, so the text never leaves your phone.';

  @override
  String get readAloudFailed => 'Reading aloud stopped.';

  @override
  String get privateTabsSection => 'Private tabs';

  @override
  String get privateNoScreenshots => 'Block screenshots';

  @override
  String get privateNoScreenshotsSub =>
      'No screenshots or screen recording while a private tab is on screen.';

  @override
  String get privateHideRecents => 'Hide from recent apps';

  @override
  String get privateHideRecentsSub =>
      'The recent apps screen shows a blank preview while private tabs are open.';

  @override
  String get privateLock => 'Lock private tabs';

  @override
  String get privateLockSub =>
      'After you leave the app, private tabs need your fingerprint, face or screen lock again.';

  @override
  String get privateLockUnavailable =>
      'Set a screen lock on your phone to use this.';

  @override
  String get privateLocked => 'Private tabs are locked.';

  @override
  String get privateUnlockReason => 'Unlock your private tabs';

  @override
  String get blockRules => 'Your block rules';

  @override
  String get blockRulesSub =>
      'Block or allow a site yourself, add filter lists';

  @override
  String blockRulesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rules and lists',
      one: '1 rule or list',
    );
    return '$_temp0';
  }

  @override
  String get blockRulesExplain =>
      'Your rules apply on every site where protection is on, and sync to your other devices, end-to-end encrypted.';

  @override
  String get alwaysBlock => 'Always block';

  @override
  String get neverBlock => 'Never block';

  @override
  String get addHostToBlock => 'Block a site or server';

  @override
  String get addHostToAllow => 'Allow a site or server';

  @override
  String get blockHostExplain =>
      'Requests to it, and to every address under it, are blocked on all sites.';

  @override
  String get allowHostExplain =>
      'Never blocked, even when a list has it. Useful when a list breaks a site you need.';

  @override
  String get notAHost => 'Type an address like ads.example.com';

  @override
  String get extraFilterLists => 'Extra filter lists';

  @override
  String get extraFilterListsExplain =>
      'Hosts files or AdBlock domain lists. Each phone downloads them straight from their address once a week. Tap a list to update it now.';

  @override
  String get addFilterList => 'Add a filter list';

  @override
  String get addFilterListExplain =>
      'The address of a hosts file or AdBlock list (https). The list\'s owner sees that your phone downloaded it, nothing more.';

  @override
  String get filterListNeedsHttps => 'Type an https:// address';

  @override
  String filterListAdded(String count) {
    return 'List added: $count hosts blocked';
  }

  @override
  String filterListUpdated(String count) {
    return 'Updated: $count hosts';
  }

  @override
  String get filterListFailed => 'Couldn\'t download the list';

  @override
  String get filterListNotYet => 'Not downloaded yet';

  @override
  String filterListStatus(String count, String date) {
    return '$count hosts · $date';
  }

  @override
  String get encryptedDns => 'Encrypted DNS';

  @override
  String get encryptedDnsOn => 'Encrypted DNS is on';

  @override
  String get encryptedDnsOff => 'Encrypted DNS is off';

  @override
  String encryptedDnsServer(String server) {
    return 'On, with $server';
  }

  @override
  String get encryptedDnsAutomatic => 'On, with your network\'s DNS';

  @override
  String get encryptedDnsOffSub =>
      'Your network can see which sites you look up.';

  @override
  String get encryptedDnsExplain =>
      'Before opening a site, your phone looks up its address (DNS). Without encryption, your Wi-Fi or mobile network sees every site you visit, even with HTTPS. Android\'s Private DNS encrypts these lookups for every app, ZT Browser included.';

  @override
  String get encryptedDnsSteps =>
      'To turn it on: Android Settings > Network & internet > Private DNS > Private DNS provider hostname, then paste one of these:';

  @override
  String dnsBlocksAds(String name) {
    return '$name, also blocks ads and trackers';
  }

  @override
  String dnsBlocksMalware(String name) {
    return '$name, also blocks malware sites';
  }

  @override
  String get copyHostname => 'Copy hostname';

  @override
  String get openNetworkSettings => 'Open network settings';

  @override
  String get encryptedDnsVpnNote =>
      'A ZT VPN, if it comes, would add per-app encrypted DNS. Until then, Private DNS is the safest choice and needs no extra app.';

  @override
  String get translate => 'Translate';

  @override
  String get translatePage => 'Translate page';

  @override
  String get translatePageSub => 'On your phone; the text never leaves it';

  @override
  String get showOriginal => 'Show original';

  @override
  String get translateFrom => 'From';

  @override
  String get translateTo => 'To';

  @override
  String get translatePickLanguage =>
      'Couldn\'t tell the page\'s language. Pick it here.';

  @override
  String get translateSameLanguage => 'Pick two different languages.';

  @override
  String get translateNoModel =>
      'There\'s no translation between these languages yet.';

  @override
  String get translateOnDevice =>
      'Translated on your phone with Firefox\'s translation engine. The page\'s text is never sent anywhere.';

  @override
  String translateDownloadExplain(String size) {
    return 'The first time, the language files ($size MB) download from ZT Browser\'s releases on GitHub (Mozilla\'s Firefox models). After that, translation works offline. The page\'s text is never sent anywhere.';
  }

  @override
  String translateDownloadAndTranslate(String size) {
    return 'Download $size MB and translate';
  }

  @override
  String get translateDownloadFailed =>
      'Couldn\'t download the language files. Check the connection and try again.';

  @override
  String get translateListFailed =>
      'Couldn\'t get the list of languages. Check the connection.';

  @override
  String get tryAgain => 'Try again';

  @override
  String get translateNeedsJs =>
      'Translation needs JavaScript on for this site (site settings).';

  @override
  String get translateFailed => 'Translation stopped. Showing the original.';

  @override
  String translatingFrom(String language) {
    return 'Translating from $language…';
  }

  @override
  String translatedFrom(String language) {
    return 'Translated from $language';
  }

  @override
  String get translationLanguages => 'Translation languages';

  @override
  String get translationLanguagesSub =>
      'Downloaded for translating on your phone';

  @override
  String get translationExplain =>
      'ZT Browser translates pages on your phone, with Firefox\'s translation engine. Each language is downloaded once, from ZT Browser\'s releases on GitHub. The text of the pages you translate is never sent anywhere.';

  @override
  String get translationNoneYet =>
      'No languages yet. They download the first time you translate a page.';

  @override
  String translationModelSize(String size) {
    return '$size MB on the phone';
  }

  @override
  String get translationCredit =>
      'Translation engine: Bergamot (Firefox Translations). Language models: Mozilla. Both under the Mozilla Public License 2.0.';

  @override
  String qrFor(String url) {
    return 'QR code for $url';
  }

  @override
  String get shareLink => 'Share link';
}
