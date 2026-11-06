import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/update/update_models.dart';
import 'package:my_fitness/features/update/update_service.dart';

/// 手动检查更新（「我的」页）：有新版弹出更新窗口，没有就提示已是最新。
Future<void> checkForUpdateManually(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
  say('正在检查更新…');
  try {
    final current = await ref.read(currentVersionProvider.future);
    final update = await ref.read(updateServiceProvider).check(current: current, ios: isIosPlatform);
    if (!context.mounted) return;
    messenger.hideCurrentSnackBar();
    if (update == null) {
      say('已经是最新版本（$current）');
      return;
    }
    await showUpdateDialog(context, update, current);
  } catch (_) {
    say('检查更新失败：连不上 GitHub，换个网络再试');
  }
}

/// 包在底部分栏外面：每次启动进入主界面时检查更新（从后台切回来隔一阵也查）；
/// 有新版就弹窗，让用户选「更新」或「暂不更新」，没有或失败都不打扰。
/// 测试用：假装离上次检查已经过了很久。
@visibleForTesting
void resetUpdateAutoCheckThrottle() => _UpdateAutoCheckState._lastCheck = null;

class UpdateAutoCheck extends ConsumerStatefulWidget {
  const UpdateAutoCheck({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<UpdateAutoCheck> createState() => _UpdateAutoCheckState();
}

class _UpdateAutoCheckState extends ConsumerState<UpdateAutoCheck> with WidgetsBindingObserver {
  /// 整个进程共用：上次检查的时间、更新窗口是否正开着（切换分栏、重建界面都不会重复弹）。
  static DateTime? _lastCheck;
  static bool _showing = false;

  /// 从后台切回来时，距离上次检查不到这么久就不再查（免得频繁打扰、频繁访问 GitHub）。
  static const _recheckAfter = Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_maybeCheck());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 每次启动进入软件都查一次；之后每次从后台切回来（隔了一阵）也查。有新版就一直提示到更新为止。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_maybeCheck());
  }

  Future<void> _maybeCheck() async {
    if (_showing || !ref.read(autoUpdateCheckProvider)) return;
    final now = DateTime.now();
    final last = _lastCheck;
    if (last != null && now.difference(last) < _recheckAfter) return;
    _lastCheck = now;
    try {
      final current = await ref.read(currentVersionProvider.future);
      final update = await ref.read(updateServiceProvider).check(current: current, ios: isIosPlatform);
      if (update == null || !mounted || _showing) return;
      _showing = true;
      try {
        await showUpdateDialog(context, update, current);
      } finally {
        _showing = false;
      }
    } catch (_) {
      // 自动检查失败不打扰用户，下次进入再查
      _lastCheck = null;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> showUpdateDialog(BuildContext context, AppUpdate update, String current) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => UpdateDialog(update: update, current: current),
  );
}

enum _Phase { idle, downloading, ready }

class UpdateDialog extends ConsumerStatefulWidget {
  const UpdateDialog({super.key, required this.update, required this.current});
  final AppUpdate update;
  final String current;

