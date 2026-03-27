import 'dart:math' as math;

/// Zero-Knowledge Face Authentication Service
/// Handles quantization and proof generation for face embeddings
class ZKFaceService {
  static const int embeddingDimension = 128;
  static const int scaleFactor = 1000000;
  static const String tag = 'ZKFaceService';

  /// Quantizes a single float value to integer with scale factor
  /// ML embeddings (-1.0 to 1.0) are scaled by 1,000,000
  static BigInt quantizeValue(double value, {int scale = scaleFactor}) {
    final quantized = (value * scale).round();
    return BigInt.from(quantized);
  }

  /// Quantizes a full embedding array
  /// Converts 128D float embedding to 128D BigInt array
  static List<BigInt> quantizeEmbedding(
    List<double> embedding, {
    int scale = scaleFactor,
  }) {
    if (embedding.length != embeddingDimension) {
      throw Exception(
        'Embedding must have exactly $embeddingDimension dimensions, '
        'got ${embedding.length}',
      );
    }

    return embedding
        .map((value) => quantizeValue(value, scale: scale))
        .toList();
  }

  /// Validates that an embedding is within expected bounds
  static bool validateEmbedding(
    List<double> embedding, {
    double min = -1.0,
    double max = 1.0,
  }) {
    if (embedding.length != embeddingDimension) {
      return false;
    }

    return embedding.every((value) => value >= min && value <= max);
  }

  /// Dequantizes a BigInt back to float
  static double dequantizeValue(BigInt quantized, {int scale = scaleFactor}) {
    return quantized.toDouble() / scale;
  }

  /// Calculates squared Euclidean distance between two float embeddings
  static double calculateFloatDistance(
    List<double> embedding1,
    List<double> embedding2,
  ) {
    if (embedding1.length != embeddingDimension ||
        embedding2.length != embeddingDimension) {
      throw Exception('Both embeddings must have $embeddingDimension dimensions');
    }

    double distanceSquared = 0;
    for (int i = 0; i < embedding1.length; i++) {
      final diff = embedding1[i] - embedding2[i];
      distanceSquared += diff * diff;
    }

    return distanceSquared;
  }

  /// Calculates squared Euclidean distance between two quantized embeddings
  static BigInt calculateQuantizedDistance(
    List<BigInt> embedding1,
    List<BigInt> embedding2,
  ) {
    if (embedding1.length != embeddingDimension ||
        embedding2.length != embeddingDimension) {
      throw Exception('Both embeddings must have $embeddingDimension dimensions');
    }

    BigInt distanceSquared = BigInt.zero;
    for (int i = 0; i < embedding1.length; i++) {
      final diff = embedding1[i] - embedding2[i];
      distanceSquared += diff * diff;
    }

    return distanceSquared;
  }

  /// Generates a random salt for hashing (hex string of 32 bytes)
  static String generateSalt() {
    final random = math.Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return _bytesToHex(values);
  }

  /// Converts hex string to BigInt
  static BigInt hexToBigInt(String hexString) {
    final cleaned = hexString.startsWith('0x') ? hexString : '0x$hexString';
    return BigInt.parse(cleaned);
  }

  /// Converts BigInt to hex string
  static String bigIntToHex(BigInt value) {
    return value.toRadixString(16);
  }

  /// Helper: Convert byte list to hex string
  static String _bytesToHex(List<int> bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Creates a registration data structure
  static Map<String, dynamic> createRegistrationData({
    required List<double> embedding,
    required String commitment,
    required String salt,
    String? userId,
  }) {
    if (!validateEmbedding(embedding)) {
      throw Exception('Invalid embedding data');
    }

    final quantized = quantizeEmbedding(embedding);

    return {
      'commitment': commitment,
      'salt': salt,
      'quantizedEmbedding': quantized.map((b) => b.toString()).toList(),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'userId': userId,
    };
  }

  /// Prepares proof data for transmission to server
  static Map<String, dynamic> prepareProofForTransmission({
    required Map<String, dynamic> proof,
    required List<String> publicSignals,
    required String userId,
  }) {
    return {
      'userId': userId,
      'proof': proof,
      'publicSignals': publicSignals,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  /// Validates that a proof response from server is valid
  static bool validateProofResponse(dynamic response) {
    if (response is! Map) return false;

    return response.containsKey('success') &&
        response.containsKey('message') &&
        (response['success'] == true || response.containsKey('reason'));
  }

  /// Calculates threshold based on quality score
  /// Lower thresholds = stricter matching
  static BigInt calculateThreshold({
    double qualityScore = 1.0,
    BigInt? baseThreshold,
  }) {
    baseThreshold ??= BigInt.from(500000000); // 0.5 in quantized space

    final adjustedFactor = (qualityScore * 1000000).toInt();
    return baseThreshold * BigInt.from(adjustedFactor) ~/ BigInt.from(1000000);
  }

  /// Estimates matching confidence based on distance
  static double getMatchingConfidence(
    double distance, {
    double threshold = 0.5,
  }) {
    if (distance > threshold) return 0.0;

    // Normalize: 0 distance = 100%, threshold distance = 0%
    return ((threshold - distance) / threshold * 100).clamp(0.0, 100.0);
  }
}
