import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'enhanced_face_detection_service.dart';

/// Face Biometric Service for zk-proof style hashing and verification
/// Handles facial landmark normalization, SHA-256 hashing, and encrypted storage
class FaceBiometricService {
  // Similarity threshold for Euclidean distance matching
  // Empirically tuned for makeup robustness
  static const double similarityThreshold = 0.18;

  /// Extract and normalize facial landmarks from a detected face
  /// Returns normalized landmark vector as list of doubles
  static List<double> extractAndNormalizeLandmarks(Face face) {
    // Extract landmarks (68-point expansion from ML Kit)
    List<double> rawLandmarks = EnhancedFaceDetectionService.extractExpanded68Landmarks(face);
    
    // Normalize: center-align by nose tip and scale by inter-ocular distance
    List<double> normalized = _normalizeLandmarks(rawLandmarks);
    
    return normalized;
  }

  /// Normalize landmarks using:
  /// 1. Center-alignment relative to nose tip (translate so nose tip = origin)
  /// 2. Scale-normalization by inter-ocular distance (for zoom/distance invariance)
  static List<double> _normalizeLandmarks(List<double> rawLandmarks) {
    if (rawLandmarks.isEmpty || rawLandmarks.length < 72) {
      throw Exception('Invalid landmark data');
    }

    // Extract nose tip (index 30 in 68-point model = nose base)
    // Landmark index: 30 = 60 in flat list (30 * 2)
    double noseTipX = rawLandmarks[60];
    double noseTipY = rawLandmarks[61];

    // Extract eye centers for inter-ocular distance
    // Left eye center (index 36) = index 72
    // Right eye center (index 45) = index 90
    double leftEyeX = (rawLandmarks[72] + rawLandmarks[78]) / 2; // Average left eye points
    double leftEyeY = (rawLandmarks[73] + rawLandmarks[79]) / 2;
    
    double rightEyeX = (rawLandmarks[84] + rawLandmarks[90]) / 2; // Average right eye points
    double rightEyeY = (rawLandmarks[85] + rawLandmarks[91]) / 2;

    // Calculate inter-ocular distance
    double interOcularDistance = sqrt(
      pow(rightEyeX - leftEyeX, 2) + pow(rightEyeY - leftEyeY, 2)
    );

    if (interOcularDistance == 0) {
      throw Exception('Invalid eye positions for normalization');
    }

    // Normalize each point:
    // 1. Center-align by nose tip
    // 2. Scale by inter-ocular distance
    List<double> normalized = [];
    for (int i = 0; i < rawLandmarks.length; i += 2) {
      double x = rawLandmarks[i];
      double y = rawLandmarks[i + 1];
      
      // Step 1: Translate relative to nose tip
      double centeredX = x - noseTipX;
      double centeredY = y - noseTipY;
      
      // Step 2: Scale by inter-ocular distance
      double scaledX = centeredX / interOcularDistance;
      double scaledY = centeredY / interOcularDistance;
      
      normalized.add(scaledX);
      normalized.add(scaledY);
    }

    return normalized;
  }

  /// Generate SHA-256 hash (zk-proof commitment) from normalized landmarks
  /// Hash is computed on a deterministic serialization of the normalized vector
  static String generateZkProofHash(List<double> normalizedLandmarks) {
    // Serialize normalized landmarks to a deterministic string format
    // Using fixed 4 decimal places for reproducibility
    List<String> serialized = normalizedLandmarks.map((value) {
      return value.toStringAsFixed(4);
    }).toList();

    String flatString = serialized.join(',');

    // UTF-8 encode and generate SHA-256 hash
    List<int> bytes = utf8.encode(flatString);
    String hash = sha256.convert(bytes).toString();

    return hash;
  }

  /// Encrypt normalized landmarks with AES-256-CBC.
  /// Encryption key should come from a secure backend source.
  static String encryptNormalizedLandmarks(
    List<double> normalizedLandmarks,
    String encryptionKey,
  ) {
    String jsonString = jsonEncode(normalizedLandmarks);
    final keyBytes = _deriveAes256Key(encryptionKey);
    final key = encrypt.Key(Uint8List.fromList(keyBytes));
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(key, mode: encrypt.AESMode.cbc),
    );
    final encrypted = encrypter.encrypt(jsonString, iv: iv);

