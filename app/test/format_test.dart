import 'package:flutter_test/flutter_test.dart';
import 'package:owen_tours/core/format.dart';

void main() {
  test('formats cents as South African rand', () {
    expect(rand(460000), 'R 4 600.00');
    expect(rand(75000), 'R 750.00');
    expect(rand(123456789), 'R 1 234 567.89');
    expect(rand(5), 'R 0.05');
    expect(rand(-100000), '-R 1 000.00');
    expect(randShort(460000), 'R 4 600');
  });

  test('parses admin price input to cents', () {
    expect(parseRandToCents('4600'), 460000);
    expect(parseRandToCents('R 4 600'), 460000);
    expect(parseRandToCents('4600.50'), 460050);
    expect(parseRandToCents(''), isNull);
    expect(parseRandToCents('abc'), isNull);
  });

  test('shows times in South African time regardless of the device', () {
    final utc = DateTime.utc(2027, 7, 9, 2, 0); // 04:00 SAST
    expect(formatTime(utc), '04:00');
    expect(formatDate(utc), '9 Jul 2027');
  });
}
