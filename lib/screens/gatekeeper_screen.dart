import 'dart:convert';
import '../zk/zk_engine.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/event_service.dart';
import '../services/camera_service.dart';
import '../services/enhanced_face_detection_service.dart';
import '../models/ticket.dart';

class GatekeeperScreen extends StatefulWidget {
  const GatekeeperScreen({super.key});

  @override
  State<GatekeeperScreen> createState() => _GatekeeperScreenState();
}

class _GatekeeperScreenState extends State<GatekeeperScreen> {
  final EventService _eventService = EventService();
  final CameraService _cameraService = CameraService();
  final TextEditingController _ticketIdController = TextEditingController();
  late FaceDetector _faceDetector;
  Ticket? _selectedTicket;
  bool _isLoading = true;
  bool _isCameraPermissionGranted = false;
  bool _isVerifying = false;
  String? _verificationMessage;
  Color? _messageColor;
  bool _showCamera = false;
  bool _canSwitchCamera = false;

  @override
  void initState() {
    super.initState();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableClassification: true,
      ),
    );
    _loadRegisteredTickets();
    _requestCameraPermission();
  }

  void _loadRegisteredTickets() async {
    try {
      // Load application ready state
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      // If loading fails, still proceed
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _requestCameraPermission() async {
    try {
      final status = await Permission.camera.request();

      if (status.isDenied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Camera permission is required for entry verification. Please grant permission.'),
              duration: Duration(seconds: 3),
            ),
          );
          // Retry after delay
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              _requestCameraPermission();
            }
          });
        }
      } else if (status.isPermanentlyDenied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Camera permission permanently denied. Please enable in settings.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
      } else if (status.isGranted) {
        _initializeCamera();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Permission request error: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _initializeCamera() async {
    try {
      await _cameraService.initializeCamera(cameraIndex: 0);
      
      final hasMultipleCameras = (await _cameraService.getAvailableCameras()).length > 1;

      if (mounted) {
        setState(() {
          _isCameraPermissionGranted = true;
          _canSwitchCamera = hasMultipleCameras;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera initialization error: ${e.toString()}')),
        );
      }
    }
  }

  void _switchCamera() async {
    try {
      setState(() {
        _isVerifying = true;
        _showCamera = false;
      });
      
      await _cameraService.switchCamera();

      if (mounted) {
        setState(() {
          _isVerifying = false;
          _showCamera = true;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera switched successfully'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _showCamera = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera switch error: $e')),
        );
      }
    }
  }

  Future<void> _captureFaceAndVerify() async {
    // Prevent multiple verification attempts
    if (_isVerifying || _verificationMessage != null) {
      return;
    }

    if (_selectedTicket == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a ticket first')),
      );
      return;
    }

    if (_cameraService.cameraController == null || 
        !_cameraService.cameraController!.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera not ready')),
      );
      return;
    }

    setState(() => _isVerifying = true);

    try {
      // Capture photo
      final XFile picturefile = await _cameraService.takePicture();

      // Detect face landmarks
      final inputImage = InputImage.fromFilePath(picturefile.path);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        if (mounted) {
          setState(() {
            _verificationMessage = '❌ No face detected. Please try again.';
            _messageColor = Colors.orange;
            _isVerifying = false;
          });
        }
        return;
      }

      // Check if ticket has registered face
      if (_selectedTicket!.facialFeatures == null || _selectedTicket!.facialFeatures!.isEmpty) {
        if (mounted) {
          setState(() {
            _verificationMessage = '❌ Face Not Registered.\nPlease register face first.';
            _messageColor = Colors.red;
            _isVerifying = false;
          });
        }
        return;
      }

      final face = faces.first;
      
      // Extract 68 expanded landmarks using enhanced service
      List<double> capturedLandmarks = EnhancedFaceDetectionService.extractExpanded68Landmarks(face);

      // Decode securely-stored payload containing registered landmarks
      String decodedJson = utf8.decode(base64Decode(_selectedTicket!.facialFeatures!));
      List<dynamic> jsonList = jsonDecode(decodedJson);
      List<double> registeredLandmarks = jsonList.map((x) => (x as num).toDouble()).toList();

      // Pad or truncate safely if lengths somehow mismatch
      List<double> safeCaptured = List.from(capturedLandmarks);
      if (safeCaptured.length < registeredLandmarks.length) {
        safeCaptured.addAll(List.filled(registeredLandmarks.length - safeCaptured.length, 0.0));
      } else if (safeCaptured.length > registeredLandmarks.length) {
        safeCaptured = safeCaptured.sublist(0, registeredLandmarks.length);
      }

      // Calculate similarity with makeup tolerance securely mimicking ZK matching rules
      double similarity = ZKEngine.calculateSimilarityWithMakeupTolerance(safeCaptured, registeredLandmarks);
      bool isVerified = similarity >= ZKEngine.makeupToleranceThreshold;

      if (mounted) {
        if (isVerified) {
          // Face matched - Grant entry
          setState(() {
            _verificationMessage = '✅ Face Verified!\nSimilarity: ${(similarity * 100).toStringAsFixed(2)}%\nEntry Granted';
            _messageColor = Colors.green;
            _isVerifying = false;
            _selectedTicket = _selectedTicket!.copyWith(
              isVerified: true,
              registrationStatus: 'verified',
            );
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Entry Verification Successful - Entry Granted'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );

          // Update ticket status in database
          await _eventService.verifyAndUpdateTicket(
            ticketId: _selectedTicket!.id,
            isVerified: true,
            verificationStatus: 'verified',
            matchSimilarity: similarity,
            matchStatus: 'good_match',
          );
        } else {
          // Face does not match - Deny entry
          setState(() {
            _verificationMessage = '❌ Biometric Match Failed\nSimilarity: ${(similarity * 100).toStringAsFixed(2)}%\nEntry Denied';
            _messageColor = Colors.red;
            _isVerifying = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Biometric verification failed - Entry Denied'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );

          // Update ticket status in database
          await _eventService.verifyAndUpdateTicket(
            ticketId: _selectedTicket!.id,
            isVerified: false,
            verificationStatus: 'denied',
            matchSimilarity: similarity,
            matchStatus: 'no_match',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _verificationMessage = '❌ Verification error: ${e.toString()}';
          _messageColor = Colors.red;
          _isVerifying = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _manualTicketVerification(String ticketId) async {
    setState(() => _isVerifying = true);

    try {
      final ticket = await _eventService.getTicketById(ticketId);

      if (ticket == null) {
        if (mounted) {
          setState(() {
            _verificationMessage = '❌ Ticket not found.';
            _messageColor = Colors.red;
            _isVerifying = false;
          });
        }
        return;
      }

      if (!ticket.isRegistered) {
        if (mounted) {
          setState(() {
            _verificationMessage = '❌ Ticket not registered yet.';
            _messageColor = Colors.orange;
            _isVerifying = false;
          });
        }
        return;
      }

      if (ticket.isVerified && ticket.usedAt != null) {
        if (mounted) {
          setState(() {
            _verificationMessage =
                '❌ Ticket already used at:\n${ticket.usedAt!.toLocal().toString().split('.')[0]}';
            _messageColor = Colors.red;
            _isVerifying = false;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _selectedTicket = ticket;
          _ticketIdController.text = ticket.id;
          _verificationMessage = 'Ticket found. Ready for face verification.';
          _messageColor = Colors.blue;
          _isVerifying = false;
          _showCamera = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _verificationMessage = '❌ Error: ${e.toString()}';
          _messageColor = Colors.red;
          _isVerifying = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _cameraService.dispose();
    _ticketIdController.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Gatekeeper - Verification'),
          backgroundColor: Colors.deepPurple,
          elevation: 4,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gatekeeper - Verification'),
        backgroundColor: Colors.deepPurple,
        elevation: 4,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Manual Ticket ID input
              Card(
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Enter Ticket ID',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _ticketIdController,
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w500,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Paste or scan ticket ID',
                                hintStyle: const TextStyle(color: Colors.grey),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Colors.deepPurple,
                                    width: 2,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Colors.deepPurple,
                                    width: 2,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Colors.deepPurple,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: _isVerifying
                                ? null
                                : () =>
                                    _manualTicketVerification(_ticketIdController.text),
                            icon: const Icon(Icons.search, color: Colors.white),
                            label: const Text(
                              'FIND',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              elevation: 3,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Selected ticket details
              if (_selectedTicket != null) ...[
                Card(
                  elevation: 3,
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ticket Details',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildTicketDetailRow('Attendee:', _selectedTicket!.attendeeName),
                        _buildTicketDetailRow('Email:', _selectedTicket!.attendeeEmail),
                        _buildTicketDetailRow('Ticket ID:', _selectedTicket!.id),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _selectedTicket!.isRegistered
                                ? Colors.green.shade100
                                : Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _selectedTicket!.isRegistered
                                  ? Colors.green
                                  : Colors.orange,
                              width: 2,
                            ),
                          ),
                          child: Text(
                            _selectedTicket!.isRegistered
                                ? '✓ Status: REGISTERED'
                                : '⚠ Status: PENDING',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _selectedTicket!.isRegistered
                                  ? Colors.green.shade900
                                  : Colors.orange.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Camera section
              if (_showCamera && _isCameraPermissionGranted && !_selectedTicket!.isVerified) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.shade50,
                    border: Border.all(
                      color: Colors.deepPurple,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Capture Face for Verification',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_cameraService.cameraController != null &&
                          _cameraService.cameraController!.value.isInitialized)
                        Container(
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
                            child: CameraPreview(_cameraService.cameraController!),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 56,
                              child: ElevatedButton.icon(
                                onPressed: _isVerifying ? null : _captureFaceAndVerify,
                                icon: _isVerifying
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : const Icon(Icons.camera_alt,
                                        color: Colors.white, size: 24),
                                label: Text(
                                  _isVerifying ? 'VERIFYING...' : 'CAPTURE & VERIFY',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.deepPurple,
                                  elevation: 4,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (_canSwitchCamera) ...[
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 56,
                              height: 56,
                              child: ElevatedButton(
                                onPressed: _isVerifying ? null : _switchCamera,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.grey.shade600,
                                  elevation: 4,
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.flip_camera_android,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
              

              // Success State
              if (_selectedTicket != null && (_selectedTicket?.isVerified ?? false)) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    border: Border.all(color: Colors.green, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 64),
                      SizedBox(height: 16),
                      Text(
                        'Entry Granted',
                        style: TextStyle(
                           fontSize: 24,
                           fontWeight: FontWeight.bold,
                           color: Colors.green,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Ticket successfully verified.',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Verification result
              if (_verificationMessage != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _messageColor?.withValues(alpha: 0.1),
                    border: Border.all(
                      color: _messageColor ?? Colors.grey,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _verificationMessage!,
                        style: TextStyle(
                          color: _messageColor ?? Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTicketDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
