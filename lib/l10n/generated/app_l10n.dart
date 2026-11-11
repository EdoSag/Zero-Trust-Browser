import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_l10n_en.dart';
import 'app_l10n_he.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppL10n
/// returned by `AppL10n.of(context)`.
///
/// Applications need to include `AppL10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_l10n.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppL10n.localizationsDelegates,
///   supportedLocales: AppL10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppL10n.supportedLocales
/// property.
abstract class AppL10n {
  AppL10n(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppL10n of(BuildContext context) {
    return Localizations.of<AppL10n>(context, AppL10n)!;
  }

  static const LocalizationsDelegate<AppL10n> delegate = _AppL10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('he'),
  ];

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @allow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get allow;

  /// No description provided for @block.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get block;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @reload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get reload;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @forward.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get forward;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @menu.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get menu;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @newTab.
  ///
  /// In en, this message translates to:
  /// **'New tab'**
  String get newTab;

  /// No description provided for @newPrivateTab.
  ///
  /// In en, this message translates to:
  /// **'New private tab'**
  String get newPrivateTab;

  /// No description provided for @privateTab.
  ///
  /// In en, this message translates to:
  /// **'Private tab'**
  String get privateTab;

  /// No description provided for @bookmarks.
  ///
  /// In en, this message translates to:
  /// **'Bookmarks'**
  String get bookmarks;

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// No description provided for @readingList.
  ///
  /// In en, this message translates to:
  /// **'Reading list'**
  String get readingList;

  /// No description provided for @downloads.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get downloads;

  /// No description provided for @tabs.
  ///
  /// In en, this message translates to:
  /// **'Tabs'**
  String get tabs;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get address;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @privacyReport.
  ///
  /// In en, this message translates to:
  /// **'Privacy report'**
  String get privacyReport;

  /// No description provided for @downloadStarted.
  ///
  /// In en, this message translates to:
  /// **'Downloading {name}'**
  String downloadStarted(String name);

  /// No description provided for @cantDownload.
  ///
  /// In en, this message translates to:
  /// **'This file can\'t be downloaded'**
  String get cantDownload;

  /// No description provided for @savedToDownloads.
  ///
  /// In en, this message translates to:
  /// **'Saved {name} to Downloads'**
  String savedToDownloads(String name);

  /// No description provided for @show.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get show;

  /// No description provided for @couldntSave.
  ///
  /// In en, this message translates to:
  /// **'{name} couldn\'t be saved'**
  String couldntSave(String name);

  /// No description provided for @badCertificate.
  ///
  /// In en, this message translates to:
  /// **'This site\'s security certificate isn\'t valid, so it was not opened.'**
  String get badCertificate;

  /// No description provided for @findNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get findNoMatches;

  /// No description provided for @findCount.
  ///
  /// In en, this message translates to:
  /// **'{active} of {count}'**
  String findCount(int active, int count);

  /// No description provided for @openInNewTab.
  ///
  /// In en, this message translates to:
  /// **'Open in new tab'**
  String get openInNewTab;

  /// No description provided for @openInPrivateTab.
  ///
  /// In en, this message translates to:
  /// **'Open in private tab'**
  String get openInPrivateTab;

  /// No description provided for @openImageInNewTab.
  ///
  /// In en, this message translates to:
  /// **'Open image in new tab'**
  String get openImageInNewTab;

  /// No description provided for @copyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get copyLink;

  /// No description provided for @copyImageAddress.
  ///
  /// In en, this message translates to:
  /// **'Copy image address'**
  String get copyImageAddress;

  /// No description provided for @openInAnotherAppTitle.
  ///
  /// In en, this message translates to:
  /// **'Open in another app?'**
  String get openInAnotherAppTitle;

  /// No description provided for @externalMail.
  ///
  /// In en, this message translates to:
  /// **'This link writes an email in your mail app.'**
  String get externalMail;

  /// No description provided for @externalTel.
  ///
  /// In en, this message translates to:
  /// **'This link calls a number with your phone app.'**
  String get externalTel;

  /// No description provided for @externalOther.
  ///
  /// In en, this message translates to:
  /// **'This page wants to open another app on your phone.'**
  String get externalOther;

  /// No description provided for @stayHere.
  ///
  /// In en, this message translates to:
  /// **'Stay here'**
  String get stayHere;

  /// No description provided for @notSecureTitle.
  ///
  /// In en, this message translates to:
  /// **'Not a secure site'**
  String get notSecureTitle;

  /// No description provided for @notSecureBody.
  ///
  /// In en, this message translates to:
  /// **'{host} doesn\'t offer a secure (HTTPS) connection. If you continue, others on your network can see and change what you send and receive on this site.'**
  String notSecureBody(String host);

  /// No description provided for @continueAnyway.
  ///
  /// In en, this message translates to:
  /// **'Continue anyway'**
  String get continueAnyway;

  /// No description provided for @goBack.
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get goBack;

  /// No description provided for @permissionAsk.
  ///
  /// In en, this message translates to:
  /// **'Allow {host} to use your {what}?'**
  String permissionAsk(String host, String what);

  /// No description provided for @permWhatCamera.
  ///
  /// In en, this message translates to:
  /// **'camera'**
  String get permWhatCamera;

  /// No description provided for @permWhatMicrophone.
  ///
  /// In en, this message translates to:
  /// **'microphone'**
  String get permWhatMicrophone;

  /// No description provided for @permWhatLocation.
  ///
  /// In en, this message translates to:
  /// **'location'**
  String get permWhatLocation;

