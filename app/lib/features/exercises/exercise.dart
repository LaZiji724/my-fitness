/// 动作的部位分类（与数据库 exercises.body_part 一致）。
enum BodyPart {
  chest('chest', '胸'),
  back('back', '背'),
  shoulders('shoulders', '肩'),
  arms('arms', '手臂'),
  legs('legs', '腿'),
  glutes('glutes', '臀'),
  core('core', '腹'),
  cardio('cardio', '有氧'),
  other('other', '拉伸');

  const BodyPart(this.key, this.label);
  final String key;
  final String label;

  static BodyPart fromKey(String key) =>
      values.firstWhere((p) => p.key == key, orElse: () => BodyPart.other);
}

/// 记录方式（与数据库 exercises.tracking_type 一致）。
enum TrackingType {
  weightReps('weight_reps', '重量 × 次数'),
  bodyweightReps('bodyweight_reps', '自重 × 次数'),
  duration('duration', '时长'),
  distanceDuration('distance_duration', '距离 + 时长');

  const TrackingType(this.key, this.label);
  final String key;
  final String label;

  static TrackingType fromKey(String key) => values.firstWhere(
        (t) => t.key == key,
        orElse: () => TrackingType.weightReps,
      );
}

/// 动作类型（与数据库 exercises.kind 一致）。
enum ExerciseKind {
  strength('strength', '力量'),
  cardio('cardio', '有氧'),
  activation('activation', '激活'),
  dynamicWarmup('dynamic', '动态热身'),
  stretch('stretch', '静态拉伸'),
  foam('foam', '泡沫轴');

  const ExerciseKind(this.key, this.label);
  final String key;
  final String label;

  static ExerciseKind fromKey(String? key) =>
      values.firstWhere((k) => k.key == key, orElse: () => ExerciseKind.strength);

  /// 属于「激活」分栏（激活 + 动态热身）
  bool get isActivationTab => this == activation || this == dynamicWarmup;

  /// 属于「拉伸」分栏（静态拉伸 + 泡沫轴）
  bool get isStretchTab => this == stretch || this == foam;
}

/// 激活 / 拉伸动作的身体区域（与数据库 exercises.region 一致）。
enum ExerciseRegion {
  neckShoulder('neck_shoulder', '颈肩'),
  chestArm('chest_arm', '胸臂'),
  backCore('back_core', '背腹'),
  hipGlute('hip_glute', '髋臀'),
  leg('leg', '大小腿'),
  full('full', '全身');

  const ExerciseRegion(this.key, this.label);
  final String key;
  final String label;

  static ExerciseRegion? fromKey(String? key) {
    for (final r in values) {
      if (r.key == key) return r;
    }
    return null;
  }
}

/// 训练 / 模板 / 计划里的分区：热身 → 正式训练 → 放松。
enum WorkoutSection {
  warmup('warmup', '热身'),
  main('main', '正式训练'),
  cooldown('cooldown', '放松');

  const WorkoutSection(this.key, this.label);
  final String key;
  final String label;

  static WorkoutSection fromKey(String? key) =>
      values.firstWhere((s) => s.key == key, orElse: () => WorkoutSection.main);
}

/// 在动作详情页「添加动作」时设置的运动量：放进哪个模块、按次数还是按时间、组数、每组次数 / 秒数、负重。
class ExerciseDose {
  const ExerciseDose({
    required this.section,
    required this.timed,
    required this.sets,
    required this.reps,
    required this.seconds,
    this.weightKg,
  });

  final WorkoutSection section;

  /// 为真按时间（用 [seconds]），否则按次数（用 [reps]）。
  final bool timed;
  final int sets;
  final int reps;
  final int seconds;

  /// 每组负重（公斤）；为空表示不设。
  final double? weightKg;

  /// 该动作最合适的默认模块：激活 / 动态热身放热身，拉伸 / 泡沫轴放放松，其余放正式训练。
  static WorkoutSection defaultSectionFor(Exercise e) {
    if (e.kind.isActivationTab) return WorkoutSection.warmup;
    if (e.kind.isStretchTab) return WorkoutSection.cooldown;
    return WorkoutSection.main;
  }

  /// 按动作自身的建议量生成初始值。
  factory ExerciseDose.initial(Exercise e) => ExerciseDose(
        section: defaultSectionFor(e),
        timed: e.isTimed,
        sets: e.defaultSets ?? 3,
        reps: e.defaultReps ?? 10,
        seconds: e.defaultSeconds ?? 30,
      );

  ExerciseDose copyWith({
    WorkoutSection? section,
    bool? timed,
    int? sets,
    int? reps,
    int? seconds,
    double? weightKg,
    bool clearWeight = false,
  }) =>
      ExerciseDose(
        section: section ?? this.section,
        timed: timed ?? this.timed,
        sets: sets ?? this.sets,
        reps: reps ?? this.reps,
        seconds: seconds ?? this.seconds,
        weightKg: clearWeight ? null : (weightKg ?? this.weightKg),
      );
}

/// 器械筛选分组：数据里的英文器械归到页面上的 6 个中文分组。
enum EquipmentGroup {
  all('all', '全部'),
  barbell('barbell', '杠铃'),
  dumbbell('dumbbell', '哑铃'),
  machine('machine', '器械'),
  cable('cable', '绳索'),
  bodyweight('bodyweight', '自重'),
  other('other', '其他');

