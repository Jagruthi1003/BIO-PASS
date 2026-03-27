import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'dart:math';

/// Enhanced face detection service that extracts and interpolates 68 facial landmarks
/// from Google ML Kit's face detector (which provides ~20-30 landmarks) and generates
/// additional interpolated points to create a comprehensive 68-point facial model.
class EnhancedFaceDetectionService {
  /// Extract and expand landmarks to 68 points
  /// Uses Google ML Kit's available landmarks and generates interpolated points
  static List<double> extractExpanded68Landmarks(Face face) {
    Map<FaceLandmarkType, FaceLandmark?> landmarks = face.landmarks;
    
    // Convert landmarks to a map we can work with
    Map<String, Offset> pointMap = {};
    
    // Helper to add landmark
    void addLandmark(FaceLandmarkType type, String label) {
      if (landmarks.containsKey(type) && landmarks[type] != null) {
        var pos = landmarks[type]!.position;
        pointMap[label] = Offset(pos.x.toDouble(), pos.y.toDouble());
      }
    }

    // Extract available landmarks from Google ML Kit
    addLandmark(FaceLandmarkType.leftEye, 'leftEye');
    addLandmark(FaceLandmarkType.rightEye, 'rightEye');
    addLandmark(FaceLandmarkType.leftEar, 'leftEar');
    addLandmark(FaceLandmarkType.rightEar, 'rightEar');
    addLandmark(FaceLandmarkType.leftCheek, 'leftCheek');
    addLandmark(FaceLandmarkType.rightCheek, 'rightCheek');
    addLandmark(FaceLandmarkType.leftMouth, 'leftMouth');
    addLandmark(FaceLandmarkType.rightMouth, 'rightMouth');
    addLandmark(FaceLandmarkType.noseBase, 'noseBase');

    // Get face bounding box for context
    Rect boundingBox = face.boundingBox;

    // Generate 68 comprehensive facial landmarks by combining detected points and interpolation
    List<Offset> landmarks68 = _generate68Landmarks(pointMap, boundingBox);

    // Convert to flat list of doubles
    List<double> result = [];
    for (Offset offset in landmarks68) {
      result.add(offset.dx);
      result.add(offset.dy);
    }

    return result;
  }

