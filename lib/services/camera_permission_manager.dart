import 'package:permission_handler/permission_handler.dart';
import 'package:camera/camera.dart';

/// Centralized camera permission management for the application
class CameraPermissionManager {
  /// Request camera permission with user-friendly error handling
  static Future<PermissionStatus> requestCameraPermission() async {
    final status = await Permission.camera.request();
    return status;
  }

  /// Check if camera permission is granted
  static Future<bool> isCameraPermissionGranted() async {
    final status = await Permission.camera.status;
    return status.isGranted;
  }

  /// Check if camera permission is permanently denied
  static Future<bool> isCameraPermissionPermanentlyDenied() async {
    final status = await Permission.camera.status;
    return status.isPermanentlyDenied;
  }

  /// Initialize and get camera controller
  static Future<CameraController?> initializeCameraController() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        return null;
      }

      // Use front-facing camera for face detection
      CameraDescription? frontCamera;
      for (var camera in cameras) {
        if (camera.lensDirection == CameraLensDirection.front) {
          frontCamera = camera;
          break;
        }
      }

      // Fall back to first available camera if no front camera
      final camera = frontCamera ?? cameras.first;

      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await controller.initialize();
      return controller;
    } catch (e) {
      return null;
    }
  }

  /// Get permission status description
  static String getPermissionStatusDescription(PermissionStatus status) {
    if (status.isGranted) {
      return 'Camera permission granted';
    } else if (status.isDenied) {
      return 'Camera permission denied. Please grant permission to use camera.';
    } else if (status.isPermanentlyDenied) {
      return 'Camera permission permanently denied. Please enable it in app settings.';
    } else if (status.isRestricted) {
      return 'Camera permission is restricted by system policy.';
    } else if (status.isLimited) {
      return 'Camera permission is limited.';
    }
    return 'Unknown permission status';
  }

  /// Request and handle camera permission with callbacks
  static Future<bool> requestAndHandleCameraPermission({
    required Function(PermissionStatus) onPermissionResult,
    required Function() onPermissionPermanentlyDenied,
  }) async {
    try {
      final status = await Permission.camera.request();

      if (status.isGranted) {
        onPermissionResult(status);
        return true;
      } else if (status.isPermanentlyDenied) {
        onPermissionPermanentlyDenied();
        return false;
      } else {
        onPermissionResult(status);
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  /// Open app settings for permission configuration
  static Future<void> openDeviceSettings() async {
    await openAppSettings();
  }
}
