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

/// 器械筛选分组：数据里的英文器械归到页面上的 6 个中文分组。
enum EquipmentGroup {
  all('all', '全部'),
  barbell('barbell', '杠铃'),
  dumbbell('dumbbell', '哑铃'),
  machine('machine', '器械'),
  cable('cable', '绳索'),
  bodyweight('bodyweight', '自重'),
  other('other', '拉伸');

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
  });

  final String id;
  final String slug;
  final String nameZh;
  final String? nameEn;
  final BodyPart bodyPart;
  final List<String> primaryMuscles;
  final List<String> secondaryMuscles;
  final String? equipment;
  final TrackingType trackingType;
  final String? instructionsZh;
  final int imageCount;

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
      );
}
