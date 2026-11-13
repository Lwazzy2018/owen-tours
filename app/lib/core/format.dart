import 'package:intl/intl.dart';

/// South Africa is always UTC+2 (no daylight saving), so times are shown in SAST
/// no matter where the phone is.
const _sastOffset = Duration(hours: 2);

DateTime toSast(DateTime utc) => utc.toUtc().add(_sastOffset);

/// 460000 → "R 4 600.00"
String rand(int cents) {
  final negative = cents < 0;
  final abs = cents.abs();
  final rands = abs ~/ 100;
  final rest = (abs % 100).toString().padLeft(2, '0');
  final digits = rands.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return '${negative ? '-' : ''}R $buffer.$rest';
}

/// Whole rands without cents for compact labels: 460000 → "R 4 600"
String randShort(int cents) {
  final full = rand(cents);
  return full.endsWith('.00') ? full.substring(0, full.length - 3) : full;
}

String formatDate(DateTime utc) => DateFormat('d MMM yyyy').format(toSast(utc));

String formatDateTime(DateTime utc) => DateFormat('d MMM yyyy, HH:mm').format(toSast(utc));

String formatTime(DateTime utc) => DateFormat('HH:mm').format(toSast(utc));

String formatDay(DateTime utc) => DateFormat('EEE d MMM').format(toSast(utc));

/// For "date only" values from the API (yyyy-MM-dd), shown as they are.
String formatDateOnly(String isoDate) => DateFormat('d MMM yyyy').format(DateTime.parse(isoDate));

String toIsoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// Converts a rand amount typed by an admin ("4 600" or "4600.50") to cents.
int? parseRandToCents(String input) {
  final cleaned = input.replaceAll(RegExp(r'[R\s,]'), '');
  if (cleaned.isEmpty) return null;
  final value = double.tryParse(cleaned);
  if (value == null || value < 0) return null;
  return (value * 100).round();
}

String centsToRandInput(int cents) {
  final r = cents / 100;
  return r == r.truncateToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(2);
}

String titleCase(String value) =>
    value.replaceAll('_', ' ').split(' ').where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');

const provinces = [
  'Eastern Cape',
  'Free State',
  'Gauteng',
  'KwaZulu-Natal',
  'Limpopo',
  'Mpumalanga',
  'North West',
  'Northern Cape',
  'Western Cape',
];

const tripCategories = [
  'beach',
  'weekend_getaway',
  'hiking',
  'snow',
  'city',
  'safari',
  'cross_border',
  'youth_camp',
  'day_trip',
  'other',
];
