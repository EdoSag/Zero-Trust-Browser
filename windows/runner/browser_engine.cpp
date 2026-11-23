#include "browser_engine.h"

#include <bcrypt.h>
#include <shlobj.h>
#include <shlwapi.h>

#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <filesystem>
#include <cctype>
#include <fstream>
#include <sstream>

using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;
using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

namespace {

constexpr char kSafetyHost[] = "zt-safety.invalid";
constexpr char kSafetyHeader[] = "# ZT Browser safety list, format 1.";

std::wstring Wide(const std::string& s) {
  if (s.empty()) return std::wstring();
  int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                              nullptr, 0);
  std::wstring out(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                      out.data(), n);
  return out;
}

std::string Utf8(const std::wstring& s) {
  if (s.empty()) return std::string();
  int n = WideCharToMultiByte(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                              nullptr, 0, nullptr, nullptr);
  std::string out(n, '\0');
  WideCharToMultiByte(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                      out.data(), n, nullptr, nullptr);
  return out;
}

// A string WebView2 allocated, as UTF-8, freed.
std::string Take(LPWSTR s) {
  if (s == nullptr) return std::string();
  std::string out = Utf8(s);
  CoTaskMemFree(s);
  return out;
}

std::string Lower(std::string s) {
  std::transform(s.begin(), s.end(), s.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return s;
}

bool StartsWith(const std::string& s, const std::string& prefix) {
  return s.size() >= prefix.size() && s.compare(0, prefix.size(), prefix) == 0;
}

// The host of an http(s) address, lower case, without a port or "user@".
std::string HostOf(const std::string& url) {
  size_t start = url.find("://");
  if (start == std::string::npos) return std::string();
  start += 3;
  size_t end = url.find_first_of("/?#", start);
  std::string host = url.substr(start, end == std::string::npos ? std::string::npos : end - start);
  size_t at = host.rfind('@');
  if (at != std::string::npos) host = host.substr(at + 1);
  if (!host.empty() && host[0] == '[') {
    size_t close = host.find(']');
    return Lower(host.substr(0, close == std::string::npos ? host.size() : close + 1));
  }
  size_t colon = host.find(':');
  if (colon != std::string::npos) host = host.substr(0, colon);
  while (!host.empty() && host.back() == '.') host.pop_back();
  return Lower(host);
}

// The site a host belongs to, as Blocker.siteOf on Android.
std::string SiteOf(const std::string& host) {
  std::vector<std::string> labels;
  std::stringstream ss(host);
  std::string part;
  while (std::getline(ss, part, '.')) labels.push_back(part);
  if (labels.size() <= 2) return host;
  const std::string& tld = labels[labels.size() - 1];
  const std::string& second = labels[labels.size() - 2];
  size_t keep = (tld.size() == 2 && second.size() <= 3) ? 3 : 2;
  std::string out;
  for (size_t i = labels.size() - keep; i < labels.size(); ++i) {
    if (!out.empty()) out += '.';
    out += labels[i];
  }
  return out;
}

std::string UrlDecode(const std::string& s) {
  std::string out;
  for (size_t i = 0; i < s.size(); ++i) {
    if (s[i] == '%' && i + 2 < s.size() && std::isxdigit(static_cast<unsigned char>(s[i + 1])) &&
        std::isxdigit(static_cast<unsigned char>(s[i + 2]))) {
      out += static_cast<char>(std::stoi(s.substr(i + 1, 2), nullptr, 16));
      i += 2;
    } else if (s[i] == '+') {
      out += ' ';
    } else {
      out += s[i];
    }
  }
  return out;
}

// An address without its #fragment, as requests carry it.
std::string NoFragment(const std::string& url) {
  size_t hash = url.find('#');
  return hash == std::string::npos ? url : url.substr(0, hash);
}

std::string HtmlEscape(const std::string& s) {
  std::string out;
  for (char c : s) {
    switch (c) {
      case '&': out += "&amp;"; break;
      case '<': out += "&lt;"; break;
      case '>': out += "&gt;"; break;
      case '"': out += "&quot;"; break;
      case '\'': out += "&#39;"; break;
      default: out += c;
    }
  }
  return out;
}

const EncodableValue* Get(const flutter::EncodableMap* args, const char* key) {
  if (args == nullptr) return nullptr;
  auto it = args->find(EncodableValue(key));
  return it == args->end() ? nullptr : &it->second;
}

std::string GetString(const flutter::EncodableMap* args, const char* key) {
  const EncodableValue* v = Get(args, key);
  if (v == nullptr) return std::string();
  if (auto s = std::get_if<std::string>(v)) return *s;
  return std::string();
}

bool GetBool(const flutter::EncodableMap* args, const char* key, bool fallback) {
  const EncodableValue* v = Get(args, key);
  if (v == nullptr) return fallback;
  if (auto b = std::get_if<bool>(v)) return *b;
  return fallback;
}

double GetNumber(const flutter::EncodableMap* args, const char* key) {
  const EncodableValue* v = Get(args, key);
  if (v == nullptr) return 0;
  if (auto i = std::get_if<int32_t>(v)) return *i;
  if (auto l = std::get_if<int64_t>(v)) return static_cast<double>(*l);
  if (auto d = std::get_if<double>(v)) return *d;
  return 0;
}

std::vector<std::string> GetStrings(const flutter::EncodableMap* args, const char* key) {
  std::vector<std::string> out;
  const EncodableValue* v = Get(args, key);
  if (v == nullptr) return out;
  if (auto list = std::get_if<EncodableList>(v)) {
    for (const EncodableValue& e : *list) {
      if (auto s = std::get_if<std::string>(&e)) out.push_back(*s);
    }
  }
  return out;
}

// The first 8 bytes of SHA-256 of [text], as a big-endian signed number
// (tool/update_safety_list.py hash64).
long long Hash64(const std::string& text) {
  static BCRYPT_ALG_HANDLE alg = nullptr;
  if (alg == nullptr &&
      BCryptOpenAlgorithmProvider(&alg, BCRYPT_SHA256_ALGORITHM, nullptr, 0) != 0) {
    alg = nullptr;
    return 0;
  }
  UCHAR digest[32] = {0};
  BCRYPT_HASH_HANDLE hash = nullptr;
  if (BCryptCreateHash(alg, &hash, nullptr, 0, nullptr, 0, 0) != 0) return 0;
  BCryptHashData(hash, reinterpret_cast<PUCHAR>(const_cast<char*>(text.data())),
                 static_cast<ULONG>(text.size()), 0);
  BCryptFinishHash(hash, digest, sizeof(digest), 0);
  BCryptDestroyHash(hash);
  unsigned long long v = 0;
  for (int i = 0; i < 8; ++i) v = (v << 8) | digest[i];
  return static_cast<long long>(v);
}

// 128 random bits as hex: the secret of one safety warning.
std::string NewToken() {
  UCHAR bytes[16] = {0};
  BCryptGenRandom(nullptr, bytes, sizeof(bytes), BCRYPT_USE_SYSTEM_PREFERRED_RNG);
  static const char* hex = "0123456789abcdef";
  std::string out;
  for (UCHAR b : bytes) {
    out += hex[b >> 4];
    out += hex[b & 15];
  }
  return out;
}

// The value of [key] in an address's query, or "".
std::string QueryParam(const std::string& url, const std::string& key) {
  size_t q = url.find('?');
  if (q == std::string::npos) return std::string();
  std::stringstream ss(url.substr(q + 1));
  std::string pair;
  while (std::getline(ss, pair, '&')) {
    size_t eq = pair.find('=');
    if (eq != std::string::npos && pair.substr(0, eq) == key) {
      std::string value = pair.substr(eq + 1);
      size_t hash = value.find('#');
      return UrlDecode(hash == std::string::npos ? value : value.substr(0, hash));
    }
  }
  return std::string();
}

// Auto-lock activity from pages: checked this often.
constexpr UINT_PTR kActivityTimer = 0x5A54;
constexpr UINT kActivityEveryMs = 10000;
BrowserEngine* g_activity_engine = nullptr;

void CALLBACK OnActivityTimer(HWND, UINT, UINT_PTR, DWORD) {
  if (g_activity_engine != nullptr) g_activity_engine->CheckPageActivity();
}

}  // namespace