  /// No description provided for @listAnd.
  ///
  /// In en, this message translates to:
  /// **'{first} and {last}'**
  String listAnd(String first, String last);

  /// No description provided for @listComma.
  ///
  /// In en, this message translates to:
  /// **'{first}, {next}'**
  String listComma(String first, String next);

  /// No description provided for @permissionPrivateNote.
  ///
  /// In en, this message translates to:
  /// **'This private tab asks every time.'**
  String get permissionPrivateNote;

  /// No description provided for @permissionChangeLater.
  ///
  /// In en, this message translates to:
  /// **'You can change this later in the site menu (the shield) or in Settings > Site permissions.'**
  String get permissionChangeLater;

  /// No description provided for @onlyThisTime.
  ///
  /// In en, this message translates to:
  /// **'Only this time'**
  String get onlyThisTime;

  /// No description provided for @readerCant.
  ///
  /// In en, this message translates to:
  /// **'This page can\'t be shown in reader view'**
  String get readerCant;

  /// No description provided for @readerNeedsJs.
  ///
  /// In en, this message translates to:
  /// **'Reader view needs JavaScript on for this site'**
  String get readerNeedsJs;

  /// No description provided for @addedToReadingList.
  ///
  /// In en, this message translates to:
  /// **'Added to reading list'**
  String get addedToReadingList;

  /// No description provided for @addedToReadingListOffline.
  ///
  /// In en, this message translates to:
  /// **'Added to reading list, saved to read offline'**
  String get addedToReadingListOffline;

  /// No description provided for @couldntAddReading.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t add to the reading list'**
  String get couldntAddReading;

  /// No description provided for @savedCopyUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The saved copy isn\'t available. Opening the page instead.'**
  String get savedCopyUnavailable;

  /// No description provided for @noHomeShortcuts.
  ///
  /// In en, this message translates to:
  /// **'Your home screen doesn\'t accept shortcuts'**
  String get noHomeShortcuts;

  /// No description provided for @fireTitle.
  ///
  /// In en, this message translates to:
  /// **'Close all tabs and clear data?'**
  String get fireTitle;

  /// No description provided for @fireBody.
  ///
  /// In en, this message translates to:
  /// **'Closes every tab, normal and private, and deletes cookies, site data and the cache on this phone. You are signed out of websites. Bookmarks, the reading list and downloads stay.'**
  String get fireBody;

  /// No description provided for @fireAlsoHistory.
  ///
  /// In en, this message translates to:
  /// **'Also delete history and the privacy report'**
  String get fireAlsoHistory;

  /// No description provided for @rangeLastHour.
  ///
  /// In en, this message translates to:
  /// **'Last hour'**
  String get rangeLastHour;

  /// No description provided for @rangeLast24.
  ///
  /// In en, this message translates to:
  /// **'Last 24 hours'**
  String get rangeLast24;

  /// No description provided for @rangeLast7Days.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get rangeLast7Days;

  /// No description provided for @rangeAll.
  ///
  /// In en, this message translates to:
  /// **'All history'**
  String get rangeAll;

  /// No description provided for @fireDone.
  ///
  /// In en, this message translates to:
  /// **'Tabs closed and browsing data cleared'**
  String get fireDone;

  /// No description provided for @bookmarkAction.
  ///
  /// In en, this message translates to:
  /// **'Bookmark'**
  String get bookmarkAction;

  /// No description provided for @removeBookmark.
  ///
  /// In en, this message translates to:
  /// **'Remove bookmark'**
  String get removeBookmark;

  /// No description provided for @bookmarked.
  ///
  /// In en, this message translates to:
  /// **'Bookmarked'**
  String get bookmarked;

  /// No description provided for @bookmarkRemoved.
  ///
  /// In en, this message translates to:
  /// **'Bookmark removed'**
  String get bookmarkRemoved;

  /// No description provided for @leaveReader.
  ///
  /// In en, this message translates to:
  /// **'Leave reader view'**
  String get leaveReader;

  /// No description provided for @readerView.
  ///
  /// In en, this message translates to:
  /// **'Reader view'**
  String get readerView;

  /// No description provided for @addToReadingList.
  ///
  /// In en, this message translates to:
  /// **'Add to reading list'**
  String get addToReadingList;

  /// No description provided for @saveAgainReadingList.
  ///
  /// In en, this message translates to:
  /// **'Save again to reading list'**
  String get saveAgainReadingList;

  /// No description provided for @findInPage.
  ///
  /// In en, this message translates to:
  /// **'Find in page'**
  String get findInPage;

  /// No description provided for @printOrPdf.
  ///
  /// In en, this message translates to:
  /// **'Print or save as PDF'**
  String get printOrPdf;

  /// No description provided for @shareAsQr.
  ///
  /// In en, this message translates to:
  /// **'Share as QR code'**
  String get shareAsQr;

  /// No description provided for @addToHomeScreen.
  ///
  /// In en, this message translates to:
  /// **'Add to home screen'**
  String get addToHomeScreen;

  /// No description provided for @desktopSite.
  ///
  /// In en, this message translates to:
  /// **'Desktop site'**
  String get desktopSite;

  /// No description provided for @fireMenu.
  ///
  /// In en, this message translates to:
  /// **'Close all tabs and clear data'**
  String get fireMenu;

  /// No description provided for @pageStopped.
  ///
  /// In en, this message translates to:
  /// **'This page stopped working.'**
  String get pageStopped;

  /// No description provided for @previous.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get previous;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @siteProtection.
  ///
  /// In en, this message translates to:
  /// **'Site protection'**
  String get siteProtection;

