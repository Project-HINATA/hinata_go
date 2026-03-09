import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'settings_provider.dart';
import 'navigation_provider.dart';

class ReaderViewState {
  final bool isCameraActive;
  final MobileScannerException? cameraError;

  ReaderViewState({this.isCameraActive = false, this.cameraError});

  ReaderViewState copyWith({
    bool? isCameraActive,
    MobileScannerException? cameraError,
  }) {
    return ReaderViewState(
      isCameraActive: isCameraActive ?? this.isCameraActive,
      cameraError: cameraError ?? this.cameraError,
    );
  }
}

final readerViewModelProvider =
    NotifierProvider<ReaderViewModel, ReaderViewState>(() {
      return ReaderViewModel();
    });

class ReaderViewModel extends Notifier<ReaderViewState>
    with WidgetsBindingObserver {
  late MobileScannerController cameraController;
  bool _isPageVisible = false;

  @override
  ReaderViewState build() {
    cameraController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      autoStart: false,
    );

    // Watch for camera setting changes
    ref.listen(settingsProvider.select((s) => s.enableCamera), (
      previous,
      next,
    ) {
      _coordinateCamera();
    });

    // Watch for branch changes to coordinate camera visibility
    // Camera MUST stop if we navigate away from the Reader tab branch
    ref.listen(activeBranchProvider, (previous, next) {
      _coordinateCamera();
    });

    // Watch for scaffold coverage (e.g. root-level dialog or CardDetail)
    ref.listen(isScaffoldCoveredProvider, (previous, next) {
      _coordinateCamera();
    });

    // Register as observer for app lifecycle
    WidgetsBinding.instance.addObserver(this);

    // Cleanup on dispose
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      _safeStopCamera();
      // Future.delayed to ensure native cleanup
      Future.delayed(const Duration(milliseconds: 200), () {
        cameraController.dispose();
      });
    });

    // Initial coordination
    Future.microtask(() => _coordinateCamera());

    return ReaderViewState();
  }

  /// Update the internal visibility state of the Reader page.
  /// This should be called from the UI layer (ReaderPage) based on route focus.
  void setPageVisible(bool visible) {
    if (_isPageVisible != visible) {
      _isPageVisible = visible;
      _coordinateCamera();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // If we are resumed, we should ensure the camera is in the correct state
    // (In case the system killed it or we need to refresh the preview)
    if (state == AppLifecycleState.resumed) {
      _coordinateCamera();
    }

    // NOTE: We deliberately DO NOT stop the camera on 'paused' or 'inactive'
    // if the Reader page is active/visible, to allow it to persist in the multi-tasking view.
  }

  /// Master coordination logic for camera.
  /// Camera should run IF:
  /// 1. Active branch is Reader (0)
  /// 2. The main scaffold is not covered by another route (!isScaffoldCovered)
  /// 3. The Reader page itself is the top-most route in its navigator (isPageVisible)
  /// 4. Settings allow camera
  void _coordinateCamera() {
    final isReaderBranch = ref.read(activeBranchProvider) == 0;
    final isScaffoldVisible = !ref.read(isScaffoldCoveredProvider);
    final isEnabled = ref.read(settingsProvider).enableCamera;

    if (isReaderBranch && isScaffoldVisible && _isPageVisible && isEnabled) {
      _safeStartCamera();
    } else {
      _safeStopCamera();
    }
  }

  Future<void> _safeStartCamera() async {
    try {
      if (cameraController.value.isStarting ||
          cameraController.value.isRunning) {
        return;
      }
      await cameraController.start();
      state = state.copyWith(isCameraActive: true, cameraError: null);
    } catch (e) {
      state = state.copyWith(isCameraActive: false);
    }
  }

  Future<void> _safeStopCamera() async {
    try {
      if (cameraController.value.isRunning) {
        await cameraController.stop();
      }
      state = state.copyWith(isCameraActive: false);
    } catch (e) {
      // ignore
    }
  }
}
