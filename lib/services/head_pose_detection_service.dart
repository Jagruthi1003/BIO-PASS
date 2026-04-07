import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter/material.dart';
import 'dart:math';

/// Service to detect head pose (yaw, pitch, roll) for face verification
/// Helps detect when user turns head left/right during registration and verification
class HeadPoseDetectionService {
  /// Detect head pose angles from face data
  /// Returns: {yaw: angle, pitch: angle, roll: angle, direction: 'center'/'left'/'right'}
  static Map<String, dynamic> detectHeadPose(Face face) {
    try {
      // Calculate yaw (left-right head rotation)
      double yaw = _calculateYaw(face);
      
      // Calculate pitch (up-down head tilt)
      double pitch = _calculatePitch(face);
      
      // Calculate roll (head tilt left-right)
      double roll = _calculateRoll(face);
      
      // Determine direction based on yaw
      String direction = 'center';
      if (yaw > 15) {
        direction = 'right'; // Head turned right
      } else if (yaw < -15) {
        direction = 'left'; // Head turned left
      }
      
      return {
        'yaw': yaw,
        'pitch': pitch,
        'roll': roll,
        'direction': direction,
        'turnDegree': yaw.abs(),
      };
    } catch (e) {
      return {
        'yaw': 0.0,
        'pitch': 0.0,
        'roll': 0.0,
        'direction': 'error',
        'error': e.toString(),
      };
    }
  }

  /// Calculate yaw (left-right rotation) from face landmarks
  /// Yaw > 0 = head turned right, Yaw < 0 = head turned left
  static double _calculateYaw(Face face) {
    try {
      final landmarks = face.landmarks;
      
      // Get left and right eye positions if available
      FaceLandmark? leftEyeLandmark = landmarks[FaceLandmarkType.leftEye];
      FaceLandmark? rightEyeLandmark = landmarks[FaceLandmarkType.rightEye];
      
      if (leftEyeLandmark == null || rightEyeLandmark == null) {
        return 0.0;
      }
      
      final leftEye = leftEyeLandmark.position;
      final rightEye = rightEyeLandmark.position;
      
      // Get nose position
      FaceLandmark? noseLandmark = landmarks[FaceLandmarkType.noseBase];
      if (noseLandmark == null) {
        return 0.0;
      }
      
      final nose = noseLandmark.position;
      
      // Calculate eye center
      double eyeCenterX = (leftEye.x.toDouble() + rightEye.x.toDouble()) / 2;
      
      // If nose is significantly to the right of eye center -> head turned left (negative)
      // If nose is significantly to the left of eye center -> head turned right (positive)
      double noseDeviation = nose.x.toDouble() - eyeCenterX;
      
      // Normalize by inter-ocular distance
      double interOcularDistance = (rightEye.x.toDouble() - leftEye.x.toDouble()).abs();
      if (interOcularDistance == 0) return 0.0;
      
      // Convert to approximate yaw angle (in degrees)
      double yaw = (noseDeviation / interOcularDistance) * 40; // Scale to ~40 degree range
      
      return yaw.clamp(-45.0, 45.0);
    } catch (e) {
      return 0.0;
    }
  }

  /// Calculate pitch (up-down rotation) from face landmarks
  /// Pitch > 0 = head tilted up, Pitch < 0 = head tilted down
  static double _calculatePitch(Face face) {
    try {
      final landmarks = face.landmarks;
      
      FaceLandmark? leftEyeLandmark = landmarks[FaceLandmarkType.leftEye];
      FaceLandmark? noseLandmark = landmarks[FaceLandmarkType.noseBase];
      
      if (leftEyeLandmark == null || noseLandmark == null) {
        return 0.0;
      }
      
      final leftEye = leftEyeLandmark.position;
      final nose = noseLandmark.position;
      
      // If nose is above eye -> head looking down (negative pitch)
      // If nose is below eye -> head looking up (positive pitch)
      double nosePitchDeviation = leftEye.y.toDouble() - nose.y.toDouble();
      
      // Normalize by face height
      Rect boundingBox = face.boundingBox;
      if (boundingBox.height == 0) return 0.0;
      
      double pitch = (nosePitchDeviation / boundingBox.height) * 30;
      
      return pitch.clamp(-45.0, 45.0);
    } catch (e) {
      return 0.0;
    }
  }