  /// No description provided for @addressHint.
  ///
  /// In en, this message translates to:
  /// **'Search or type an address'**
  String get addressHint;

  /// No description provided for @addressHintPrivate.
  ///
  /// In en, this message translates to:
  /// **'Private tab: search or type an address'**
  String get addressHintPrivate;

  /// No description provided for @voiceSearch.
  ///
  /// In en, this message translates to:
  /// **'Voice search'**
  String get voiceSearch;

  /// No description provided for @scanQr.
  ///
  /// In en, this message translates to:
  /// **'Scan QR code'**
  String get scanQr;

  /// No description provided for @privateTooltip.
  ///
  /// In en, this message translates to:
  /// **'Private tab: no history, cookies cleared on close'**
  String get privateTooltip;

  /// No description provided for @searchWith.
  ///
  /// In en, this message translates to:
  /// **'Search with {engine}'**
  String searchWith(String engine);

  /// No description provided for @qrPrompt.
  ///
  /// In en, this message translates to:
  /// **'Point at a QR code'**
  String get qrPrompt;

  /// No description provided for @voicePrompt.
  ///
  /// In en, this message translates to:
  /// **'Search or say an address'**
  String get voicePrompt;

  /// No description provided for @pinToStart.
  ///
  /// In en, this message translates to:
  /// **'Pin to start page'**
  String get pinToStart;

  /// No description provided for @unpinFromStart.
  ///
  /// In en, this message translates to:
  /// **'Unpin from start page'**
  String get unpinFromStart;

  /// No description provided for @pinnedToStart.
  ///
  /// In en, this message translates to:
  /// **'Pinned to the start page'**
  String get pinnedToStart;

  /// No description provided for @unpinnedFromStart.
  ///
  /// In en, this message translates to:
  /// **'Removed from the start page'**
  String get unpinnedFromStart;

  /// No description provided for @editThisSearch.
  ///
  /// In en, this message translates to:
  /// **'Edit this search'**
  String get editThisSearch;

  /// No description provided for @yourPasswords.
  ///
  /// In en, this message translates to:
  /// **'Your passwords'**
  String get yourPasswords;

  /// No description provided for @passwordsTip.
  ///
  /// In en, this message translates to:
  /// **'ZT Browser never stores passwords. Your password manager (Bitwarden, Proton Pass, 1Password...) fills sign-in forms through Android\'s autofill, in private tabs too.'**
  String get passwordsTip;

  /// No description provided for @chooseInAndroid.
  ///
  /// In en, this message translates to:
  /// **'Choose in Android'**
  String get chooseInAndroid;

  /// No description provided for @gotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get gotIt;

  /// No description provided for @privateExplain.
  ///
  /// In en, this message translates to:
  /// **'Pages you open here are not saved to your history. Cookies and site data are kept apart from your normal tabs and deleted when you close the last private tab or the app locks. Downloads and bookmarks you add are kept.\n\nPrivate tabs hide your browsing on this phone. Sites, your network and your internet provider can still see your visits.'**
  String get privateExplain;

  /// No description provided for @startBlurb.
  ///
  /// In en, this message translates to:
  /// **'Trackers and ads are blocked on every site. Your bookmarks and history are end-to-end encrypted in your Zero-Trust account: only your devices can read them.'**
  String get startBlurb;

  /// No description provided for @shortcuts.
  ///
  /// In en, this message translates to:
  /// **'Shortcuts'**
  String get shortcuts;

  /// No description provided for @mostVisited.
  ///
  /// In en, this message translates to:
  /// **'Most visited'**
  String get mostVisited;

  /// No description provided for @addShortcut.
  ///
  /// In en, this message translates to:
  /// **'Add shortcut'**
  String get addShortcut;

  /// No description provided for @editShortcut.
  ///
  /// In en, this message translates to:
  /// **'Edit shortcut'**
  String get editShortcut;

  /// No description provided for @editShortcuts.
  ///
  /// In en, this message translates to:
  /// **'Edit shortcuts'**
  String get editShortcuts;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @pin.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get pin;

  /// No description provided for @unpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get unpin;

  /// No description provided for @dontShowHere.
  ///
  /// In en, this message translates to:
  /// **'Don\'t show here'**
  String get dontShowHere;

  /// No description provided for @shortcutInvalid.
  ///
  /// In en, this message translates to:
  /// **'Type a web address, like example.com'**
  String get shortcutInvalid;

  /// No description provided for @shortcutsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Pin the sites you open most. On any page, open the menu and tap \"Pin to start page\", or add one here.'**
  String get shortcutsEmpty;

  /// No description provided for @dragToReorder.
  ///
  /// In en, this message translates to:
  /// **'Hold and drag to change the order'**
  String get dragToReorder;

  /// No description provided for @blockedThisWeek.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 tracker or ad blocked this week} other{{count} trackers and ads blocked this week}}'**
  String blockedThisWeek(int count);

  /// No description provided for @defaultBrowser.
  ///
  /// In en, this message translates to:
  /// **'Default browser'**
  String get defaultBrowser;

  /// No description provided for @defaultBrowserOn.
  ///
  /// In en, this message translates to:
  /// **'Links from other apps open in ZT Browser'**
  String get defaultBrowserOn;

  /// No description provided for @defaultBrowserOff.
  ///
  /// In en, this message translates to:
  /// **'Tap to open links from other apps in ZT Browser'**
  String get defaultBrowserOff;

  /// No description provided for @searchEngine.
  ///
  /// In en, this message translates to:
  /// **'Search engine'**
  String get searchEngine;

  /// No description provided for @privacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacy;

