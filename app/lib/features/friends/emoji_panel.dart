import 'package:flutter/material.dart';

import 'package:my_fitness/core/theme/app_icons.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';

/// 内置表情。前两行是健身时最常用的，后面是常见的表情和手势。
const kChatEmojis = <String>[
  '💪', '🔥', '👍', '👏', '🎉', '😂', '🥹', '😎',
  '🏋️', '🏃', '🚴', '🧘', '🤸', '🏊', '⛹️', '🥊',
  '😀', '😄', '😁', '😆', '😅', '🤣', '😊', '🙂',
  '😉', '😍', '🥰', '😘', '😋', '😜', '🤪', '🤗',
  '🤔', '🫡', '😏', '😌', '😴', '🥱', '😪', '😮‍💨',
  '😭', '😢', '😤', '😡', '🥵', '🥶', '😱', '😳',
  '🤯', '😵‍💫', '🤒', '🤕', '🤢', '🤐', '🙄', '😬',
  '🫠', '😇', '🤩', '🥳', '🤝', '🙏', '👌', '✌️',
  '🤞', '🤙', '👊', '✊', '🙌', '👋', '🫶', '❤️',
  '🧡', '💛', '💚', '💙', '💔', '💯', '✅', '❌',
  '⭐', '🏆', '🥇', '🎯', '⏰', '📅', '📈', '⚡',
  '🍗', '🥩', '🥚', '🥛', '🍌', '🥗', '🍚', '☕',
  '🍺', '💧', '😈', '👀', '🐂', '🐶', '🌞', '🌙',
];

/// 把 [emoji] 插到输入框光标处（没有光标就加在末尾）。
void insertEmoji(TextEditingController controller, String emoji) {
  final text = controller.text;
  final sel = controller.selection;
  final start = sel.isValid ? sel.start : text.length;
  final end = sel.isValid ? sel.end : text.length;
  final next = text.replaceRange(start, end, emoji);
  controller.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: start + emoji.length));
}

/// 删掉光标前的一个字（表情按一整个算）。
void deleteBackward(TextEditingController controller) {
  final text = controller.text;
  final sel = controller.selection;
  if (sel.isValid && !sel.isCollapsed) {
    controller.value = TextEditingValue(text: text.replaceRange(sel.start, sel.end, ''), selection: TextSelection.collapsed(offset: sel.start));
    return;
  }
  final at = sel.isValid ? sel.start : text.length;
  if (at <= 0) return;
  final before = text.substring(0, at).characters.skipLast(1).toString();
  controller.value = TextEditingValue(text: before + text.substring(at), selection: TextSelection.collapsed(offset: before.length));
}

/// 聊天输入框下面的表情面板：点一个表情就插进输入框，右下角是删除键。
class EmojiPanel extends StatelessWidget {
  const EmojiPanel({super.key, required this.controller, this.height = 272});

  final TextEditingController controller;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          GridView.builder(
            padding: const EdgeInsets.fromLTRB(AppSpace.s8, AppSpace.s8, AppSpace.s8, 64),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
            itemCount: kChatEmojis.length,
            itemBuilder: (context, i) => PressScale(
              scale: PressScale.smallScale,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: () => insertEmoji(controller, kChatEmojis[i]),
                child: Center(
                  child: Text(kChatEmojis[i], style: const TextStyle(fontSize: 26, height: 1.2)),
                ),
              ),
            ),
          ),
          Positioned(
            right: AppSpace.s12,
            bottom: AppSpace.s12,
            child: PressScale(
              scale: PressScale.chipScale,
              child: Material(
                color: c.surface,
                elevation: 3,
                shadowColor: const Color(0x33000000),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  side: BorderSide(color: c.border, width: AppStroke.hairline),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => deleteBackward(controller),
                  child: Tooltip(
                    message: '删除',
                    child: SizedBox(width: 56, height: 40, child: Icon(AppIcons.backspace, size: 22, color: c.text)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
