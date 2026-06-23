#!/usr/bin/env python3
"""
stream_receiver.py — Receives time-sync packets from ScanCapture iOS app over USB cable.

All sensor data (IMU, GPS, camera, poses, barometer, Bluetooth) is saved directly on
the iPhone. This receiver only records a (pc_timestamp_us, phone_timestamp_us) mapping
so you can align iPhone timestamps with PC wall-clock time in post-processing.

Setup (run once):
    brew install libimobiledevice

Usage:
    # Terminal 1 — keep running while the iOS app is connected via USB:
    iproxy 12345 12345

    # Terminal 2 — start the receiver:
    python3 stream_receiver.py [--host 127.0.0.1] [--port 12345] [--output ./output]

    Press Ctrl+C to send STOP to the iOS app and exit.

Output:
    output/<timestamp>/timesync.txt
        Columns: pc_timestamp_us, phone_timestamp_us
        pc_timestamp_us   — PC wall-clock Unix time in microseconds
        phone_timestamp_us — iPhone time since last boot in microseconds

    To convert phone timestamps to PC time in post-processing:
        import numpy as np
        data = np.loadtxt('timesync.txt', delimiter=',', comments='#')
        pc_ts, phone_ts = data[:,0], data[:,1]
        # linear fit: pc = a * phone + b
        a, b = np.polyfit(phone_ts, pc_ts, 1)
        # apply to any sensor file:
        sensor_pc_ts = a * sensor_phone_ts + b
"""

import argparse
import os
import signal
import socket
import sys
import time
from pathlib import Path

from packet_defs import (
    HEADER_SIZE,
    PacketType,
    build_command,
    parse_header,
    parse_session_start,
    parse_timesync,
)


def pc_timestamp_us() -> int:
    """Current PC wall-clock time in microseconds (Unix epoch)."""
    return time.time_ns() // 1000


class StreamReceiver:
    def __init__(self, host: str, port: int, out_dir: str):
        self.host = host
        self.port = port
        self.out_dir = Path(out_dir)
        self.sock: socket.socket | None = None
        self.running = False
        self.timesync_file = None
        self.sync_count = 0

    # ------------------------------------------------------------------
    # Connection
    # ------------------------------------------------------------------

    def connect(self):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        self.sock.connect((self.host, self.port))
        print(f"[receiver] Connected to iOS app at {self.host}:{self.port}")

    def _recv_exactly(self, n: int) -> bytes:
        buf = b''
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                raise ConnectionError("iOS app disconnected")
            buf += chunk
        return buf

    def send_command(self, cmd: int, fps: int | None = None):
        self.sock.sendall(build_command(cmd, fps=fps))

    # ------------------------------------------------------------------
    # Main loop
    # ------------------------------------------------------------------

    def run(self, fps: int | None = None):
        self.running = True
        signal.signal(signal.SIGINT, self._handle_sigint)

        print("[receiver] Sending START command…")
        self.send_command(PacketType.CMD_START, fps=fps)
        print("[receiver] Waiting for session data…")

        while self.running:
            try:
                header_bytes = self._recv_exactly(HEADER_SIZE)
                hdr = parse_header(header_bytes)
            except ConnectionError as e:
                print(f"[receiver] {e}")
                break
            except ValueError as e:
                print(f"[receiver] Protocol error: {e} — trying to re-sync")
                continue

            recv_ts = pc_timestamp_us()
            ptype = hdr['type']
            payload = self._recv_exactly(hdr['payload_len']) if hdr['payload_len'] > 0 else b''

            self._dispatch(ptype, payload, recv_ts)

        self._close_files()
        self._print_stats()

    def _dispatch(self, ptype: int, payload: bytes, recv_ts: int):
        if ptype == PacketType.SESSION_START:
            self._on_session_start(payload)

        elif ptype == PacketType.SESSION_END:
            print("[receiver] Session ended by iOS app.")
            self.running = False

        elif ptype == PacketType.ACK:
            ok = (payload[0] == 0x00) if payload else False
            print(f"[receiver] ACK: {'OK' if ok else 'ERROR'}")

        elif ptype == PacketType.DATA_TIMESYNC:
            if self.timesync_file is None:
                return
            d = parse_timesync(payload)
            self.timesync_file.write(f"{d['phone_ts']}, {recv_ts}\n")
            self.sync_count += 1
            if self.sync_count % 300 == 0:  # every ~10 seconds at 30fps
                print(f"[receiver] {self.sync_count} sync packets received")

    # ------------------------------------------------------------------
    # Session lifecycle
    # ------------------------------------------------------------------

    def _on_session_start(self, payload: bytes):
        info = parse_session_start(payload)
        ts = time.strftime("%Y-%m-%d_%H.%M.%S")
        self.out_dir.mkdir(parents=True, exist_ok=True)
        self.sync_count = 0

        csv_path = self.out_dir / f'timesync_{ts}.csv'
        self.timesync_file = open(csv_path, 'w', buffering=1)
        self.timesync_file.write("phone_timestamp_us,pc_timestamp_us\n")

        print(f"[receiver] Session started — device: {info['device_name']}, "
              f"{info['img_w']}×{info['img_h']} @ {info['fps']:.1f} FPS")
        print(f"[receiver] Saving timesync to {csv_path}")
        print(f"[receiver] All sensor data is saved on the iPhone.")

    def stop(self):
        if self.sock and self.running:
            print("\n[receiver] Sending STOP command…")
            try:
                self.send_command(PacketType.CMD_STOP)
            except OSError:
                pass
        self.running = False

    def _handle_sigint(self, sig, frame):
        self.stop()

    def _close_files(self):
        if self.timesync_file:
            self.timesync_file.close()
            self.timesync_file = None

    def _print_stats(self):
        print(f"[receiver] {self.sync_count} sync packets recorded.")


# ------------------------------------------------------------------
# Entry point
# ------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description='ScanCapture time-sync receiver',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__)
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=12345)
    _default_output = os.path.join(os.path.dirname(__file__), "..", "results", "iphone")
    parser.add_argument('--output', default=_default_output)
    args = parser.parse_args()

    rx = StreamReceiver(args.host, args.port, args.output)
    try:
        rx.connect()
    except ConnectionRefusedError:
        print(f"[receiver] ERROR: Could not connect to {args.host}:{args.port}")
        print("[receiver] Make sure iproxy is running:  iproxy 12345 12345")
        print("[receiver] And the ScanCapture app is open on the connected iPhone.")
        sys.exit(1)

    rx.run(fps=30)


if __name__ == '__main__':
    main()