BrowserEngine::BrowserEngine(flutter::BinaryMessenger* messenger, HWND window,
                             HWND flutter_view)
    : window_(window), flutter_view_(flutter_view) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "zt_browser/engine", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue>& call, Result result) {
        HandleMethod(call, std::move(result));
      });

  LoadBlocklist();
  LoadSafetyList();

  g_activity_engine = this;
  SetTimer(window_, kActivityTimer, kActivityEveryMs, OnActivityTimer);

  std::wstring data = DataDir() + L"\\WebView2";
  CreateDirectoryW(DataDir().c_str(), nullptr);
  // A clear asked for last time that couldn't finish (no normal tab was
  // open, then the app closed): nothing runs yet, so remove it all now.
  if (GetFileAttributesW(ClearMarker().c_str()) != INVALID_FILE_ATTRIBUTES) {
    std::error_code ignored;
    std::filesystem::remove_all(std::filesystem::path(data), ignored);
    DeleteFileW(ClearMarker().c_str());
  }
  HRESULT hr = CreateCoreWebView2EnvironmentWithOptions(
      nullptr, data.c_str(), nullptr,
      Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
          [this](HRESULT result, ICoreWebView2Environment* env) -> HRESULT {
            if (FAILED(result) || env == nullptr) {
              env_failed_ = true;
              return S_OK;
            }
            env_ = env;
            std::vector<std::string> waiting;
            waiting.swap(waiting_);
            for (const std::string& id : waiting) StartController(id);
            return S_OK;
          })
          .Get());
  if (FAILED(hr)) env_failed_ = true;
}

BrowserEngine::~BrowserEngine() {
  KillTimer(window_, kActivityTimer);
  if (g_activity_engine == this) g_activity_engine = nullptr;
  for (auto& entry : tabs_) {
    if (entry.second->controller) entry.second->controller->Close();
  }
  tabs_.clear();
}