  /// No description provided for @blockTrackers.
  ///
  /// In en, this message translates to:
  /// **'Block trackers and ads'**
  String get blockTrackers;

  /// No description provided for @blockTrackersCount.
  ///
  /// In en, this message translates to:
  /// **'{count} known tracker and ad hosts, from EasyList and EasyPrivacy'**
  String blockTrackersCount(String count);

  /// No description provided for @blockTrackersNoCount.
  ///
  /// In en, this message translates to:
  /// **'Known tracker and ad hosts, from EasyList and EasyPrivacy'**
  String get blockTrackersNoCount;

  /// No description provided for @hideBanners.
  ///
  /// In en, this message translates to:
  /// **'Hide cookie banners and ad boxes'**
  String get hideBanners;

  /// No description provided for @hideBannersSub.
  ///
  /// In en, this message translates to:
  /// **'Hides \"accept cookies\" pop-ups (without accepting anything) and the empty spaces blocked ads leave. EasyList Cookie List.'**
  String get hideBannersSub;

  /// No description provided for @stripTracking.
  ///
  /// In en, this message translates to:
  /// **'Remove tracking from links'**
  String get stripTracking;

  /// No description provided for @stripTrackingSub.
  ///
  /// In en, this message translates to:
  /// **'Removes tags like utm_source and fbclid when you open, copy or share a link, and skips Google AMP copies and pages that only report your click before sending you on.'**
  String get stripTrackingSub;

  /// No description provided for @fingerprinting.
  ///
  /// In en, this message translates to:
  /// **'Fingerprinting protection'**
  String get fingerprinting;

  /// No description provided for @fingerprintingSub.
  ///
  /// In en, this message translates to:
  /// **'Adds noise to what sites read to recognise your phone (canvas, audio, graphics chip, memory), different on every site and every time you open the app.'**
  String get fingerprintingSub;

  /// No description provided for @httpsOnly.
  ///
  /// In en, this message translates to:
  /// **'HTTPS-only'**
  String get httpsOnly;

  /// No description provided for @httpsOnlySub.
  ///
  /// In en, this message translates to:
  /// **'Open sites securely, and ask before loading one that only works without encryption'**
  String get httpsOnlySub;

  /// No description provided for @blocklistUpdates.
  ///
  /// In en, this message translates to:
  /// **'Blocklist updates'**
  String get blocklistUpdates;

  /// No description provided for @blocklistUpdatesSub.
  ///
  /// In en, this message translates to:
  /// **'Downloaded weekly from ZT Browser\'s releases on GitHub and checked against its signature. Tap to check now.'**
  String get blocklistUpdatesSub;

  /// No description provided for @blocklistUpdatesSubDated.
  ///
  /// In en, this message translates to:
  /// **'Downloaded weekly from ZT Browser\'s releases on GitHub and checked against its signature. List from {date}. Tap to check now.'**
  String blocklistUpdatesSubDated(String date);

  /// No description provided for @sitePermissions.
  ///
  /// In en, this message translates to:
  /// **'Site permissions'**
  String get sitePermissions;

  /// No description provided for @sitePermissionsNone.
  ///
  /// In en, this message translates to:
  /// **'Sites ask before using your camera, microphone or location'**
  String get sitePermissionsNone;

  /// No description provided for @sitePermissionsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 site with a remembered answer} other{{count} sites with a remembered answer}}'**
  String sitePermissionsCount(int count);

  /// No description provided for @sitesWithoutProtection.
  ///
  /// In en, this message translates to:
  /// **'Sites without protection'**
  String get sitesWithoutProtection;

  /// No description provided for @sitesWithoutProtectionExplain.
  ///
  /// In en, this message translates to:
  /// **'Trackers and ads are not blocked on these sites.'**
  String get sitesWithoutProtectionExplain;

  /// No description provided for @protect.
  ///
  /// In en, this message translates to:
  /// **'Protect'**
  String get protect;

  /// No description provided for @javascriptOff.
  ///
  /// In en, this message translates to:
  /// **'JavaScript off'**
  String get javascriptOff;

  /// No description provided for @javascriptOffExplain.
  ///
  /// In en, this message translates to:
  /// **'JavaScript does not run on these sites.'**
  String get javascriptOffExplain;

  /// No description provided for @turnOn.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get turnOn;

  /// No description provided for @passwordManager.
  ///
  /// In en, this message translates to:
  /// **'Password manager'**
  String get passwordManager;

  /// No description provided for @autofillUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This phone doesn\'t support autofill'**
  String get autofillUnsupported;

  /// No description provided for @autofillActive.
  ///
  /// In en, this message translates to:
  /// **'{name} fills passwords in ZT Browser, in private tabs too. ZT Browser never saves passwords.'**
  String autofillActive(String name);

  /// No description provided for @autofillPick.
  ///
  /// In en, this message translates to:
  /// **'Pick a password manager (Bitwarden, Proton Pass, 1Password...) in Android settings to fill sign-in forms. ZT Browser never saves passwords itself.'**
  String get autofillPick;

  /// No description provided for @pagesSection.
  ///
  /// In en, this message translates to:
  /// **'Pages'**
  String get pagesSection;

  /// No description provided for @textSize.
  ///
  /// In en, this message translates to:
  /// **'Text size'**
  String get textSize;

  /// No description provided for @darkPages.
  ///
  /// In en, this message translates to:
  /// **'Dark pages'**
  String get darkPages;

  /// No description provided for @darkPagesSub.
  ///
  /// In en, this message translates to:
  /// **'When your phone is in dark mode, darken sites that have no dark design of their own'**
  String get darkPagesSub;

