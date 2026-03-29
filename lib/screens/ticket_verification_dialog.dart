import 'dart:convert';
import '../zk/zk_engine.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/ticket.dart';
import '../services/event_service.dart';
import '../services/camera_service.dart';
import '../services/enhanced_face_detection_service.dart';
import '../services/local_storage_service.dart';

class TicketVerificationDialog extends StatefulWidget {
  final Ticket ticket;
  final Function(bool) onVerificationComplete;

  const TicketVerificationDialog({
    super.key,
    required this.ticket,
    required this.onVerificationComplete,
  });

  @override
  State<TicketVerificationDialog> createState() => _TicketVerificationDialogState();
}

class _TicketVerificationDialogState extends State<TicketVerificationDialog> {
  final EventService _eventService = EventService();
  final CameraService _cameraService = CameraService();
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      enableClassification: true,
    ),
  );

  bool _isVerifying = false;
  String? _verificationMessage;
  Color? _messageColor;
  bool _isCameraInitialized = false;
  bool _canSwitchCamera = false;
  bool _isVerified = false;
  bool _showCamera = false;

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
  }

  void _requestCameraPermission() async {
    try {
      final status = await Permission.camera.request();

      if (status.isDenied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Camera permission is required for verification'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else if (status.isPermanentlyDenied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Camera permission permanently denied'),
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
            content: Text('Permission error: $e'),
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
          _isCameraInitialized = true;
          _canSwitchCamera = hasMultipleCameras;
          _showCamera = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera init error: ${e.toString()}')),
        );
      }
    }
  }

  void _switchCamera() async {
    try {
      setState(() {
        _isVerifying = true;
        _isCameraInitialized = false;
      });
      
      await _cameraService.switchCamera();

      if (mounted) {
        setState(() {
          _isVerifying = false;
          _isCameraInitialized = true;
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
          _isCameraInitialized = true;
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
      final XFile pictureFile = await _cameraService.takePicture();

      // Detect face landmarks
      final inputImage = InputImage.fromFilePath(pictureFile.path);
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

      // Decode securely-stored payload containing registered landmarks
      List<double>? registeredLandmarks;
      
      if (widget.ticket.facialFeatures != null && widget.ticket.facialFeatures!.isNotEmpty) {
        String decodedJson = utf8.decode(base64Decode(widget.ticket.facialFeatures!));
        List<dynamic> jsonList = jsonDecode(decodedJson);
        registeredLandmarks = jsonList.map((x) => (x as num).toDouble()).toList();
      } else {
        // Fallback to local storage
        registeredLandmarks = await LocalStorageService.getFacialFeatures(widget.ticket.id);
      }

      if (registeredLandmarks == null || registeredLandmarks.isEmpty) {
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
            _isVerified = true;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Verification Successful - Entry Granted'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );

          // Update ticket status in database
          await _eventService.verifyAndUpdateTicket(
            ticketId: widget.ticket.id,
            isVerified: true,
            verificationStatus: 'verified',
            matchSimilarity: similarity,
            matchStatus: 'good_match',
          );

          await Future.delayed(const Duration(seconds: 2));
          
          if (mounted) {
            widget.onVerificationComplete(true);
            Navigator.of(context).pop(true);
          }
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

          // Update ticket status in database for denial
          await _eventService.verifyAndUpdateTicket(
            ticketId: widget.ticket.id,
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

  @override
  void dispose() {
    _cameraService.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Verify Ticket',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Attendee info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue, width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Attendee: ${widget.ticket.attendeeName}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ticket ID: ${widget.ticket.id}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Camera section
              if (_isCameraInitialized && _showCamera && !_isVerified) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.deepPurple,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Position your face in the camera',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_cameraService.cameraController != null &&
                          _cameraService.cameraController!.value.isInitialized)
                        Container(
                          width: 400,
                          height: 500,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.deepPurple, width: 2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CameraPreview(_cameraService.cameraController!),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: ElevatedButton.icon(
                                onPressed: _isVerifying ? null : _captureFaceAndVerify,
                                icon: _isVerifying
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(
                                            Colors.white,
                                          ),
                                        ),
                                      )
                                    : const Icon(Icons.camera_alt,
                                        color: Colors.white, size: 18),
                                label: Text(
                                  _isVerifying ? 'VERIFYING...' : 'CAPTURE & VERIFY',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.deepPurple,
                                  elevation: 3,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (_canSwitchCamera) ...[
                            const SizedBox(width: 8),
                            SizedBox(
                              height: 48,
                              width: 48,
                              child: ElevatedButton(
                                onPressed: _isVerifying ? null : _switchCamera,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.grey.shade600,
                                  elevation: 2,
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.flip_camera_android,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              if (_isVerified) ...[
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
              if (_verificationMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _messageColor?.withValues(alpha: 0.1),
                    border: Border.all(
                      color: _messageColor ?? Colors.grey,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _verificationMessage!,
                    style: TextStyle(
                      color: _messageColor ?? Colors.black,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Close button
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade600,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
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