void BrowserEngine::CheckPageActivity() {
  // Windows' own last input time: the page runs in WebView2's process, so
  // its clicks and keys can't be seen any other way. A page can't fake it.
  LASTINPUTINFO info{};
  info.cbSize = sizeof(info);
  if (!GetLastInputInfo(&info) || info.dwTime == last_input_seen_) return;
  last_input_seen_ = info.dwTime;
  // Only input while this window is the one in front, with a page showing.
  HWND front = GetForegroundWindow();
  if (front == nullptr || GetAncestor(front, GA_ROOT) != GetAncestor(window_, GA_ROOT)) {
    return;
  }
  const bool page_shown = std::any_of(tabs_.begin(), tabs_.end(), [](const auto& entry) {
    return entry.second->shown && entry.second->controller;
  });
  if (page_shown) channel_->InvokeMethod("pageActivity", nullptr);
}

void BrowserEngine::OnWindowMoved() {
  for (auto& entry : tabs_) {
    if (entry.second->controller) {
      entry.second->controller->NotifyParentWindowPositionChanged();
    }
  }
}

BrowserEngine::Tab* BrowserEngine::Find(const std::string& id) {
  auto it = tabs_.find(id);
  return it == tabs_.end() ? nullptr : it->second.get();
}

void BrowserEngine::HandleMethod(const flutter::MethodCall<EncodableValue>& call,
                                 Result result) {
  const std::string& method = call.method_name();
  Args args = std::get_if<EncodableMap>(call.arguments());
  const std::string tab_id = GetString(args, "tabId");
  Tab* tab = tab_id.empty() ? nullptr : Find(tab_id);

  if (method == "createTab") {
    CreateTab(tab_id, GetBool(args, "private", false), GetString(args, "url"));
    result->Success();
  } else if (method == "closeTab") {
    CloseTab(tab_id);
    result->Success();
  } else if (method == "select") {
    current_ = tab_id;
    result->Success();
  } else if (method == "load" || method == "loadInsecure") {
    if (tab != nullptr) {
      std::string url = GetString(args, "url");
      if (method == "loadInsecure") tab->insecure_allowed.insert(HostOf(url));
      Navigate(*tab, url);
    }
    result->Success();
  } else if (method == "back") {
    if (tab != nullptr && tab->webview) tab->webview->GoBack();
    result->Success();
  } else if (method == "forward") {
    if (tab != nullptr && tab->webview) tab->webview->GoForward();
    result->Success();
  } else if (method == "reload") {
    if (tab != nullptr && tab->webview) tab->webview->Reload();
    result->Success();
  } else if (method == "stop") {
    if (tab != nullptr && tab->webview) tab->webview->Stop();
    result->Success();
  } else if (method == "state") {
    if (tab != nullptr) SendState(*tab);
    result->Success();
  } else if (method == "setTabBounds") {
    if (tab != nullptr) {
      tab->bounds.left = static_cast<LONG>(GetNumber(args, "x"));
      tab->bounds.top = static_cast<LONG>(GetNumber(args, "y"));
      tab->bounds.right = tab->bounds.left + static_cast<LONG>(GetNumber(args, "width"));
      tab->bounds.bottom = tab->bounds.top + static_cast<LONG>(GetNumber(args, "height"));
      tab->shown = GetBool(args, "visible", true);
      ApplyVisibility();
    }
    result->Success();
  } else if (method == "setPrivacy") {
    block_trackers_ = GetBool(args, "blockTrackers", true);
    https_only_ = GetBool(args, "httpsOnly", true);
    safe_browsing_ = GetBool(args, "safeBrowsing", true);
    allowed_sites_.clear();
    for (const std::string& s : GetStrings(args, "allowedSites")) {
      allowed_sites_.insert(Lower(s));
    }
    result->Success();
  } else if (method == "clearBrowsingData") {
    ClearBrowsingData();
    result->Success();
  } else if (method == "deviceName") {
    wchar_t name[256] = {0};
    DWORD size = 256;
    if (!GetComputerNameExW(ComputerNamePhysicalDnsHostname, name, &size)) {
      result->Success(EncodableValue("Windows PC"));
    } else {
      result->Success(EncodableValue(Utf8(name)));
    }
  } else if (method == "isDefaultBrowser") {
    result->Success(EncodableValue(false));
  } else if (method == "downloads") {
    // Phase 1: WebView2 shows its own downloads and saves to Downloads.
    result->Success(EncodableValue(EncodableList()));
  } else if (method == "blocklistSize") {
    result->Success(EncodableValue(static_cast<int64_t>(everywhere_.size() + third_party_.size())));
  } else if (method == "blocklistInfo") {
    result->Success(EncodableValue(EncodableMap{
        {EncodableValue("size"), EncodableValue(static_cast<int64_t>(everywhere_.size() + third_party_.size()))},
        {EncodableValue("date"), EncodableValue(list_date_)},
        {EncodableValue("updated"), EncodableValue(from_update_)},
        {EncodableValue("file"), EncodableValue(Utf8(DataDir() + L"\\blocklist\\blocklist.txt"))},
    }));
  } else if (method == "reloadBlocklist") {
    LoadBlocklist();
    result->Success();
  } else if (method == "safetyInfo") {
    result->Success(EncodableValue(EncodableMap{
        {EncodableValue("size"), EncodableValue(static_cast<int64_t>(phishing_.size() + malware_.size()))},
        {EncodableValue("date"), EncodableValue(safety_date_)},
        {EncodableValue("file"), EncodableValue(Utf8(DataDir() + L"\\safety\\safety-list.bin"))},
    }));
  } else if (method == "reloadSafetyList") {
    LoadSafetyList();
    result->Success();
  } else if (method == "safetyLabels") {
    safety_labels_.clear();
    const EncodableValue* labels = Get(args, "labels");
    if (labels != nullptr) {
      if (auto map = std::get_if<EncodableMap>(labels)) {
        for (const auto& entry : *map) {
          auto k = std::get_if<std::string>(&entry.first);
          auto v = std::get_if<std::string>(&entry.second);
          if (k != nullptr && v != nullptr) safety_labels_[*k] = *v;
        }
      }
    }
    result->Success();
  } else {
    result->NotImplemented();
  }
}

