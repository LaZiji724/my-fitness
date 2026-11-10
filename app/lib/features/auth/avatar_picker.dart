import 'package:flutter/material.dart';

import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/avatar_view.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/auth/avatars.dart';

/// 注册页的默认头像选择：4 列 × 3 行，选中项用墨色描边。
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
          PressScale(
            scale: PressScale.chipScale,
            child: Semantics(
              button: true,
              selected: ref == selected,
              label: '头像 ${ref.substring(ref.length - 2)}',
              child: GestureDetector(
                onTap: () => onChanged(ref),
                child: AnimatedContainer(
                  duration: AppMotion.fast,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: ref == selected ? c.selectedFill : Colors.transparent,
                      width: 2,
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
          ),
      ],
    );
  }
}
