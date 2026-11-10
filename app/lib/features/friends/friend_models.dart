/// 好友功能的数据模型。都是从云端读来的只读数据，不进本地数据库。
library;

/// 我和某个人的关系。
enum FriendRelation {
  none,
  friend,

  /// 我已经向对方发了申请
  outgoing,

  /// 对方向我发了申请
  incoming,

  /// 就是我自己（扫到自己的二维码）
  self;

  static FriendRelation parse(String? s) => switch (s) {
        'friend' => friend,
        'outgoing' => outgoing,
        'incoming' => incoming,
        'self' => self,
        _ => none,
      };
}

/// 一个用户的公开资料。
class UserCard {
  const UserCard({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarKind = 'preset',
    this.avatarRef = 'avatar_01',
    this.relation = FriendRelation.none,
  });

  final String id;
  final String username;
  final String displayName;
  final String avatarKind;
  final String avatarRef;
  final FriendRelation relation;

  factory UserCard.fromJson(Map<String, dynamic> j, {String idKey = 'id'}) => UserCard(
        id: j[idKey] as String,
        username: (j['username'] as String?) ?? '',
        displayName: (j['display_name'] as String?)?.trim().isNotEmpty == true ? j['display_name'] as String : (j['username'] as String?) ?? '',
        avatarKind: (j['avatar_kind'] as String?) ?? 'preset',
        avatarRef: (j['avatar_ref'] as String?) ?? 'avatar_01',
        relation: FriendRelation.parse(j['relation'] as String?),
      );

  UserCard withRelation(FriendRelation r) => UserCard(
        id: id,
        username: username,
        displayName: displayName,
        avatarKind: avatarKind,
        avatarRef: avatarRef,
        relation: r,
      );
}

/// 好友列表里的一行：好友或一条申请，带最后一条消息和未读数。
class FriendEntry {
  const FriendEntry({
    required this.friendshipId,
    required this.user,
    required this.since,
    this.lastBody,
    this.lastAt,
    this.lastFromMe = false,
    this.unread = 0,
  });

  final String friendshipId;
  final UserCard user;

  /// 成为好友（或发出申请）的时间
  final DateTime since;
  final String? lastBody;
  final DateTime? lastAt;
  final bool lastFromMe;
  final int unread;

  FriendRelation get relation => user.relation;

  factory FriendEntry.fromJson(Map<String, dynamic> j) => FriendEntry(
        friendshipId: j['friendship_id'] as String,
        user: UserCard.fromJson(j, idKey: 'user_id'),
        since: DateTime.parse(j['since'] as String).toLocal(),
        lastBody: j['last_body'] as String?,
        lastAt: j['last_at'] == null ? null : DateTime.parse(j['last_at'] as String).toLocal(),
        lastFromMe: (j['last_from_me'] as bool?) ?? false,
        unread: (j['unread'] as num?)?.toInt() ?? 0,
      );

  FriendEntry copyWith({String? lastBody, DateTime? lastAt, bool? lastFromMe, int? unread}) => FriendEntry(
        friendshipId: friendshipId,
        user: user,
        since: since,
        lastBody: lastBody ?? this.lastBody,
        lastAt: lastAt ?? this.lastAt,
        lastFromMe: lastFromMe ?? this.lastFromMe,
        unread: unread ?? this.unread,
      );
}

enum MessageStatus { sent, sending, failed }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.body,
    required this.createdAt,
    this.status = MessageStatus.sent,
  });

  final String id;
  final String senderId;
  final String receiverId;
  final String body;
  final DateTime createdAt;
  final MessageStatus status;

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        senderId: j['sender_id'] as String,
        receiverId: j['receiver_id'] as String,
        body: (j['body'] as String?) ?? '',
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      );

  ChatMessage withStatus(MessageStatus s, {DateTime? createdAt}) => ChatMessage(
        id: id,
        senderId: senderId,
        receiverId: receiverId,
        body: body,
        createdAt: createdAt ?? this.createdAt,
        status: s,
      );
}

/// 隐私设置：好友能看到我的哪些运动数据。
class PrivacySettings {
  const PrivacySettings({
    this.historyDays = 30,
    this.showWorkouts = true,
    this.showDuration = true,
    this.showExercises = true,
    this.showVolume = true,
    this.showBodyWeight = false,
  });

  /// 默认值：训练相关的公开，体重不公开。和数据库里的默认值保持一致。
  static const defaults = PrivacySettings();

  /// 可选的时间范围；0 = 全部
  static const dayOptions = [7, 30, 90, 0];

  final int historyDays;
  final bool showWorkouts;
  final bool showDuration;
  final bool showExercises;
  final bool showVolume;
  final bool showBodyWeight;

