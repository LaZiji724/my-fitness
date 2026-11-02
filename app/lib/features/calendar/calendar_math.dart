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

const weekdayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

String formatMd(DateTime d) => '${d.month}月${d.day}日 ${weekdayNames[d.weekday - 1]}';

String formatClock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
