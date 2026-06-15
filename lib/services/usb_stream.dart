import 'dart:io';

class UsbStreamService {
  Socket? _socket;
  final String _host = '127.0.0.1'; // Localhost, ADB
  final int _port = 5000;

  bool get isConnected => _socket != null;

  Future<bool> connect() async {
    try {
      _socket = await Socket.connect(_host, _port);
      print('Verbunden mit Raspberry Pi via USB!');
      return true;
    } catch (e) {
      print('Verbindungsfehler: $e');
      return false;
    }
  }

  void streamSensor(String sensorName, List<dynamic> values) {
    if (_socket == null) return;

    final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    
    final String joinedValues = values.map((e) => e.toString()).join(',');
    final String csvLine = '$timestamp,$sensorName,$joinedValues\n';

    _socket!.write(csvLine);
  }

  void disconnect() {
    _socket?.close();
    _socket = null;
    print('USB-Stream beendet.');
  }
}