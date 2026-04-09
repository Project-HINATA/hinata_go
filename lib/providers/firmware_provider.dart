import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_firmware_feature/hinata_firmware_feature.dart';

import '../services/communication/device_interface.dart';
import '../services/communication/usb_hinata_impl.dart';

enum FirmUpdateStateEnum {
  deviceSelecting,
  deviceSelected,
  flashing,
  flashInterrupted,
  done,
  idle,
}

class FirmwareState {
  final FirmwareReleaseInfo? firmware;
  final bool isRequesting;
  final FirmUpdateStateEnum updateState;
  final int shouldUpdatedPid;
  final String shouldUpdatedVersion;

  // Flashing status
  final bool isFlashing;
  final double progress;
  final String statusText;
  final String? flashError;

  bool get isUpdating => updateState != FirmUpdateStateEnum.idle || isFlashing;

  FirmwareState({
    this.firmware,
    this.isRequesting = false,
    this.updateState = FirmUpdateStateEnum.idle,
    this.shouldUpdatedPid = 0,
    this.shouldUpdatedVersion = "",
    this.isFlashing = false,
    this.progress = 0.0,
    this.statusText = "",
    this.flashError,
  });

  FirmwareState copyWith({
    FirmwareReleaseInfo? firmware,
    bool? isRequesting,
    FirmUpdateStateEnum? updateState,
    int? shouldUpdatedPid,
    String? shouldUpdatedVersion,
    bool? isFlashing,
    double? progress,
    String? statusText,
    String? flashError,
    bool clearFirmware = false,
    bool clearError = false,
  }) {
    return FirmwareState(
      firmware: clearFirmware ? null : (firmware ?? this.firmware),
      isRequesting: isRequesting ?? this.isRequesting,
      updateState: updateState ?? this.updateState,
      shouldUpdatedPid: shouldUpdatedPid ?? this.shouldUpdatedPid,
      shouldUpdatedVersion: shouldUpdatedVersion ?? this.shouldUpdatedVersion,
      isFlashing: isFlashing ?? this.isFlashing,
      progress: progress ?? this.progress,
      statusText: statusText ?? this.statusText,
      flashError: clearError ? null : (flashError ?? this.flashError),
    );
  }
}

class FirmwareNotifier extends Notifier<FirmwareState> {
  @override
  FirmwareState build() {
    return FirmwareState();
  }

  void reset() {
    state = FirmwareState();
  }

  void setUpdateState(FirmUpdateStateEnum newState) {
    state = state.copyWith(updateState: newState);
  }

  void enterUpdateMode(int pid, String version) {
    state = state.copyWith(
      shouldUpdatedPid: pid,
      shouldUpdatedVersion: version,
      updateState: FirmUpdateStateEnum.deviceSelecting,
    );
  }

  void exitUpdateMode() {
    if (state.firmware != null) {
      state.firmware!.isLatest = true;
    }
    state = state.copyWith(
      updateState: FirmUpdateStateEnum.idle,
      isFlashing: false,
    );
  }

  Future<void> requestFirmware(DeviceInterface device) async {
    if (state.isRequesting) return;
    if (device is! UsbHinataDeviceImpl) return;
    if (!firmwareFeatureEnabled) return;

    state = state.copyWith(isRequesting: true);
    try {
      final pid = int.tryParse(device.deviceId) ?? 0;
      final versionStr =
          device.firmVersion; // Uses timestamp-commithash as in hinatacc
      final chipIdBytes = await device.getChipId();

      final firmRes = await firmwareFeature.requestFirmware(
        pid: pid,
        currentVersion: versionStr,
        chipId: chipIdBytes,
      );
      state = state.copyWith(firmware: firmRes, isRequesting: false);
    } catch (e) {
      state = state.copyWith(isRequesting: false);
    }
  }

  Future<void> startFlash(UsbHinataDeviceImpl device) async {
    final firmware = state.firmware;
    if (!firmwareFeatureEnabled || firmware == null || firmware.firm == null) {
      return;
    }

    state = state.copyWith(
      isFlashing: true,
      progress: 0.0,
      statusText: "Ready to flash...",
      clearError: true,
    );

    try {
      await firmwareFeature.flashFirmware(
        firmwareBase64: firmware.firm!,
        rebootToBootloader: device.enterBootloader,
        onProgress: (progress, statusText) {
          state = state.copyWith(progress: progress, statusText: statusText);
        },
      );

      // Success
      exitUpdateMode();
    } catch (e) {
      state = state.copyWith(
        isFlashing: false,
        statusText: "Flash Error",
        flashError: e.toString(),
      );
    }
  }
}

final firmwareProvider = NotifierProvider<FirmwareNotifier, FirmwareState>(() {
  return FirmwareNotifier();
});
