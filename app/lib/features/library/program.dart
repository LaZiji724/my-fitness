// 内置计划库的数据模型。内容随 App 打包（assets/seed/programs.json），离线可用；
// 同一份内容也写在 Supabase 的 programs / program_sessions / program_session_items 表里。

/// 左侧分类栏。前三项是由数据推导的「虚拟分类」，其余是计划自带的目标分类。
enum LibraryCategory {
  newest('近期上新'),
  favorites('我的收藏'),
  beginner('新手入门'),
  advanced('进阶计划'),
  cardio('有氧跟练'),
  group('团课计划'),
  fatLoss('瘦身减脂'),
  shaping('塑形美体'),
  muscle('增肌增重'),
  health('健康改善'),
  stretch('拉伸放松'),
  glute('丰满翘臀');

  const LibraryCategory(this.label);
  final String label;

  /// 对应数据里的 category 字段；虚拟分类为 null。
  String? get dataKey => switch (this) {
        newest || favorites || beginner || advanced => null,
        _ => label,
      };
}

/// 难度：1 初阶 2 中阶 3 高阶。
String levelLabel(int level) => switch (level) {
      1 => '初阶',
      2 => '中阶',
      _ => '高阶',
    };

/// 每周次数的筛选分档。
enum FrequencyBand {
  light('每周 1–2 次', 1, 2),
  three('每周 3 次', 3, 3),
  four('每周 4 次', 4, 4),
  many('每周 5 次以上', 5, 7);

  const FrequencyBand(this.label, this.min, this.max);
  final String label;
  final int min;
  final int max;

  bool contains(int perWeek) => perWeek >= min && perWeek <= max;
}

/// 动作链里的一项：一个动作的热身组 + 正式组目标。
class ProgramItem {
  const ProgramItem({
    required this.id,
    required this.exerciseId,
    required this.position,
    required this.warmupSets,
    required this.sets,
    this.repsMin,
    this.repsMax,
    this.durationSec,
    this.distanceM,
    required this.restSec,
    this.note,
  });

  final String id;
  final String exerciseId;
  final int position;
  final int warmupSets;
  final int sets;
  final int? repsMin;
  final int? repsMax;

  /// 每组目标秒数（按时间的动作）；按次数的动作为空
  final int? durationSec;

  /// 距离目标（米），只用来展示
  final int? distanceM;
  final int restSec;
  final String? note;

  bool get isTimed => durationSec != null;

  factory ProgramItem.fromJson(Map<String, dynamic> j) => ProgramItem(
        id: j['id'] as String,
        exerciseId: j['exercise_id'] as String,
        position: j['position'] as int,
        warmupSets: j['warmup_sets'] as int,
        sets: j['sets'] as int,
        repsMin: j['reps_min'] as int?,
        repsMax: j['reps_max'] as int?,
        durationSec: j['duration_sec'] as int?,
        distanceM: j['distance_m'] as int?,
        restSec: j['rest_sec'] as int,
        note: j['note'] as String?,
      );
}

/// 目标写成人话，如「4 组 × 6–8 次 · 热身 2 组 · 休息 120 秒」「1 组 × 20 分钟」。
String describeItemTarget(ProgramItem it) {
  final parts = <String>[];
  if (it.warmupSets > 0) parts.add('热身 ${it.warmupSets} 组');
  final String target;
  if (it.durationSec != null) {
    target = '${it.sets} 组 × ${formatDuration(it.durationSec!)}';
  } else if (it.repsMin == null) {
    target = '${it.sets} 组';
  } else if (it.repsMax == null || it.repsMax == it.repsMin) {
    target = '${it.sets} 组 × ${it.repsMin} 次';
  } else {
    target = '${it.sets} 组 × ${it.repsMin}–${it.repsMax} 次';
  }
  final out = <String>[target, ...parts];
  if (it.distanceM != null) out.add('目标 ${formatDistance(it.distanceM!)}');
  if (it.sets > 1 && it.restSec > 0) out.add('休息 ${it.restSec} 秒');
  return out.join(' · ');
}

String formatDuration(int sec) {
  if (sec >= 60 && sec % 60 == 0) return '${sec ~/ 60} 分钟';
  if (sec > 60) return '${sec ~/ 60} 分 ${sec % 60} 秒';
  return '$sec 秒';
}

String formatDistance(int meters) =>
    meters >= 1000 ? '${(meters / 1000).toStringAsFixed(meters % 1000 == 0 ? 0 : 1)} 公里' : '$meters 米';

class ProgramSession {
  const ProgramSession({
    required this.id,
    required this.key,
    required this.name,
    required this.focus,
    required this.minutes,
    required this.items,
  });

  final String id;

  /// 在计划安排里的代号（A、B、C…）
  final String key;
  final String name;
  final String focus;
  final int minutes;
  final List<ProgramItem> items;

  int get totalSets => items.fold(0, (n, i) => n + i.sets);