  /// No description provided for @tabsAndHistory.
  ///
  /// In en, this message translates to:
  /// **'Tabs and history'**
  String get tabsAndHistory;

  /// No description provided for @closeUnusedTabs.
  ///
  /// In en, this message translates to:
  /// **'Close unused tabs'**
  String get closeUnusedTabs;

  /// No description provided for @keepHistory.
  ///
  /// In en, this message translates to:
  /// **'Keep history'**
  String get keepHistory;

  /// No description provided for @clearCookies.
  ///
  /// In en, this message translates to:
  /// **'Clear cookies and site data'**
  String get clearCookies;

  /// No description provided for @clearCookiesSub.
  ///
  /// In en, this message translates to:
  /// **'Signs you out of websites on this phone'**
  String get clearCookiesSub;

  /// No description provided for @alwaysOn.
  ///
  /// In en, this message translates to:
  /// **'Always on'**
  String get alwaysOn;

  /// No description provided for @alwaysOnSub.
  ///
  /// In en, this message translates to:
  /// **'Third-party cookies blocked. Global Privacy Control sent, telling sites not to sell or share your data. Camera, microphone and location only after you say yes to a site. No usage statistics sent from the web engine.'**
  String get alwaysOnSub;

  /// No description provided for @credits.
  ///
  /// In en, this message translates to:
  /// **'Open-source credits'**
  String get credits;

  /// No description provided for @creditsSub.
  ///
  /// In en, this message translates to:
  /// **'EasyList, EasyPrivacy and the EasyList Cookie List by The EasyList authors (easylist.to), used under CC BY-SA 3.0. Reader view: Mozilla Readability (Apache 2.0). QR scanner: ZXing (Apache 2.0).'**
  String get creditsSub;

  /// No description provided for @keepHistoryExplain.
  ///
  /// In en, this message translates to:
  /// **'Older pages are deleted from your history on all your devices.'**
  String get keepHistoryExplain;

  /// No description provided for @closeTabsExplain.
  ///
  /// In en, this message translates to:
  /// **'Tabs you haven\'t looked at for this long close by themselves. Private tabs always close when the app locks.'**
  String get closeTabsExplain;

  /// No description provided for @checkingBlocklist.
  ///
  /// In en, this message translates to:
  /// **'Checking for a newer blocklist…'**
  String get checkingBlocklist;

  /// No description provided for @blocklistUpdated.
  ///
  /// In en, this message translates to:
  /// **'Blocklist updated'**
  String get blocklistUpdated;

  /// No description provided for @blocklistUpToDate.
  ///
  /// In en, this message translates to:
  /// **'The blocklist is up to date'**
  String get blocklistUpToDate;

  /// No description provided for @blocklistFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check now. Try again later.'**
  String get blocklistFailed;

  /// No description provided for @clearCookiesTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear cookies and site data?'**
  String get clearCookiesTitle;

  /// No description provided for @clearCookiesBody.
  ///
  /// In en, this message translates to:
  /// **'You will be signed out of websites on this phone. Bookmarks and history stay.'**
  String get clearCookiesBody;

  /// No description provided for @cookiesCleared.
  ///
  /// In en, this message translates to:
  /// **'Cookies and site data cleared'**
  String get cookiesCleared;

  /// No description provided for @historyNone.
  ///
  /// In en, this message translates to:
  /// **'Don\'t keep history'**
  String get historyNone;

  /// No description provided for @forever.
  ///
  /// In en, this message translates to:
  /// **'Forever'**
  String get forever;

  /// No description provided for @oneWeek.
  ///
  /// In en, this message translates to:
  /// **'1 week'**
  String get oneWeek;

  /// No description provided for @oneMonth.
  ///
  /// In en, this message translates to:
  /// **'1 month'**
  String get oneMonth;

  /// No description provided for @threeMonths.
  ///
  /// In en, this message translates to:
  /// **'3 months'**
  String get threeMonths;

  /// No description provided for @oneYear.
  ///
  /// In en, this message translates to:
  /// **'1 year'**
  String get oneYear;

  /// No description provided for @nDays.
  ///
  /// In en, this message translates to:
  /// **'{count} days'**
  String nDays(int count);

  /// No description provided for @never.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get never;

  /// No description provided for @afterDay.
  ///
  /// In en, this message translates to:
  /// **'After a day'**
  String get afterDay;

  /// No description provided for @afterWeek.
  ///
  /// In en, this message translates to:
  /// **'After a week'**
  String get afterWeek;

  /// No description provided for @afterTwoWeeks.
  ///
  /// In en, this message translates to:
  /// **'After 2 weeks'**
  String get afterTwoWeeks;

  /// No description provided for @afterMonth.
  ///
  /// In en, this message translates to:
  /// **'After a month'**
  String get afterMonth;

  /// No description provided for @afterDays.
  ///
  /// In en, this message translates to:
  /// **'After {count} days'**
  String afterDays(int count);

  /// No description provided for @searchSuggestions.
  ///
  /// In en, this message translates to:
  /// **'Search suggestions'**
  String get searchSuggestions;

  /// No description provided for @searchSuggestionsOff.
  ///
  /// In en, this message translates to:
  /// **'Off: nothing you type is sent anywhere until you search.'**
  String get searchSuggestionsOff;

  /// No description provided for @searchSuggestionsOn.
  ///
  /// In en, this message translates to:
  /// **'What you type in the address bar is sent to {engine} as you type. Never addresses, and never in private tabs.'**
  String searchSuggestionsOn(String engine);

