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
}
