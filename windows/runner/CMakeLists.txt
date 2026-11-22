cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "browser_engine.cpp"
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")

# Microsoft Edge WebView2 SDK (BSD-3-Clause), the page engine on Windows.
# The loader is linked in statically, so the app is one .exe plus its data;
# the WebView2 Runtime itself comes with Windows 10 and 11.
set(WEBVIEW2_VERSION "1.0.2903.40")
set(WEBVIEW2_DIR "${CMAKE_BINARY_DIR}/webview2-${WEBVIEW2_VERSION}")
if(NOT EXISTS "${WEBVIEW2_DIR}/build/native/include/WebView2.h")
  file(DOWNLOAD
    "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/${WEBVIEW2_VERSION}"
    "${CMAKE_BINARY_DIR}/webview2-${WEBVIEW2_VERSION}.nupkg"
    STATUS WEBVIEW2_STATUS
    SHOW_PROGRESS)
  list(GET WEBVIEW2_STATUS 0 WEBVIEW2_CODE)
  if(NOT WEBVIEW2_CODE EQUAL 0)
    message(FATAL_ERROR "Could not download the WebView2 SDK: ${WEBVIEW2_STATUS}")
  endif()
  file(SHA256 "${CMAKE_BINARY_DIR}/webview2-${WEBVIEW2_VERSION}.nupkg" WEBVIEW2_SHA)
  message(STATUS "WebView2 SDK ${WEBVIEW2_VERSION} sha256 ${WEBVIEW2_SHA}")
  file(ARCHIVE_EXTRACT
    INPUT "${CMAKE_BINARY_DIR}/webview2-${WEBVIEW2_VERSION}.nupkg"
    DESTINATION "${WEBVIEW2_DIR}")
endif()
if(CMAKE_SIZEOF_VOID_P EQUAL 8)
  if(CMAKE_SYSTEM_PROCESSOR MATCHES "ARM64|arm64")
    set(WEBVIEW2_ARCH "arm64")
  else()
    set(WEBVIEW2_ARCH "x64")
  endif()
else()
  set(WEBVIEW2_ARCH "x86")
endif()
target_include_directories(${BINARY_NAME} PRIVATE
  "${WEBVIEW2_DIR}/build/native/include")
target_link_libraries(${BINARY_NAME} PRIVATE
  "${WEBVIEW2_DIR}/build/native/${WEBVIEW2_ARCH}/WebView2LoaderStatic.lib"
  "bcrypt.lib" "shlwapi.lib" "shell32.lib" "ole32.lib" "version.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