  /// No description provided for @searchSuggestionsNone.
  ///
  /// In en, this message translates to:
  /// **'{engine} doesn\'t offer suggestions.'**
  String searchSuggestionsNone(String engine);

  /// No description provided for @searchSuggestionsAskTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn on search suggestions?'**
  String get searchSuggestionsAskTitle;

  /// No description provided for @searchSuggestionsAskBody.
  ///
  /// In en, this message translates to:
  /// **'As you type in the address bar, the letters are sent to {engine} so it can suggest searches. That tells it what you type even if you never search for it. Addresses and private tabs are never sent.'**
  String searchSuggestionsAskBody(String engine);

  /// No description provided for @addSearchEngine.
  ///
  /// In en, this message translates to:
  /// **'Add search engine'**
  String get addSearchEngine;

  /// No description provided for @engineAddress.
  ///
  /// In en, this message translates to:
  /// **'Search address, with %s where the words go'**
  String get engineAddress;

  /// No description provided for @engineInvalid.
  ///
  /// In en, this message translates to:
  /// **'Type a name and a web address that contains %s'**
  String get engineInvalid;

  /// No description provided for @removeEngine.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}'**
  String removeEngine(String name);

  /// No description provided for @startPageSection.
  ///
  /// In en, this message translates to:
  /// **'Start page'**
  String get startPageSection;

  /// No description provided for @showMostVisited.
  ///
  /// In en, this message translates to:
  /// **'Show most visited sites'**
  String get showMostVisited;

  /// No description provided for @showMostVisitedSub.
  ///
  /// In en, this message translates to:
  /// **'From your history, on the start page'**
  String get showMostVisitedSub;

  /// No description provided for @privacyReportSub.
  ///
  /// In en, this message translates to:
  /// **'Counts the trackers and ads blocked on each site. Kept like your history: end-to-end encrypted in your account.'**
  String get privacyReportSub;

  /// No description provided for @reportWeek.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Nothing blocked in the last 7 days} =1{1 tracker or ad blocked in the last 7 days} other{{count} trackers and ads blocked in the last 7 days}}'**
  String reportWeek(int count);

  /// No description provided for @reportMonth.
  ///
  /// In en, this message translates to:
  /// **'Last {days} days: {count}'**
  String reportMonth(int days, int count);

  /// No description provided for @reportTopSites.
  ///
  /// In en, this message translates to:
  /// **'Where most was blocked this week'**
  String get reportTopSites;

  /// No description provided for @reportEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing counted yet. Browse a little and come back.'**
  String get reportEmpty;

  /// No description provided for @reportOff.
  ///
  /// In en, this message translates to:
  /// **'The privacy report is off. Trackers are still blocked; they just aren\'t counted.'**
  String get reportOff;

  /// No description provided for @reportClear.
  ///
  /// In en, this message translates to:
  /// **'Clear report'**
  String get reportClear;

  /// No description provided for @reportCleared.
  ///
  /// In en, this message translates to:
  /// **'Privacy report cleared'**
  String get reportCleared;

  /// No description provided for @reportNote.
  ///
  /// In en, this message translates to:
  /// **'Counted on your devices and kept end-to-end encrypted in your account, like your history. Private tabs add to the total without the name of the site.'**
  String get reportNote;

  /// No description provided for @reportNoSites.
  ///
  /// In en, this message translates to:
  /// **'Site names are not kept while history is off.'**
  String get reportNoSites;

  /// No description provided for @reportCountOnSite.
  ///
  /// In en, this message translates to:
  /// **'{count} blocked'**
  String reportCountOnSite(int count);

  /// No description provided for @newGroup.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get newGroup;

  /// No description provided for @removeFromGroup.
  ///
  /// In en, this message translates to:
  /// **'Remove from group'**
  String get removeFromGroup;

  /// No description provided for @groupName.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get groupName;

  /// No description provided for @newTabInGroup.
  ///
  /// In en, this message translates to:
  /// **'New tab in this group'**
  String get newTabInGroup;

  /// No description provided for @renameGroup.
  ///
  /// In en, this message translates to:
  /// **'Rename group'**
  String get renameGroup;

  /// No description provided for @ungroupTabs.
  ///
  /// In en, this message translates to:
  /// **'Ungroup tabs'**
  String get ungroupTabs;

  /// No description provided for @closeNTabs.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Close 1 tab} other{Close {count} tabs}}'**
  String closeNTabs(int count);

  /// No description provided for @searchTabs.
  ///
  /// In en, this message translates to:
  /// **'Search tabs'**
  String get searchTabs;

  /// No description provided for @stopSearching.
  ///
  /// In en, this message translates to:
  /// **'Stop searching'**
  String get stopSearching;

  /// No description provided for @closeAllPrivateTabs.
  ///
  /// In en, this message translates to:
  /// **'Close all private tabs'**
  String get closeAllPrivateTabs;

  /// No description provided for @closeAllTabs.
  ///
  /// In en, this message translates to:
  /// **'Close all tabs'**
  String get closeAllTabs;

  /// No description provided for @tabsCount.
  ///
  /// In en, this message translates to:
  /// **'Tabs ({count})'**
  String tabsCount(int count);

  /// No description provided for @privateCount.
  ///
  /// In en, this message translates to:
  /// **'Private ({count})'**
  String privateCount(int count);

  /// No description provided for @otherDevices.
  ///
  /// In en, this message translates to:
  /// **'Other devices'**
  String get otherDevices;

  /// No description provided for @noOpenTabs.
  ///
  /// In en, this message translates to:
  /// **'No open tabs'**
  String get noOpenTabs;

