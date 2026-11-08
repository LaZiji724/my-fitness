/// 下载线路里的一段文件：整个安装包是一段；放在 Supabase 上的备用线路因为免费版单文件限制，会切成几段。
class DownloadSegment {
  const DownloadSegment(this.url, this.size);
  final String url;

  /// 字节数；0 表示不知道（只允许单段，读到连接结束为止）。
  final int size;
}

/// 一条下载线路（如「备用服务器」「加速线路一」「GitHub 官方」）。几段拼起来就是完整安装包。
class DownloadSource {
  const DownloadSource(this.label, this.segments);
  final String label;
  final List<DownloadSegment> segments;

  int get total => segments.fold(0, (sum, s) => sum + s.size);
}

/// 浏览器兜底下载用的链接。
class DownloadLink {
  const DownloadLink(this.label, this.url);
  final String label;
  final String url;
}

const kRepo = 'LaZiji724/my-fitness';

/// 国内常用的 GitHub 下载加速代理：把完整的 GitHub 链接接在它后面即可。
/// 这类代理会不定期失效，所以更新信息（manifest）里也可以下发新的列表。
const kDefaultMirrors = ['https://ghfast.top/', 'https://gh-proxy.com/'];

const _numberWords = ['一', '二', '三', '四', '五', '六', '七', '八', '九'];

/// 一个可以更新到的新版本。
class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.notes,
    required this.pageUrl,
    required this.assetName,
    required this.assetUrl,
    required this.assetSize,
    this.sha256,
    this.storage,
    this.mirrors = kDefaultMirrors,
  });

  /// 如 2.3.0
  final String version;

  /// Release 说明（可能为空）。
  final String notes;

  /// Release 网页，下载失败时可以让用户手动打开。
  final String pageUrl;

  /// 安装包文件名、GitHub 直链、大小（字节，0 表示不知道）。
  final String assetName;
  final String assetUrl;
  final int assetSize;

  /// 安装包的 SHA-256（小写十六进制），有的话下载完会校验，防止代理返回被篡改/损坏的文件。
  final String? sha256;

  /// Supabase 备用线路（切成几段的安装包）。
  final DownloadSource? storage;

  /// GitHub 加速代理前缀。
  final List<String> mirrors;

  AppUpdate copyWith({String? sha256, DownloadSource? storage, List<String>? mirrors}) => AppUpdate(
        version: version,
        notes: notes,
        pageUrl: pageUrl,
        assetName: assetName,
        assetUrl: assetUrl,
        assetSize: assetSize,
        sha256: sha256 ?? this.sha256,
        storage: storage ?? this.storage,
        mirrors: mirrors ?? this.mirrors,
      );

  /// 按顺序尝试的下载线路：备用服务器 → GitHub 官方 → 各加速代理。
  List<DownloadSource> get sources {
    DownloadSource single(String label, String url) => DownloadSource(label, [DownloadSegment(url, assetSize)]);
    return [
      ?storage,
      single('GitHub 官方', assetUrl),
      for (var i = 0; i < mirrors.length; i++) single('加速线路${i < _numberWords.length ? _numberWords[i] : '${i + 1}'}', '${mirrors[i]}$assetUrl'),
    ];
  }

  /// 浏览器下载用的链接（备用服务器的安装包是分段的，浏览器下不了，所以不放进来）。
  List<DownloadLink> get browserLinks => [
        for (var i = 0; i < mirrors.length; i++)
          DownloadLink('加速线路${i < _numberWords.length ? _numberWords[i] : '${i + 1}'}', '${mirrors[i]}$assetUrl'),
        DownloadLink('GitHub 官方', assetUrl),
      ];
}

/// 把 `v2.3.0` / `ios-v2.3.0` / `2.3.0+15` 解析成 [2, 3, 0]；格式不对返回 null。
List<int>? parseVersion(String text) {
  final m = RegExp(r'^(?:ios-)?v?(\d+)\.(\d+)\.(\d+)(?:\+\d+)?$').firstMatch(text.trim());
  if (m == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
}

/// a 比 b 新返回正数，相同返回 0，旧返回负数。
int compareVersions(List<int> a, List<int> b) {
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i].compareTo(b[i]);
  }
  return 0;
}

String _assetNameFor(String version, bool ios) => ios ? 'my-fitness-ios-$version-unsigned.ipa' : 'my-fitness-$version.apk';

String? _cleanSha(Object? raw) {
  final s = '${raw ?? ''}'.trim().toLowerCase().replaceFirst('sha256:', '');
  return RegExp(r'^[0-9a-f]{64}$').hasMatch(s) ? s : null;
}

