"""Laptop stand-in for the teacher's phone (Windows only).

Broadcasts a session code over the laptop's Bluetooth and lists the students
whose phones answer with it, exactly like the app's teacher mode.
Byte format must match lib/protocol.dart.

    tools\\.venv\\Scripts\\python tools\\teacher.py [--min-rssi -75] [--csv out.csv]

Stop with Ctrl+C.
"""

import argparse
import asyncio
import csv
import secrets
import struct
import time
from datetime import datetime

from bleak import BleakScanner
from winrt.windows.devices.bluetooth.advertisement import (
    BluetoothLEAdvertisementPublisher,
    BluetoothLEAdvertisementPublisherStatus,
    BluetoothLEManufacturerData,
)
from winrt.windows.storage.streams import DataWriter

MANUFACTURER_ID = 0xFFFF  # Bluetooth SIG test ID, same as the app


ACK_ROTATE_S = 1  # each still-broadcasting student gets the ack slot in turn
ACK_WINDOW_S = 5  # a student not heard for this long got their ack and stopped


def teacher_payload(session: int, ack: str = "") -> bytes:
    return b"T" + struct.pack(">I", session) + ack.encode()


def parse_student(data: bytes):
    """Returns (session, device, roll, name) or None."""
    if len(data) < 10 or data[0] != ord("S"):
        return None
    session, device = struct.unpack(">II", data[1:9])
    roll, sep, name = data[9:].decode("utf-8", errors="replace").partition("|")
    if not sep or not roll:
        return None
    return session, device, roll, name


async def start_publisher(payload: bytes) -> BluetoothLEAdvertisementPublisher:
    writer = DataWriter()
    writer.write_bytes(payload)
    md = BluetoothLEManufacturerData()
    md.company_id = MANUFACTURER_ID
    md.data = writer.detach_buffer()

    publisher = BluetoothLEAdvertisementPublisher()
    publisher.advertisement.manufacturer_data.append(md)
    publisher.start()
    # Status updates asynchronously.
    for _ in range(40):
        if publisher.status not in (BluetoothLEAdvertisementPublisherStatus.CREATED,
                                    BluetoothLEAdvertisementPublisherStatus.WAITING):
            break
        await asyncio.sleep(0.05)
    if publisher.status != BluetoothLEAdvertisementPublisherStatus.STARTED:
        raise RuntimeError(
            f"Windows refused to broadcast (status {publisher.status.name}). "
            "Is Bluetooth on?"
        )
    return publisher


async def run(min_rssi: int, present: dict) -> None:
    session = secrets.randbits(32)
    publisher = await start_publisher(teacher_payload(session))
    too_weak = set()

    def on_advertisement(_device, adv):
        data = adv.manufacturer_data.get(MANUFACTURER_ID)
        student = parse_student(data) if data else None
        # A different session code means an old or replayed broadcast.
        if not student or student[0] != session:
            return
        # shortcut: no class list or phone binding here; the app's teacher mode has them.
        _, _, roll, name = student
        if roll in present:
            present[roll]["rssi"] = adv.rssi
            present[roll]["seen"] = time.monotonic()
        elif adv.rssi < min_rssi:
            if roll not in too_weak:
                too_weak.add(roll)
                print(f"  ignored  {roll:<10} {name:<20} {adv.rssi} dBm (too weak)")
        else:
            present[roll] = {"name": name, "time": datetime.now(),
                             "rssi": adv.rssi, "seen": time.monotonic()}
            print(f"PRESENT    {roll:<10} {name:<20} {adv.rssi} dBm")

    async def rotate_acks():
        nonlocal publisher
        current, turn = "", 0
        while True:
            await asyncio.sleep(ACK_ROTATE_S)
            now = time.monotonic()
            waiting = sorted(r for r, a in present.items() if now - a["seen"] < ACK_WINDOW_S)
            ack = waiting[turn % len(waiting)] if waiting else ""
            turn += 1
            if ack != current:
                publisher.stop()
                publisher = await start_publisher(teacher_payload(session, ack))
                current = ack

    print(f"Session {session:X} started. Min signal {min_rssi} dBm. Ctrl+C to stop.")
    try:
        async with BleakScanner(on_advertisement):
            await rotate_acks()
    finally:
        publisher.stop()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--min-rssi", type=int, default=-75,
                        help="weaker signals count as outside the room (dBm)")
    parser.add_argument("--csv", help="save the attendance list here on exit")
    args = parser.parse_args()

    present = {}
    try:
        asyncio.run(run(args.min_rssi, present))
    except KeyboardInterrupt:
        pass

    print(f"\n{len(present)} present.")
    if args.csv:
        with open(args.csv, "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(["roll", "name", "time", "rssi"])
            for roll, a in sorted(present.items()):
                w.writerow([roll, a["name"], a["time"].isoformat(timespec="seconds"), a["rssi"]])
        print(f"Saved {args.csv}")


if __name__ == "__main__":
    main()