    // Store iv:ciphertext (both base64) for deterministic parsing.
    return '${iv.base64}:${encrypted.base64}';
  }

  /// Decrypt normalized landmarks
  static List<double> decryptNormalizedLandmarks(
    String encryptedData,
    String encryptionKey,
  ) {
    try {
      final parts = encryptedData.split(':');
      if (parts.length != 2) {
        throw Exception('Invalid encrypted payload format');
      }
      final keyBytes = _deriveAes256Key(encryptionKey);
      final key = encrypt.Key(Uint8List.fromList(keyBytes));
      final iv = encrypt.IV.fromBase64(parts[0]);
      final cipher = encrypt.Encrypted.fromBase64(parts[1]);
      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc),
      );
      final jsonString = encrypter.decrypt(cipher, iv: iv);

      // Parse JSON array
      List<dynamic> decoded = jsonDecode(jsonString);
      return decoded.cast<double>();
    } catch (e) {
      throw Exception('Failed to decrypt landmarks: $e');
    }
  }

  /// Calculate Euclidean distance between two normalized landmark vectors
  /// Returns distance metric (lower = more similar, should be < 0.18 for match)
  static double calculateEuclideanDistance(
    List<double> liveNormalized,
    List<double> storedNormalized,
  ) {
    if (liveNormalized.length != storedNormalized.length) {
      throw Exception('Landmark vectors have different lengths');
    }

    double sumSquaredDifferences = 0.0;

    for (int i = 0; i < liveNormalized.length; i++) {
      double diff = liveNormalized[i] - storedNormalized[i];
      sumSquaredDifferences += diff * diff;
    }

    return sqrt(sumSquaredDifferences);
  }

  /// Verify a face against stored landmarks using Euclidean distance
  /// Returns verification result with distance, match status, and message
  static Map<String, dynamic> verifyFaceWithEuclideanDistance(
    List<double> liveNormalized,
    List<double> storedNormalized,
    String? liveZkHash,
    String? storedZkHash,
  ) {
    try {
      // Calculate Euclidean distance
      double distance = calculateEuclideanDistance(liveNormalized, storedNormalized);

      // Check against threshold
      bool isMatch = distance < similarityThreshold;

      // Compare hashes for audit logging
      bool hashMatch = liveZkHash != null && storedZkHash != null && liveZkHash == storedZkHash;

      String matchStatus;
      if (distance < 0.10) {
        matchStatus = 'perfect_match';
      } else if (distance < 0.15) {
        matchStatus = 'good_match';
      } else if (distance < similarityThreshold) {
        matchStatus = 'acceptable_match';
      } else if (distance < 0.25) {
        matchStatus = 'poor_match';
      } else {
        matchStatus = 'no_match';
      }

      return {
        'isMatch': isMatch,
        'euclideanDistance': distance,
        'threshold': similarityThreshold,
        'matchStatus': matchStatus,
        'hashMatch': hashMatch,
        'message': isMatch
            ? '✅ Face Verified!\nDistance: ${distance.toStringAsFixed(4)}\nEntry Granted'
            : '❌ Face Mismatch\nDistance: ${distance.toStringAsFixed(4)}\nEntry Denied',
      };
    } catch (e) {
      return {
        'isMatch': false,
        'euclideanDistance': double.infinity,
        'threshold': similarityThreshold,
        'matchStatus': 'error',
        'hashMatch': false,
        'message': 'Error during verification: $e',
        'error': e.toString(),
      };
    }
  }

  /// Create audit log entry for verification attempt
  static Map<String, dynamic> createVerificationAuditLog({
    required String ticketId,
    required String attendeeId,
    required String gatekeeperId,
    required String eventId,
    required bool hashComparison,
    required double euclideanDistance,
    required String verificationStatus, // 'verified', 'failed_distance', 'failed_hash', 'error'
    String? errorMessage,
  }) {
    return {
      'ticketId': ticketId,
      'attendeeId': attendeeId,
      'gatekeeperId': gatekeeperId,
      'eventId': eventId,
      'timestamp': DateTime.now().toUtc(),
      'hashComparison': hashComparison,
      'euclideanDistance': euclideanDistance,
      'verificationStatus': verificationStatus,
      'errorMessage': errorMessage,
    };
  }

  /// Serialize normalized landmarks for display/debugging
  static String serializeNormalized(List<double> normalized) {
    return normalized.map((v) => v.toStringAsFixed(4)).join(',');
  }

  static List<int> _deriveAes256Key(String encryptionKey) {
    final keyHash = sha256.convert(utf8.encode(encryptionKey));
    return keyHash.bytes; // 32-byte key for AES-256
  }
}
