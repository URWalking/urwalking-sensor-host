#!/usr/bin/env python3
"""PC-side receivers for the urwalking sensor library, run over a USB
adb-reverse tunnel (default) or Wi-Fi (--host 0.0.0.0 --no-adb).
Runs two independent servers concurrently. The wire format is described in
docs/protocol.md.
"""

import argparse
import csv
import io
import json
import os
import socket
import subprocess
import tarfile
import threading
import time
from datetime import datetime

from data_processor import build_combined_outputs

STOP_SEND_PORT = 5000
STREAM_PORT = 5001

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "results", "android")
STOP_SEND_OUTPUT_DIR = OUTPUT_DIR
STREAM_LOG_FILE = os.path.join(OUTPUT_DIR, "timestamps.csv")

ADB_RETRY_DELAY_SECONDS = 3
HOST = "127.0.0.1"
USE_ADB = True


def ensure_adb_reverse(port: int, label: str) -> None:
    """Retries `adb reverse` for `port` until it succeeds. Runs forever in
    the background so a device plugged in after this script starts (or a
    USB reconnect) still gets picked up."""
    if not USE_ADB:
        return
    while True:
        try:
            subprocess.run(
                ["adb", "reverse", f"tcp:{port}", f"tcp:{port}"],
                check=True,
                capture_output=True,
            )
            print(f"[{label}] adb reverse tunnel established on port {port}")
            return
        except FileNotFoundError:
            print(f"[{label}] adb not found on PATH - retrying in {ADB_RETRY_DELAY_SECONDS}s")
        except subprocess.CalledProcessError as e:
            print(
                f"[{label}] adb reverse failed, retrying in "
                f"{ADB_RETRY_DELAY_SECONDS}s: {e.stderr.decode().strip()}"
            )
        time.sleep(ADB_RETRY_DELAY_SECONDS)


def recv_exact(conn: socket.socket, n: int) -> bytes:
    buf = b""
    while len(buf) < n:
        packet = conn.recv(min(4096, n - len(buf)))
        if not packet:
            break
        buf += packet
    return buf


def run_stop_and_send_server() -> None:
    label = "StopAndSend"
    ensure_adb_reverse(STOP_SEND_PORT, label)
    os.makedirs(STOP_SEND_OUTPUT_DIR, exist_ok=True)

    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server_socket.bind((HOST, STOP_SEND_PORT))
    server_socket.listen(1)
    print(f"[{label}] Listening on {HOST}:{STOP_SEND_PORT} - waiting for app to connect...")

    while True:
        conn, addr = server_socket.accept()
        print(f"[{label}] Connected: {addr}")
        try:
            tar_size = int.from_bytes(recv_exact(conn, 8), byteorder="big")
            if tar_size == 0:
                print(f"[{label}] Received an empty transfer, nothing to extract.")
                conn.sendall(b"OK")
                continue

            tar_data = recv_exact(conn, tar_size)
            if len(tar_data) < tar_size:
                message = f"Connection closed early ({len(tar_data)}/{tar_size} bytes received)."
                print(f"[{label}] {message}")
                conn.sendall(f"ERROR: {message}".encode())
                continue

            with tarfile.open(fileobj=io.BytesIO(tar_data), mode="r:") as tar:
                members = tar.getnames()
                tar.extractall(path=STOP_SEND_OUTPUT_DIR)
            print(f"[{label}] Extracted {tar_size} bytes to {STOP_SEND_OUTPUT_DIR}")

            csv_members = [m for m in members if m.endswith(".csv") and "/" not in m]
            if csv_members:
                combined_dir = os.path.join(STOP_SEND_OUTPUT_DIR, "combined")
                try:
                    build_combined_outputs(
                        [os.path.join(STOP_SEND_OUTPUT_DIR, m) for m in csv_members],
                        combined_dir,
                        label,
                    )
                except Exception as e:
                    print(f"[{label}] Failed to build combined CSVs: {e}")

            conn.sendall(b"OK")
        except Exception as e:
            print(f"[{label}] Error receiving data: {e}")
            try:
                conn.sendall(f"ERROR: {e}".encode())
            except OSError:
                pass
        finally:
            conn.close()
            print(f"[{label}] Disconnected - waiting for next connection...")


