DateTime dateOnly(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);
String isoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
DateTime? parseDate(Object? value) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return null;
  }
  final parsed = DateTime.tryParse(value);
  return parsed != null && isoDate(parsed) == value ? dateOnly(parsed) : null;
}

String displayDate(Object? value) {
  if (value == null) return '—';
  final date = DateTime.tryParse(value.toString());
  return date == null
      ? '—'
      : '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
}

String money(Object? value) {
  final number = (value is num ? value : num.tryParse('$value')) ?? 0;
  final parts = number
      .toStringAsFixed(number == number.roundToDouble() ? 0 : 2)
      .split('.');
  final digits = parts.first.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]} ',
  );
  return '$digits${parts.length == 2 ? ',${parts[1]}' : ''} ₽';
}

// All pickup points operate in Moscow (UTC+3), independent of the browser time zone.
DateTime businessToday([DateTime? instant]) =>
    dateOnly((instant ?? DateTime.now()).toUtc().add(const Duration(hours: 3)));
