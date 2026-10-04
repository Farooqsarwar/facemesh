import 'package:flutter/material.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Privacy Notice'),
      ),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Privacy Notice',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            Text(
              'This app processes your camera feed locally on your device for face detection and mesh overlay.',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 10),
            Text(
              '• All face detection processing happens on-device',
              style: TextStyle(fontSize: 14),
            ),
            Text(
              '• No video frames are uploaded or stored',
              style: TextStyle(fontSize: 14),
            ),
            Text(
              '• Only final captured photos are saved locally',
              style: TextStyle(fontSize: 14),
            ),
            Text(
              '• No data is shared with third parties',
              style: TextStyle(fontSize: 14),
            ),
            Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: Text('I Understand'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}