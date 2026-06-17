import socket
import os
import subprocess
import tarfile
import io

HOST = "127.0.0.1" 
PORT = 5000
OUTPUT_DIR = "./received_sensor_logs"

def starte_server():
    if not os.path.exists(OUTPUT_DIR):
        os.makedirs(OUTPUT_DIR, exist_ok=True)
        print(f"[INFO] Target directory created: {OUTPUT_DIR}")

    print("[ADB] Trying to set up port forwarding via USB...")
    try:
        subprocess.run(
            ["adb", "reverse", f"tcp:{PORT}", f"tcp:{PORT}"], 
            capture_output=True, text=True, check=True
        )
        print(f"[ADB] Erfolg! USB-Brücke auf Port {PORT} steht.")
    except FileNotFoundError:
        print("[ADB WARNING] Command 'adb' was not found.")
    except subprocess.CalledProcessError as e:
        print(f"[ADB Error] Configuration problem: {e.stderr.strip()}")
    print("-" * 50)

    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server_socket.bind((HOST, PORT))
    server_socket.listen(1)
    print(f"Connecting to {PORT}...")

    try:
        while True:
            conn, addr = server_socket.accept()
            print(f"[+] Connected to: {addr}")
            
            try:
                print("[...]  CSV-File received...")
                csv_size_bytes = conn.recv(8)
                if not csv_size_bytes:
                    continue
                csv_size = int.from_bytes(csv_size_bytes, byteorder='big')
                
                csv_data = b""
                while len(csv_data) < csv_size:
                    packet = conn.recv(4096)
                    if not packet:
                        break
                    csv_data += packet
                
                csv_path = os.path.join(OUTPUT_DIR, "all_sensors_combined.csv")
                with open(csv_path, "wb") as f:
                    f.write(csv_data)
                print(f"CSV saved under: {csv_path}")

                print("[...] Pictures received...")
                tar_size_bytes = conn.recv(8)
                if not tar_size_bytes:
                    continue
                tar_size = int.from_bytes(tar_size_bytes, byteorder='big')
                
                tar_io = io.BytesIO()
                while tar_io.tell() < tar_size:
                    packet = conn.recv(4096)
                    if not packet:
                        break
                    tar_io.write(packet)
                
                tar_io.seek(0)  # Gehe an den Anfang des In-Memory-Speichers, um ihn zu entpacken

                print("[...] Extracting images on the Pi...")
                images_target_dir = os.path.join(OUTPUT_DIR, "images")
                os.makedirs(images_target_dir, exist_ok=True)

                with tarfile.open(fileobj=tar_io, mode="r:") as tar:
                    tar.extractall(path=images_target_dir)

                print(f"All images successfully extracted to: {images_target_dir}")
                
            except Exception as e:
                print(f"Error receiving data: {e}")
            finally:
                conn.close()
                print("Connection closed.")               
    except KeyboardInterrupt:
        print("Server will be shut down.")
    finally:
        server_socket.close()

if __name__ == "__main__":
    starte_server()