class LiveRecording:
    """Writes the samples of one live-stream connection to per-sensor CSVs
    in the same format as the phone's CsvSink, then combines them."""

    def __init__(self, label: str):
        self.label = label
        self.directory = os.path.join(
            OUTPUT_DIR, "live", datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
        )
        self.files = {}  # sensor id -> (file, csv writer, column names)
        self.sample_count = 0

    def add(self, message: dict) -> None:
        sensor = str(message.get("sensor", "unknown"))
        values = message.get("values") or {}
        if sensor not in self.files:
            os.makedirs(self.directory, exist_ok=True)
            f = open(os.path.join(self.directory, f"{sensor}_raw.csv"), "w", newline="")
            writer = csv.writer(f)
            columns = list(values.keys())
            writer.writerow(["phone_ts_ms", *columns])
            self.files[sensor] = (f, writer, columns)
        _, writer, columns = self.files[sensor]
        writer.writerow([message.get("ts_ms", ""), *(_csv_value(values.get(c)) for c in columns)])
        self.sample_count += 1

    def finish(self) -> None:
        for f, _, _ in self.files.values():
            f.close()
        if not self.files:
            return
        print(f"[{self.label}] Saved {self.sample_count} live samples to {self.directory}")
        try:
            build_combined_outputs(
                [f.name for f, _, _ in self.files.values()],
                os.path.join(self.directory, "combined"),
                self.label,
            )
        except Exception as e:
            print(f"[{self.label}] Failed to build combined CSVs: {e}")


def _csv_value(value) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def parse_stream_line(line: str):
    """Returns the message of one live-stream line as a dict, or None.
    A line of only digits is the legacy clock format."""
    line = line.strip()
    if not line:
        return None
    if line.isdigit():
        return {"type": "clock", "ts_ms": int(line)}
    try:
        message = json.loads(line)
    except json.JSONDecodeError:
        return None
    return message if isinstance(message, dict) else None


def run_stream_server() -> None:
    label = "Stream"
    ensure_adb_reverse(STREAM_PORT, label)
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server_socket.bind((HOST, STREAM_PORT))
    server_socket.listen(1)
    print(f"[{label}] Listening on {HOST}:{STREAM_PORT} - waiting for app to connect...")

    write_header = not os.path.exists(STREAM_LOG_FILE)
    with open(STREAM_LOG_FILE, "a") as log:
        if write_header:
            log.write("phone_ts_ms,host_ts_ms,offset_ms\n")
            log.flush()

        while True:
            conn, addr = server_socket.accept()
            print(f"[{label}] Connected: {addr}")
            recording = LiveRecording(label)
            last_print = 0.0
            buf = ""
            try:
                while True:
                    data = conn.recv(65536)
                    if not data:
                        break
                    buf += data.decode("utf-8", errors="ignore")
                    lines = buf.split("\n")
                    buf = lines[-1]
                    for line in lines[:-1]:
                        message = parse_stream_line(line)
                        if message is None:
                            continue
                        kind = message.get("type")
                        if kind == "sample":
                            recording.add(message)
                        elif kind == "clock" and isinstance(message.get("ts_ms"), int):
                            phone_ts = message["ts_ms"]
                            host_ts = int(time.time() * 1000)
                            offset = host_ts - phone_ts
                            log.write(f"{phone_ts},{host_ts},{offset}\n")
                            if time.monotonic() - last_print >= 1:
                                last_print = time.monotonic()
                                print(
                                    f"[{label}] offset={offset:+d}ms  "
                                    f"samples={recording.sample_count}"
                                )
                        elif kind == "hello":
                            print(f"[{label}] Protocol version {message.get('protocol')}")
                    log.flush()
            except (ConnectionResetError, BrokenPipeError):
                pass
            finally:
                conn.close()
                recording.finish()
                print(f"[{label}] Disconnected - waiting for next connection...")


def main() -> None:
    global HOST, USE_ADB, OUTPUT_DIR, STOP_SEND_OUTPUT_DIR, STREAM_LOG_FILE
    global STOP_SEND_PORT, STREAM_PORT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default=HOST,
                        help="address to listen on; use 0.0.0.0 for Wi-Fi (default: %(default)s)")
    parser.add_argument("--no-adb", action="store_true",
                        help="don't set up adb reverse tunnels (for Wi-Fi)")
    parser.add_argument("--upload-port", type=int, default=STOP_SEND_PORT)
    parser.add_argument("--stream-port", type=int, default=STREAM_PORT)
    parser.add_argument("--output", default=OUTPUT_DIR,
                        help="where recordings are saved (default: results/android)")
    args = parser.parse_args()
    HOST = args.host
    USE_ADB = not args.no_adb
    STOP_SEND_PORT = args.upload_port
    STREAM_PORT = args.stream_port
    OUTPUT_DIR = STOP_SEND_OUTPUT_DIR = args.output
    STREAM_LOG_FILE = os.path.join(OUTPUT_DIR, "timestamps.csv")

    threading.Thread(target=run_stop_and_send_server, daemon=True).start()
    threading.Thread(target=run_stream_server, daemon=True).start()
    print("Both receivers starting. Press Ctrl+C to stop.")
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