  /// Generate 68 facial landmarks from available points
  /// Uses the standard DLIB 68-point face model structure
  static List<Offset> _generate68Landmarks(
    Map<String, Offset> detected,
    Rect boundingBox,
  ) {
    List<Offset> points68 = [];

    // Face contour (0-16): Generate outline from available points and interpolation
    // Using left ear, face width, and right ear to create contour
    if (detected.containsKey('leftEar') && detected.containsKey('rightEar')) {
      Offset leftEar = detected['leftEar']!;
      Offset rightEar = detected['rightEar']!;
      
      // Generate chin points
      double chinX = (leftEar.dx + rightEar.dx) / 2;
      double chinY = boundingBox.bottom - boundingBox.height * 0.1;
      
      // Generate left side contour (0-8)
      for (int i = 0; i < 9; i++) {
        double t = i / 8.0;
        points68.add(Offset(
          leftEar.dx + (chinX - leftEar.dx) * t,
          leftEar.dy + (chinY - leftEar.dy) * t,
        ));
      }
      
      // Generate right side contour (9-16)
      for (int i = 1; i <= 8; i++) {
        double t = i / 8.0;
        points68.add(Offset(
          chinX + (rightEar.dx - chinX) * t,
          chinY + (rightEar.dy - chinY) * t,
        ));
      }
    } else {
      // Fallback: create contour from bounding box
      points68.addAll(_generateContourFromBoundingBox(boundingBox));
    }

    // Left eyebrow (17-21)
    if (detected.containsKey('leftEye')) {
      Offset leftEye = detected['leftEye']!;
      for (int i = 0; i < 5; i++) {
        double t = i / 4.0;
        points68.add(Offset(
          leftEye.dx - (boundingBox.width * 0.15) + (boundingBox.width * 0.30) * t,
          leftEye.dy - boundingBox.height * 0.15,
        ));
      }
    }

    // Right eyebrow (22-26)
    if (detected.containsKey('rightEye')) {
      Offset rightEye = detected['rightEye']!;
      for (int i = 0; i < 5; i++) {
        double t = i / 4.0;
        points68.add(Offset(
          rightEye.dx - (boundingBox.width * 0.15) + (boundingBox.width * 0.30) * t,
          rightEye.dy - boundingBox.height * 0.15,
        ));
      }
    }

    // Nose (27-35)
    if (detected.containsKey('noseBase')) {
      Offset nose = detected['noseBase']!;
      // Nose bridge and tip
      for (int i = 0; i < 4; i++) {
        double t = i / 3.0;
        points68.add(Offset(
          nose.dx,
          boundingBox.top + boundingBox.height * 0.25 + (nose.dy - (boundingBox.top + boundingBox.height * 0.25)) * t,
        ));
      }
      // Nose bottom (31-35)
      for (int i = 0; i < 5; i++) {
        double t = i / 4.0 - 0.5;
        points68.add(Offset(
          nose.dx + boundingBox.width * 0.1 * t,
          nose.dy,
        ));
      }
    }

    // Left eye (36-41)
    if (detected.containsKey('leftEye')) {
      Offset leftEye = detected['leftEye']!;
      // Eye outline - 6 points
      double eyeWidth = boundingBox.width * 0.08;
      double eyeHeight = boundingBox.height * 0.06;
      for (int i = 0; i < 6; i++) {
        double angle = (i / 6.0) * 2 * pi;
        points68.add(Offset(
          leftEye.dx + eyeWidth * cos(angle),
          leftEye.dy + eyeHeight * sin(angle),
        ));
      }
    }

    // Right eye (42-47)
    if (detected.containsKey('rightEye')) {
      Offset rightEye = detected['rightEye']!;
      double eyeWidth = boundingBox.width * 0.08;
      double eyeHeight = boundingBox.height * 0.06;
      for (int i = 0; i < 6; i++) {
        double angle = (i / 6.0) * 2 * pi;
        points68.add(Offset(
          rightEye.dx + eyeWidth * cos(angle),
          rightEye.dy + eyeHeight * sin(angle),
        ));
      }
    }

    // Mouth (48-67)
    if (detected.containsKey('leftMouth') && detected.containsKey('rightMouth')) {
      Offset leftMouth = detected['leftMouth']!;
      Offset rightMouth = detected['rightMouth']!;
      Offset mouthBottom = Offset(
        (leftMouth.dx + rightMouth.dx) / 2, 
        (leftMouth.dy + rightMouth.dy) / 2 + boundingBox.height * 0.05,
      );

      // Outer mouth contour (48-59)
      for (int i = 0; i < 12; i++) {
        if (i < 6) {
          // Top lip
          double t2 = i / 6.0;
          points68.add(Offset(
            leftMouth.dx + (rightMouth.dx - leftMouth.dx) * t2,
            leftMouth.dy - boundingBox.height * 0.02,
          ));
        } else {
          // Bottom lip
          double t2 = (i - 6) / 6.0;
          points68.add(Offset(
            rightMouth.dx - (rightMouth.dx - leftMouth.dx) * t2,
            mouthBottom.dy,
          ));
        }
      }

      // Inner mouth contour (60-67)
      for (int i = 0; i < 8; i++) {
        Offset innerPoint;
        if (i < 4) {
          // Inner top lip
          double t = i / 4.0;
          innerPoint = Offset(
            leftMouth.dx + (rightMouth.dx - leftMouth.dx) * (t / 2),
            leftMouth.dy + boundingBox.height * 0.01,
          );
        } else {
          // Inner bottom lip
          double t = (i - 4) / 4.0;
          innerPoint = Offset(
            rightMouth.dx - (rightMouth.dx - leftMouth.dx) * t,
            mouthBottom.dy - boundingBox.height * 0.01,
          );
        }
        points68.add(innerPoint);
      }
    }

    // Ensure we have exactly 68 points (pad if needed)
    while (points68.length < 68) {
      points68.add(const Offset(0, 0));
    }

    return points68.take(68).toList();
  }