/// 从 GitHub `releases` 接口返回的列表里找出本平台最新、且比 [current] 新的版本。
///
/// 安卓发布的 tag 形如 `v2.3.0`（附 .apk），苹果形如 `ios-v2.3.0`（附 .ipa），
/// 两条线在同一个仓库里，所以要按 tag 前缀和附件类型分开挑。
AppUpdate? findUpdate({
  required List<dynamic> releases,
  required bool ios,
  required String current,
}) {
  final cur = parseVersion(current);
  if (cur == null) return null;
  final ext = ios ? '.ipa' : '.apk';
  AppUpdate? best;
  List<int>? bestVer;
  for (final r in releases) {
    if (r is! Map) continue;
    if (r['draft'] == true || r['prerelease'] == true) continue;
    final tag = '${r['tag_name'] ?? ''}';
    if (tag.startsWith('ios-') != ios) continue;
    final ver = parseVersion(tag);
    if (ver == null || compareVersions(ver, cur) <= 0) continue;
    if (bestVer != null && compareVersions(ver, bestVer) <= 0) continue;
    final assets = r['assets'];
    if (assets is! List) continue;
    final asset = assets.whereType<Map>().where((a) => '${a['name'] ?? ''}'.toLowerCase().endsWith(ext)).firstOrNull;
    if (asset == null) continue;
    bestVer = ver;
    best = AppUpdate(
      version: ver.join('.'),
      notes: '${r['body'] ?? ''}'.trim(),
      pageUrl: '${r['html_url'] ?? ''}',
      assetName: '${asset['name']}',
      assetUrl: '${asset['browser_download_url']}',
      assetSize: (asset['size'] as num?)?.toInt() ?? 0,
      sha256: _cleanSha(asset['digest']),
    );
  }
  return best;
}

/// 从 Supabase 上的更新信息（android.json / ios.json，由发布流程上传）解析出新版本。
///
/// [fileUrl] 把存储里的相对路径换成可下载的完整地址。
AppUpdate? updateFromManifest(
  Map<dynamic, dynamic> json, {
  required bool ios,
  required String current,
  required String Function(String path) fileUrl,
}) {
  final cur = parseVersion(current);
  final ver = parseVersion('${json['version'] ?? ''}');
  if (cur == null || ver == null || compareVersions(ver, cur) <= 0) return null;
  final version = ver.join('.');
  final asset = json['asset'] is Map ? json['asset'] as Map : const {};
  final name = '${asset['name'] ?? _assetNameFor(version, ios)}';
  final size = (asset['size'] as num?)?.toInt() ?? 0;
  final tag = '${json['tag'] ?? (ios ? 'ios-v$version' : 'v$version')}';

  DownloadSource? storage;
  final parts = json['parts'];
  if (parts is List && parts.isNotEmpty) {
    final segments = <DownloadSegment>[];
    for (final p in parts) {
      if (p is! Map || p['path'] is! String) {
        segments.clear();
        break;
      }
      segments.add(DownloadSegment(fileUrl('${p['path']}'), (p['size'] as num?)?.toInt() ?? 0));
    }
    // 各段加起来必须等于整个安装包的大小，对不上就不用这条线路
    if (segments.isNotEmpty && segments.every((s) => s.size > 0) && (size == 0 || segments.fold(0, (a, s) => a + s.size) == size)) {
      storage = DownloadSource('备用服务器', segments);
    }
  }

  final mirrors = json['mirrors'] is List
      ? [for (final m in json['mirrors'] as List) if (m is String && m.startsWith('https://')) m.endsWith('/') ? m : '$m/']
      : <String>[];

  return AppUpdate(
    version: version,
    notes: '${json['notes'] ?? ''}'.trim(),
    pageUrl: '${json['page_url'] ?? 'https://github.com/$kRepo/releases/tag/$tag'}',
    assetName: name,
    assetUrl: '${json['github_url'] ?? 'https://github.com/$kRepo/releases/download/$tag/$name'}',
    assetSize: size,
    sha256: _cleanSha(asset['sha256']),
    storage: storage,
    mirrors: mirrors.isEmpty ? kDefaultMirrors : mirrors,
  );
}

/// 从 GitHub 的 releases.atom（走 github.com 而不是 api.github.com）里读出 tag，拼出新版本。
/// 只在前两种办法都失败时才用；拿不到文件大小和校验值，所以只能做最基本的检查。
AppUpdate? findUpdateFromAtom({
  required String atom,
  required bool ios,
  required String current,
}) {
  final cur = parseVersion(current);
  if (cur == null) return null;
  AppUpdate? best;
  List<int>? bestVer;
  for (final m in RegExp(r'/releases/tag/([^"<\s]+)"').allMatches(atom)) {
    final tag = Uri.decodeComponent(m.group(1)!);
    if (tag.startsWith('ios-') != ios) continue;
    final ver = parseVersion(tag);
    if (ver == null || compareVersions(ver, cur) <= 0) continue;
    if (bestVer != null && compareVersions(ver, bestVer) <= 0) continue;
    final version = ver.join('.');
    final name = _assetNameFor(version, ios);
    bestVer = ver;
    best = AppUpdate(
      version: version,
      notes: '',
      pageUrl: 'https://github.com/$kRepo/releases/tag/$tag',
      assetName: name,
      assetUrl: 'https://github.com/$kRepo/releases/download/$tag/$name',
      assetSize: 0,
    );
  }
  return best;
}
