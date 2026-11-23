#ifndef RUNNER_BROWSER_ENGINE_H_
#define RUNNER_BROWSER_ENGINE_H_

#include <windows.h>
#include <wrl.h>

#include <WebView2.h>
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <functional>
#include <map>
#include <memory>
#include <set>
#include <string>
#include <unordered_set>
#include <vector>

// ZT Browser's web engine on Windows: the same "zt_browser/engine" channel
// the Android app answers (MainActivity.kt), on Microsoft Edge WebView2.
// Each tab is a WebView2 controller, a child window of the app's window that
// Dart places over its TabView (setTabBounds). Methods the Windows engine
// doesn't have yet answer "not implemented", which Dart treats as absent.
class BrowserEngine {
 public:
  BrowserEngine(flutter::BinaryMessenger* messenger, HWND window,
                HWND flutter_view);
  ~BrowserEngine();

  BrowserEngine(const BrowserEngine&) = delete;
  BrowserEngine& operator=(const BrowserEngine&) = delete;

  // The app window moved: WebView2 needs to know for pop-ups and menus.
  void OnWindowMoved();

  // Tells Dart the person is using a page ("pageActivity"), for auto-lock:
  // clicks and keys inside a WebView2 window never reach Flutter.
  void CheckPageActivity();

 private:
  struct Tab {
    std::string id;
    bool is_private = false;
    Microsoft::WRL::ComPtr<ICoreWebView2Controller> controller;
    Microsoft::WRL::ComPtr<ICoreWebView2> webview;
    // A load asked for before the controller was ready.
    std::string pending_url;
    RECT bounds{0, 0, 0, 0};
    bool shown = false;
    bool loading = false;
    int progress = 0;
    int blocked = 0;
    std::string page_host;
    // The address the top-level page is loading (NavigationStarting), to
    // tell it apart from documents in frames.
    std::string main_url;
    // Hosts the user chose to open despite a safety warning.
    std::set<std::string> unsafe_allowed;
    // Hosts let through over plain http once (loadInsecure).
    std::set<std::string> insecure_allowed;
    // Warnings shown in this tab: their secret token to the address.
    std::map<std::string, std::string> warnings;
  };

  using Result = std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>;
  using Args = const flutter::EncodableMap*;

  void HandleMethod(const flutter::MethodCall<flutter::EncodableValue>& call,
                    Result result);

  // Tabs.
  void CreateTab(const std::string& id, bool is_private,
                 const std::string& url);
  void StartController(const std::string& id);
  void SetUpTab(Tab& tab);
  void CloseTab(const std::string& id);
  void Navigate(Tab& tab, const std::string& url);
  void ApplyVisibility();
  Tab* Find(const std::string& id);

  // Events to Dart.
  void SendEvent(const std::string& tab_id, const std::string& type,
                 flutter::EncodableMap data);
  void SendState(Tab& tab);

  // Protection.
  bool ShouldBlock(const std::string& host, const std::string& page_host);
  bool Protects(const std::string& page_host);
  std::string SafetyCheck(const std::string& host);
  void LoadBlocklist();
  void LoadSafetyList();
  std::string BlocklistDate(const std::wstring& path);
  std::wstring DataDir();
  std::wstring AssetPath(const std::wstring& relative);
  std::string WarningPage(const std::string& host, const std::string& kind,
                          const std::string& token);

  // Clears cookies, storage and cache of normal tabs, then calls [done].
  // A marker file makes sure it happens even if the app quits first.
  void ClearBrowsingData(std::function<void()> done = nullptr);
  std::wstring ClearMarker();

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  // The last input time CheckPageActivity saw (GetLastInputInfo).
  DWORD last_input_seen_ = 0;
  HWND window_;
  HWND flutter_view_;
  Microsoft::WRL::ComPtr<ICoreWebView2Environment> env_;
  bool env_failed_ = false;
  std::vector<std::string> waiting_;  // Tabs created before env_ was ready.
  std::map<std::string, std::unique_ptr<Tab>> tabs_;
  std::string current_;
  // Clear browsing data once the next normal tab exists (Fire with no tabs).
  bool pending_clear_ = false;
  // A clear is running: loads wait for it (Navigate).
  bool clearing_ = false;

  // Settings from Dart (setPrivacy).
  bool block_trackers_ = true;
  bool https_only_ = true;
  bool safe_browsing_ = true;
  std::set<std::string> allowed_sites_;

  // The blocklist (assets/blocklist/blocklist.txt or a newer download).
  std::unordered_set<std::string> everywhere_;
  std::unordered_set<std::string> third_party_;
  std::string list_date_;
  bool from_update_ = false;

  // The phishing and malware list (B-1), sorted hashes.
  std::vector<long long> phishing_;
  std::vector<long long> malware_;
  std::string safety_date_;
  std::map<std::string, std::string> safety_labels_;
};

#endif  // RUNNER_BROWSER_ENGINE_H_
