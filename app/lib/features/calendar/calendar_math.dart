/// 日历的纯函数。周一排在第一列。
library;

/// 某月的格子：前面用 null 补到周一，后面补到整周。
List<DateTime?> monthCells(DateTime month) {
  final first = DateTime(month.year, month.month, 1);
  final days = DateTime(month.year, month.month + 1, 0).day;
  final cells = <DateTime?>[
    for (var i = 0; i < first.weekday - 1; i++) null,
    for (var d = 1; d <= days; d++) DateTime(month.year, month.month, d),
  ];
  while (cells.length % 7 != 0) {
    cells.add(null);
  }
  return cells;
}

String dateKeyOf(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

/// 包含 [d] 在内，前后连着练的总天数（可跨行、跨月）。[d] 本身没练返回 0。
int streakLength(DateTime d, bool Function(DateTime) trained) {
  if (!trained(d)) return 0;
  var n = 1;
  for (var p = DateTime(d.year, d.month, d.day - 1); trained(p); p = DateTime(p.year, p.month, p.day - 1)) {
    n++;
  }
  for (var q = DateTime(d.year, d.month, d.day + 1); trained(q); q = DateTime(q.year, q.month, q.day + 1)) {
    n++;
  }
  return n;
}

const weekdayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

String formatMd(DateTime d) => '${d.month}月${d.day}日 ${weekdayNames[d.weekday - 1]}';

String formatClock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
