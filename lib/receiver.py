import socket
import os
from datetime import datetime
import subprocess

HOST = '127.0.0.1'
PORT = 5000
EXCEL_FILE = "sensorData.csv"

aktueller_zustand = {
    "gyro_x": "", "gyro_y": "", "gyro_z": "",
    "acc_x": "", "acc_y": "", "acc_z": "",
    "com": "",
    "bar": "",
    "mag_x": "", "mag_y": "", "mag_z": "",
    "img_wide": "", "img_far": "",
    "gps_long": "", "gps_lat": "", "gps_alt": "", "gps_acc": "", "gps_spd": "", "gps_hed": "",  
    "wifi_name_list": "", "wifi_sig_strength": ""
}

def schreibe_live_zeile(csv_file, timestamp, sensor_type, values):
    global aktueller_zustand
    try:
        ts_sekunden = int(timestamp) / 1000.0
        lesbare_zeit = datetime.fromtimestamp(ts_sekunden).strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]
    except:
        lesbare_zeit = timestamp
    
    if sensor_type == "Gyroscope" and len(values) >= 3: 
        aktueller_zustand["gyro_x"], aktueller_zustand["gyro_y"], aktueller_zustand["gyro_z"] = values[0], values[1], values[2]
    elif sensor_type == "Accelerometer" and len(values) >= 3:
        aktueller_zustand["acc_x"], aktueller_zustand["acc_y"], aktueller_zustand["acc_z"] = values[0], values[1], values[2]
    elif sensor_type == "Compass" and len(values) >= 1:
        aktueller_zustand["com"] = values[0] 
    elif sensor_type == "Barometer" and len(values) >= 1:
        aktueller_zustand["bar"] = values[0]
    elif sensor_type == "Magnetometer" and len(values) >= 3:
        aktueller_zustand["mag_x"], aktueller_zustand["mag_y"], aktueller_zustand["mag_z"] = values[0], values[1], values[2]
    elif sensor_type == "Camera" and len(values) >= 2:
        # Erwartet Dateinamen/Pfade der Weitwinkel- und Telekamera
        aktueller_zustand["img_wide"], aktueller_zustand["img_far"] = values[0], values[1]
    elif sensor_type == "GPS" and len(values) >= 6:
        aktueller_zustand["gps_lat"] = values[0]
        aktueller_zustand["gps_long"] = values[1]
        aktueller_zustand["gps_alt"] = values[2]
        aktueller_zustand["gps_acc"] = values[3]
        aktueller_zustand["gps_spd"] = values[4]
        aktueller_zustand["gps_hed"] = values[5]  
    elif sensor_type == "Wifi" and len(values) >= 2:
        aktueller_zustand["wifi_name_list"], aktueller_zustand["wifi_sig_strength"] = values[0], values[1]
 
    werte_liste = [aktueller_zustand[key] for key in aktueller_zustand]
    zeile = f"{lesbare_zeit}," + ",".join(werte_liste) + "\n"
    csv_file.write(zeile)

def starte_server():

    print("[ADB] Versuche, die Port-Weiterleitung via USB einzurichten...")
    
    try:
        subprocess.run(
            ["adb", "reverse", f"tcp:{PORT}", f"tcp:{PORT}"], 
            capture_output=True, 
            text=True, 
            check=True
        )
        print("[ADB] Erfolg! USB-Brücke auf Port 5000 steht.")
    except FileNotFoundError:
        print(f"[ADB WARNUNG] Befehl 'adb' wurde nicht gefunden.")
        print("Stelle sicher, dass ADB installiert ist (oder auf dem Mac im selben Ordner liegt).")
    except subprocess.CalledProcessError as e:
        print(f"[ADB FEHLER] Fehler beim Einrichten: {e.stderr.strip()}")
        print("[ADB] Ist dein Handy per USB angeschlossen und 'USB-Debugging' aktiv?")
    print("-" * 50)

    if not os.path.exists(EXCEL_FILE):
        with open(EXCEL_FILE, "w", encoding="utf-8") as f:
            header = "Timestamp," + ",".join(aktueller_zustand.keys()) + "\n"
            f.write(header)

    print(f"Live-Server gestartet auf Port {PORT}...")

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server_socket:
        server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server_socket.bind((HOST, PORT))
        server_socket.listen(1)

        while True:
            conn, addr = server_socket.accept()
            print("\n[INFO] Daten werden live in Excel-Struktur geschrieben...")
            
            with conn, open(EXCEL_FILE, "a", encoding="utf-8") as csv_file:
                buffer = ""
                while True:
                    data = conn.recv(1024)
                    if not data:
                        break
                    
                    buffer += data.decode('utf-8')
                    while "\n" in buffer:
                        line, buffer = buffer.split("\n", 1)
                        line = line.strip()
                        if line:
                            parts = line.split(",", 2)
                            if len(parts) >= 3:
                                timestamp = parts[0]
                                sensor_type = parts[1]
                                values = parts[2].split(",") 
                                schreibe_live_zeile(csv_file, timestamp, sensor_type, values)
                csv_file.flush()
            print("[INFO] Aufnahme beendet. Datei aktualisiert.")

if __name__ == "__main__":
    starte_server()