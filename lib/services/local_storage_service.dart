import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocalStorageService {
  static const String _prefix = 'facial_features_';

  static Future<void> saveFacialFeatures(String ticketId, List<double> landmarks) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(landmarks);
    await prefs.setString('$_prefix$ticketId', jsonStr);
  }

  static Future<List<double>?> getFacialFeatures(String ticketId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('$_prefix$ticketId');
    if (jsonStr == null) return null;
    
    try {
      final List<dynamic> jsonList = jsonDecode(jsonStr);
      return jsonList.map((e) => (e as num).toDouble()).toList();
    } catch (e) {
      return null;
    }
  }

  /// Clear facial features for a specific ticket (for privacy)
  static Future<void> clearFacialFeatures(String ticketId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$ticketId');
  }

  /// Clear all cached facial features (for privacy/compliance)
  static Future<void> clearAllFacialFeatures() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith(_prefix)) {
        await prefs.remove(key);
      }
    }
  }
}