// ---- Tabs -----------------------------------------------------------------

void BrowserEngine::CreateTab(const std::string& id, bool is_private,
                              const std::string& url) {
  if (id.empty() || Find(id) != nullptr) return;
  auto tab = std::make_unique<Tab>();
  tab->id = id;
  tab->is_private = is_private;
  tab->pending_url = url;
  tabs_[id] = std::move(tab);
  if (env_) {
    StartController(id);
  } else if (!env_failed_) {
    waiting_.push_back(id);
  }
}

void BrowserEngine::StartController(const std::string& id) {
  Tab* tab = Find(id);
  if (tab == nullptr || !env_) return;
  auto done = Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
      [this, id](HRESULT result, ICoreWebView2Controller* controller) -> HRESULT {
        Tab* t = Find(id);
        if (FAILED(result) || controller == nullptr) return S_OK;
        if (t == nullptr) {
          // Closed while it was being made.
          controller->Close();
          return S_OK;
        }
        t->controller = controller;
        controller->get_CoreWebView2(&t->webview);
        SetUpTab(*t);
        return S_OK;
      });
  ComPtr<ICoreWebView2Environment10> env10;
  if (tab->is_private && SUCCEEDED(env_.As(&env10))) {
    // Private tabs: InPrivate, nothing kept after they close.
    ComPtr<ICoreWebView2ControllerOptions> options;
    if (SUCCEEDED(env10->CreateCoreWebView2ControllerOptions(&options)) &&
        SUCCEEDED(options->put_IsInPrivateModeEnabled(TRUE)) &&
        SUCCEEDED(env10->CreateCoreWebView2ControllerWithOptions(window_, options.Get(),
                                                                 done.Get()))) {
      return;
    }
  }
  if (tab->is_private) {
    // An old WebView2 Runtime without InPrivate: never open a private tab
    // as a normal one, which would keep its cookies. The tab shows as
    // failed instead (Windows Update brings a newer runtime).
    SendEvent(id, "crashed", EncodableMap());
    return;
  }
  env_->CreateCoreWebView2Controller(window_, done.Get());
}

