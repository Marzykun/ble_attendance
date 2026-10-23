import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// 0xFFFF is the company ID the Bluetooth SIG reserves for testing.
const kManufacturerId = 0xFFFF;

const _teacherTag = 0x54; // 'T'
const _studentTag = 0x53; // 'S'

/// A legacy BLE advertisement is 31 bytes. Flags (3) and the manufacturer
/// header (4) leave 24 bytes for our payload.
const kMaxPayload = 24;
const kMaxRollLength = 10;

/// Random 32-bit value, used for session codes and per-install phone IDs.
int randomId() => Random.secure().nextInt(1 << 32);

/// Session code (4 bytes) + optionally the roll number being acknowledged.
/// The teacher rotates the ack through students still broadcasting, so each
/// one learns it was marked present.
Uint8List teacherPayload(int session, [String ack = '']) =>
    Uint8List.fromList([_teacherTag, ..._u32(session), ...utf8.encode(ack)]);

/// Session code (4 bytes) + phone ID (4 bytes) + "roll|name", with the name
/// cut to fit.
Uint8List studentPayload(int session, int device, String roll, String name) {
  final bytes = [
    _studentTag,
    ..._u32(session),
    ..._u32(device),
    ...utf8.encode('$roll|$name'),
  ];
  return Uint8List.fromList(bytes.take(kMaxPayload).toList());
}

({int session, String ack})? parseTeacher(List<int> d) =>
    d.length >= 5 && d[0] == _teacherTag
        ? (
            session: _readU32(d, 1),
            ack: utf8.decode(d.sublist(5), allowMalformed: true),
          )
        : null;

({int session, int device, String roll, String name})? parseStudent(
    List<int> d) {
  if (d.length < 10 || d[0] != _studentTag) return null;
  final text = utf8.decode(d.sublist(9), allowMalformed: true);
  final sep = text.indexOf('|');
  if (sep <= 0) return null;
  return (
    session: _readU32(d, 1),
    device: _readU32(d, 5),
    roll: text.substring(0, sep),
    name: text.substring(sep + 1),
  );
}

List<int> _u32(int v) => [v >> 24 & 0xFF, v >> 16 & 0xFF, v >> 8 & 0xFF, v & 0xFF];

int _readU32(List<int> d, int at) =>
    d[at] << 24 | d[at + 1] << 16 | d[at + 2] << 8 | d[at + 3];
