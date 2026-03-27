import '../zk/zk_engine.dart';

/// Face matching service for comparing registered and verification face landmarks
class FaceMatchingService {
  /// Match current face landmarks against registered landmarks
  /// Returns detailed matching result with status and message
  static Map<String, dynamic> matchFace(
    List<double> registeredLandmarks,
    List<double> currentLandmarks,
  ) {
    try {
      // Validate inputs
      if (registeredLandmarks.isEmpty || currentLandmarks.isEmpty) {
        return {
          'isMatched': false,
          'similarity': 0.0,
          'similarityPercentage': '0.00',
          'matchStatus': 'invalid',
          'message': 'Invalid face data provided',
          'isDenied': true,
        };
      }

      if (registeredLandmarks.length != currentLandmarks.length) {
        return {
          'isMatched': false,
          'similarity': 0.0,
          'similarityPercentage': '0.00',
          'matchStatus': 'invalid',
          'message': 'Face landmark data mismatch',
          'isDenied': true,
        };
      }

      // Calculate similarity using ZK engine with makeup tolerance
      // This uses weighted landmarks to handle makeup variations better
      double similarity = ZKEngine.calculateSimilarityWithMakeupTolerance(
        currentLandmarks,
        registeredLandmarks,
      );

      String similarityPercentage = (similarity * 100).toStringAsFixed(2);

      // Determine match status based on similarity
      String matchStatus;
      bool isMatched;
      bool isDenied;
      String message;

      if (similarity >= 0.95) {
        matchStatus = 'perfect_match';
        isMatched = true;
        isDenied = false;
        message = '✅ Perfect Face Match!\nSimilarity: $similarityPercentage%\nEntry Granted';
      } else if (similarity >= 0.88) {
        matchStatus = 'good_match';
        isMatched = true;
        isDenied = false;
        message = '✅ Face Verified!\nSimilarity: $similarityPercentage%\nEntry Granted';
      } else if (similarity >= 0.75) {
        matchStatus = 'poor_match';
        isMatched = false;
        isDenied = false;
        message = '⚠️ Low Match Confidence\nSimilarity: $similarityPercentage%\nPlease Try Again';
      } else {
        matchStatus = 'no_match';
        isMatched = false;
        isDenied = true;
        message = '❌ Face Does Not Match\nSimilarity: $similarityPercentage%\nEntry Denied';
      }

      return {
        'isMatched': isMatched,
        'isDenied': isDenied,
        'similarity': similarity,
        'similarityPercentage': similarityPercentage,
        'matchStatus': matchStatus,
        'message': message,
        'verificationThreshold': ZKEngine.verificationThreshold,
        'registeredLandmarksCount': registeredLandmarks.length,
        'currentLandmarksCount': currentLandmarks.length,
      };
    } catch (e) {
      return {
        'isMatched': false,
        'isDenied': true,
        'similarity': 0.0,
        'similarityPercentage': '0.00',
        'matchStatus': 'error',
        'message': 'Error during face matching: $e',
      };
    }
  }

  /// Get user-friendly message based on match result
  static String getMatchMessage(Map<String, dynamic> matchResult) {
    return matchResult['message'] as String? ?? 'Face matching error';
  }

  /// Check if face should be allowed entry
  static bool isEntryGranted(Map<String, dynamic> matchResult) {
    return matchResult['isMatched'] as bool? ?? false;
  }

  /// Check if face should be denied entry
  static bool isEntryDenied(Map<String, dynamic> matchResult) {
    return matchResult['isDenied'] as bool? ?? true;
  }

  /// Get match status for logging/tracking
  static String getMatchStatusForLog(Map<String, dynamic> matchResult) {
    return matchResult['matchStatus'] as String? ?? 'unknown';
  }
}