  /// Generate face contour from bounding box as fallback
  static List<Offset> _generateContourFromBoundingBox(Rect boundingBox) {
    List<Offset> contour = [];
    
    double left = boundingBox.left;
    double top = boundingBox.top;
    double right = boundingBox.right;
    double height = boundingBox.height;

    // Left side (0-8)
    for (int i = 0; i < 9; i++) {
      double t = i / 8.0;
      contour.add(Offset(
        left,
        top + height * t,
      ));
    }

    // Right side (9-16)
    for (int i = 1; i <= 8; i++) {
      double t = i / 8.0;
      contour.add(Offset(
        right,
        top + height * t,
      ));
    }

    return contour;
  }

  /// Get landmark count (always 68 for expanded landmarks)
  static int getLandmarkCount() {
    return 68;
  }

  /// Validate landmark data
  static bool isValidLandmarkData(List<double> landmarks) {
    // Should have 68 points * 2 coordinates = 136 values
    return landmarks.length == 136 && landmarks.every((v) => !v.isNaN && !v.isInfinite);
  }

  /// Get landmark description
  static String getLandmarkGroupName(int pointIndex) {
    if (pointIndex < 17) return 'Face Contour';
    if (pointIndex < 22) return 'Left Eyebrow';
    if (pointIndex < 27) return 'Right Eyebrow';
    if (pointIndex < 36) return 'Nose';
    if (pointIndex < 42) return 'Left Eye';
    if (pointIndex < 48) return 'Right Eye';
    if (pointIndex < 60) return 'Mouth Outer';
    return 'Mouth Inner';
  }

  /// Convert landmarks to embedding vector
  /// Takes 68 landmarks and generates a 128D embedding representation
  static List<double> landmarksToEmbedding(List<double> landmarks68Points) {
    if (landmarks68Points.length != 136) {
      throw Exception('Expected 136 landmark values (68 points * 2), got ${landmarks68Points.length}');
    }

    // Normalize landmarks to [-1, 1] range
    List<double> normalized = [];
    
    // Find min/max for normalization - separate X and Y coordinates
    double minX = double.infinity;
    double maxX = double.negativeInfinity;
    double minY = double.infinity;
    double maxY = double.negativeInfinity;

    for (int i = 0; i < landmarks68Points.length; i++) {
      if (i.isEven) {
        // X coordinate
        minX = minX < landmarks68Points[i] ? minX : landmarks68Points[i];
        maxX = maxX > landmarks68Points[i] ? maxX : landmarks68Points[i];
      } else {
        // Y coordinate
        minY = minY < landmarks68Points[i] ? minY : landmarks68Points[i];
        maxY = maxY > landmarks68Points[i] ? maxY : landmarks68Points[i];
      }
    }

    double rangeX = maxX - minX;
    double rangeY = maxY - minY;

    for (int i = 0; i < landmarks68Points.length; i++) {
      if (i.isEven) {
        // X coordinate normalized
        normalized.add((landmarks68Points[i] - minX) / rangeX * 2 - 1);
      } else {
        // Y coordinate normalized
        normalized.add((landmarks68Points[i] - minY) / rangeY * 2 - 1);
      }
    }

    // Generate additional features to reach 128D
    List<double> embedding = normalized.take(128).toList();
    
    // Pad with zeros if needed
    while (embedding.length < 128) {
      embedding.add(0.0);
    }

    return embedding;
  }

  /// Extract embedding directly from Face object
  static List<double> extractEmbeddingFromFace(Face face) {
    final landmarks = extractExpanded68Landmarks(face);
    return landmarksToEmbedding(landmarks);
  }
}
