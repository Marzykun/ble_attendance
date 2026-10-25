"""Checks teacher.py reads the same bytes the Flutter app sends.

    tools\\.venv\\Scripts\\python tools\\test_teacher.py
"""

from student import parse_teacher, student_payload
from teacher import parse_student, teacher_payload

# What studentPayload(0xCAFEBABE, 0x01020304, '22CS101', 'Aditya Kumar Nath')
# produces in lib/protocol.dart: cut to 24 bytes, so the name is truncated.
student = b"S\xca\xfe\xba\xbe\x01\x02\x03\x04" + b"22CS101|Aditya "
assert len(student) == 24
assert parse_student(student) == (0xCAFEBABE, 0x01020304, "22CS101", "Aditya ")
assert parse_student(teacher_payload(1)) is None
assert parse_student(b"S\x00\x00\x00\x01\x00\x00\x00\x02|NoRoll") is None
assert teacher_payload(0xDEADBEEF) == b"T\xde\xad\xbe\xef"
assert teacher_payload(0xDEADBEEF, "22CS101") == b"T\xde\xad\xbe\xef22CS101"

# student.py builds the same bytes as the app's studentPayload.
assert student_payload(0xCAFEBABE, 0x01020304, "22CS101", "Aditya Kumar Nath") == student
assert parse_teacher(teacher_payload(7, "208")) == (7, "208")
assert parse_teacher(teacher_payload(7)) == (7, "")
assert parse_teacher(student) is None
print("ok")
