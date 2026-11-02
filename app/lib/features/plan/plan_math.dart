/// 计划的纯函数：给定循环起始日，算出某天处在循环的第几天。
library;

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime parseDateKey(String key) {
  final p = key.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

/// 返回 0 到 cycleDays-1。起始日之前的日期按同样规律向前推（不会出现负数）。
int planDayIndex({required String startDate, required int cycleDays, required DateTime date}) {
  assert(cycleDays > 0);
  final start = parseDateKey(startDate);
  // 用 UTC 日期相减，避开夏令时造成的 23/25 小时。
  final a = DateTime.utc(start.year, start.month, start.day);
  final b = DateTime.utc(date.year, date.month, date.day);
  final diff = b.difference(a).inDays;
  return ((diff % cycleDays) + cycleDays) % cycleDays;
}

DateTime dateOnly(DateTime d) => _dateOnly(d);

/// [d] 所在那一周的周一（周一到周日算一周）。
DateTime mondayOf(DateTime d) {
  final day = _dateOnly(d);
  return DateTime(day.year, day.month, day.day - (day.weekday - DateTime.monday));
}
