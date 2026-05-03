import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:path_provider/path_provider.dart';

class CompassScreen extends StatefulWidget {
  const CompassScreen({super.key});

  @override
  State<CompassScreen> createState() => _CompassScreenState();
}


class _CompassScreenState extends State<CompassScreen> {
  // Properties for the Compass Needle:
  double? _heading = 0;
  double _currentRotation = 0; 
  File? _csvFile;

  @override
  void initState() {
    super.initState();
    _prepareCsvFile(); // Initialize the file

    // Listen to sensor events, normalize the heading to 360°, 
    // and calculate the rotation path to prevent needle flickering.
    FlutterCompass.events?.listen((event) {
      if (mounted) {
        double? newHeading = event.heading;
        if (newHeading != null) {
          setState(() {
            _heading = newHeading % 360;
            _currentRotation = _calculateShortestPath(newHeading);
          });
          // Log to CSV
          _logToCsv(_heading!);
        }
      }
    });
  }
  
  // Format: Timestamp (ISO-8601), Heading (Degrees)
  // Example: 2026-05-01T09:15:30.123,106.00
  // Legend: YYYY-MM-DD 'T' HH:mm:ss.ms , 0.00-359.99°
 

   // Find the documents directory and create the file
  Future<void> _prepareCsvFile() async {
    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/compass_logs.csv';
    _csvFile = File(path);

    // Write header if the file is new
    if (!await _csvFile!.exists()) {
      await _csvFile!.writeAsString('Timestamp,Heading\n');
    }
    print("Logging to: $path");
  }

  // Append a new row to the CSV
  Future<void> _logToCsv(double heading) async {
    if (_csvFile == null) return;
    
    final timestamp = DateTime.now().toIso8601String();
    final row = '$timestamp,${heading.toStringAsFixed(2)}\n';
    
    await _csvFile!.writeAsString(row, mode: FileMode.append);
  }

  // Convert degrees to radians and find the mathematically shortest 
  // turn distance to prevent the needle from spinning 360° at North.
  double _calculateShortestPath(double newHeading) {
    double targetRotation = (newHeading * (math.pi / 180)) * -1;
    double delta = targetRotation - _currentRotation;
    while (delta <= -math.pi) { delta += 2 * math.pi; }
    while (delta > math.pi) { delta -= 2 * math.pi; }
    return _currentRotation + delta;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("I'm on my way!"), 
        backgroundColor: Colors.grey[900],
        elevation: 0,
        centerTitle: true,
      ),
      body: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center, 
          children: [
            const Spacer(),
            
            // Numerical degrees
            Text(
              "${_heading?.toInt() ?? 0}°", 
              style: const TextStyle(fontSize: 80, fontWeight: FontWeight.w200)
            ),

            // Cardinal direction
            Text(
              _getDirection(_heading ?? 0),
              style: const TextStyle(color: Colors.redAccent, fontSize: 32, fontWeight: FontWeight.bold),
            ),
            
            const SizedBox(height: 40),
            
            // Animated Compass Needle
            TweenAnimationBuilder<double>(
              tween: Tween<double>(end: _currentRotation),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              builder: (context, angle, child) {
                return Transform.rotate(
                  angle: angle,
                  child: child,
                );
              },
              child: SizedBox(
                width: 280,
                height: 280,
                child: CustomPaint(
                  painter: CompassArrowPainter(),
                ),
              ),
            ),
            
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }

  // Helper to translate degree values into compass directions.
  String _getDirection(double heading) {
    if (heading >= 337.5 || heading < 22.5) return "N";
    if (heading >= 22.5 && heading < 67.5) return "NE";
    if (heading >= 67.5 && heading < 112.5) return "E";
    if (heading >= 112.5 && heading < 157.5) return "SE";
    if (heading >= 157.5 && heading < 202.5) return "S";
    if (heading >= 202.5 && heading < 247.5) return "SW";
    if (heading >= 247.5 && heading < 292.5) return "W";
    if (heading >= 292.5 && heading < 337.5) return "NW";
    return "N";
  }

}

//Creation of the arrow
class CompassArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paintRed = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.fill;

    final paintDarkRed = Paint()
      ..color = (Colors.red[900] ?? Colors.red)
      ..style = PaintingStyle.fill;

    final shaftPaint = Paint()
      ..color = Colors.redAccent
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final double arrowLength = size.height * 0.7; 
    final double top = center.dy - arrowLength / 2;
    final double bottom = center.dy + arrowLength / 2;

    // Drawing the arrow shaft
    canvas.drawLine(
      Offset(center.dx, top + 25), 
      Offset(center.dx, bottom), 
      shaftPaint
    );

    // Drawing the arrow head
    final Path headPath = Path();
    headPath.moveTo(center.dx, top);           
    headPath.lineTo(center.dx - 12, top + 25); 
    headPath.lineTo(center.dx + 12, top + 25); 
    headPath.close();
    
    canvas.drawPath(headPath, paintRed);

    // Decoration, shadow on the arrow head
    final Path halfHead = Path();
    halfHead.moveTo(center.dx, top);
    halfHead.lineTo(center.dx - 12, top + 25);
    halfHead.lineTo(center.dx, top + 25);
    halfHead.close();
    
    canvas.drawPath(halfHead, paintDarkRed);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}