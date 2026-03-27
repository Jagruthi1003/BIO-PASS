import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:camera/camera.dart';
import '../services/face_biometric_service.dart';
import '../services/enhanced_event_service.dart';

class ZkFaceRegistrationScreenNew extends StatefulWidget {
  final String ticketId;
  final String eventId;
  final EnhancedEventService eventService;

  const ZkFaceRegistrationScreenNew({
    super.key,
    required this.ticketId,
    required this.eventId,
    required this.eventService,
  });

  @override
  State<ZkFaceRegistrationScreenNew> createState() =>
      _ZkFaceRegistrationScreenNewState();
}

class _ZkFaceRegistrationScreenNewState
    extends State<ZkFaceRegistrationScreenNew> {
  CameraController? _cameraController;
  FaceDetector? _faceDetector;
  bool _isProcessing = false;
  String _statusMessage = 'Initialize camera...';
  double _captureProgress = 0.0;
  bool _faceCaptured = false;
  DateTime? _stableFaceSince;
  bool _faceDetectedInFrame = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _faceDetector = FaceDetector(options: FaceDetectorOptions());
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      final frontCamera =
          cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front);

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController?.initialize();

      if (!mounted) return;
      setState(() {
        _statusMessage = 'Ready to capture - Look at the camera';
        _captureProgress = 0.0;
      });

      _startFaceDetection();
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Error initializing camera: $e';
        });
      }
    }
  }

  void _startFaceDetection() {
    _cameraController?.startImageStream((image) async {
      if (_isProcessing || _faceCaptured) return;
      try {
        final inputImage = InputImage.fromBytes(
          bytes: image.planes[0].bytes,
          metadata: InputImageMetadata(
            size: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: InputImageRotation.rotation0deg,
            format: InputImageFormat.nv21,
            bytesPerRow: image.planes[0].bytesPerRow,
          ),
        );

        final List<Face> faces = await _faceDetector!.processImage(inputImage);

        if (faces.isEmpty && mounted) {
          _stableFaceSince = null;
          setState(() {
            _statusMessage = 'No face detected - Position your face in the frame';
            _captureProgress = 0.0;
            _faceDetectedInFrame = false;
          });
          return;
        }

        final now = DateTime.now();
        _stableFaceSince ??= now;
        final stableMs = now.difference(_stableFaceSince!).inMilliseconds;
        final stableProgress = (stableMs / 1500).clamp(0.0, 1.0);

        if (mounted) {
          setState(() {
            _faceDetectedInFrame = true;
            _statusMessage = stableMs < 1500
                ? 'Hold still for auto-capture... (${stableMs ~/ 150}/10)'
                : 'Face locked. Capturing now...';
            _captureProgress = stableProgress;
          });
        }

        if (stableMs < 1500) {
          return;
        }

        _isProcessing = true;
        if (faces.isNotEmpty && mounted) {
          Face face = faces.first;

          // Extract and normalize landmarks
          List<double> normalizedLandmarks =
              FaceBiometricService.extractAndNormalizeLandmarks(face);

          // Generate ZK proof hash
          String zkProof =
              FaceBiometricService.generateZkProofHash(normalizedLandmarks);

          // Generate encrypted vector
          String encryptedVector =
              FaceBiometricService.encryptNormalizedLandmarks(
            normalizedLandmarks,
            widget.ticketId,
          );

          setState(() {
            _statusMessage = 'Face captured! Processing...';
            _captureProgress = 0.9;
          });

          // Save biometric data to Firestore
          await widget.eventService.updateTicketWithBiometrics(
            ticketId: widget.ticketId,
            zkProof: zkProof,
            normalizedLandmarksEncrypted: encryptedVector,
          );

          setState(() {
            _faceCaptured = true;
            _statusMessage = '✅ Face registered successfully!';
            _captureProgress = 1.0;
          });

          // Stop camera
          await _cameraController?.stopImageStream();

          // Show success message
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            Navigator.pop(context, true);
          }
        }
      } catch (e) {
        setState(() {
          _statusMessage = 'Error: $e';
          _captureProgress = 0.0;
        });
      } finally {
        if (_faceCaptured) {
          _isProcessing = true;
        } else {
          _isProcessing = false;
        }
      }
    });
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register Your Face'),
        elevation: 0,
        backgroundColor: const Color(0xFF2D3E50),
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Camera Preview Section
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.black,
              child: _cameraController != null &&
                      _cameraController!.value.isInitialized
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        // Camera Preview
                        CameraPreview(_cameraController!),

                        // Darkened overlay to focus attention on face area
                        Container(
                          color: Colors.black.withValues(alpha: 0.3),
                        ),

                        // Centered Face Guide Overlay
                        Center(
                          child: CustomPaint(
                            size: Size.infinite,
                            painter: FaceGuidePainter(
                              faceDetected: _faceDetectedInFrame,
                            ),
                          ),
                        ),

                        // Success Overlay
                        if (_faceCaptured)
                          Container(
                            color: Colors.black.withValues(alpha: 0.5),
                            child: const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                    size: 100,
                                  ),
                                  SizedBox(height: 20),
                                  Text(
                                    'Face Registered!',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    )
                  : const Center(
                      child: CircularProgressIndicator(
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.blue),
                      ),
                    ),
            ),
          ),

          // Status & Controls Section
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.grey[50],
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Status Message
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _faceDetectedInFrame
                          ? Colors.blue[50]
                          : Colors.orange[50],
                      border: Border.all(
                        color: _faceDetectedInFrame
                            ? Colors.blue
                            : Colors.orange,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _statusMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _faceDetectedInFrame
                                ? Colors.blue[900]
                                : Colors.orange[900],
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Progress Bar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: _captureProgress,
                            minHeight: 10,
                            backgroundColor: Colors.grey[300],
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _faceCaptured ? Colors.green : Colors.blue,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${(_captureProgress * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Instructions Box
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      border: Border.all(color: Colors.blue[200]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '📸 Registration Instructions:',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '• Position your face in the oval frame\n'
                          '• Ensure good lighting and clear visibility\n'
                          '• Face the camera directly\n'
                          '• Keep still - auto-capture when stable\n'
                          '• Do not wear sunglasses or hats',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Action Buttons
                  if (!_faceCaptured && !_isProcessing)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(
                                  color: Colors.grey, width: 2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (_isProcessing && !_faceCaptured)
                    const Center(
                      child: Column(
                        children: [
                          CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.blue),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Processing face data...',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FaceGuidePainter extends CustomPainter {
  final bool faceDetected;

  FaceGuidePainter({this.faceDetected = false});

  @override
  void paint(Canvas canvas, Size size) {
    // Draw oval guide frame
    final paint = Paint()
      ..color = (faceDetected ? Colors.green : Colors.blue).withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    final ovalWidth = size.width * 0.65;
    final ovalHeight = size.height * 0.75;

    final left = (size.width - ovalWidth) / 2;
    final top = (size.height - ovalHeight) / 2;

    final rect = Rect.fromLTWH(left, top, ovalWidth, ovalHeight);
    canvas.drawOval(rect, paint);

    // Draw corner markers
    final cornerPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    const cornerSize = 20.0;

    // Top-left
    canvas.drawLine(
      Offset(left, top),
      Offset(left + cornerSize, top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left, top),
      Offset(left, top + cornerSize),
      cornerPaint,
    );

    // Top-right
    canvas.drawLine(
      Offset(left + ovalWidth, top),
      Offset(left + ovalWidth - cornerSize, top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left + ovalWidth, top),
      Offset(left + ovalWidth, top + cornerSize),
      cornerPaint,
    );

    // Bottom-left
    canvas.drawLine(
      Offset(left, top + ovalHeight),
      Offset(left + cornerSize, top + ovalHeight),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left, top + ovalHeight),
      Offset(left, top + ovalHeight - cornerSize),
      cornerPaint,
    );

    // Bottom-right
    canvas.drawLine(
      Offset(left + ovalWidth, top + ovalHeight),
      Offset(left + ovalWidth - cornerSize, top + ovalHeight),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left + ovalWidth, top + ovalHeight),
      Offset(left + ovalWidth, top + ovalHeight - cornerSize),
      cornerPaint,
    );

    // Draw text instruction
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'Align your face here',
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        top - 50,
      ),
    );
  }

  @override
  bool shouldRepaint(FaceGuidePainter oldDelegate) =>
      faceDetected != oldDelegate.faceDetected;
}
