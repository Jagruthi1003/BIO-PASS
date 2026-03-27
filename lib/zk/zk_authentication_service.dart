import 'zk_face_service.dart';
import 'zk_auth_http_client.dart';

/// Main ZK Authentication Service
/// Orchestrates registration and authentication workflows
class ZKAuthenticationService {
  late ZKAuthHttpClient httpClient;
  
  String? userId;
  String? sessionToken;
  String? currentCommitment;
  String? currentSalt;

  ZKAuthenticationService({
    required String serverUrl,
  }) {
    httpClient = ZKAuthHttpClient(baseUrl: serverUrl);
  }

  /// Registers a new user with face embedding
  Future<bool> registerFace({
    required String userId,
    required List<double> embedding,
  }) async {
    try {
      // Validate embedding
      if (!ZKFaceService.validateEmbedding(embedding)) {
        throw Exception('Invalid embedding data');
      }

      // Generate salt for this registration
      final salt = ZKFaceService.generateSalt();

      // In production, you would call the backend to compute Poseidon hash
      // For now, we'll use a simple hash representation
      final commitment = _computeCommitmentLocally(embedding, salt);

      // Register with server
      final response = await httpClient.register(
        userId: userId,
        commitment: commitment,
        salt: salt,
      );

      if (response['success'] == true) {
        this.userId = userId;
        currentCommitment = commitment;
        currentSalt = salt;
        return true;
      }

      return false;
    } catch (e) {
      rethrow;
    }
  }

  /// Authenticates user with new face embedding
  Future<bool> authenticateFace({
    required String userId,
    required List<double> newEmbedding,
    required List<double> registeredEmbedding,
    required String challenge, // Replaced registrationSalt with challenge nonce
    required String commitment,
  }) async {
    try {
      // Validate embeddings
      if (!ZKFaceService.validateEmbedding(newEmbedding) ||
          !ZKFaceService.validateEmbedding(registeredEmbedding)) {
        throw Exception('Invalid embedding data');
      }

      // Quantize embeddings for ZK circuit
      final quantizedNew = ZKFaceService.quantizeEmbedding(newEmbedding);
      final quantizedRegistered =
          ZKFaceService.quantizeEmbedding(registeredEmbedding);

      // Create proof data (simplified for mobile)
      // In production, you would generate actual ZK proof using snarkjs via bridge
      final proof = _createProofStructure(
        quantizedRegistered,
        quantizedNew,
        challenge,
        commitment,
      );

      // Submit authentication
      final response = await httpClient.authenticate(
        userId: userId,
        proof: proof['proof'],
        publicSignals: proof['publicSignals'],
      );

      if (response['success'] == true) {
        this.userId = userId;
        sessionToken = response['sessionToken'] as String?;
        return true;
      }

      return false;
    } catch (e) {
      rethrow;
    }
  }

  /// Verifies session token
  Future<bool> verifySession(String token) async {
    try {
      final response = await httpClient.verifyToken(token);

      if (response['success'] == true) {
        sessionToken = token;
        userId = response['userId'] as String?;
        return true;
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  /// Gets user status from server
  Future<bool> getUserStatus(String userId) async {
    try {
      final response = await httpClient.getUserStatus(userId);
      return response['registered'] == true;
    } catch (e) {
      return false;
    }
  }

  /// Checks server health
  Future<bool> checkServerHealth() async {
    return await httpClient.healthCheck();
  }

  /// Local commitment computation (placeholder for server-side Poseidon)
  String _computeCommitmentLocally(List<double> embedding, String salt) {
    // This is a simplified hash - in production use server-side Poseidon
    final quantized = ZKFaceService.quantizeEmbedding(embedding);
    final saltInt = ZKFaceService.hexToBigInt(salt);

    BigInt hash = BigInt.zero;
    for (int i = 0; i < quantized.length; i++) {
      hash = hash ^ quantized[i];
    }
    hash = hash ^ saltInt;

    return ZKFaceService.bigIntToHex(hash);
  }

  /// Creates proof structure for transmission
  Map<String, dynamic> _createProofStructure(
    List<BigInt> registeredEmbedding,
    List<BigInt> newEmbedding,
    String challenge,
    String commitment,
  ) {
    // Simplified proof structure - in production use actual ZK proof
    return {
      'proof': {
        'pi_a': ['0', '0', '1'],
        'pi_b': [
          ['0', '0'],
          ['0', '0'],
          ['1', '0']
        ],
        'pi_c': ['0', '0', '1'],
        'protocol': 'groth16',
        'curve': 'bn128',
      },
      'publicSignals': [
        commitment,
        '500000000', // threshold
      ],
    };
  }

  /// Calculates face match confidence
  double getMatchConfidence(double distance) {
    return ZKFaceService.getMatchingConfidence(distance, threshold: 0.5);
  }

  /// Cleans up resources
  void dispose() {
    httpClient.close();
  }
}
