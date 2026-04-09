// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'HINATA Go';

  @override
  String get settings => 'Settings';

  @override
  String get cardExpiration => 'Card Display Duration';

  @override
  String get cardExpirationDescription =>
      'Duration in seconds before a scanned card is automatically cleared';

  @override
  String cardExpirationValue(String seconds) {
    return '$seconds seconds';
  }

  @override
  String get secondaryConfirmation => 'Secondary Confirmation';

  @override
  String get secondaryConfirmationDescription =>
      'Ask for confirmation before sending card data';

  @override
  String get about => 'About';

  @override
  String updateToVersion(String version) {
    return 'UPDATE TO $version';
  }

  @override
  String get language => 'Language';

  @override
  String get languageDescription => 'Choose app display language';

  @override
  String get languageSystem => 'System';

  @override
  String get languageEnglishNative => 'English';

  @override
  String get languageChineseNative => '简体中文';

  @override
  String get scan => 'Scan';

  @override
  String get cards => 'Cards';

  @override
  String get scanQrCode => 'Scan QR Code';

  @override
  String get scanning => 'Scanning...';

  @override
  String get tapToScan => 'Tap to Scan';

  @override
  String get readyToScan => 'Ready to Scan';

  @override
  String get nfcInactive => 'NFC Inactive';

  @override
  String get holdCardNearTop => 'Hold your card near the top of your iPhone.';

  @override
  String get tapToActivateNfc => 'Tap this area to activate the NFC reader.';

  @override
  String get holdCardNearReader =>
      'Hold your card near the NFC reader area of your device.';

  @override
  String get nfcUnavailable =>
      'NFC service is currently unavailable or disabled.';

  @override
  String get noActiveInstanceSelectedTap =>
      'No active instance selected.\nTap to select.';

  @override
  String get noRecentScans => 'No recent scans.';

  @override
  String get recentScans => 'Recent Scans';

  @override
  String get viewAllLogs => 'View All Logs';

  @override
  String get resendToActiveInstance => 'Resend to active instance';

  @override
  String get scanHistoryLogs => 'Scan History Logs';

  @override
  String get clearHistory => 'Clear History';

  @override
  String get noScanHistoryYet => 'No scan history yet.';

  @override
  String get savedCardsSource => 'Saved Cards';

  @override
  String sourceLine(String source) {
    return 'Source: $source';
  }

  @override
  String timeLine(String time) {
    return 'Time: $time';
  }

  @override
  String get saveToSavedCards => 'Save to Saved Cards';

  @override
  String get savedCards => 'Saved Cards';

  @override
  String get newFolder => 'New Folder';

  @override
  String get noCardsInFolder => 'No cards in this folder.';

  @override
  String get addCard => 'Add Card';

  @override
  String get cannotDeleteDefaultFolders => 'Cannot delete default folders.';

  @override
  String get deleteFolder => 'Delete Folder?';

  @override
  String deleteFolderMessage(String folderName) {
    return 'Are you sure you want to delete \"$folderName\" and all cards inside it?';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get quickSend => 'Quick Send';

  @override
  String get addCardManually => 'Add Card Manually';

  @override
  String get nameDescription => 'Name / Description';

  @override
  String get folder => 'Folder';

  @override
  String get newFolderOption => '+ New Folder';

  @override
  String get accessCode => 'Access Code';

  @override
  String get save => 'Save';

  @override
  String get folderName => 'Folder Name';

  @override
  String get create => 'Create';

  @override
  String get confirmSend => 'Confirm Send';

  @override
  String confirmSendWithValue(String value) {
    return 'Are you sure you want to send this card?\nValue: $value';
  }

  @override
  String get remoteInstances => 'Remote Instances';

  @override
  String get noInstancesConfigured => 'No instances configured.';

  @override
  String get addInstance => 'Add Instance';

  @override
  String instanceNowActive(String name) {
    return '$name is now active';
  }

  @override
  String get invalidUrl => 'Please enter a valid URL (http/https)';

  @override
  String get invalidEndpoint => 'Please enter a valid address';

  @override
  String get editInstance => 'Edit Instance';

  @override
  String get nameExample => 'Name (e.g. maimaiDX)';

  @override
  String get webhookUrl => 'Webhook URL (http://...)';

  @override
  String get endpointLabel => 'Address';

  @override
  String get instanceType => 'Instance Type';

  @override
  String get instanceTypeHinataIo => 'HINATA IO';

  @override
  String get instanceTypeSpiceApi => 'SpiceAPI (TcpSocket)';

  @override
  String get instanceTypeSpiceApiWebSocket => 'SpiceAPI (WebSocket)';

  @override
  String get spiceApiUnit => 'SpiceAPI Unit';

  @override
  String get spiceApiPassword => 'Password (Optional)';

  @override
  String get selectIcon => 'Select Icon:';

  @override
  String confirmSendToActiveInstance(String cardName) {
    return 'Send this $cardName card to the active instance?';
  }

  @override
  String cardDetails(String cardName) {
    return '$cardName Details';
  }

  @override
  String get valueCopiedToClipboard => 'Value copied to clipboard';

  @override
  String get copyValue => 'Copy Value';

  @override
  String get amusementIcInfo => 'Amusement IC Information';

  @override
  String get manufacturer => 'Manufacturer';

  @override
  String get aimeInfo => 'Aime Information';

  @override
  String get felicaDetails => 'FeliCa Technical Details';

  @override
  String get idm => 'IDm';

  @override
  String get pmm => 'PMm';

  @override
  String get systemCode => 'System Code';

  @override
  String get banapassData => 'Banapassport Data';

  @override
  String get block1 => 'Block 1';

  @override
  String get block2 => 'Block 2';

  @override
  String get iso14443Details => 'ISO14443 Technical Details';

  @override
  String get uid => 'UID';

  @override
  String get sak => 'SAK';

  @override
  String get atqa => 'ATQA';

  @override
  String get technicalDetails => 'Technical Details';

  @override
  String get idOrValue => 'ID / Value';

  @override
  String get savingUpper => 'SAVING...';

  @override
  String get saveUpper => 'SAVE';

  @override
  String get sendingUpper => 'SENDING...';

  @override
  String get sendUpper => 'SEND';

  @override
  String get send => 'Send';

  @override
  String get saveToFolder => 'Save to Folder';

  @override
  String get selectInstance => 'Select Instance';

  @override
  String get noInstances => 'No instances configured.';

  @override
  String savedToFolder(String name, String folder) {
    return 'Saved \"$name\" to $folder.';
  }

  @override
  String get cameraScanInstruction => 'Scan QR Code';

  @override
  String get historyFolder => 'History';

  @override
  String get favoritesFolder => 'Favorites';

  @override
  String sourceNfcWithType(String displayType) {
    return 'NFC ($displayType)';
  }

  @override
  String get nfcDeviceNotSupported => 'Your device does not support NFC';

  @override
  String get nfcEnablePrompt => 'Please enable NFC';

  @override
  String get nfcListening => 'Listening for NFC...';

  @override
  String nfcError(String error) {
    return 'Error: $error';
  }

  @override
  String get nfcIosAlert => 'Hold your card near the top of your iPhone';

  @override
  String get noActiveInstanceSelected => 'No active instance selected.';

  @override
  String sendingToInstance(String name) {
    return 'Sending to $name...';
  }

  @override
  String successSentToInstance(String name) {
    return 'Success: Sent to $name';
  }

  @override
  String failedSentToInstance(String name) {
    return 'Failed: Could not send to $name';
  }

  @override
  String get dataManagement => 'Data Management';

  @override
  String get dataManagementDescription =>
      'Import or export cards and instances';

  @override
  String get exportData => 'Export Data';

  @override
  String get importData => 'Import Data';

  @override
  String get exportSuccess => 'Export successful';

  @override
  String exportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get importSuccess => 'Import successful';

  @override
  String importFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String get exportToClipboard => 'Copy to Clipboard';

  @override
  String get exportToFile => 'Save to File';

  @override
  String get importFromClipboard => 'Paste from Clipboard';

  @override
  String get importFromFile => 'Load from File';

  @override
  String get selectExportMethod => 'Select Export Method';

  @override
  String get selectImportMethod => 'Select Import Method';

  @override
  String get invalidDataFormat => 'Invalid data format';

  @override
  String get importPreviewTitle => 'Import Preview';

  @override
  String get importPreviewMessage => 'The following data will be imported:';

  @override
  String itemCountCards(int count) {
    return 'Cards: $count';
  }

  @override
  String itemCountFolders(int count) {
    return 'Folders: $count';
  }

  @override
  String itemCountInstances(int count) {
    return 'Instances: $count';
  }

  @override
  String get confirmImport => 'Confirm Import';

  @override
  String get importMerge => 'Merge Import';

  @override
  String get importOverwrite => 'Overwrite Import';

  @override
  String get confirmOverwriteTitle => 'Confirm Overwrite';

  @override
  String get confirmOverwriteMessage =>
      'This will overwrite your local data irrecoverably. Are you sure?';

  @override
  String get invalidAccessCodeLength =>
      'Access code must be 20 digits and not start with 3';

  @override
  String get hardwareDevice => 'Device';

  @override
  String get firmwareUpdate => 'Firmware Update';

  @override
  String get ledSettings => 'LED Settings';

  @override
  String get deviceHub => 'Device Hub';

  @override
  String get noDeviceConnected => 'No Device Connected';

  @override
  String get scanForDevices => 'Scan for HINATA USB readers';

  @override
  String get scanUsbDevice => 'Scan USB Device';

  @override
  String get saveToFlash => 'Save to Flash Storage';

  @override
  String get configSavedSuccess => 'Configuration saved to Flash successfully!';

  @override
  String errorSavingFlash(String error) {
    return 'Error saving to flash: $error';
  }

  @override
  String get upToDate => 'Your device is up to date!';

  @override
  String get updateAvailable => 'Update Available';

  @override
  String latestVersion(String version) {
    return 'Latest Version: $version';
  }

  @override
  String get startUpdate => 'Start Update';

  @override
  String get retryUpdate => 'Retry Update';

  @override
  String get failedToCheckFirmware => 'Failed to check firmware status.';

  @override
  String get settingsAndControls => 'Settings & Controls';

  @override
  String get advancedConfig => 'Advanced Config';

  @override
  String get checkLatestSoftware => 'Check for the latest software version';

  @override
  String get configureLighting => 'Configure lighting effects';

  @override
  String firmwareVersion(String version) {
    return 'Firmware: $version';
  }

  @override
  String get tapToConnect => 'Tap to Connect';

  @override
  String get globalSettings => 'Global Settings';

  @override
  String get segaSerialSettings => 'SEGA Serial Protocol Settings';

  @override
  String get cardioSettings => 'CardIO Settings';

  @override
  String get restoreDefaults => 'Restore Defaults';

  @override
  String get processing => 'Processing';

  @override
  String get applySettings => 'Apply Settings';

  @override
  String get tipsTitle => 'Tips:';

  @override
  String get flashWarning =>
      'If you don\'t click Apply Settings, the reader will revert to the original settings after power cycling. However, since the flash chip has limited write cycles (hundreds at most), please apply settings only after confirming everything works correctly.';

  @override
  String get usbDescriptorNote =>
      'USB Descriptor uniqueness takes effect only after applying settings and power cycling the reader. After modification, the OS will treat it as a new device, SEGA games will require reassigning ports, and PC host apps may need to pair again.';

  @override
  String get cardioDisableIso14443a => 'Disable ISO14443-A Card';

  @override
  String get cardioIso14443aE004 =>
      'Fill E004 to head when scanned ISO14443-A Card';

  @override
  String get uniqueDescriptor => 'USB Descriptor Unique';

  @override
  String get ledRainbow => 'Rainbow Light';

  @override
  String get segaFwHw => 'HW/FW';

  @override
  String get segaFastRead => 'Rapid Scan';

  @override
  String get segaBrightness => 'LED Brightness';

  @override
  String get idleRGB => 'Idle Light Color';

  @override
  String get busyRGB => 'Busy Light Color';

  @override
  String get pickFavoriteColor => 'Pick a favorite color~';

  @override
  String get confirmColorChoice => 'Confirm';

  @override
  String get scanPaused => 'Scan Pause';

  @override
  String get scanPausedDescription => 'App is out of focus, scanning paused';
}
