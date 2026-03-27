import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:bio_pass/services/face_service.dart';
import 'package:bio_pass/zk/zk_authentication_service.dart';

/// ZK Face Registration Screen
/// Captures face and registers with ZK commitment
class ZKFaceRegistrationScreen extends StatefulWidget {
  final String userId;
  final String serverUrl;

  const ZKFaceRegistrationScreen({
    super.key,
    required this.userId,
    required this.serverUrl,
  });

  @override
  State<ZKFaceRegistrationScreen> createState() =>
      _ZKFaceRegistrationScreenState();
}

class _ZKFaceRegistrationScreenState extends State<ZKFaceRegistrationScreen> {
  late CameraController _cameraController;
  late FaceService _faceService;
  late ZKAuthenticationService _zkAuthService;
  
  bool _isProcessing = false;
  String _status = 'Ready to register face';
  double _faceConfidence = 0.0;
  bool _registrationComplete = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      // Initialize face service
      _faceService = FaceService();

      // Initialize ZK service
      _zkAuthService = ZKAuthenticationService(serverUrl: widget.serverUrl);

      // Initialize camera
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.high,
      );

      await _cameraController.initialize();

      if (mounted) {
        setState(() {
          _status = 'Position your face in the camera';
        });

        // Start continuous face detection
        _startFaceDetection();
      }
    } catch (e) {
      _showError('Failed to initialize: $e');
    }
  }

  void _startFaceDetection() {
    _cameraController.startImageStream((image) async {
      if (_isProcessing || _registrationComplete) return;

      _isProcessing = true;

      try {
        // Get face embedding
        final embedding = await _faceService.getFaceEmbedding(image);

        if (embedding != null && mounted) {
          // Extract confidence from detection
          final detections = await _faceService.detectFaces(image);
          final confidence =
              detections.isNotEmpty ? detections.first.headEulerAngleX?.abs() ?? 0.0 : 0.0;

          setState(() {
            _faceConfidence = (1.0 - (confidence / 45.0)).clamp(0.0, 1.0);
            _status = 'Face detected (${(_faceConfidence * 100).toStringAsFixed(0)}%)';
          });

          // Auto-register when confidence is high
          if (_faceConfidence > 0.85) {
            await _registerFace(embedding);
          }
        }
      } catch (e) {
        // Silently continue on detection errors
      } finally {
        _isProcessing = false;
      }
    });
  }

  Future<void> _registerFace(List<double> embedding) async {
    setState(() {
      _status = 'Registering face...';
      _isProcessing = true;
    });

    try {
      // Register with ZK backend
      final success = await _zkAuthService.registerFace(
        userId: widget.userId,
        embedding: embedding,
      );

      if (success && mounted) {
        setState(() {
          _registrationComplete = true;
          _status = 'Registration successful! ✓';
        });

        // Stop camera stream
        await _cameraController.stopImageStream();

        // Show success and navigate
        _showSuccess();
      } else {
        throw Exception('Registration failed on server');
      }
    } catch (e) {
      if (mounted) {
        _showError('Registration error: $e');
        setState(() {
          _isProcessing = false;
          _status = 'Failed. Try again.';
        });
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccess() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Registration Successful'),
        content: const Text('Your face has been registered successfully.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context, true); // Return success to previous screen
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _zkAuthService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_cameraController.value.isInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Registration'),
      ),
      body: Stack(
        children: [
          // Background
          Container(color: Colors.black87),

          // Camera preview with fixed bounding box matching verification screen
          Center(
            child: Container(
              width: 400,
              height: 500,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.deepPurple,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepPurple.withValues(alpha: 0.3),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CameraPreview(_cameraController),
              ),
            ),
          ),

          // Overlay with instructions
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.3),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.5),
                ],
              ),
            ),
          ),

          // Status and confidence display
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black87,
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Status text
                  Text(
                    _status,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 12),

                  // Confidence indicator
                  LinearProgressIndicator(
                    value: _faceConfidence,
                    minHeight: 8,
                    backgroundColor: Colors.grey[700],
                    valueColor: AlwaysStoppedAnimation(
                      _faceConfidence > 0.7
                          ? Colors.green
                          : _faceConfidence > 0.4
                              ? Colors.orange
                              : Colors.red,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Confidence percentage
                  Text(
                    'Confidence: ${(_faceConfidence * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),

                  // Registration complete indicator
                  if (_registrationComplete) ...[
                    const SizedBox(height: 12),
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 32,
                    ),
                  ],

                  // Manual register button (fallback)
                  if (!_registrationComplete && !_isProcessing) ...[
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () => _showError('Please wait for auto-registration'),
                      icon: const Icon(Icons.face),
                      label: const Text('Register Now'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