void BrowserEngine::SetUpTab(Tab& tab) {
  const std::string id = tab.id;
  ICoreWebView2* webview = tab.webview.Get();
  if (webview == nullptr) return;

  // Pages sit above the Flutter view.
  SetWindowPos(flutter_view_, HWND_BOTTOM, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);

  ComPtr<ICoreWebView2Settings> settings;
  if (SUCCEEDED(webview->get_Settings(&settings))) {
    settings->put_AreDevToolsEnabled(FALSE);
    settings->put_IsStatusBarEnabled(TRUE);
    ComPtr<ICoreWebView2Settings4> settings4;
    if (SUCCEEDED(settings.As(&settings4))) {
      // ZT keeps no form or password data in the engine.
      settings4->put_IsGeneralAutofillEnabled(FALSE);
      settings4->put_IsPasswordAutosaveEnabled(FALSE);
    }
  }
  ComPtr<ICoreWebView2_13> webview13;
  if (SUCCEEDED(webview->QueryInterface(IID_PPV_ARGS(&webview13)))) {
    ComPtr<ICoreWebView2Profile> profile;
    ComPtr<ICoreWebView2Profile3> profile3;
    if (SUCCEEDED(webview13->get_Profile(&profile)) && SUCCEEDED(profile.As(&profile3))) {
      profile3->put_PreferredTrackingPreventionLevel(
          COREWEBVIEW2_TRACKING_PREVENTION_LEVEL_STRICT);
    }
  }

  EventRegistrationToken token;

  // Blocking (B4, B30 lists) and the safety warning (B-1).
  webview->AddWebResourceRequestedFilter(L"*", COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
  webview->add_WebResourceRequested(
      Callback<ICoreWebView2WebResourceRequestedEventHandler>(
          [this, id](ICoreWebView2*, ICoreWebView2WebResourceRequestedEventArgs* args) -> HRESULT {
            Tab* t = Find(id);
            if (t == nullptr || !env_) return S_OK;
            ComPtr<ICoreWebView2WebResourceRequest> request;
            if (FAILED(args->get_Request(&request))) return S_OK;
            LPWSTR raw = nullptr;
            request->get_Uri(&raw);
            const std::string url = Take(raw);
            if (!StartsWith(url, "http://") && !StartsWith(url, "https://")) return S_OK;
            const std::string host = HostOf(url);
            COREWEBVIEW2_WEB_RESOURCE_CONTEXT context;
            args->get_ResourceContext(&context);
            // The top-level page is never blocked as a tracker, but checked
            // against the safety list. Documents in frames are filtered
            // like any other request.
            if (context == COREWEBVIEW2_WEB_RESOURCE_CONTEXT_DOCUMENT &&
                NoFragment(url) == NoFragment(t->main_url)) {
              if (t->unsafe_allowed.count(host) != 0) return S_OK;
              const std::string kind = SafetyCheck(host);
              if (kind.empty()) return S_OK;
              const std::string token = NewToken();
              if (t->warnings.size() > 32) t->warnings.clear();
              t->warnings[token] = url;
              const std::string html = WarningPage(host, kind, token);
              ComPtr<IStream> stream;
              stream.Attach(SHCreateMemStream(reinterpret_cast<const BYTE*>(html.data()),
                                              static_cast<UINT>(html.size())));
              ComPtr<ICoreWebView2WebResourceResponse> response;
              env_->CreateWebResourceResponse(
                  stream.Get(), 200, L"OK",
                  L"Content-Type: text/html; charset=utf-8\r\nCache-Control: no-store",
                  &response);
              args->put_Response(response.Get());
              return S_OK;
            }
            if (!ShouldBlock(host, t->page_host)) return S_OK;
            ComPtr<ICoreWebView2WebResourceResponse> response;
            env_->CreateWebResourceResponse(nullptr, 403, L"Blocked", L"", &response);
            args->put_Response(response.Get());
            t->blocked++;
            return S_OK;
          })
          .Get(),
      &token);

  webview->add_NavigationStarting(
      Callback<ICoreWebView2NavigationStartingEventHandler>(
          [this, id](ICoreWebView2* sender, ICoreWebView2NavigationStartingEventArgs* args) -> HRESULT {
            Tab* t = Find(id);
            if (t == nullptr) return S_OK;
            LPWSTR raw = nullptr;
            args->get_Uri(&raw);
            const std::string url = Take(raw);
            const std::string host = HostOf(url);
            // The safety warning's two links (WarningPage). Only a warning
            // this tab showed can be answered: a page that loads these
            // links itself has no token and is ignored.
            if (host == kSafetyHost) {
              args->put_Cancel(TRUE);
              auto warning = t->warnings.find(QueryParam(url, "t"));
              if (warning == t->warnings.end()) return S_OK;
              const std::string target = warning->second;
              t->warnings.erase(warning);
              if (url.find("/proceed?") != std::string::npos) {
                t->unsafe_allowed.insert(HostOf(target));
                sender->Navigate(Wide(target).c_str());
              } else {
                BOOL back = FALSE;
                sender->get_CanGoBack(&back);
                if (back) {
                  sender->GoBack();
                } else {
                  SendEvent(id, "unsafeLeave", EncodableMap());
                }
              }
              return S_OK;
            }
            // HTTPS-Only: plain http goes to https first.
            if (https_only_ && StartsWith(url, "http://") && Protects(host) &&
                t->insecure_allowed.count(host) == 0 && host != "localhost" &&
                host != "127.0.0.1") {
              args->put_Cancel(TRUE);
              sender->Navigate(Wide("https://" + url.substr(7)).c_str());
              return S_OK;
            }
            t->main_url = url;
            t->page_host = host;
            t->blocked = 0;
            t->loading = true;
            t->progress = 10;
            SendState(*t);
            return S_OK;
          })
          .Get(),
      &token);

  webview->add_ContentLoading(
      Callback<ICoreWebView2ContentLoadingEventHandler>(
          [this, id](ICoreWebView2*, ICoreWebView2ContentLoadingEventArgs*) -> HRESULT {
            Tab* t = Find(id);
            if (t == nullptr) return S_OK;
            t->progress = 60;
            SendState(*t);
            return S_OK;
          })
          .Get(),
      &token);

  webview->add_NavigationCompleted(
      Callback<ICoreWebView2NavigationCompletedEventHandler>(
          [this, id](ICoreWebView2* sender, ICoreWebView2NavigationCompletedEventArgs* args) -> HRESULT {
            Tab* t = Find(id);
            if (t == nullptr) return S_OK;
            t->loading = false;
            t->progress = 100;
            BOOL ok = FALSE;
            args->get_IsSuccess(&ok);
            if (ok) {
              LPWSTR raw = nullptr;
              sender->get_Source(&raw);
              const std::string url = Take(raw);
              LPWSTR title = nullptr;
              sender->get_DocumentTitle(&title);
              if (StartsWith(url, "http://") || StartsWith(url, "https://")) {
                SendEvent(id, "visited",
                          EncodableMap{{EncodableValue("url"), EncodableValue(url)},
                                       {EncodableValue("title"), EncodableValue(Take(title))}});
              } else {
                CoTaskMemFree(title);
              }
            }
            SendState(*t);
            return S_OK;
          })
          .Get(),
      &token);

  webview->add_SourceChanged(
      Callback<ICoreWebView2SourceChangedEventHandler>(
          [this, id](ICoreWebView2*, ICoreWebView2SourceChangedEventArgs*) -> HRESULT {
            if (Tab* t = Find(id)) SendState(*t);
            return S_OK;
          })
          .Get(),
      &token);

  webview->add_DocumentTitleChanged(
      Callback<ICoreWebView2DocumentTitleChangedEventHandler>(
          [this, id](ICoreWebView2*, IUnknown*) -> HRESULT {
            if (Tab* t = Find(id)) SendState(*t);
            return S_OK;
          })
          .Get(),
      &token);

  webview->add_HistoryChanged(
      Callback<ICoreWebView2HistoryChangedEventHandler>(
          [this, id](ICoreWebView2*, IUnknown*) -> HRESULT {
            if (Tab* t = Find(id)) SendState(*t);
            return S_OK;
          })
          .Get(),
      &token);

  // Pop-ups and target=_blank links open as ZT tabs.
  webview->add_NewWindowRequested(
      Callback<ICoreWebView2NewWindowRequestedEventHandler>(
          [this, id](ICoreWebView2*, ICoreWebView2NewWindowRequestedEventArgs* args) -> HRESULT {
            Tab* t = Find(id);
            LPWSTR raw = nullptr;
            args->get_Uri(&raw);
            const std::string url = Take(raw);
            args->put_Handled(TRUE);
            if (t != nullptr && !url.empty()) {
              SendEvent(id, "openTab",
                        EncodableMap{{EncodableValue("url"), EncodableValue(url)},
                                     {EncodableValue("private"), EncodableValue(t->is_private)}});
            }
            return S_OK;
          })
          .Get(),
      &token);

  ComPtr<ICoreWebView2_15> webview15;
  if (SUCCEEDED(webview->QueryInterface(IID_PPV_ARGS(&webview15)))) {
    webview15->add_FaviconChanged(
        Callback<ICoreWebView2FaviconChangedEventHandler>(
            [this, id](ICoreWebView2* sender, IUnknown*) -> HRESULT {
              ComPtr<ICoreWebView2_15> wv15;
              if (FAILED(sender->QueryInterface(IID_PPV_ARGS(&wv15)))) return S_OK;
              wv15->GetFavicon(
                  COREWEBVIEW2_FAVICON_IMAGE_FORMAT_PNG,
                  Callback<ICoreWebView2GetFaviconCompletedHandler>(
                      [this, id](HRESULT result, IStream* stream) -> HRESULT {
                        if (FAILED(result) || stream == nullptr || Find(id) == nullptr) return S_OK;
                        std::vector<uint8_t> png;
                        BYTE buffer[4096];
                        ULONG read = 0;
                        while (SUCCEEDED(stream->Read(buffer, sizeof(buffer), &read)) && read > 0) {
                          png.insert(png.end(), buffer, buffer + read);
                          if (png.size() > 512 * 1024) return S_OK;
                        }
                        if (!png.empty()) {
                          SendEvent(id, "favicon",
                                    EncodableMap{{EncodableValue("png"), EncodableValue(png)}});
                        }
                        return S_OK;
                      })
                      .Get());
              return S_OK;
            })
            .Get(),
        &token);
  }

  if (pending_clear_ && !tab.is_private) {
    // Nothing loads before the asked-for clear is done.
    pending_clear_ = false;
    ClearBrowsingData();
  }
  ApplyVisibility();
  if (!tab.pending_url.empty()) {
    const std::string url = tab.pending_url;
    tab.pending_url.clear();
    Navigate(tab, url);
  }
}

void BrowserEngine::Navigate(Tab& tab, const std::string& url) {
  if (url.empty()) return;
  if (!tab.webview || clearing_) {
    tab.pending_url = url;
    return;
  }
  tab.webview->Navigate(Wide(url).c_str());
}

void BrowserEngine::CloseTab(const std::string& id) {
  auto it = tabs_.find(id);
  if (it == tabs_.end()) return;
  if (it->second->controller) it->second->controller->Close();
  tabs_.erase(it);
  waiting_.erase(std::remove(waiting_.begin(), waiting_.end(), id), waiting_.end());
  if (current_ == id) current_.clear();
}

void BrowserEngine::ApplyVisibility() {
  for (auto& entry : tabs_) {
    Tab& t = *entry.second;
    if (!t.controller) continue;
    const bool visible = t.shown && t.bounds.right > t.bounds.left &&
                         t.bounds.bottom > t.bounds.top;
    if (visible) t.controller->put_Bounds(t.bounds);
    t.controller->put_IsVisible(visible ? TRUE : FALSE);
  }
}

// ---- Events ---------------------------------------------------------------

void BrowserEngine::SendEvent(const std::string& tab_id, const std::string& type,
                              EncodableMap data) {
  data[EncodableValue("tabId")] = EncodableValue(tab_id);
  data[EncodableValue("type")] = EncodableValue(type);
  channel_->InvokeMethod("tabEvent", std::make_unique<EncodableValue>(data));
}

void BrowserEngine::SendState(Tab& tab) {
  if (!tab.webview) return;
  LPWSTR raw = nullptr;
  tab.webview->get_Source(&raw);
  const std::string url = Take(raw);
  LPWSTR title = nullptr;
  tab.webview->get_DocumentTitle(&title);
  BOOL back = FALSE;
  BOOL forward = FALSE;
  tab.webview->get_CanGoBack(&back);
  tab.webview->get_CanGoForward(&forward);
  EncodableMap data{
      {EncodableValue("url"), EncodableValue(url)},
      {EncodableValue("title"), EncodableValue(Take(title))},
      {EncodableValue("progress"), EncodableValue(tab.progress)},
      {EncodableValue("loading"), EncodableValue(tab.loading)},
      {EncodableValue("canGoBack"), EncodableValue(back == TRUE)},
      {EncodableValue("canGoForward"), EncodableValue(forward == TRUE)},
      {EncodableValue("secure"), EncodableValue(StartsWith(url, "https://"))},
      {EncodableValue("blocked"), EncodableValue(tab.blocked)},
      {EncodableValue("desktop"), EncodableValue(true)},
      {EncodableValue("javascript"), EncodableValue(true)},
  };
  // about:blank and the like are not addresses to show.
  if (!StartsWith(url, "http://") && !StartsWith(url, "https://")) {
    data.erase(EncodableValue("url"));
  }
  SendEvent(tab.id, "state", std::move(data));
}

// ---- Protection -----------------------------------------------------------

bool BrowserEngine::Protects(const std::string& page_host) {
  if (page_host.empty()) return true;
  return allowed_sites_.count(SiteOf(page_host)) == 0;
}

bool BrowserEngine::ShouldBlock(const std::string& host, const std::string& page_host) {
  if (!block_trackers_ || host.empty()) return false;
  if (!Protects(page_host)) return false;
  const bool same_site = !page_host.empty() && SiteOf(page_host) == SiteOf(host);
  std::string d = host;
  while (true) {
    if (everywhere_.count(d) != 0) return true;
    if (!same_site && third_party_.count(d) != 0) return true;
    size_t dot = d.find('.');
    if (dot == std::string::npos || d.find('.', dot + 1) == std::string::npos) return false;
    d = d.substr(dot + 1);
  }
}

std::string BrowserEngine::SafetyCheck(const std::string& host) {
  if (!safe_browsing_ || host.empty()) return std::string();
  if (phishing_.empty() && malware_.empty()) return std::string();
  std::string h = host;
  if (StartsWith(h, "www.")) h = h.substr(4);
  while (true) {
    const long long key = Hash64(h);
    if (std::binary_search(phishing_.begin(), phishing_.end(), key)) return "phishing";
    if (std::binary_search(malware_.begin(), malware_.end(), key)) return "malware";
    size_t dot = h.find('.');
    if (dot == std::string::npos || h.find('.', dot + 1) == std::string::npos) return std::string();
    h = h.substr(dot + 1);
  }
}

std::wstring BrowserEngine::DataDir() {
  PWSTR local = nullptr;
  std::wstring dir;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &local))) {
    dir = std::wstring(local) + L"\\ZT Browser";
  }
  CoTaskMemFree(local);
  return dir;
}

