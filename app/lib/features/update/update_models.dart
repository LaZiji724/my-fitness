/// 一个可以更新到的新版本（来自 GitHub Release）。
class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.notes,
    required this.pageUrl,
    required this.assetName,
    required this.assetUrl,
    required this.assetSize,
  });

  /// 如 2.3.0
  final String version;

  /// Release 说明（可能为空）。
  final String notes;

  /// Release 网页，下载失败时可以让用户手动打开。
  final String pageUrl;

  /// 安装包文件名与直链、大小（字节）。
  final String assetName;
  final String assetUrl;
  final int assetSize;
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
    );
  }
  return best;
}