  /// Calculate roll (head tilt left-right) from face landmarks
  /// Roll > 0 = head tilted right, Roll < 0 = head tilted left
  static double _calculateRoll(Face face) {
    try {
      final landmarks = face.landmarks;
      
      FaceLandmark? leftEyeLandmark = landmarks[FaceLandmarkType.leftEye];
      FaceLandmark? rightEyeLandmark = landmarks[FaceLandmarkType.rightEye];
      
      if (leftEyeLandmark == null || rightEyeLandmark == null) {
        return 0.0;
      }
      
      final leftEye = leftEyeLandmark.position;
      final rightEye = rightEyeLandmark.position;
      
      // Calculate angle between eyes
      double eyeDeltaX = rightEye.x.toDouble() - leftEye.x.toDouble();
      double eyeDeltaY = rightEye.y.toDouble() - leftEye.y.toDouble();
      
      // Calculate angle in radians, then convert to degrees
      double angleRadians = atan2(eyeDeltaY, eyeDeltaX);
      double angleDegrees = angleRadians * (180 / pi);
      
      // Normalize so 0 degrees = horizontal eyes
      double roll = angleDegrees - 0; // Assumes eyes are horizontal when aligned
      
      return roll.clamp(-45.0, 45.0);
    } catch (e) {
      return 0.0;
    }
  }

  /// Check if head pose meets requirements for registration/verification
  /// Requirements: 
  /// - Center position: yaw between -10 and 10
  /// - Left position: yaw < -15
  /// - Right position: yaw > 15
  static bool isHeadPoseValid(
    Map<String, dynamic> headPose, {
    required String requiredDirection, // 'center', 'left', 'right'
  }) {
    double yaw = headPose['yaw'] as double;
    String direction = headPose['direction'] as String;
    
    switch (requiredDirection) {
      case 'center':
        return yaw.abs() < 10;
      case 'left':
        return direction == 'left';
      case 'right':
        return direction == 'right';
      default:
        return false;
    }
  }

  /// Get user-friendly instruction text based on head pose
  static String getInstructionText(Map<String, dynamic> headPose) {
    String direction = headPose['direction'] as String;
    double turnDegree = (headPose['turnDegree'] as double?)?.abs() ?? 0;
    
    if (direction == 'error') {
      return 'Face detection error - please try again';
    }
    
    if (direction == 'center') {
      return 'Look straight at camera ✓';
    } else if (direction == 'left') {
      return 'Turn head more to the left (${turnDegree.toStringAsFixed(0)}°)';
    } else if (direction == 'right') {
      return 'Turn head more to the right (${turnDegree.toStringAsFixed(0)}°)';
    }
    
    return 'Adjust head position';
  }

  /// Multi-angle capture for enhanced verification
  /// Captures landmarks at center, left (25°), and right (25°) angles
  static bool isMultiAngleCaptureComplete(
    List<Map<String, dynamic>> capturedPoses,
  ) {
    if (capturedPoses.length < 3) return false;
    
    // Check that we have captures from different directions
    bool hasCenter = capturedPoses.any((p) => (p['direction'] as String) == 'center');
    bool hasLeft = capturedPoses.any((p) => (p['direction'] as String) == 'left');
    bool hasRight = capturedPoses.any((p) => (p['direction'] as String) == 'right');
    
    return hasCenter && hasLeft && hasRight;
  }

  /// Calculate confidence score for head pose stability
  /// Returns value between 0 and 1
  static double calculatePoseConfidence(
    Map<String, dynamic> headPose,
  ) {
    double yaw = (headPose['yaw'] as double).abs();
    double pitch = (headPose['pitch'] as double).abs();
    double roll = (headPose['roll'] as double).abs();
    
    // Lower angles = higher confidence
    double yawConfidence = 1.0 - (yaw / 45.0);
    double pitchConfidence = 1.0 - (pitch / 45.0);
    double rollConfidence = 1.0 - (roll / 45.0);
    
    // Average the three
    double avgConfidence = (yawConfidence + pitchConfidence + rollConfidence) / 3;
    
    return avgConfidence.clamp(0.0, 1.0);
  }
}
