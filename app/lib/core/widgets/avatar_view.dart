import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:my_fitness/core/theme/app_icons.dart';
import 'package:my_fitness/core/theme/app_theme.dart';

/// 圆形头像：preset 读 App 内置图片，custom 读 Supabase Storage 的公开地址。
class AvatarView extends StatelessWidget {
  const AvatarView({
    super.key,
    required this.kind,
    required this.avatarRef,
    this.size = 40,
  });

  final String kind;
  final String avatarRef;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fallback = ColoredBox(
      color: c.sunken,
      child: Icon(AppIcons.userOn, size: size * 0.6, color: c.text3),
    );
    final Widget image;
    if (kind == 'custom') {
      final url =
          Supabase.instance.client.storage.from('avatars').getPublicUrl(avatarRef);
      image = Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    } else {
      image = Image.asset(
        'assets/avatars/$avatarRef.png',
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    return ClipOval(child: SizedBox.square(dimension: size, child: image));
  }
}
