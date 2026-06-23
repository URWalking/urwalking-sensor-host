#!/usr/bin/env python3
"""Receives Unix timestamps from the Flutter app via ADB reverse tunnel (port 5001).
Prints phone timestamp, local host timestamp, and clock offset for sync analysis."""

import os
import socket
import subprocess
import time

HOST = "127.0.0.1"
PORT = 5001
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "results", "android")
LOG_FILE = os.path.join(OUTPUT_DIR, "timestamps.csv")


def setup_adb_reverse() -> bool:
    try:
        subprocess.run(
            ["adb", "reverse", f"tcp:{PORT}", f"tcp:{PORT}"],
            check=True,
            capture_output=True,
        )
        print(f"ADB reverse tunnel established on port {PORT}")
        return True
    except FileNotFoundError:
        print("Error: adb not found — install with: sudo apt install adb")
        return False
    except subprocess.CalledProcessError as e:
        print(f"Error: adb reverse failed: {e.stderr.decode().strip()}")
        print("Make sure USB debugging is enabled and the device is authorized.")
        return False


def run():
    if not setup_adb_reverse():
        print("Run 'adb devices' to check the connection. Aborting.")
        return

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as srv:
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind((HOST, PORT))
        srv.listen(1)
        print(f"Listening on {HOST}:{PORT} — waiting for app to connect...")

        os.makedirs(OUTPUT_DIR, exist_ok=True)
        with open(LOG_FILE, "a") as log:
            log.write("phone_ts_ms,host_ts_ms,offset_ms\n")

            while True:
                conn, addr = srv.accept()
                print(f"Connected: {addr}")
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
                            print(f"phone={phone_ts}  host={host_ts}  offset={offset:+d}ms")
                            log.write(f"{phone_ts},{host_ts},{offset}\n")
                            log.flush()
                except (ConnectionResetError, BrokenPipeError):
                    pass
                finally:
                    conn.close()
                    print("Disconnected — waiting for next connection...")


if __name__ == "__main__":
    try:
        run()
    except KeyboardInterrupt:
        print("\nStopped.")
