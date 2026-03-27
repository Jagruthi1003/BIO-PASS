import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/face_service.dart';

class FaceRegistrationScreenSimple extends StatefulWidget {
  const FaceRegistrationScreenSimple({super.key});

  @override
  State<FaceRegistrationScreenSimple> createState() =>
      _FaceRegistrationScreenSimpleState();
}

class _FaceRegistrationScreenSimpleState
    extends State<FaceRegistrationScreenSimple> {
  CameraController? _cameraController;
  late FaceDetector _faceDetector;
  final FaceService _faceService = FaceService();
  bool _isCapturing = false;
  String _statusMessage = 'Initializing camera...';
  List<double>? _detectedLandmarks;
  bool _faceDetected = false;
  int _selectedCameraIndex = 0;
  bool _canSwitchCamera = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera({int cameraIndex = 0}) async {
    if (kIsWeb) {
      // For web, show a mock setup
      setState(() {
        _statusMessage = 'Camera not available on web. Using mock landmarks.';
      });
      return;
    }

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableContours: true,
        enableTracking: true,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );

    final status = await Permission.camera.request();

    if (!status.isGranted) {
      if (mounted) {
        setState(() => _statusMessage = 'Camera permission denied');
      }
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() => _statusMessage = 'No cameras available');
        }
        return;
      }

      // Ensure camera index is valid
      if (cameraIndex >= cameras.length) {
        cameraIndex = 0;
      }

      await _cameraController?.stopImageStream();
      await _cameraController?.dispose();

      _cameraController = CameraController(
        cameras[cameraIndex],
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      // Start streaming for face detection
      _cameraController!.startImageStream(_processCameraImage);

      final hasMultipleCameras = cameras.length > 1;

      if (mounted) {
        setState(() {
          _statusMessage = 'Position your face in the center';
          _selectedCameraIndex = cameraIndex;
          _canSwitchCamera = hasMultipleCameras;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusMessage = 'Error: $e');
      }
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isCapturing) return;

    try {
      final landmarks = await _faceService.extractFaceLandmarks(image);

      if (landmarks != null && landmarks.isNotEmpty) {
        if (mounted) {
          setState(() {
            _detectedLandmarks = landmarks;
            _faceDetected = true;
            _statusMessage = 'Face detected! Tap capture to register.';
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _faceDetected = false;
            _statusMessage = 'No face detected. Try again.';
          });
        }
      }
    } catch (e) {
      // Ignore errors during streaming
    }
  }

  Future<void> _captureFace() async {
    if (_detectedLandmarks == null || _detectedLandmarks!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No face detected. Please try again.')),
      );
      return;
    }

    setState(() => _isCapturing = true);

    try {
      // Return the landmarks to the auth screen
      if (mounted) {
        Navigator.of(context).pop<List<double>>(_detectedLandmarks);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
        setState(() => _isCapturing = false);
      }
    }
  }

  Future<void> _switchCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.length < 2) return;

      // Toggle camera
      int newIndex = _selectedCameraIndex == 0 ? 1 : 0;
      await _initializeCamera(cameraIndex: newIndex);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera switched successfully'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error switching camera: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _useMockLandmarks() {
    // Use mock landmarks for testing (simulates face registration)
    final mockLandmarks = List<double>.generate(136, (i) => (50.0 + i % 100));
    Navigator.of(context).pop<List<double>>(mockLandmarks);
  }

  @override
  void dispose() {
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register Face'),
        centerTitle: true,
      ),
      body: kIsWeb
          ? _buildWebView()
          : _cameraController?.value.isInitialized ?? false
              ? _buildCameraView()
              : _buildLoadingView(),
    );
  }

  Widget _buildWebView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.face, size: 80, color: Colors.blue),
          const SizedBox(height: 20),
          const Text(
            'Face Registration',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Text(
            'Camera not available on web.\nUsing mock landmarks for testing.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          ElevatedButton.icon(
            onPressed: _useMockLandmarks,
            icon: const Icon(Icons.check),
            label: const Text('Use Mock Face Data'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(_statusMessage),
        ],
      ),
    );
  }

  Widget _buildCameraView() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera preview
        CameraPreview(_cameraController!),

        // Overlay with instructions
        Container(
          color: Colors.black.withValues(alpha: 0.3),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top section with status and camera switch button
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Status message
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _statusMessage,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    // Camera switch button
                    if (_canSwitchCamera) ...[
                      const SizedBox(width: 12),
                      FloatingActionButton(
                        mini: true,
                        backgroundColor: Colors.deepPurple.shade700,
                        onPressed: _switchCamera,
                        tooltip: 'Switch Camera',
                        child: const Icon(Icons.flip_camera_android, color: Colors.white),
                      ),
                    ],
                  ],
                ),
              ),

              // Center face detection indicator
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 200,
                      height: 250,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _faceDetected ? Colors.green : Colors.red,
                          width: 3,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Center(
                        child: Icon(
                          _faceDetected ? Icons.check_circle : Icons.face,
                          size: 80,
                          color: _faceDetected ? Colors.green : Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Bottom action buttons
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Cancel'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    if (_faceDetected)
                      ElevatedButton.icon(
                        onPressed: _isCapturing ? null : _captureFace,
                        icon: const Icon(Icons.check),
                        label: const Text('Capture'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
