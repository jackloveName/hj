import 'dart:math';

final Random _random = Random();

/// 本地唯一 ID（不依赖任何服务端）
String newId([String prefix = 'id']) {
  final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final rand = _random.nextInt(0x7FFFFFFF).toRadixString(36);
  return '${prefix}_${now}_$rand';
}

String _p2(int value) => value.toString().padLeft(2, '0');

/// 2026-03-01
String fmtDate(DateTime d) => '${d.year}-${_p2(d.month)}-${_p2(d.day)}';

/// 03-01
String fmtMonthDay(DateTime d) => '${_p2(d.month)}-${_p2(d.day)}';

/// 10:24
String fmtTime(DateTime d) => '${_p2(d.hour)}:${_p2(d.minute)}';

/// 2026-03-01 10:24
String fmtDateTime(DateTime d) => '${fmtDate(d)} ${fmtTime(d)}';

/// 2026年3月1日
String fmtDateCn(DateTime d) => '${d.year}年${d.month}月${d.day}日';

/// 2026-03
String monthKey(DateTime d) => '${d.year}-${_p2(d.month)}';

/// 2026年3月
String monthLabel(String key) {
  final parts = key.split('-');
  if (parts.length != 2) return key;
  final month = int.tryParse(parts[1]);
  return month == null ? key : '${parts[0]}年$month月';
}

/// 3月
String monthShortLabel(String key) {
  final parts = key.split('-');
  if (parts.length != 2) return key;
  return '${int.tryParse(parts[1]) ?? parts[1]}月';
}

String fmtMoney(num value, {bool symbol = true}) {
  final text = value == value.roundToDouble()
      ? _withThousands(value.round().toString())
      : _withThousands(value.toStringAsFixed(2));
  return symbol ? '¥$text' : text;
}

String fmtAmount(num value) => value == value.roundToDouble()
    ? value.round().toString()
    : value.toStringAsFixed(2);

String _withThousands(String value) {
  final negative = value.startsWith('-');
  final raw = negative ? value.substring(1) : value;
  final dot = raw.indexOf('.');
  final intPart = dot < 0 ? raw : raw.substring(0, dot);
  final decPart = dot < 0 ? '' : raw.substring(dot);
  final buffer = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write(',');
    buffer.write(intPart[i]);
  }
  return '${negative ? '-' : ''}$buffer$decPart';
}

DateTime parseDate(String? value, {DateTime? fallback}) {
  if (value == null || value.isEmpty) return fallback ?? DateTime.now();
  return DateTime.tryParse(value) ?? (fallback ?? DateTime.now());
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

int daysBetween(DateTime a, DateTime b) =>
    dateOnly(b).difference(dateOnly(a)).inDays;

int daysFromToday(DateTime target) => daysBetween(DateTime.now(), target);

/// 从某天到今天过了多少天（已入住天数）
int daysSince(DateTime start) => daysBetween(start, DateTime.now());

/// 入住时长文案：还没到入住日显示「距入住 N 天」，当天显示「今天入住」
String stayDurationLabel(DateTime moveInDate, {DateTime? now}) {
  final days = daysBetween(moveInDate, now ?? DateTime.now());
  if (days == 0) return '今天入住';
  return days < 0 ? '距入住 ${-days} 天' : '已入住 $days 天';
}

String relativeDays(int days) {
  if (days < 0) return '已逾期 ${-days} 天';
  if (days == 0) return '就是今天';
  if (days == 1) return '明天';
  return '$days 天后';
}

const List<String> _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

String weekdayCn(DateTime d) => '周${_weekdays[d.weekday - 1]}';

/// 距离下一次「每月几号」交租还有几天
DateTime nextRentDue(int rentDueDay, {DateTime? from}) {
  final now = dateOnly(from ?? DateTime.now());
  final day = rentDueDay.clamp(1, 28);
  var candidate = DateTime(now.year, now.month, day);
  if (candidate.isBefore(now)) {
    candidate = DateTime(now.year, now.month + 1, day);
  }
  return candidate;
}

/// 该月有几天
int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// 该月 1 号是周几（1=周一）
int firstWeekdayOfMonth(int year, int month) =>
    DateTime(year, month, 1).weekday;

/// 相对上月的变化百分比描述，如「9 月偏高 19%」
String trendNote(List<double> values) {
  if (values.length < 2) return '';
  final current = values.last;
  final previous = values[values.length - 2];
  if (previous <= 0) return '';
  final diff = (current - previous) / previous * 100;
  if (diff.abs() < 1) return '较上月基本持平';
  return diff > 0 ? '较上月偏高 ${diff.round()}%' : '较上月下降 ${diff.abs().round()}%';
}