  @override
  ConsumerState<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends ConsumerState<UpdateDialog> {
  _Phase _phase = _Phase.idle;
  double? _progress; // 0~1
  String? _error;
  String? _hint;
  File? _file;
  final _cancel = DownloadCancel();

  bool get _ios => isIosPlatform;

  @override
  void dispose() {
    _cancel.cancelled = true;
    super.dispose();
  }

  String _mb(int bytes) => '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

  Future<void> _download() async {
    setState(() {
      _phase = _Phase.downloading;
      _progress = null;
      _error = null;
      _hint = null;
    });
    try {
      final file = await ref.read(updateServiceProvider).download(widget.update, (got, total) {
        if (!mounted || total <= 0) return;
        setState(() => _progress = got / total);
      }, _cancel);
      if (!mounted) return;
      setState(() {
        _file = file;
        _phase = _Phase.ready;
      });
      if (!_ios) await _installAndroid();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _error = e is UpdateException ? e.message : '下载失败，请检查网络后重试';
      });
    }
  }

  Future<void> _installAndroid() async {
    final installer = ref.read(apkInstallerProvider);
    try {
      if (!await installer.canInstall()) {
        // 第一次：先去系统设置里允许本应用安装应用
        setState(() => _hint = '需要先在系统设置里打开「允许安装应用」开关（只用设置一次）。'
            '打开后按返回键回到「我的健身」，再点一次「安装」。');
        await installer.openInstallSettings();
        return;
      }
      setState(() => _hint = '已调起系统安装界面，点「更新」即可覆盖安装，数据会保留。');
      await installer.install(_file!.path);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '调起安装失败，可以点下方「打开下载页」手动下载安装');
    }
  }

  /// 苹果：安装包没有签名，系统不允许 App 自己装，只能交给全能签之类的工具去签名安装。
  Future<void> _shareToSigner() async {
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile(_file!.path, mimeType: 'application/octet-stream')],
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '打不开分享面板，可以点「打开下载页」手动下载');
    }
  }

  Future<void> _openPage() async {
    final ok = await launchUrl(Uri.parse(widget.update.pageUrl), mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && mounted) {
      setState(() => _error = '打不开浏览器，请复制链接到浏览器里打开');
    }
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: widget.update.assetUrl));
    if (!mounted) return;
    setState(() => _hint = '下载链接已复制，可以粘贴到浏览器或全能签里下载。');
  }

  /// Release 说明去掉 Markdown 符号，只留纯文字。
  String get _notes => widget.update.notes
      .replaceAll(RegExp(r'^#+\s*', multiLine: true), '')
      .replaceAll('**', '')
      .replaceAll('`', '')
      .trim();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final u = widget.update;
    final size = u.assetSize > 0 ? '，${_mb(u.assetSize)}' : '';
    final downloading = _phase == _Phase.downloading;

    final body = <Widget>[
      Text('当前 ${widget.current} → 新版 ${u.version}$size', style: AppText.body.copyWith(color: c.text)),
      if (_notes.isNotEmpty) ...[
        const SizedBox(height: AppSpace.s12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 140),
          child: SingleChildScrollView(child: Text(_notes, style: AppText.label.copyWith(color: c.text2))),
        ),
      ],
      if (_ios && _phase != _Phase.ready) ...[
        const SizedBox(height: AppSpace.s12),
        Text(
          '苹果系统不允许 App 自己安装没有签名的新版。下载好之后会打开分享面板，'
          '选「全能签」就能导入，在全能签里点签名安装即可覆盖旧版，数据保留。',
          style: AppText.label.copyWith(color: c.text2),
        ),
      ],
      if (_ios && _phase == _Phase.ready) ...[
        const SizedBox(height: AppSpace.s12),
        Text('下载完成。点「导入全能签」，在分享面板里选「全能签」（找不到就选「存储到文件」，再到全能签里导入），'
            '然后在全能签里签名安装。', style: AppText.label.copyWith(color: c.text2)),
      ],
      if (downloading) ...[
        const SizedBox(height: AppSpace.s16),
        LinearProgressIndicator(value: _progress),
        const SizedBox(height: AppSpace.s8),
        Text(_progress == null ? '正在连接…' : '正在下载 ${(_progress! * 100).toStringAsFixed(0)}%',
            style: AppText.label.copyWith(color: c.text2)),
      ],
      if (_hint != null) ...[
        const SizedBox(height: AppSpace.s12),
        Text(_hint!, style: AppText.label.copyWith(color: c.accentText)),
      ],
      if (_error != null) ...[
        const SizedBox(height: AppSpace.s12),
        Text(_error!, style: AppText.label.copyWith(color: c.danger)),
      ],
    ];

    Widget btn(String text, VoidCallback? onTap, {bool primary = false}) => PressScale(
          child: primary ? FilledButton(onPressed: onTap, child: Text(text)) : TextButton(onPressed: onTap, child: Text(text)),
        );

    final actions = <Widget>[
      if (downloading)
        btn('取消', () {
          _cancel.cancelled = true;
          Navigator.pop(context);
        })
      else ...[
        btn('暂不更新', () => Navigator.pop(context)),
        if (_ios || _error != null) btn('打开下载页', _openPage),
        if (_ios && _phase == _Phase.ready) btn('复制链接', _copyLink),
        if (_phase == _Phase.ready)
          btn(_ios ? '导入全能签' : '安装', _ios ? _shareToSigner : _installAndroid, primary: true)
        else
          btn(_error != null ? '重试' : '更新', _download, primary: true),
      ],
    ];

    return PopScope(
      canPop: !downloading,
      child: AlertDialog(
        title: const Text('发现新版本'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: body),
        ),
        actions: actions,
      ),
    );
  }
}
