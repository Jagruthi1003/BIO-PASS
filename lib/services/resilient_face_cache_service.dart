import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'local_storage_service.dart';
import 'event_service.dart';
import '../models/ticket.dart';

/// Service for resilient facial feature caching with Firestore as source of truth
/// 
/// Strategy:
/// 1. Try Firestore first (primary source of truth)
/// 2. Fallback to local storage if Firestore unavailable
/// 3. Automatically refresh local cache when Firestore data is accessed
/// 4. Provide clear error messages for missing data
class ResilientFaceCacheService {
  final EventService _eventService = EventService();
  
  /// Maximum age of local cache in hours before forcing Firestore refresh
  static const int cacheTtlHours = 24;

  /// Get facial features with resilient fallback strategy
  /// 
  /// Priority order:
  /// 1. Fresh Firestore data (if available and valid)
  /// 2. Local storage cache (if Firestore unavailable)
  /// 3. Force re-fetch from Firestore (if local cache also missing)
  /// 4. Return null with clear error (if all sources exhausted)
  Future<List<double>?> getFacialFeaturesWithResilience(
    String ticketId, {
    bool forceRefresh = false,
  }) async {
    try {
      debugPrint('🔍 [ResilientCache] Fetching facial features for ticket: $ticketId');

      // ========== STEP 1: Try Firestore (Primary Source) ==========
      if (!forceRefresh) {
        try {
          Ticket? ticket = await _eventService.getTicketById(ticketId);
          
          if (ticket != null && 
              ticket.facialFeatures != null && 
              ticket.facialFeatures!.isNotEmpty) {
            
            // Decode and validate Firestore data
            List<double>? landmarks = _decodeFacialFeatures(ticket.facialFeatures!);
            
            if (landmarks != null && landmarks.isNotEmpty) {
              debugPrint(
                '✅ [ResilientCache] Facial features loaded from Firestore '
                '(${landmarks.length} landmarks)'
              );
              
              // Asynchronously update local cache (don't block verification)
              _updateLocalCacheAsync(ticketId, landmarks);
              
              return landmarks;
            }
          }
        } catch (e) {
          debugPrint(
            '⚠️ [ResilientCache] Firestore fetch failed (will try cache): $e'
          );
        }
      }

      // ========== STEP 2: Fallback to Local Storage Cache ==========
      List<double>? cachedLandmarks = 
          await LocalStorageService.getFacialFeatures(ticketId);
      
      if (cachedLandmarks != null && cachedLandmarks.isNotEmpty) {
        debugPrint(
          '📦 [ResilientCache] Facial features loaded from local cache '
          '(${cachedLandmarks.length} landmarks)'
        );
        return cachedLandmarks;
      }

      // ========== STEP 3: Force Fresh Firestore Fetch ==========
      // If both Firestore (first attempt) and local cache failed,
      // try one more time with forced refresh
      try {
        Ticket? ticket = await _eventService.getTicketById(ticketId);
        
        if (ticket != null && 
            ticket.facialFeatures != null && 
            ticket.facialFeatures!.isNotEmpty) {
          
          List<double>? landmarks = _decodeFacialFeatures(ticket.facialFeatures!);
          
          if (landmarks != null && landmarks.isNotEmpty) {
            debugPrint(
              '✅ [ResilientCache] Facial features loaded from Firestore (force refresh) '
              '(${landmarks.length} landmarks)'
            );
            
            // Update local cache
            await LocalStorageService.saveFacialFeatures(ticketId, landmarks);
            
            return landmarks;
          }
        }
      } catch (e) {
        debugPrint(
          '❌ [ResilientCache] Firestore force refresh also failed: $e'
        );
      }

      // ========== STEP 4: All Sources Exhausted ==========
      debugPrint(
        '❌ [ResilientCache] No facial features found in any source (Firestore or Local) '
        'for ticket: $ticketId'
      );
      
      return null;
    } catch (e) {
      debugPrint('❌ [ResilientCache] Unexpected error: $e');
      return null;
    }
  }