  /// No description provided for @privateTabsExplain.
  ///
  /// In en, this message translates to:
  /// **'Private tabs keep no history, and their cookies are deleted when the last one closes or the app locks.'**
  String get privateTabsExplain;

  /// No description provided for @noTabsMatch.
  ///
  /// In en, this message translates to:
  /// **'No tabs match.'**
  String get noTabsMatch;

  /// No description provided for @notInGroup.
  ///
  /// In en, this message translates to:
  /// **'Not in a group'**
  String get notInGroup;

  /// No description provided for @nTabs.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 tab} other{{count} tabs}}'**
  String nTabs(int count);

  /// No description provided for @groupOptions.
  ///
  /// In en, this message translates to:
  /// **'Group options'**
  String get groupOptions;

  /// No description provided for @closeTab.
  ///
  /// In en, this message translates to:
  /// **'Close tab'**
  String get closeTab;

  /// No description provided for @otherDevicesEmpty.
  ///
  /// In en, this message translates to:
  /// **'Tabs open in ZT Browser on your other devices show here, end-to-end encrypted. Private tabs are never shared.'**
  String get otherDevicesEmpty;

  /// No description provided for @editBookmark.
  ///
  /// In en, this message translates to:
  /// **'Edit bookmark'**
  String get editBookmark;

  /// No description provided for @importBookmarks.
  ///
  /// In en, this message translates to:
  /// **'Import bookmarks'**
  String get importBookmarks;

  /// No description provided for @importExplain.
  ///
  /// In en, this message translates to:
  /// **'Pick the bookmarks file you exported from your other browser:\n\n• Chrome or Edge: Bookmarks > Bookmark manager > ⋮ > Export bookmarks (on a computer).\n• Firefox: Bookmarks > Manage bookmarks > Import and Backup > Export bookmarks to HTML.\n\nThe file stays on this phone; the bookmarks are end-to-end encrypted in your account.'**
  String get importExplain;

  /// No description provided for @pickFile.
  ///
  /// In en, this message translates to:
  /// **'Pick file'**
  String get pickFile;

  /// No description provided for @noBookmarksInFile.
  ///
  /// In en, this message translates to:
  /// **'No bookmarks found in that file'**
  String get noBookmarksInFile;

  /// No description provided for @allAlreadySaved.
  ///
  /// In en, this message translates to:
  /// **'All {count} bookmarks were already saved'**
  String allAlreadySaved(int count);

  /// No description provided for @importedCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Imported 1 bookmark} other{Imported {count} bookmarks}}'**
  String importedCount(int count);

  /// No description provided for @searchBookmarks.
  ///
  /// In en, this message translates to:
  /// **'Search bookmarks'**
  String get searchBookmarks;

  /// No description provided for @noBookmarksYet.
  ///
  /// In en, this message translates to:
  /// **'No bookmarks yet. Tap the star in the menu to save a page. Bookmarks are end-to-end encrypted and on all your devices.'**
  String get noBookmarksYet;

  /// No description provided for @noBookmarksMatch.
  ///
  /// In en, this message translates to:
  /// **'No bookmarks match.'**
  String get noBookmarksMatch;

  /// No description provided for @daysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} days ago'**
  String daysAgo(int count);

  /// No description provided for @clearHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear history'**
  String get clearHistory;

  /// No description provided for @historyCleared.
  ///
  /// In en, this message translates to:
  /// **'History cleared on all your devices'**
  String get historyCleared;

  /// No description provided for @searchHistory.
  ///
  /// In en, this message translates to:
  /// **'Search history'**
  String get searchHistory;

  /// No description provided for @historyOff.
  ///
  /// In en, this message translates to:
  /// **'History is off. Turn it on in Settings, under Keep history.'**
  String get historyOff;

  /// No description provided for @historyEmpty.
  ///
  /// In en, this message translates to:
  /// **'Pages you visit show here, end-to-end encrypted. Private tabs are never saved.'**
  String get historyEmpty;

  /// No description provided for @nothingMatches.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches.'**
  String get nothingMatches;

  /// No description provided for @sizeBytes.
  ///
  /// In en, this message translates to:
  /// **'{count} bytes'**
  String sizeBytes(int count);

  /// No description provided for @fileFallbackName.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get fileFallbackName;

  /// No description provided for @noAppOpens.
  ///
  /// In en, this message translates to:
  /// **'No app on this phone opens this kind of file'**
  String get noAppOpens;

  /// No description provided for @cancelDownloadTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel download?'**
  String get cancelDownloadTitle;

  /// No description provided for @deleteFileTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete file?'**
  String get deleteFileTitle;

  /// No description provided for @stopsDownloading.
  ///
  /// In en, this message translates to:
  /// **'{name} stops downloading.'**
  String stopsDownloading(String name);

  /// No description provided for @deletedFromPhone.
  ///
  /// In en, this message translates to:
  /// **'{name} is deleted from this phone.'**
  String deletedFromPhone(String name);

  /// No description provided for @keep.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get keep;

  /// No description provided for @cancelDownload.
  ///
  /// In en, this message translates to:
  /// **'Cancel download'**
  String get cancelDownload;

  /// No description provided for @downloadsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Files you download show here. They are saved in your phone\'s Downloads folder.'**
  String get downloadsEmpty;

  /// No description provided for @progressOf.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total}'**
  String progressOf(String done, String total);

  /// No description provided for @downloadingEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get downloadingEllipsis;

  /// No description provided for @waitingConnection.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a connection'**
  String get waitingConnection;