std::wstring BrowserEngine::AssetPath(const std::wstring& relative) {
  wchar_t exe[MAX_PATH] = {0};
  GetModuleFileNameW(nullptr, exe, MAX_PATH);
  std::wstring dir(exe);
  size_t slash = dir.find_last_of(L"\\/");
  if (slash != std::wstring::npos) dir = dir.substr(0, slash);
  return dir + L"\\data\\flutter_assets\\" + relative;
}

std::string BrowserEngine::BlocklistDate(const std::wstring& path) {
  std::ifstream in(path);
  std::string line;
  for (int i = 0; i < 20 && std::getline(in, line); ++i) {
    if (StartsWith(line, "# list-date: ")) return line.substr(13, 16);
    if (StartsWith(line, "!")) break;
  }
  return std::string();
}

void BrowserEngine::LoadBlocklist() {
  const std::wstring bundled = AssetPath(L"assets\\blocklist\\blocklist.txt");
  const std::wstring update = DataDir() + L"\\blocklist\\blocklist.txt";
  const std::string bundled_date = BlocklistDate(bundled);
  const std::string update_date = BlocklistDate(update);
  const bool use_update = !update_date.empty() && update_date > bundled_date;
  std::ifstream in(use_update ? update : bundled);
  if (!in) return;
  std::unordered_set<std::string> all;
  std::unordered_set<std::string> third;
  all.reserve(80000);
  std::string section;
  std::string date;
  std::string line;
  while (std::getline(in, line)) {
    if (!line.empty() && line.back() == '\r') line.pop_back();
    if (line.empty()) continue;
    if (line[0] == '!') {
      section = line.substr(1);
      continue;
    }
    if (section.empty()) {
      if (StartsWith(line, "# list-date: ")) date = line.substr(13, 16);
    } else if (section == "hosts") {
      size_t space = line.find(' ');
      if (space == std::string::npos) {
        all.insert(line);
      } else {
        third.insert(line.substr(0, space));
      }
    }
  }
  everywhere_.swap(all);
  third_party_.swap(third);
  list_date_ = date;
  from_update_ = use_update;
}

