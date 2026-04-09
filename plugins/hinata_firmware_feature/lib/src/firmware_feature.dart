typedef FirmwareProgressCallback =
    void Function(double progress, String statusText);

class FirmwareReleaseInfo {
  FirmwareReleaseInfo({
    this.isLatest,
    this.isErr = false,
    this.product,
    this.model,
    this.version,
    this.message,
    this.firm,
  });

  bool? isLatest;
  bool isErr;
  String? product;
  String? model;
  String? version;
  String? message;
  String? firm;
}

abstract class FirmwareFeature {
  const FirmwareFeature();

  bool get isEnabled;

  Future<FirmwareReleaseInfo?> requestFirmware({
    required int pid,
    required String currentVersion,
    required List<int> chipId,
  });

  Future<void> flashFirmware({
    required String firmwareBase64,
    required Future<void> Function() rebootToBootloader,
    required FirmwareProgressCallback onProgress,
  });
}

class StubFirmwareFeature extends FirmwareFeature {
  const StubFirmwareFeature();

  @override
  bool get isEnabled => false;

  @override
  Future<FirmwareReleaseInfo?> requestFirmware({
    required int pid,
    required String currentVersion,
    required List<int> chipId,
  }) async {
    return null;
  }

  @override
  Future<void> flashFirmware({
    required String firmwareBase64,
    required Future<void> Function() rebootToBootloader,
    required FirmwareProgressCallback onProgress,
  }) async {
    throw UnsupportedError(
      'Firmware updates are not available in the public build.',
    );
  }
}

const FirmwareFeature firmwareFeature = StubFirmwareFeature();

const bool firmwareFeatureEnabled = false;
