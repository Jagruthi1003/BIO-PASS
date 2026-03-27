import 'package:camera/camera.dart';

class CameraService {
  CameraController? _cameraController;
  int _selectedCameraIndex = 0;
  List<CameraDescription>? _availableCameras;
  bool _isCameraFlipped = false;

  CameraController? get cameraController => _cameraController;
  bool get isCameraFlipped => _isCameraFlipped;
  int get selectedCameraIndex => _selectedCameraIndex;

  /// Get all available cameras
  Future<List<CameraDescription>> getAvailableCameras() async {
    _availableCameras ??= await availableCameras();
    return _availableCameras ?? [];
  }

  /// Initialize camera with specific camera index
  Future<void> initializeCamera({
    int cameraIndex = 0,
    ResolutionPreset resolution = ResolutionPreset.high,
  }) async {
    try {
      final cameras = await getAvailableCameras();
      
      if (cameras.isEmpty) {
        throw Exception('No cameras available');
      }

      // Ensure camera index is valid
      if (cameraIndex >= cameras.length) {
        cameraIndex = 0;
      }

      await _cameraController?.dispose();

      _cameraController = CameraController(
        cameras[cameraIndex],
        resolution,
        enableAudio: false,
      );

      _selectedCameraIndex = cameraIndex;

      await _cameraController!.initialize();
    } catch (e) {
      rethrow;
    }
  }

  /// Switch between front and back cameras (returns the new camera index)
  Future<int?> switchCamera({
    ResolutionPreset resolution = ResolutionPreset.high,
  }) async {
    try {
      final cameras = await getAvailableCameras();

      if (cameras.isEmpty) {
        throw Exception('No cameras available');
      }

      // If only one camera available, return current index
      if (cameras.length < 2) {
        return _selectedCameraIndex;
      }

      // Toggle camera
      int newIndex = _selectedCameraIndex == 0 ? 1 : 0;

      await initializeCamera(
        cameraIndex: newIndex,
        resolution: resolution,
      );

      _isCameraFlipped = !_isCameraFlipped;
      return newIndex;
    } catch (e) {
      rethrow;
    }
  }

  /// Get current camera description
  Future<CameraDescription?> getCurrentCamera() async {
    try {
      final cameras = await getAvailableCameras();
      if (_selectedCameraIndex < cameras.length) {
        return cameras[_selectedCameraIndex];
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Check if front camera is available
  Future<bool> hasFrontCamera() async {
    try {
      final cameras = await getAvailableCameras();
      return cameras.any((camera) => camera.lensDirection == CameraLensDirection.front);
    } catch (e) {
      return false;
    }
  }

  /// Check if back camera is available
  Future<bool> hasBackCamera() async {
    try {
      final cameras = await getAvailableCameras();
      return cameras.any((camera) => camera.lensDirection == CameraLensDirection.back);
    } catch (e) {
      return false;
    }
  }

  /// Get camera lens direction for current camera
  Future<CameraLensDirection?> getCurrentLensDirection() async {
    try {
      final camera = await getCurrentCamera();
      return camera?.lensDirection;
    } catch (e) {
      return null;
    }
  }

  /// Check if current camera is front camera
  Future<bool> isFrontCameraActive() async {
    try {
      final lensDirection = await getCurrentLensDirection();
      return lensDirection == CameraLensDirection.front;
    } catch (e) {
      return false;
    }
  }

  /// Capture picture from current camera
  Future<XFile> takePicture() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      throw Exception('Camera not initialized');
    }

    try {
      return await _cameraController!.takePicture();
    } catch (e) {
      rethrow;
    }
  }

  /// Get camera info as string
  Future<String> getCameraInfo() async {
    try {
      final camera = await getCurrentCamera();
      if (camera == null) return 'No camera';

      final lensDirection = camera.lensDirection == CameraLensDirection.front
          ? 'Front'
          : camera.lensDirection == CameraLensDirection.back
              ? 'Back'
              : 'Unknown';

      return '$lensDirection Camera';
    } catch (e) {
      return 'Unknown';
    }
  }

  /// Dispose camera resources
  Future<void> dispose() async {
    await _cameraController?.dispose();
    _cameraController = null;
  }
}
