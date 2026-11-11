import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_fitness/core/theme/app_icons.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/avatar_view.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/auth/auth_providers.dart';
import 'package:my_fitness/features/auth/avatar_picker.dart';
import 'package:my_fitness/features/profile/avatar_crop_page.dart';
import 'package:my_fitness/features/profile/avatar_service.dart';

/// 「更换头像」：选一个内置头像，或者从相册选一张自己的照片（自动裁成圆形，可拖动缩放调整）。
Future<void> showAvatarSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const AvatarEditSheet(),
  );
}

class AvatarEditSheet extends ConsumerStatefulWidget {
  const AvatarEditSheet({super.key});

  @override
  ConsumerState<AvatarEditSheet> createState() => _AvatarEditSheetState();
}

class _AvatarEditSheetState extends ConsumerState<AvatarEditSheet> {
  bool _busy = false;

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    // 提示要在弹层关掉之后出现在页面上，所以先拿到页面的 messenger
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      // 国内直连有时很慢，给足时间，但不要一直转圈
      await job().timeout(const Duration(seconds: 90));
      navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('头像已更换')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(avatarErrorText(e));
    }
  }

  Future<void> _pickPreset(String presetRef) => _run(() => ref.read(avatarUpdaterProvider).setPreset(presetRef));

  Future<void> _pickPhoto() async {
    if (_busy) return;
    final picked = await FilePicker.pickFile(type: FileType.image);
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    final cropped = await AvatarCropPage.open(context, bytes);
    if (cropped == null || !mounted) return;
    await _run(() => ref.read(avatarUpdaterProvider).setCustom(cropped));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final profile = ref.watch(profileSummaryProvider);
    final isCustom = profile?.avatarKind == 'custom';
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpace.pageGutter, 0, AppSpace.pageGutter, AppSpace.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.accent, width: 2)),
                child: AvatarView(kind: profile?.avatarKind ?? 'preset', avatarRef: profile?.avatarRef ?? 'avatar_01', size: 88),
              ),
            ),
            const SizedBox(height: AppSpace.s12),
            Text('更换头像', textAlign: TextAlign.center, style: AppText.titleSmall.copyWith(color: c.text)),
            const SizedBox(height: AppSpace.s16),
            PressScale(
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _pickPhoto,
                icon: const Icon(AppIcons.photo, size: 20),
                label: const Text('从相册选择照片'),
                style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size.fromHeight(AppSize.button))),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.s8),
              child: Text('选好后会自动裁成圆形，也可以拖动、缩放调整', textAlign: TextAlign.center, style: AppText.caption.copyWith(color: c.text3)),
            ),
            const SizedBox(height: AppSpace.s24),
            Text('默认头像', style: AppText.label.copyWith(color: c.text2, fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpace.s12),
            Stack(
              children: [
                Opacity(
                  opacity: _busy ? 0.5 : 1,
                  child: IgnorePointer(
                    ignoring: _busy,
                    child: AvatarPicker(
                      // 正在用自己的照片时，默认头像里没有选中项
                      selected: isCustom ? '' : (profile?.avatarRef ?? ''),
                      onChanged: _pickPreset,
                    ),
                  ),
                ),
                if (_busy) const Positioned.fill(child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
