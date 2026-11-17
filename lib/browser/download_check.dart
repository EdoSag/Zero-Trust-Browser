/// Checks on a file before it is downloaded (B35), all on the phone:
/// nothing about the file is sent anywhere.
library;

/// Why a download deserves a second look.
enum DownloadWarning {
  /// An Android app (.apk): installing apps from websites is how most
  /// phone malware arrives.
  app,

  /// A program or script for a computer (.exe, .bat, .ps1, .jar...).
  program,

  /// The name hides what the file is: a double extension
  /// ("invoice.pdf.exe"), invisible characters that flip the name's
  /// direction, or a type that doesn't match the name.
  disguised,

  /// Downloaded over plain http: anyone on the network could swap it.
  insecure,
}

const Set<String> _appExtensions = <String>{'apk', 'apks', 'xapk', 'apkm'};

const Set<String> _programExtensions = <String>{
  'exe',
  'msi',
  'msix',
  'appx',
  'bat',
  'cmd',
  'com',
  'scr',
  'pif',
  'cpl',
  'ps1',
  'psm1',
  'vbs',
  'vbe',
  'jse',
  'wsf',
  'wsh',
  'hta',
  'lnk',
  'reg',
  'jar',
  'sh',
  'run',
  'dmg',
  'pkg',
  'deb',
  'rpm',
  'appimage',
};

/// Types a site may send for an app or program, whatever the name says.
const Set<String> _riskyTypes = <String>{
  'application/vnd.android.package-archive',
  'application/x-msdownload',
  'application/x-msdos-program',
  'application/x-ms-installer',
  'application/x-msi',
  'application/java-archive',
  'application/x-sh',
  'application/x-executable',
};

/// Extensions people trust at a glance, used to hide a program behind.
const Set<String> _innocentExtensions = <String>{
  'pdf',
  'doc',
  'docx',
  'xls',
  'xlsx',
  'ppt',
  'pptx',
  'txt',
  'rtf',
  'odt',
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'heic',
  'mp3',
  'mp4',
  'mov',
  'zip',
  'csv',
};

/// Characters that are invisible or change the direction of text.
final RegExp _bidiOrInvisible = RegExp(
  '[\u200e\u200f\u202a-\u202e\u2066-\u2069]',
);
final RegExp _control = RegExp('[\u0000-\u001f\u007f]');
final RegExp _forbidden = RegExp(r'[/\\:*?"<>|]');

/// The lower-case extension after the last dot, or ''.
String fileExtension(String name) {
  final int dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).trim().toLowerCase();
}

/// The name as it will be saved: no folders, no invisible or
/// direction-changing characters, not empty, at most 120 characters with
/// the extension kept. The same rules as DownloadEngine.cleanName.
String cleanFileName(String raw) {
  String name = raw
      .replaceAll(_control, '')
      .replaceAll(_bidiOrInvisible, '')
      .replaceAll(_forbidden, '_')
      .trim();
  while (name.startsWith('.')) {
    name = name.substring(1);
  }
  name = name.trim();
  if (name.isEmpty) name = 'download';
  if (name.length <= 120) return name;
  final int dot = name.lastIndexOf('.');
  final String ext = dot > 0 && name.length - dot <= 10
      ? name.substring(dot)
      : '';
  return name.substring(0, 120 - ext.length) + ext;
}

bool _risky(String ext) =>
    _appExtensions.contains(ext) || _programExtensions.contains(ext);

/// What is worth pointing out about downloading [name] (as the site
/// named it), of type [mime], from [url].
Set<DownloadWarning> downloadWarnings({
  required String name,
  required String mime,
  required String url,
}) {
  final Set<DownloadWarning> out = <DownloadWarning>{};
  final String clean = cleanFileName(name);
  final String ext = fileExtension(clean);
  final String type = mime.toLowerCase().split(';').first.trim();

  if (_appExtensions.contains(ext) ||
      type == 'application/vnd.android.package-archive') {
    out.add(DownloadWarning.app);
  } else if (_programExtensions.contains(ext) || _riskyTypes.contains(type)) {
    out.add(DownloadWarning.program);
  }

  // "invoice.pdf.exe", "photo.jpg      .apk": a trusted-looking name in
  // front of a program.
  final String withoutExt = ext.isEmpty
      ? clean
      : clean.substring(0, clean.length - ext.length - 1);
  final String inner = fileExtension(withoutExt.trimRight());
  final bool doubled =
      _risky(ext) &&
      (_innocentExtensions.contains(inner) || withoutExt.endsWith('  '));
  // The site says it's an app or program, the name says something else.
  final bool mismatched = _riskyTypes.contains(type) && !_risky(ext);
  if (_bidiOrInvisible.hasMatch(name) || doubled || mismatched) {
    out.add(DownloadWarning.disguised);
  }

  if (url.toLowerCase().startsWith('http://') && !_isLocal(url)) {
    out.add(DownloadWarning.insecure);
  }
  return out;
}

/// A device on this network (router, printer, NAS): http is normal there.
bool _isLocal(String url) {
  final String host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  if (host == 'localhost' || host.endsWith('.local')) return true;
  final List<int>? ip = _ipv4(host);
  if (ip == null) return false;
  return ip[0] == 10 ||
      ip[0] == 127 ||
      (ip[0] == 192 && ip[1] == 168) ||
      (ip[0] == 172 && ip[1] >= 16 && ip[1] <= 31);
}

List<int>? _ipv4(String host) {
  final List<String> parts = host.split('.');
  if (parts.length != 4) return null;
  final List<int> out = <int>[];
  for (final String p in parts) {
    final int? n = int.tryParse(p);
    if (n == null || n < 0 || n > 255) return null;
    out.add(n);
  }
  return out;
}
