import "dart:io";
import "dart:typed_data";
import "package:path_provider/path_provider.dart";
import 'package:archive/archive_io.dart';


Future<void> sendDataToPi(String piIpAddress) async {
  Socket? socket;
  final int piPort = 5000;
    
  try {
    final docsDir = await getApplicationDocumentsDirectory();
    final csvFile = File("${docsDir.path}/sensor_logs/all_sensors_combined.csv");
    final imagesDir = Directory("${docsDir.path}/sensor_logs/images");

    if (!await csvFile.exists()){ 
      return;
    }

    socket = await Socket.connect(piIpAddress, piPort, timeout: Duration(seconds: 10));
   
    print("Sending CSV...");
    final csvBytes = await csvFile.readAsBytes();
    socket.add(Uint8List(8)..buffer.asByteData().setUint64(0, csvBytes.length, Endian.big));
    socket.add(csvBytes);
    await socket.flush();

    print("Sending images...");

    print("[Flutter] Packing images into TAR archive...");
    
    if (await imagesDir.exists()) {
      final archive = Archive();
      final files = imagesDir.listSync(recursive: true);

      for (final file in files) {
        if (file is File) {
          // Erstellt den relativen Pfad für das Archiv (z.B. "images/bild1.jpg")
          final relativePath = file.path.substring(imagesDir.path.length + 1);
          final bytes = await file.readAsBytes();
          archive.addFile(ArchiveFile(relativePath, bytes.length, bytes));
        }
      }

      // Generiert die TAR-Bytes direkt im Arbeitsspeicher
      final tarBytes = TarEncoder().encode(archive);
      
      if (tarBytes != null && tarBytes.isNotEmpty) {
        print("[Flutter] Sending images (${(tarBytes.length / 1024 / 1024).toStringAsFixed(2)} MB)...");
        
        // Größe + Inhalt senden
        socket.add(Uint8List(8)..buffer.asByteData().setUint64(0, tarBytes.length, Endian.big));
        socket.add(Uint8List.fromList(tarBytes));
        await socket.flush();
        print("[Flutter] Images successfully sent.");
      } else {
        print("[Flutter] Error: TAR archive could not be generated.");
      }
    } else {
      print("[Flutter] Warning: Images folder does not exist. Sending empty archive.");
      socket.add(Uint8List(8)..buffer.asByteData().setUint64(0, 0, Endian.big));
      await socket.flush();
    }
    await socket.close();
    } catch (e) {
    print("Error while sending data: $e");
    if (socket != null) {
      await socket.close();
    } 
  }
}    