  factory PrivacySettings.fromJson(Map<String, dynamic> j) => PrivacySettings(
        historyDays: (j['history_days'] as num?)?.toInt() ?? 30,
        showWorkouts: (j['show_workouts'] as bool?) ?? true,
        showDuration: (j['show_duration'] as bool?) ?? true,
        showExercises: (j['show_exercises'] as bool?) ?? true,
        showVolume: (j['show_volume'] as bool?) ?? true,
        showBodyWeight: (j['show_body_weight'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'history_days': historyDays,
        'show_workouts': showWorkouts,
        'show_duration': showDuration,
        'show_exercises': showExercises,
        'show_volume': showVolume,
        'show_body_weight': showBodyWeight,
      };

  PrivacySettings copyWith({
    int? historyDays,
    bool? showWorkouts,
    bool? showDuration,
    bool? showExercises,
    bool? showVolume,
    bool? showBodyWeight,
  }) =>
      PrivacySettings(
        historyDays: historyDays ?? this.historyDays,
        showWorkouts: showWorkouts ?? this.showWorkouts,
        showDuration: showDuration ?? this.showDuration,
        showExercises: showExercises ?? this.showExercises,
        showVolume: showVolume ?? this.showVolume,
        showBodyWeight: showBodyWeight ?? this.showBodyWeight,
      );

  @override
  bool operator ==(Object other) =>
      other is PrivacySettings &&
      other.historyDays == historyDays &&
      other.showWorkouts == showWorkouts &&
      other.showDuration == showDuration &&
      other.showExercises == showExercises &&
      other.showVolume == showVolume &&
      other.showBodyWeight == showBodyWeight;

  @override
  int get hashCode => Object.hash(historyDays, showWorkouts, showDuration, showExercises, showVolume, showBodyWeight);
}

String historyDaysLabel(int days) => days == 0 ? '全部' : '$days 天';

/// 扫一扫用的随机码。
class FriendCode {
  const FriendCode({required this.code, required this.expiresAt});
  final String code;
  final DateTime expiresAt;

  static const _prefix = 'myfit://friend/';

  /// 二维码里的内容
  String get payload => '$_prefix$code';

  /// 从扫到的内容里取出随机码；不是本应用的二维码返回 null。
  static String? parse(String? raw) {
    final s = raw?.trim() ?? '';
    if (!s.startsWith(_prefix)) return null;
    final code = s.substring(_prefix.length);
    return RegExp(r'^[0-9a-f]{32}$').hasMatch(code) ? code : null;
  }
}

/// 好友的一组记录（对方公开了具体运动量时才有）。
class FriendSet {
  const FriendSet({this.kind = 'normal', this.weightKg, this.reps, this.durationSec, this.distanceM});
  final String kind;
  final double? weightKg;
  final int? reps;
  final int? durationSec;
  final double? distanceM;

  factory FriendSet.fromJson(Map<String, dynamic> j) => FriendSet(
        kind: (j['kind'] as String?) ?? 'normal',
        weightKg: (j['weight_kg'] as num?)?.toDouble(),
        reps: (j['reps'] as num?)?.toInt(),
        durationSec: (j['duration_sec'] as num?)?.toInt(),
        distanceM: (j['distance_m'] as num?)?.toDouble(),
      );
}

class FriendExercise {
  const FriendExercise({required this.name, this.bodyPart = 'other', this.sets});
  final String name;
  final String bodyPart;

  /// null = 对方没有公开具体运动量
  final List<FriendSet>? sets;

  factory FriendExercise.fromJson(Map<String, dynamic> j) => FriendExercise(
        name: (j['name'] as String?) ?? '',
        bodyPart: (j['body_part'] as String?) ?? 'other',
        sets: (j['sets'] as List?)?.map((e) => FriendSet.fromJson((e as Map).cast<String, dynamic>())).toList(),
      );
}

class FriendWorkout {
  const FriendWorkout({
    required this.id,
    required this.localDate,
    this.name,
    this.durationMin,
    this.setCount,
    this.volumeKg,
    this.exercises,
  });

  final String id;

  /// yyyy-MM-dd
  final String localDate;
  final String? name;

  /// 以下几项为 null 表示对方没有公开
  final int? durationMin;
  final int? setCount;
  final double? volumeKg;
  final List<FriendExercise>? exercises;

  DateTime get date => DateTime.parse(localDate);

  factory FriendWorkout.fromJson(Map<String, dynamic> j) => FriendWorkout(
        id: j['id'] as String,
        localDate: j['local_date'] as String,
        name: j['name'] as String?,
        durationMin: (j['duration_min'] as num?)?.toInt(),
        setCount: (j['set_count'] as num?)?.toInt(),
        volumeKg: (j['volume_kg'] as num?)?.toDouble(),
        exercises: (j['exercises'] as List?)?.map((e) => FriendExercise.fromJson((e as Map).cast<String, dynamic>())).toList(),
      );
}

class WeightPoint {
  const WeightPoint(this.date, this.weightKg);
  final DateTime date;
  final double weightKg;
}

/// 好友公开给我看的运动记录。
class FriendActivity {
  const FriendActivity({required this.settings, this.workouts, this.bodyWeight});

  /// 对方的隐私设置（决定了下面哪些有内容）
  final PrivacySettings settings;

  /// null = 对方没有公开训练记录
  final List<FriendWorkout>? workouts;

  /// null = 对方没有公开体重
  final List<WeightPoint>? bodyWeight;

  factory FriendActivity.fromJson(Map<String, dynamic> j) => FriendActivity(
        settings: PrivacySettings.fromJson(j),
        workouts: (j['workouts'] as List?)?.map((e) => FriendWorkout.fromJson((e as Map).cast<String, dynamic>())).toList(),
        bodyWeight: (j['body_weight'] as List?)
            ?.map((e) => WeightPoint(DateTime.parse((e as Map)['date'] as String), (e['weight_kg'] as num).toDouble()))
            .toList(),
      );
}

/// 给用户看的错误。
class FriendsException implements Exception {
  const FriendsException(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => message;
}