  factory ProgramSession.fromJson(Map<String, dynamic> j) => ProgramSession(
        id: j['id'] as String,
        key: j['key'] as String,
        name: j['name'] as String,
        focus: j['focus'] as String,
        minutes: j['minutes'] as int,
        items: [for (final i in j['items'] as List) ProgramItem.fromJson(i as Map<String, dynamic>)],
      );
}

class Program {
  const Program({
    required this.id,
    required this.slug,
    required this.name,
    required this.subtitle,
    required this.description,
    required this.progression,
    required this.category,
    required this.level,
    required this.weeks,
    required this.daysPerWeek,
    required this.minutes,
    required this.schedule,
    required this.scenes,
    required this.audiences,
    required this.equipment,
    required this.isNew,
    required this.featured,
    required this.sortOrder,
    required this.sessions,
  });

  final String id;
  final String slug;
  final String name;
  final String subtitle;
  final String description;
  final String progression;
  final String category;
  final int level;
  final int weeks;
  final int daysPerWeek;
  final int minutes;

  /// 周一到周日，7 个字符：课次代号，或 '.' 表示休息
  final String schedule;
  final List<String> scenes;
  final List<String> audiences;
  final List<String> equipment;
  final bool isNew;
  final bool featured;
  final int sortOrder;
  final List<ProgramSession> sessions;

  String get levelText => levelLabel(level);

  ProgramSession? sessionByKey(String key) => sessions.where((s) => s.key == key).firstOrNull;

  /// 一个循环里按安排顺序出现的课次（用来决定「下一节练哪个」）。
  List<ProgramSession> get weekOrder => [
        for (final ch in schedule.split(''))
          if (ch != '.') ?sessionByKey(ch),
      ];

  int get totalSessions => weekOrder.length * weeks;

  factory Program.fromJson(Map<String, dynamic> j) => Program(
        id: j['id'] as String,
        slug: j['slug'] as String,
        name: j['name'] as String,
        subtitle: j['subtitle'] as String,
        description: j['description'] as String,
        progression: j['progression'] as String,
        category: j['category'] as String,
        level: j['level'] as int,
        weeks: j['weeks'] as int,
        daysPerWeek: j['days_per_week'] as int,
        minutes: j['minutes'] as int,
        schedule: j['schedule'] as String,
        scenes: List<String>.from(j['scenes'] as List),
        audiences: List<String>.from(j['audiences'] as List),
        equipment: List<String>.from(j['equipment'] as List),
        isNew: j['is_new'] as bool,
        featured: j['featured'] as bool,
        sortOrder: j['sort_order'] as int,
        sessions: [for (final s in j['sessions'] as List) ProgramSession.fromJson(s as Map<String, dynamic>)],
      );
}

/// 列表页筛选条件：分类 + 频率/难度/场景/人群 + 搜索词。
class LibraryFilter {
  const LibraryFilter({
    this.category = LibraryCategory.newest,
    this.frequency,
    this.level,
    this.scene,
    this.audience,
    this.query = '',
  });

  final LibraryCategory category;
  final FrequencyBand? frequency;
  final int? level;
  final String? scene;
  final String? audience;
  final String query;

  bool get hasAdvancedFilter => frequency != null || level != null || scene != null || audience != null;
  bool get isSearching => query.trim().isNotEmpty;

  LibraryFilter copyWith({
    LibraryCategory? category,
    Object? frequency = _keep,
    Object? level = _keep,
    Object? scene = _keep,
    Object? audience = _keep,
    String? query,
  }) =>
      LibraryFilter(
        category: category ?? this.category,
        frequency: identical(frequency, _keep) ? this.frequency : frequency as FrequencyBand?,
        level: identical(level, _keep) ? this.level : level as int?,
        scene: identical(scene, _keep) ? this.scene : scene as String?,
        audience: identical(audience, _keep) ? this.audience : audience as String?,
        query: query ?? this.query,
      );

  static const _keep = Object();
}

/// 按条件筛选。搜索时跨分类，其余条件仍然生效。
List<Program> filterPrograms(List<Program> all, LibraryFilter f, Set<String> favoriteIds) {
  Iterable<Program> r = all;
  if (f.isSearching) {
    final q = f.query.trim().toLowerCase();
    r = r.where((p) =>
        p.name.toLowerCase().contains(q) ||
        p.subtitle.toLowerCase().contains(q) ||
        p.category.contains(q) ||
        p.equipment.any((e) => e.toLowerCase().contains(q)));
  } else {
    r = switch (f.category) {
      LibraryCategory.newest => r.where((p) => p.isNew),
      LibraryCategory.favorites => r.where((p) => favoriteIds.contains(p.id)),
      LibraryCategory.beginner => r.where((p) => p.level == 1),
      LibraryCategory.advanced => r.where((p) => p.level >= 2),
      _ => r.where((p) => p.category == f.category.dataKey),
    };
  }
  if (f.frequency != null) r = r.where((p) => f.frequency!.contains(p.daysPerWeek));
  if (f.level != null) r = r.where((p) => p.level == f.level);
  if (f.scene != null) r = r.where((p) => p.scenes.contains(f.scene));
  if (f.audience != null) r = r.where((p) => p.audiences.contains(f.audience));
  return r.toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
}
