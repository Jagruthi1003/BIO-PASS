import 'package:flutter/material.dart';

/// Standardized face capture constants for consistent registration and verification
class FaceCaptureConstants {
  // Standardized face capture frame dimensions
  static const double faceFrameWidth = 200.0;
  static const double faceFrameHeight = 250.0;
  static const double faceFrameBorderRadius = 20.0;
  static const double faceFrameBorderWidth = 3.0;

  // Camera preview dimensions during registration
  static const double cameraPreviewWidth = 400.0;
  static const double cameraPreviewHeight = 500.0;
  static const double cameraPreviewBorderRadius = 12.0;

  // Verification thresholds (adjusted for makeup tolerance)
  static const double highMatchThreshold = 0.80; // Excellent match
  static const double goodMatchThreshold = 0.70; // Good match
  static const double acceptableMatchThreshold = 0.65; // Acceptable match with makeup
  static const double poorMatchThreshold = 0.50; // Poor match - retry

  // Messages for verification results
  static const String facePerfectMatchMessage = '✅ Perfect Face Match! Entry Granted';
  static const String faceGoodMatchMessage = '✅ Face Verified! Entry Granted';
  static const String faceAcceptableMatchMessage = '✅ Face Verified! Entry Granted';
  static const String facePoorMatchMessage = '⚠️ Face Quality Low - Please Try Again';
  static const String faceNoMatchMessage = '❌ Face Does Not Match - Entry Denied';
  static const String faceNotDetectedMessage = '❌ No Face Detected - Please Try Again';
  static const String faceNotRegisteredMessage = '❌ Face Not Registered - Please Register First';

  /// Get verification message based on similarity score
  static String getVerificationMessage(double similarity) {
    if (similarity >= highMatchThreshold) {
      return facePerfectMatchMessage;
    } else if (similarity >= goodMatchThreshold) {
      return faceGoodMatchMessage;
    } else if (similarity >= acceptableMatchThreshold) {
      return faceAcceptableMatchMessage;
    } else if (similarity >= poorMatchThreshold) {
      return facePoorMatchMessage;
    } else {
      return faceNoMatchMessage;
    }
  }

  /// Get color based on similarity score
  static Color getVerificationColor(double similarity) {
    if (similarity >= acceptableMatchThreshold) {
      return const Color(0xFF4CAF50); // Green
    } else if (similarity >= poorMatchThreshold) {
      return const Color(0xFFFF9800); // Orange
    } else {
      return const Color(0xFFF44336); // Red
    }
  }

  /// Get icon based on verification status
  static IconData getVerificationIcon(bool isVerified) {
    return isVerified ? Icons.check_circle : Icons.cancel;
  }
}
