import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class ZKEngine {
  // Threshold for face recognition similarity (0-1 scale, where 1 is identical)
  // Adjusted to require high similarity and prevent false positives
  static const double verificationThreshold = 0.88;
  
  // Makeup tolerance threshold - landmarks within this distance are considered makeup variation
  // High threshold to ensure security is not compromised
  static const double makeupToleranceThreshold = 0.85;

  // Generate ZK proof from face landmarks using SHA256 (Message Digest)
  // This creates a cryptographic commitment to the landmarks
  static String generateProof(List<double> faceLandmarks) {
    try {
      // Convert landmarks to JSON string
      String landmarkString = jsonEncode(faceLandmarks);

      // Generate hash using SHA256 (equivalent to Java MessageDigest.getInstance("SHA-256"))
      // Using the crypto package which provides SHA256 hashing
      String proof = sha256.convert(utf8.encode(landmarkString)).toString();

      return proof;
    } catch (e) {
      rethrow;
    }
  }

  // Create a detailed proof with metadata
  static Map<String, dynamic> generateDetailedProof(List<double> faceLandmarks) {
    try {
      String proof = generateProof(faceLandmarks);
      String hash = sha256.convert(utf8.encode(jsonEncode(faceLandmarks))).toString();
      
      return {
        'proof': proof,
        'hash': hash,
        'timestamp': DateTime.now().toIso8601String(),
        'landmarkCount': faceLandmarks.length,
      };
    } catch (e) {
      rethrow;
    }
  }

  // Verify if two sets of landmarks match using proof
  static bool verifyProof(
    List<double> currentLandmarks,
    String storedProof,
  ) {
    try {
      String currentProof = generateProof(currentLandmarks);
      return currentProof == storedProof;
    } catch (e) {
      return false;
    }
  }

  // Normalize landmarks to be more makeup-tolerant and scale-invariant
  // This focuses on structural features that aren't affected by makeup
  static List<double> normalizeLandmarks(List<double> landmarks) {
    if (landmarks.isEmpty) return landmarks;
    
    // Find center point
    double centerX = 0, centerY = 0;
    for (int i = 0; i < landmarks.length; i += 2) {
      if (i < landmarks.length) centerX += landmarks[i];
      if (i + 1 < landmarks.length) centerY += landmarks[i + 1];
    }
    int pointCount = (landmarks.length / 2).ceil();
    centerX /= pointCount;
    centerY /= pointCount;

    // Centered points
    List<double> centered = [];
    double maxDistance = 0;

    for (int i = 0; i < landmarks.length; i += 2) {
      double x = landmarks[i] - centerX;
      double y = landmarks[i + 1] - centerY;
      centered.add(x);
      centered.add(y);
      
      double distance = sqrt(x * x + y * y);
      if (distance > maxDistance) {
        maxDistance = distance;
      }
    }

    // To avoid division by zero
    if (maxDistance == 0) maxDistance = 1;

    // Scale to a standard face size (e.g., max radius of 100)
    double targetRadius = 100.0;
    double scaleFactor = targetRadius / maxDistance;

    List<double> normalized = [];
    for (int i = 0; i < centered.length; i++) {
        normalized.add(centered[i] * scaleFactor);
    }
    
    return normalized;
  }

  // Calculate similarity with makeup tolerance
  // Uses weighted comparison focusing on structural landmarks
  static double calculateSimilarityWithMakeupTolerance(
    List<double> landmarks1,
    List<double> landmarks2,
  ) {
    if (landmarks1.length != landmarks2.length || landmarks1.isEmpty) {
      return 0.0;
    }

    // Normalize both landmark sets to reduce makeup effect
    List<double> norm1 = normalizeLandmarks(landmarks1);
    List<double> norm2 = normalizeLandmarks(landmarks2);

    double sumSquaredDifferences = 0.0;
    int structuralLandmarkCount = 0;

    // Focus on structural landmarks (face outline, nose, eyes)
    // Indices 0-16: Face contour
    // Indices 17-21: Left eyebrow, 22-26: Right eyebrow
    // Indices 27-35: Nose
    // Indices 36-41: Left eye, 42-47: Right eye
    // Indices 48+: Mouth (might have makeup, lower weight)

    for (int i = 0; i < norm1.length; i++) {
      double diff = norm1[i] - norm2[i];
      
      // Weight structural features higher (face contour, nose, eyes)
      double weight = 1.0;
      int landmarkIndex = i ~/ 2;
      
      if (landmarkIndex < 16 || (landmarkIndex >= 27 && landmarkIndex <= 47)) {
        // Structural landmarks get full weight
        weight = 1.0;
      } else if (landmarkIndex >= 48) {
        // Mouth region with potential makeup - reduced weight
        weight = 0.6;
      } else {
        weight = 0.9;
      }
      
      sumSquaredDifferences += (diff * diff) * (weight * weight);
      structuralLandmarkCount++;
    }

    double weightedDistance = sqrt(sumSquaredDifferences / structuralLandmarkCount);
    
    // Normalize distance to similarity score (0-1)
    // Strict divisor to heavily penalize mismatching landmarks
    double similarity = 1.0 / (1.0 + pow(weightedDistance / 12.0, 2));

    return similarity.clamp(0.0, 1.0);
  }

  // Calculate similarity between two landmark sets (Euclidean distance based)
  static double calculateSimilarity(
    List<double> landmarks1,
    List<double> landmarks2,
  ) {
    if (landmarks1.length != landmarks2.length || landmarks1.isEmpty) {
      return 0.0;
    }

    // Normalize both landmark sets to account for scale and translation differences
    List<double> norm1 = normalizeLandmarks(landmarks1);
    List<double> norm2 = normalizeLandmarks(landmarks2);

    double sumSquaredDifferences = 0.0;
    for (int i = 0; i < norm1.length; i++) {
      double diff = norm1[i] - norm2[i];
      sumSquaredDifferences += diff * diff;
    }

    double euclideanDistance = sqrt(sumSquaredDifferences);
    
    // Normalize distance to similarity score (0-1)
    // Use smaller divisor to drop the similarity dramatically on small deviations
    double similarity = 1.0 / (1.0 + pow(euclideanDistance / 40.0, 2));

    return similarity.clamp(0.0, 1.0);
  }

  // Verify with configurable threshold
  static bool verifyWithThreshold(
    List<double> currentLandmarks,
    List<double> storedLandmarks,
    {double threshold = verificationThreshold,
  }) {
    double similarity = calculateSimilarity(currentLandmarks, storedLandmarks);
    return similarity >= threshold;
  }

  // Verify with makeup tolerance
  static bool verifyWithMakeupTolerance(
    List<double> currentLandmarks,
    List<double> storedLandmarks,
    {double threshold = makeupToleranceThreshold,
  }) {
    double similarity = calculateSimilarityWithMakeupTolerance(
      currentLandmarks,
      storedLandmarks,
    );
    return similarity >= threshold;
  }

  // Get similarity percentage (0-100)
  static double getSimilarityPercentage(
    List<double> landmarks1,
    List<double> landmarks2,
  ) {
    return calculateSimilarity(landmarks1, landmarks2) * 100;
  }

  // Get similarity percentage with makeup tolerance (0-100)
  static double getSimilarityPercentageWithMakeupTolerance(
    List<double> landmarks1,
    List<double> landmarks2,
  ) {
    return calculateSimilarityWithMakeupTolerance(landmarks1, landmarks2) * 100;
  }

  // Get verification result with message
  static Map<String, dynamic> getVerificationResult(
    List<double> currentLandmarks,
    List<double> storedLandmarks,
  ) {
    double similarity = calculateSimilarity(currentLandmarks, storedLandmarks);
    bool isVerified = similarity >= verificationThreshold;
    
    return {
      'isVerified': isVerified,
      'similarity': similarity,
      'similarityPercentage': (similarity * 100).toStringAsFixed(2),
      'message': isVerified ? 'Face verified successfully' : 'Face does not match',
      'threshold': verificationThreshold,
    };
  }

  // Get verification result with makeup tolerance
  static Map<String, dynamic> getVerificationResultWithMakeupTolerance(
    List<double> currentLandmarks,
    List<double> storedLandmarks,
  ) {
    double similarity = calculateSimilarityWithMakeupTolerance(
      currentLandmarks,
      storedLandmarks,
    );
    bool isVerified = similarity >= makeupToleranceThreshold;
    
    return {
      'isVerified': isVerified,
      'similarity': similarity,
      'similarityPercentage': (similarity * 100).toStringAsFixed(2),
      'message': isVerified 
        ? 'Face verified successfully (makeup-tolerant verification)' 
        : 'Face does not match',
      'threshold': makeupToleranceThreshold,
      'makeupTolerant': true,
    };
  }

  // Compress landmarks to fixed size for ZK circuit
  static List<int> compressLandmarks(List<double> landmarks) {
    List<int> compressed = [];
    // Normalize and compress to 68 points (standard face landmark count)
    int step = landmarks.length ~/ 68;
    for (int i = 0; i < landmarks.length && compressed.length < 68; i += step) {
      compressed.add((landmarks[i].abs().toInt()) % 256);
    }
    // Pad if needed
    while (compressed.length < 68) {
      compressed.add(0);
    }
    return compressed.take(68).toList();
  }
}