  /// No description provided for @couldntDownload.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t download'**
  String get couldntDownload;

  /// No description provided for @cantShare.
  ///
  /// In en, this message translates to:
  /// **'This file can\'t be shared'**
  String get cantShare;

  /// No description provided for @readingListError.
  ///
  /// In en, this message translates to:
  /// **'The reading list couldn\'t load.'**
  String get readingListError;

  /// No description provided for @readingListEmpty.
  ///
  /// In en, this message translates to:
  /// **'Save pages from the menu with \"Add to reading list\". Articles are kept to read offline, end-to-end encrypted in your account.'**
  String get readingListEmpty;

  /// No description provided for @savedOffline.
  ///
  /// In en, this message translates to:
  /// **'Saved offline'**
  String get savedOffline;

  /// No description provided for @openSavedCopy.
  ///
  /// In en, this message translates to:
  /// **'Open saved copy'**
  String get openSavedCopy;

  /// No description provided for @markUnread.
  ///
  /// In en, this message translates to:
  /// **'Mark unread'**
  String get markUnread;

  /// No description provided for @markRead.
  ///
  /// In en, this message translates to:
  /// **'Mark read'**
  String get markRead;

  /// No description provided for @savedCopy.
  ///
  /// In en, this message translates to:
  /// **'Saved copy'**
  String get savedCopy;

  /// No description provided for @permCamera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get permCamera;

  /// No description provided for @permMicrophone.
  ///
  /// In en, this message translates to:
  /// **'Microphone'**
  String get permMicrophone;

  /// No description provided for @permLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get permLocation;

  /// No description provided for @permOnHost.
  ///
  /// In en, this message translates to:
  /// **'{kind} on {host}'**
  String permOnHost(String kind, String host);

  /// No description provided for @askNextTime.
  ///
  /// In en, this message translates to:
  /// **'Ask next time'**
  String get askNextTime;

  /// No description provided for @sitePermsEmpty.
  ///
  /// In en, this message translates to:
  /// **'When a site asks for your camera, microphone or location, ZT Browser asks you first. Answers you choose to remember show here.'**
  String get sitePermsEmpty;

  /// No description provided for @permAllowedChip.
  ///
  /// In en, this message translates to:
  /// **'{kind}: allowed'**
  String permAllowedChip(String kind);

  /// No description provided for @permBlockedChip.
  ///
  /// In en, this message translates to:
  /// **'{kind}: blocked'**
  String permBlockedChip(String kind);

  /// No description provided for @forget.
  ///
  /// In en, this message translates to:
  /// **'Forget'**
  String get forget;

  /// No description provided for @allowed.
  ///
  /// In en, this message translates to:
  /// **'Allowed'**
  String get allowed;

  /// No description provided for @blocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get blocked;

  /// No description provided for @connectionSecure.
  ///
  /// In en, this message translates to:
  /// **'Connection is secure'**
  String get connectionSecure;

  /// No description provided for @connectionNotSecure.
  ///
  /// In en, this message translates to:
  /// **'Connection is not secure'**
  String get connectionNotSecure;

  /// No description provided for @connectionSecureSub.
  ///
  /// In en, this message translates to:
  /// **'What you send and see on this site is encrypted on the way.'**
  String get connectionSecureSub;

  /// No description provided for @connectionNotSecureSub.
  ///
  /// In en, this message translates to:
  /// **'Others on your network can see and change this page. Don\'t enter passwords or card numbers here.'**
  String get connectionNotSecureSub;

  /// No description provided for @blockedOnPage.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 tracker or ad blocked} other{{count} trackers and ads blocked}}'**
  String blockedOnPage(int count);

  /// No description provided for @blockedOnPageSub.
  ///
  /// In en, this message translates to:
  /// **'On this page, from EasyList and EasyPrivacy.'**
  String get blockedOnPageSub;

  /// No description provided for @protectionOn.
  ///
  /// In en, this message translates to:
  /// **'Protection on {site}'**
  String protectionOn(String site);

  /// No description provided for @protectionSub.
  ///
  /// In en, this message translates to:
  /// **'Turn off only if the site doesn\'t work. It reloads.'**
  String get protectionSub;

  /// No description provided for @trackerBlockingOff.
  ///
  /// In en, this message translates to:
  /// **'Tracker blocking is off'**
  String get trackerBlockingOff;

  /// No description provided for @turnOnInSettings.
  ///
  /// In en, this message translates to:
  /// **'Turn it on in Settings.'**
  String get turnOnInSettings;

  /// No description provided for @javascriptOn.
  ///
  /// In en, this message translates to:
  /// **'JavaScript on {site}'**
  String javascriptOn(String site);

  /// No description provided for @javascriptSub.
  ///
  /// In en, this message translates to:
  /// **'Off makes many sites simpler and harder to track you on, but some stop working. It reloads.'**
  String get javascriptSub;

  /// No description provided for @qrFor.
  ///
  /// In en, this message translates to:
  /// **'QR code for {url}'**
  String qrFor(String url);

  /// No description provided for @shareLink.
  ///
  /// In en, this message translates to:
  /// **'Share link'**
  String get shareLink;
}

class _AppL10nDelegate extends LocalizationsDelegate<AppL10n> {
  const _AppL10nDelegate();

  @override
  Future<AppL10n> load(Locale locale) {
    return SynchronousFuture<AppL10n>(lookupAppL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'he'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppL10nDelegate old) => false;
}

AppL10n lookupAppL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppL10nEn();
    case 'he':
      return AppL10nHe();
  }

  throw FlutterError(
    'AppL10n.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
