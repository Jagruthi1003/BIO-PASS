import 'dart:convert';
import 'package:http/http.dart' as http;

/// HTTP Client for ZK Face Authentication Server
/// Handles registration and authentication requests
class ZKAuthHttpClient {
  final String baseUrl;
  final http.Client? httpClient;
  static const int timeoutSeconds = 30;

  ZKAuthHttpClient({
    required this.baseUrl,
    this.httpClient,
  });

  /// Registers a new user with face commitment
  Future<Map<String, dynamic>> register({
    required String userId,
    required String commitment,
    required String salt,
  }) async {
    try {
      final response = await (httpClient ?? http.Client()).post(
        Uri.parse('$baseUrl/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': userId,
          'commitment': commitment,
          'salt': salt,
        }),
      ).timeout(
        const Duration(seconds: timeoutSeconds),
        onTimeout: () => throw Exception('Registration request timeout'),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Registration failed');
    } catch (e) {
      throw Exception('Registration error: $e');
    }
  }

  /// Submits a ZK proof for authentication
  Future<Map<String, dynamic>> authenticate({
    required String userId,
    required Map<String, dynamic> proof,
    required List<String> publicSignals,
  }) async {
    try {
      final response = await (httpClient ?? http.Client()).post(
        Uri.parse('$baseUrl/authenticate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': userId,
          'proof': proof,
          'publicSignals': publicSignals,
        }),
      ).timeout(
        const Duration(seconds: timeoutSeconds),
        onTimeout: () => throw Exception('Authentication request timeout'),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? error['error'] ?? 'Authentication failed');
    } catch (e) {
      throw Exception('Authentication error: $e');
    }
  }

  /// Verifies a session token
  Future<Map<String, dynamic>> verifyToken(String token) async {
    try {
      final response = await (httpClient ?? http.Client()).post(
        Uri.parse('$baseUrl/verify-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': token}),
      ).timeout(
        const Duration(seconds: timeoutSeconds),
        onTimeout: () => throw Exception('Token verification timeout'),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      throw Exception('Invalid token');
    } catch (e) {
      throw Exception('Token verification error: $e');
    }
  }

  /// Gets user registration status
  Future<Map<String, dynamic>> getUserStatus(String userId) async {
    try {
      final response = await (httpClient ?? http.Client()).get(
        Uri.parse('$baseUrl/user/$userId'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(
        const Duration(seconds: timeoutSeconds),
        onTimeout: () => throw Exception('Get user request timeout'),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      throw Exception('User not found');
    } catch (e) {
      throw Exception('Get user error: $e');
    }
  }

  /// Health check endpoint
  Future<bool> healthCheck() async {
    try {
      final response = await (httpClient ?? http.Client()).get(
        Uri.parse('$baseUrl/health'),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Health check timeout'),
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Closes the HTTP client
  void close() {
    httpClient?.close();
  }
}
