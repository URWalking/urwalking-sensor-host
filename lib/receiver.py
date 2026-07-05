#!/usr/bin/env python3
"""PC-side receivers for the Flutter sensor host app, run over a USB
adb-reverse tunnel. Runs two independent servers concurrently:

  - port 5000: "Stop & Send" - receives one tar of the whole sensor_logs
    directory (all per-sensor CSVs plus captured images) and extracts it.
  - port 5001: "Timestamps streamen" - receives a live ~30Hz stream of
    phone timestamps for clock-sync analysis while a recording is running.

Both keep retrying `adb reverse` in the background, so it doesn't matter
whether this script or the phone/USB connection comes up first.
"""

import io
import os
import socket
import subprocess
import tarfile
import threading
import time

STOP_SEND_PORT = 5000
STREAM_PORT = 5001

# Both receivers are Android-side data, so both land under results/android
# next to each other.
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "results", "android")
STOP_SEND_OUTPUT_DIR = OUTPUT_DIR
STREAM_LOG_FILE = os.path.join(OUTPUT_DIR, "timestamps.csv")

ADB_RETRY_DELAY_SECONDS = 3
HOST = "127.0.0.1"


def ensure_adb_reverse(port: int, label: str) -> None:
    """Retries `adb reverse` for `port` until it succeeds. Runs forever in
    the background so a device plugged in after this script starts (or a
    USB reconnect) still gets picked up."""
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
                message = (
                    f"Connection closed early "
                    f"({len(tar_data)}/{tar_size} bytes received)."
                )
                print(f"[{label}] {message}")
                conn.sendall(f"ERROR: {message}".encode())
                continue

            with tarfile.open(fileobj=io.BytesIO(tar_data), mode="r:") as tar:
                tar.extractall(path=STOP_SEND_OUTPUT_DIR)
            print(f"[{label}] Extracted {tar_size} bytes to {STOP_SEND_OUTPUT_DIR}")
            # Only ack once extraction is actually done, so the phone can
            # wait for real completion instead of just "bytes handed off".
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
            buf = ""
            try:
                while True:
                    data = conn.recv(256)
                    if not data:
                        break
                    buf += data.decode("utf-8", errors="ignore")
                    lines = buf.split("\n")
                    buf = lines[-1]
                    for line in lines[:-1]:
                        line = line.strip()
                        if not line.isdigit():
                            continue
                        phone_ts = int(line)
                        host_ts = int(time.time() * 1000)
                        offset = host_ts - phone_ts
                        print(f"[{label}] phone={phone_ts}  host={host_ts}  offset={offset:+d}ms")
                        log.write(f"{phone_ts},{host_ts},{offset}\n")
                        log.flush()
            except (ConnectionResetError, BrokenPipeError):
                pass
            finally:
                conn.close()
                print(f"[{label}] Disconnected - waiting for next connection...")


def main() -> None:
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
