import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../services/face_service.dart';

class EventEntryScreen extends StatefulWidget {
  const EventEntryScreen({super.key});
  @override
  State<EventEntryScreen> createState() => _EventEntryScreenState();
}

class _EventEntryScreenState extends State<EventEntryScreen> {
  CameraController? controller;
  final FaceService service = FaceService();
  bool processing = false;
  String status = "Press SCAN for Entry";
  bool cameraReady = false;

  @override
  void initState() {
    super.initState();
    initCamera();
  }

  Future<void> initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        controller = CameraController(cameras[0], ResolutionPreset.medium);
        await controller!.initialize();
        if (mounted) setState(() => cameraReady = true);
      }
    } catch (e) {
      status = "Camera error: $e";
    }
  }

  Future<void> scanFace() async {
    setState(() {
      processing = true;
      status = "🔐 Verifying Match...";
    });

    try {
      final image = await controller!.takePicture();
      final result = await service.verifyEntry(image, 'mock-commitment');
      
      if (mounted) {
        setState(() {
          status = result['success'] ? "✅ ${result['proofId']}" : result['error'] ?? 'Failed';
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['success'] ? "🎫 Entry Approved!" : result['error']),
            backgroundColor: result['success'] ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      status = "Error: $e";
    }

    if (mounted) setState(() => processing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          if (cameraReady && controller != null)
            Positioned.fill(child: CameraPreview(controller!)),
          Container(
            color: Colors.black54,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.verified_user_outlined, size: 100, color: Colors.white),
                  const SizedBox(height: 30),
                  Text(status, 
                    style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
                  const SizedBox(height: 40),
                  ElevatedButton(
                    onPressed: processing || !cameraReady ? null : scanFace,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                    ),
                    child: Text(processing ? "WAIT..." : "🔐 SCAN FACE",
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }
}
