import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/event.dart';
import '../models/user.dart';
import '../services/event_service.dart';
import '../services/enhanced_face_detection_service.dart';

class FaceRegistrationScreen extends StatefulWidget {
  final Event event;
  final User user;
  final VoidCallback onRegistrationComplete;

  const FaceRegistrationScreen({
    super.key,
    required this.event,
    required this.user,
    required this.onRegistrationComplete,
  });

  @override
  State<FaceRegistrationScreen> createState() => _FaceRegistrationScreenState();
}

class _FaceRegistrationScreenState extends State<FaceRegistrationScreen> {
  CameraController? _cameraController;
  late FaceDetector _faceDetector;
  bool _isCameraPermissionGranted = false;
  bool _isCapturing = false;
  bool _isProcessing = false;
  List<double>? _capturedLandmarks;
  String? _ticketId;
  String _currentStep = 'permission'; // permission, camera, captured, registered
  int _selectedCameraIndex = 0;
  bool _canSwitchCamera = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableClassification: true,
      ),
    );
  }

  Future<void> _initializeCamera({int cameraIndex = 0}) async {
    if (kIsWeb) {
      // Web doesn't support camera access - show message
      if (mounted) {
        setState(() {
          _currentStep = 'web_not_supported';
        });
      }
      return;
    }

    try {
      // Request camera permission with explicit handling
      final status = await Permission.camera.request();
      
      if (status.isGranted) {
        final cameras = await availableCameras();
        if (cameras.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No camera found on this device.'),
                duration: Duration(seconds: 3),
              ),
            );
          }
          return;
        }
        
        // Ensure camera index is valid
        if (cameraIndex >= cameras.length) {
          cameraIndex = 0;
        }
        
        await _cameraController?.dispose();
        
        _cameraController = CameraController(
          cameras[cameraIndex],
          ResolutionPreset.high,
          enableAudio: false,
        );
        
        await _cameraController!.initialize();
        
        final hasMultipleCameras = cameras.length > 1;
        
        if (mounted) {
          setState(() {
            _isCameraPermissionGranted = true;
            _currentStep = 'camera';
            _selectedCameraIndex = cameraIndex;
            _canSwitchCamera = hasMultipleCameras;
          });
        }
      } else if (status.isDenied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Camera permission is required for face registration. Please grant permission.'),
              duration: Duration(seconds: 4),
            ),
          );
          // Retry after user dismisses message
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              _initializeCamera(cameraIndex: cameraIndex);
            }
          });
        }
      } else if (status.isPermanentlyDenied) {
        if (mounted) {
          _showPermissionDialog();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera initialization error: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Camera Permission Required'),
        content: const Text(
          'Camera access is permanently denied. Please enable it in app settings to continue with face registration.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              openAppSettings();
              Navigator.pop(context);
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
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

  Future<void> _captureFace() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    setState(() => _isCapturing = true);

    try {
      // Take a picture
      final XFile picturefile = await _cameraController!.takePicture();
      
      // Detect faces and extract landmarks
      final inputImage = InputImage.fromFilePath(picturefile.path);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isNotEmpty) {
        final face = faces.first;
        
        // Extract 68 expanded landmarks using enhanced service
        List<double> landmarks = EnhancedFaceDetectionService.extractExpanded68Landmarks(face);

        if (landmarks.isNotEmpty && EnhancedFaceDetectionService.isValidLandmarkData(landmarks)) {
          if (mounted) {
            setState(() {
              _capturedLandmarks = landmarks;
              _currentStep = 'captured';
              _isCapturing = false;
            });

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✓ Face landmarks captured (${landmarks.length ~/ 2} points)!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not detect landmarks. Please try again.'),
                backgroundColor: Colors.orange,
              ),
            );
            setState(() => _isCapturing = false);
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No face detected. Please try again.'),
              backgroundColor: Colors.orange,
            ),
          );
          setState(() => _isCapturing = false);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error capturing face: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isCapturing = false);
      }
    }
  }

  Future<void> _registerFace() async {
    if (_capturedLandmarks == null || _capturedLandmarks!.isEmpty) return;

    setState(() => _isProcessing = true);

    try {
      final eventService = EventService();

      // Create a ticket for the attendee
      await eventService.registerAttendeeForEvent(
        eventId: widget.event.id,
        attendeeId: widget.user.uid,
        attendeeName: widget.user.name,
        attendeeEmail: widget.user.email,
      );

      // Get the ticket that was just created
      final ticket = await eventService.getTicketByEventAndAttendee(
        widget.event.id,
        widget.user.uid,
      );

      if (ticket != null) {
        // Update ticket with face landmarks and generate ZK proof
        await eventService.updateTicketWithFaceLandmarks(
          ticketId: ticket.id,
          faceLandmarks: _capturedLandmarks!,
        );

        if (mounted) {
          setState(() {
            _ticketId = ticket.id;
            _currentStep = 'registered';
            _isProcessing = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ Registration successful! Ticket ID: ${ticket.id}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Registration failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isProcessing = false);
      }
    }
  }

  void _retakeFace() {
    setState(() {
      _capturedLandmarks = null;
      _currentStep = 'camera';
    });
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Face Registration'),
          backgroundColor: Colors.deepPurple,
        ),
        body: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    switch (_currentStep) {
      case 'permission':
        return _buildPermissionScreen();
      case 'camera':
        return _buildCameraScreen();
      case 'web_not_supported':
        return _buildWebNotSupportedScreen();
      case 'captured':
        return _buildCapturedScreen();
      case 'registered':
        return _buildRegisteredScreen();
      default:
        return _buildPermissionScreen();
    }
  }

  Widget _buildPermissionScreen() {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.camera_alt,
              size: 80,
              color: Colors.deepPurple.shade700,
            ),
            const SizedBox(height: 24),
            const Text(
              'Camera Permission Required',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.deepPurple,
                    width: 2,
                  ),
                ),
                child: const Text(
                  'We need access to your camera to capture your face for secure access verification. Your face data will be used only for this event.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.deepPurple,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _initializeCamera,
              icon: const Icon(Icons.camera_alt, color: Colors.white, size: 24),
              label: const Text(
                'GRANT CAMERA PERMISSION',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple.shade700,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraScreen() {
    if (!_isCameraPermissionGranted || _cameraController == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        // Full screen background
        Container(color: Colors.black),
        
        // Centered camera preview with medium size
        Center(
          child: SizedBox(
            width: 400,
            height: 500,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CameraPreview(_cameraController!),
            ),
          ),
        ),

        // Top instruction overlay
        Positioned(
          top: 24,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade700,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Position your face in the center',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),

        // Camera switch button (top right)
        if (_canSwitchCamera)
          Positioned(
            top: 24,
            right: 24,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: Colors.deepPurple.shade700,
              onPressed: _switchCamera,
              tooltip: 'Switch Camera',
              child: const Icon(Icons.flip_camera_android, color: Colors.white),
            ),
          ),

        // Bottom capture button
        Positioned(
          bottom: 32,
          left: 0,
          right: 0,
          child: Center(
            child: ElevatedButton.icon(
              onPressed: _isCapturing ? null : _captureFace,
              icon: _isCapturing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.camera, color: Colors.white),
              label: Text(
                _isCapturing ? 'Capturing...' : 'CAPTURE FACE',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple.shade700,
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 8,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWebNotSupportedScreen() {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.computer,
                size: 80,
                color: Colors.orange.shade700,
              ),
              const SizedBox(height: 24),
              const Text(
                'Camera Not Available',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.orange.shade300,
                      width: 2,
                    ),
                  ),
                  child: const Text(
                    'Face registration requires camera access. The web version does not support direct camera access.\n\n'
                    'Please use a mobile device or desktop application with a connected camera for face registration.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.orange,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                label: const Text(
                  'GO BACK',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple.shade700,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCapturedScreen() {
    if (_capturedLandmarks == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 12),
            const Icon(Icons.check_circle, size: 64, color: Colors.green),
            const SizedBox(height: 12),
            const Text(
              'Face Captured!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '✓ ${_capturedLandmarks!.length} facial landmarks detected',
                      style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Event: ${widget.event.name}',
                      style: const TextStyle(fontSize: 12, color: Colors.deepPurple),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isProcessing ? null : _retakeFace,
                    icon: const Icon(Icons.camera_alt, color: Colors.deepPurple, size: 18),
                    label: const Text(
                      'Retake',
                      style: TextStyle(
                        color: Colors.deepPurple,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.deepPurple, width: 2),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _registerFace,
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.lock, color: Colors.white, size: 18),
                    label: Text(
                      _isProcessing ? 'Registering...' : 'Register',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegisteredScreen() {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.verified, size: 80, color: Colors.green),
              const SizedBox(height: 16),
              const Text(
                'Registration Complete!',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      const Text(
                        'Event:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.deepPurple,
                        ),
                      ),
                      Text(
                        widget.event.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Ticket ID:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.deepPurple,
                        ),
                      ),
                      SelectableText(
                        _ticketId ?? 'N/A',
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Colors.deepPurple,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green, width: 2),
                        ),
                        child: const Text(
                          'Your face has been registered with Biometric Match. '
                          'You can now use this ticket for entry verification.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
