import 'package:ble_attendance/protocol.dart';
import 'package:ble_attendance/roster.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('teacher payload round-trips', () {
    expect(parseTeacher(teacherPayload(0xDEADBEEF)), (session: 0xDEADBEEF, ack: ''));
    expect(
      parseTeacher(teacherPayload(7, '22CS101')),
      (session: 7, ack: '22CS101'),
    );
    expect(teacherPayload(7, '1234567890').length, lessThanOrEqualTo(kMaxPayload));
    expect(parseTeacher(studentPayload(1, 2, 'A1', 'Bo')), isNull);
  });

  test('student payload round-trips and fits in one advertisement', () {
    final p = studentPayload(0xCAFEBABE, 0x01020304, '22CS101', 'Aditya Kumar Nath');
    expect(p.length, lessThanOrEqualTo(kMaxPayload));
    final s = parseStudent(p)!;
    expect(s.session, 0xCAFEBABE);
    expect(s.device, 0x01020304);
    expect(s.roll, '22CS101');
    expect(s.name, startsWith('Aditya'));
    expect(parseStudent(teacherPayload(1)), isNull);
  });

  test('longest roll number still fits', () {
    final s = parseStudent(studentPayload(1, 2, '1234567890', 'Name'))!;
    expect(s.roll, '1234567890');
  });

  test('roster parses pasted CSV or spreadsheet rows', () {
    final roster = parseRoster(
      'Roll,Name\n22CS101, Aditya Kumar\n\n22CS102\tPriya S\nbad line\n,No roll\n',
    );
    expect(roster, {'22CS101': 'Aditya Kumar', '22CS102': 'Priya S'});
    expect(parseRoster(formatRoster(roster)), roster);
  });
}