void BrowserEngine::LoadSafetyList() {
  std::ifstream in(DataDir() + L"\\safety\\safety-list.bin", std::ios::binary);
  if (!in) return;
  std::string line;
  std::string date;
  long long p = -1;
  long long m = -1;
  bool first = true;
  while (std::getline(in, line)) {
    if (first) {
      if (line != kSafetyHeader) return;
      first = false;
      continue;
    }
    if (line.empty()) break;
    if (StartsWith(line, "# list-date: ")) date = line.substr(13);
    if (StartsWith(line, "# phishing: ")) p = std::atoll(line.c_str() + 12);
    if (StartsWith(line, "# malware: ")) m = std::atoll(line.c_str() + 11);
  }
  if (p < 0 || m < 0 || p + m > 3000000) return;
  auto read = [&in](long long count, std::vector<long long>& out) -> bool {
    out.resize(static_cast<size_t>(count));
    for (long long i = 0; i < count; ++i) {
      unsigned char b[8];
      if (!in.read(reinterpret_cast<char*>(b), 8)) return false;
      unsigned long long v = 0;
      for (int k = 0; k < 8; ++k) v = (v << 8) | b[k];
      out[static_cast<size_t>(i)] = static_cast<long long>(v);
    }
    return true;
  };
  std::vector<long long> ph;
  std::vector<long long> mw;
  if (!read(p, ph) || !read(m, mw)) return;
  phishing_.swap(ph);
  malware_.swap(mw);
  safety_date_ = date;
}

