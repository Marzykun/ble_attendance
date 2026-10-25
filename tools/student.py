"""Laptop stand-in for a student's phone (Windows only), to test the app's teacher mode.

Finds the teacher's session code, broadcasts this roll number with it and waits
for the teacher to acknowledge it, like the app's student mode minus the
fingerprint check. Byte format must match lib/protocol.dart.

    tools\\.venv\\Scripts\\python tools\\student.py <roll> <name>
"""

import argparse
import asyncio
import struct
import zlib

from bleak import BleakScanner

from teacher import MANUFACTURER_ID, start_publisher

MAX_PAYLOAD = 24
FIND_TEACHER_S = 20
WAIT_ACK_S = 60


def student_payload(session: int, device: int, roll: str, name: str) -> bytes:
    return (b"S" + struct.pack(">II", session, device) + f"{roll}|{name}".encode())[:MAX_PAYLOAD]


def parse_teacher(data: bytes):
    """Returns (session, ack) or None."""
    if len(data) < 5 or data[0] != ord("T"):
        return None
    (session,) = struct.unpack(">I", data[1:5])
    return session, data[5:].decode("utf-8", errors="replace")


async def run(roll: str, name: str) -> bool:
    # Same ID every run for this roll, so the teacher's phone binding stays valid.
    device = zlib.crc32(f"laptop:{roll}".encode())
    teachers: asyncio.Queue = asyncio.Queue()

    def on_adv(_device, adv):
        data = adv.manufacturer_data.get(MANUFACTURER_ID)
        teacher = parse_teacher(data) if data else None
        if teacher:
            teachers.put_nowait((*teacher, adv.rssi))

    async with BleakScanner(on_adv):
        print("Looking for the teacher...")
        try:
            session, _, rssi = await asyncio.wait_for(teachers.get(), FIND_TEACHER_S)
        except asyncio.TimeoutError:
            print("Teacher not found. Is a session running on the teacher's phone?")
            return False
        print(f"Found session {session:X} at {rssi} dBm. Sending roll {roll}...")

        publisher = await start_publisher(student_payload(session, device, roll, name))
        try:
            async def acked():
                while True:
                    s, ack, _ = await teachers.get()
                    if s == session and ack == roll:
                        return
            await asyncio.wait_for(acked(), WAIT_ACK_S)
            print("Present marked.")
            return True
        except asyncio.TimeoutError:
            print("No confirmation from the teacher. Lower its Min signal or move closer.")
            return False
        finally:
            publisher.stop()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("roll", help="roll number, at most 10 characters")
    parser.add_argument("name")
    args = parser.parse_args()
    if not 0 < len(args.roll) <= 10 or "|" in args.roll:
        parser.error("roll must be 1-10 characters without '|'")
    raise SystemExit(0 if asyncio.run(run(args.roll, args.name)) else 1)


if __name__ == "__main__":
    main()