  const EquipmentGroup(this.key, this.label);
  final String key;
  final String label;

  static EquipmentGroup of(String? equipment) {
    switch (equipment) {
      case 'barbell':
      case 'e-z curl bar':
        return barbell;
      case 'dumbbell':
        return dumbbell;
      case 'machine':
        return machine;
      case 'cable':
        return cable;
      case 'body only':
        return bodyweight;
      default:
        return other;
    }
  }
}

const Map<String, String> kMuscleZh = {
  'chest': '胸大肌',
  'lats': '背阔肌',
  'middle back': '中背部',
  'lower back': '下背部',
  'traps': '斜方肌',
  'shoulders': '三角肌',
  'biceps': '肱二头肌',
  'triceps': '肱三头肌',
  'forearms': '前臂',
  'quadriceps': '股四头肌',
  'hamstrings': '腘绳肌',
  'calves': '小腿',
  'adductors': '大腿内侧',
  'abductors': '大腿外侧',
  'glutes': '臀大肌',
  'abdominals': '腹肌',
  'neck': '颈部',
  'hip flexors': '髋屈肌',
  'obliques': '腹斜肌',
};

String muscleZh(String key) => kMuscleZh[key] ?? key;

class Exercise {
  const Exercise({
    required this.id,
    required this.slug,
    required this.nameZh,
    required this.nameEn,
    required this.bodyPart,
    required this.primaryMuscles,
    required this.secondaryMuscles,
    required this.equipment,
    required this.trackingType,
    required this.instructionsZh,
    required this.imageCount,
    TrackingType? defaultTrackingType,
    this.kind = ExerciseKind.strength,
    this.region,
    this.perSide = false,
    this.defaultSets,
    this.defaultReps,
    this.defaultSeconds,
    this.imageRatio = 1.0,
  }) : defaultTrackingType = defaultTrackingType ?? trackingType;

  final String id;
  final String slug;
  final String nameZh;
  final String? nameEn;
  final BodyPart bodyPart;
  final List<String> primaryMuscles;
  final List<String> secondaryMuscles;
  final String? equipment;

  /// 当前生效的记录方式（已叠加用户的「按次数 / 按时间」偏好）
  final TrackingType trackingType;

  /// 动作自带的默认记录方式
  final TrackingType defaultTrackingType;
  final String? instructionsZh;
  final int imageCount;
  final ExerciseKind kind;
  final ExerciseRegion? region;

  /// 左右各做一次（拉伸、单侧激活）
  final bool perSide;
  final int? defaultSets;
  final int? defaultReps;
  final int? defaultSeconds;

  /// 配图宽高比：原有动作 1:1，激活 / 拉伸新图 4:3
  final double imageRatio;

  /// 能否在「按次数 / 按时间」之间切换（距离类除外）
  bool get canSwitchTracking => defaultTrackingType != TrackingType.distanceDuration;

  bool get isTimed => trackingType == TrackingType.duration;

  /// 「按次数」时用的记录方式：默认就是按次数的保持原样，默认按时间的用自重 × 次数。
  TrackingType get repsVariant =>
      defaultTrackingType == TrackingType.duration ? TrackingType.bodyweightReps : defaultTrackingType;

  Exercise withTracking(TrackingType t) => Exercise(
        id: id,
        slug: slug,
        nameZh: nameZh,
        nameEn: nameEn,
        bodyPart: bodyPart,
        primaryMuscles: primaryMuscles,
        secondaryMuscles: secondaryMuscles,
        equipment: equipment,
        trackingType: t,
        defaultTrackingType: defaultTrackingType,
        instructionsZh: instructionsZh,
        imageCount: imageCount,
        kind: kind,
        region: region,
        perSide: perSide,
        defaultSets: defaultSets,
        defaultReps: defaultReps,
        defaultSeconds: defaultSeconds,
        imageRatio: imageRatio,
      );

  EquipmentGroup get equipmentGroup => EquipmentGroup.of(equipment);

  /// 内置动作的图片打包在 App 里：assets/exercises/{slug}_{i}.webp
  String imageAsset(int index) => 'assets/exercises/${slug}_$index.webp';

  factory Exercise.fromJson(Map<String, dynamic> j) => Exercise(
        id: j['id'] as String,
        slug: j['slug'] as String,
        nameZh: j['name_zh'] as String,
        nameEn: j['name_en'] as String?,
        bodyPart: BodyPart.fromKey(j['body_part'] as String),
        primaryMuscles: List<String>.from(j['primary_muscles'] as List),
        secondaryMuscles: List<String>.from(j['secondary_muscles'] as List),
        equipment: j['equipment'] as String?,
        trackingType: TrackingType.fromKey(j['tracking_type'] as String),
        instructionsZh: j['instructions_zh'] as String?,
        imageCount: (j['image_paths'] as List).length,
        kind: ExerciseKind.fromKey(j['kind'] as String?),
        region: ExerciseRegion.fromKey(j['region'] as String?),
        perSide: (j['per_side'] as bool?) ?? false,
        defaultSets: j['default_sets'] as int?,
        defaultReps: j['default_reps'] as int?,
        defaultSeconds: j['default_seconds'] as int?,
        imageRatio: ((j['image_ratio'] as num?) ?? 1).toDouble(),
      );
}