std::string BrowserEngine::WarningPage(const std::string& host, const std::string& kind,
                                       const std::string& token) {
  auto label = [this](const std::string& key, const std::string& fallback) {
    auto it = safety_labels_.find(key);
    return (it == safety_labels_.end() || it->second.empty()) ? fallback : it->second;
  };
  const bool malware = kind == "malware";
  const std::string title = malware ? label("malwareTitle", "This site may harm your computer")
                                    : label("phishingTitle", "Deceptive site ahead");
  const std::string body =
      malware ? label("malwareBody", "It is known for spreading harmful apps and files.")
              : label("phishingBody", "It may try to trick you into giving away a password, card number or code.");
  const std::string back = std::string("https://") + kSafetyHost + "/back?t=" + token;
  const std::string proceed = std::string("https://") + kSafetyHost + "/proceed?t=" + token;
  const std::string dir = label("dir", "ltr") == "rtl" ? "rtl" : "ltr";
  std::string html;
  html += "<!doctype html><html dir=\"" + dir + "\"><head><meta charset=\"utf-8\">";
  html += "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">";
  html += "<title>" + HtmlEscape(title) + "</title><style>";
  html += "body{margin:0;font-family:sans-serif;background:#7f1d1d;color:#fff;display:flex;min-height:100vh;align-items:center;justify-content:center}";
  html += "main{max-width:34em;padding:32px 24px}h1{font-size:1.5em;margin:16px 0}p{line-height:1.5}";
  html += ".host{direction:ltr;unicode-bidi:embed;font-weight:bold;word-break:break-all}";
  html += "a.b{display:block;text-align:center;background:#fff;color:#7f1d1d;padding:14px;border-radius:24px;text-decoration:none;font-weight:bold;margin:28px 0 20px}";
  html += "details{opacity:.85}summary{cursor:pointer}a.p{color:#fff}";
  html += "</style></head><body><main><div style=\"font-size:48px\">&#9888;</div><h1>" + HtmlEscape(title) + "</h1>";
  html += "<p><span class=\"host\">" + HtmlEscape(host) + "</span></p><p>" + HtmlEscape(body) + "</p>";
  html += "<a class=\"b\" href=\"" + HtmlEscape(back) + "\">" + HtmlEscape(label("back", "Back to safety")) + "</a>";
  html += "<details><summary>" + HtmlEscape(label("details", "Details")) + "</summary>";
  html += "<p>" + HtmlEscape(label("detailsBody", "ZT Browser checked this address on your computer against a public list of dangerous sites. Nothing was sent anywhere.")) + "</p>";
  html += "<p><a class=\"p\" href=\"" + HtmlEscape(proceed) + "\">" + HtmlEscape(label("proceed", "Open the site anyway (not safe)")) + "</a></p>";
  html += "</details></main></body></html>";
  return html;
}

std::wstring BrowserEngine::ClearMarker() {
  return DataDir() + L"\\clear-pending";
}

void BrowserEngine::ClearBrowsingData(std::function<void()> done) {
  // Written first, removed once the clear is done: if the app quits
  // before that, the next start removes the data folder (constructor).
  HANDLE marker = CreateFileW(ClearMarker().c_str(), GENERIC_WRITE, 0, nullptr,
                              CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (marker != INVALID_HANDLE_VALUE) CloseHandle(marker);
  // Any normal tab's profile: they all share the one profile.
  for (auto& entry : tabs_) {
    Tab& t = *entry.second;
    if (t.is_private || !t.webview) continue;
    ComPtr<ICoreWebView2_13> webview13;
    ComPtr<ICoreWebView2Profile> profile;
    ComPtr<ICoreWebView2Profile2> profile2;
    if (SUCCEEDED(t.webview->QueryInterface(IID_PPV_ARGS(&webview13))) &&
        SUCCEEDED(webview13->get_Profile(&profile)) && SUCCEEDED(profile.As(&profile2))) {
      clearing_ = true;
      HRESULT hr = profile2->ClearBrowsingDataAll(
          Callback<ICoreWebView2ClearBrowsingDataCompletedHandler>(
              [this, done](HRESULT result) -> HRESULT {
                if (SUCCEEDED(result)) DeleteFileW(ClearMarker().c_str());
                clearing_ = false;
                // Loads asked for meanwhile go now.
                for (auto& waiting : tabs_) {
                  Tab& w = *waiting.second;
                  if (w.webview && !w.pending_url.empty()) {
                    const std::string url = w.pending_url;
                    w.pending_url.clear();
                    Navigate(w, url);
                  }
                }
                if (done) done();
                return S_OK;
              })
              .Get());
      if (FAILED(hr)) clearing_ = false;
      return;
    }
  }
  // No page open yet (the Fire button closes them all first): as soon as
  // the next one is.
  pending_clear_ = true;
}
