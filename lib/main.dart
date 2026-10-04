import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'view/enhanced_face_mesh_camera_screen.dart';
import 'view/face_ratio_analyzer_screen.dart';
import 'view/privacy_screen.dart';

void main() {
  // Entry point of the application
  runApp(MyApp());
}

/// The root widget of the application.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Face Mesh Camera',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      // Set the initial screen to HomeScreen
      home: HomeScreen(),
    );
  }
}

/// The main landing screen of the app.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  /// Requests necessary permissions (camera and storage) from the user.
  Future<void> _requestPermissions() async {
    await Permission.camera.request();
    await Permission.storage.request();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Face Mesh Camera'),
        actions: [
          // Navigation to the Privacy Policy screen
          IconButton(
            icon: Icon(Icons.privacy_tip),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => PrivacyScreen()),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App branding icon
            Icon(Icons.face, size: 100, color: Colors.blue),
            SizedBox(height: 20),
            Text(
              'Face Mesh Camera',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            // Button to open the real-time face mesh camera
            ElevatedButton(
              onPressed: () async {
                await _requestPermissions();
                if (!context.mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => FaceMeshCameraScreen(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              ),
              child: Text('Open Camera'),
            ),
            SizedBox(height: 20),
            // Button to open the face ratio analyzer screen
            ElevatedButton(
              onPressed: () async {
                await _requestPermissions();
                if (!context.mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => FaceRatioAnalyzerScreen(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                backgroundColor: Colors.cyan,
                foregroundColor: Colors.white,
              ),
              child: Text('Analyze Face Ratio'),
            ),
          ],
        ),
      ),
    );
  }
}
