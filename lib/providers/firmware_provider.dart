import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_firmware_feature/hinata_firmware_feature.dart';

import '../services/reader/usb_hinata_impl.dart';

enum FirmwareUpdateStatus { idle, updating, success, error }

class FirmwareState {
  final FirmwareReleaseInfo? firmware;
  final bool isRequesting;
  final String channel;
  final bool hasBadgeUpdate;

  // Flashing status
  final FirmwareUpdateStatus status;
  final double progress;
  final String statusText;
  final String? flashError;
  final String? fetchError;

  bool get isFlashing => status == FirmwareUpdateStatus.updating;
  bool get isUpdating => isFlashing;

  bool get hasUpdate => firmwareFeatureEnabled && hasBadgeUpdate;

  bool get hasFetchError =>
      fetchError != null || (firmware != null && firmware!.isErr);

  FirmwareState({
    this.firmware,
    this.isRequesting = false,
    this.channel = 'stable',
    this.hasBadgeUpdate = false,
    this.status = FirmwareUpdateStatus.idle,
    this.progress = 0.0,
    this.statusText = "",
    this.flashError,
    this.fetchError,
  });

  FirmwareState copyWith({
    FirmwareReleaseInfo? firmware,
    bool? isRequesting,
    String? channel,
    bool? hasBadgeUpdate,
    FirmwareUpdateStatus? status,
    double? progress,
    String? statusText,
    String? flashError,
    String? fetchError,
    bool clearFirmware = false,
    bool clearError = false,
    bool clearFetchError = false,
  }) {
    return FirmwareState(
      firmware: clearFirmware ? null : (firmware ?? this.firmware),
      isRequesting: isRequesting ?? this.isRequesting,
      channel: channel ?? this.channel,
      hasBadgeUpdate: hasBadgeUpdate ?? this.hasBadgeUpdate,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      statusText: statusText ?? this.statusText,
      flashError: clearError ? null : (flashError ?? this.flashError),
      fetchError: clearFetchError ? null : (fetchError ?? this.fetchError),
    );
  }
}

class FirmwareNotifier extends Notifier<FirmwareState> {
  int _requestGeneration = 0;

  @override
  FirmwareState build() {
    return FirmwareState();
  }

  void reset() {
    _requestGeneration++;
    state = FirmwareState();
  }

  Future<void> setChannel(String channel, UsbHinataDeviceImpl? device) async {
    if (channel == state.channel || state.isFlashing) return;
    state = state.copyWith(
      channel: channel,
      clearFirmware: true,
      clearFetchError: true,
      clearError: true,
      status: FirmwareUpdateStatus.idle,
    );
    if (device != null) {
      await requestFirmware(device, force: true);
    }
  }

  Future<void> requestFirmware(
    UsbHinataDeviceImpl device, {
    bool force = false,
  }) async {
    if (state.isRequesting && !force) return;
    if (!firmwareFeatureEnabled) return;

    final generation = ++_requestGeneration;
    final requestedChannel = state.channel;
    state = state.copyWith(isRequesting: true, clearFetchError: true);
    try {
      final pid = int.tryParse(device.deviceId) ?? 0;
      final versionStr =
          device.firmVersion; // Uses timestamp-commithash as in hinatacc
      final chipIdBytes = await device.getChipId();

      final firmRes = await firmwareFeature.requestFirmware(
        pid: pid,
        currentVersion: versionStr,
        chipId: chipIdBytes,
        channel: requestedChannel,
      );
      if (generation != _requestGeneration) return;

      if (firmRes == null || firmRes.isErr) {
        state = state.copyWith(
          firmware: firmRes,
          isRequesting: false,
          fetchError: 'Failed to check firmware status.',
          hasBadgeUpdate: requestedChannel == 'stable'
              ? false
              : state.hasBadgeUpdate,
        );
        return;
      }

      var badgeUpdate = state.hasBadgeUpdate;
      if (requestedChannel == 'stable') {
        if (firmRes.isLatest == false) {
          // Stable differs from current firmware; check canary before showing a badge.
          try {
            final canaryRes = await firmwareFeature.requestFirmware(
              pid: pid,
              currentVersion: versionStr,
              chipId: chipIdBytes,
              channel: 'canary',
            );
            if (generation != _requestGeneration) return;
            final matchesCanary =
                canaryRes != null &&
                !canaryRes.isErr &&
                canaryRes.isLatest == true;
            badgeUpdate = !matchesCanary;
          } catch (_) {
            if (generation != _requestGeneration) return;
            badgeUpdate = true;
          }
        } else {
          badgeUpdate = false;
        }
      } else if (requestedChannel == 'canary' && firmRes.isLatest == true) {
        badgeUpdate = false;
      }

      state = state.copyWith(
        firmware: firmRes,
        isRequesting: false,
        status: FirmwareUpdateStatus.idle,
        hasBadgeUpdate: badgeUpdate,
        clearFetchError: true,
      );
    } catch (e) {
      if (generation != _requestGeneration) return;
      state = state.copyWith(isRequesting: false, fetchError: e.toString());
    }
  }

  Future<void> startFlash(UsbHinataDeviceImpl device) async {
    if (kIsWeb && defaultTargetPlatform == TargetPlatform.windows) return;

    final firmware = state.firmware;
    if (!firmwareFeatureEnabled || firmware == null || firmware.firm == null) {
      return;
    }

    state = state.copyWith(
      status: FirmwareUpdateStatus.updating,
      progress: 0.0,
      statusText: "Ready to flash...",
      clearError: true,
    );

    try {
      await firmwareFeature.flashFirmware(
        firmwareBase64: firmware.firm!,
        rebootToBootloader: device.enterBootloader,
        onProgress: (progress, statusText) {
          state = state.copyWith(
            status: FirmwareUpdateStatus.updating,
            progress: progress,
            statusText: statusText,
          );
        },
      );

      // Success
      firmware.isLatest = true;
      state = state.copyWith(
        status: FirmwareUpdateStatus.success,
        progress: 1.0,
        hasBadgeUpdate: false,
      );
    } catch (e) {
      state = state.copyWith(
        status: FirmwareUpdateStatus.error,
        statusText: "Flash Error",
        flashError: e.toString(),
      );
    }
  }
}

final firmwareProvider = NotifierProvider<FirmwareNotifier, FirmwareState>(() {
  return FirmwareNotifier();
});