  /// Validate that facial features exist and are properly formatted
  bool validateFacialFeatures(List<double>? features) {
    if (features == null || features.isEmpty) {
      return false;
    }
    
    // Landmark arrays should be even (X, Y pairs)
    if (features.length % 2 != 0) {
      debugPrint(
        '⚠️ [ResilientCache] Invalid landmark count: ${features.length} '
        '(expected even number for X,Y pairs)'
      );
      return false;
    }
    
    // Reasonable bounds check (landmarks should be in 0-1000 range typically)
    bool allInRange = features.every((val) => val >= -1000 && val <= 1000);
    if (!allInRange) {
      debugPrint(
        '⚠️ [ResilientCache] Landmarks out of expected range'
      );
      return false;
    }
    
    return true;
  }

  /// Private helper: Decode Base64-encoded facial features from Firestore
  List<double>? _decodeFacialFeatures(String encodedFeatures) {
    try {
      String decodedJson = utf8.decode(base64Decode(encodedFeatures));
      List<dynamic> jsonList = jsonDecode(decodedJson);
      
      List<double> landmarks = 
          jsonList.map((x) => (x as num).toDouble()).toList();
      
      if (!validateFacialFeatures(landmarks)) {
        return null;
      }
      
      return landmarks;
    } catch (e) {
      debugPrint(
        '❌ [ResilientCache] Failed to decode facial features: $e'
      );
      return null;
    }
  }

  /// Asynchronously update local cache without blocking current operation
  void _updateLocalCacheAsync(String ticketId, List<double> landmarks) {
    // Fire and forget - don't wait for this
    LocalStorageService.saveFacialFeatures(ticketId, landmarks).catchError((e) {
      debugPrint(
        '⚠️ [ResilientCache] Failed to update local cache async: $e'
      );
    });
  }

  /// Get detailed diagnostic info about facial feature availability
  Future<Map<String, dynamic>> getDiagnosticInfo(String ticketId) async {
    final info = <String, dynamic>{
      'ticketId': ticketId,
      'timestamp': DateTime.now().toIso8601String(),
    };

    try {
      // Check Firestore
      Ticket? ticket = await _eventService.getTicketById(ticketId);
      info['firestore'] = {
        'exists': ticket != null,
        'hasFacialFeatures': ticket?.facialFeatures != null && 
                             ticket!.facialFeatures!.isNotEmpty,
        'hasZkProof': ticket?.zkProof != null && ticket!.zkProof!.isNotEmpty,
        'isRegistered': ticket?.isRegistered ?? false,
        'status': ticket?.status ?? 'N/A',
      };
    } catch (e) {
      info['firestore'] = {'error': e.toString()};
    }

    try {
      // Check local storage
      List<double>? cached = 
          await LocalStorageService.getFacialFeatures(ticketId);
      info['localStorage'] = {
        'hasCachedFeatures': cached != null && cached.isNotEmpty,
        'landmarkCount': cached?.length ?? 0,
      };
    } catch (e) {
      info['localStorage'] = {'error': e.toString()};
    }

    return info;
  }

  /// Clear all cached facial features for a ticket (for privacy/compliance)
  Future<void> clearFacialFeatureCache(String ticketId) async {
    try {
      debugPrint('🗑️ [ResilientCache] Clearing facial features for: $ticketId');
      // Note: We cannot delete from Firestore directly from here
      // That should be done through EventService or a privacy endpoint
      // We only clear local storage
      await LocalStorageService.clearFacialFeatures(ticketId);
    } catch (e) {
      debugPrint('❌ [ResilientCache] Failed to clear cache: $e');
    }
  }

  /// Get cache statistics for debugging
  Future<Map<String, int>> getCacheStats() async {
    try {
      // This would require extending LocalStorageService to track stats
      // For now, return empty map
      return {
        'totalCachedTickets': 0, // Would need implementation
      };
    } catch (e) {
      debugPrint('❌ [ResilientCache] Failed to get cache stats: $e');
      return {};
    }
  }
}
