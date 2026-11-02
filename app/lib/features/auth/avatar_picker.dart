import 'package:flutter/material.dart';

import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/avatar_view.dart';
import 'package:my_fitness/features/auth/avatars.dart';

/// 注册页的默认头像选择：4 列 × 3 行，选中项用炭火橙描边。
class AvatarPicker extends StatelessWidget {
  const AvatarPicker({super.key, required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GridView.count(
      crossAxisCount: 4,
      mainAxisSpacing: AppSpace.s12,
      crossAxisSpacing: AppSpace.s12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final ref in kPresetAvatarRefs)
          Semantics(
            button: true,
            selected: ref == selected,
            label: '头像 ${ref.substring(ref.length - 2)}',
            child: GestureDetector(
              onTap: () => onChanged(ref),
              child: AnimatedContainer(
                duration: AppMotion.fast,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: ref == selected ? c.accent : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: LayoutBuilder(
                  builder: (_, box) => AvatarView(
                    kind: 'preset',
                    avatarRef: ref,
                    size: box.biggest.shortestSide,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
