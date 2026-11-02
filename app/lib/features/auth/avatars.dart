/// 内置默认头像：assets/avatars/avatar_01.png … avatar_12.png
final List<String> kPresetAvatarRefs = List.unmodifiable(
  List.generate(12, (i) => 'avatar_${(i + 1).toString().padLeft(2, '0')}'),
);

const String kDefaultAvatarRef = 'avatar_01';
