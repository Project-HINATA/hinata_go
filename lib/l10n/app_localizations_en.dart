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
  String get github => 'GitHub';

  @override
  String get prism => 'PRiSM';

  @override
  String updateToVersion(String version) {
    return 'UPDATE TO $version';
  }

  @override
  String get updateViaGithub => 'GitHub Release';

  @override
  String get updateViaGooglePlay => 'Google Play';

  @override
  String get updateViaAppStore => 'App Store';

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
  String get nfcInactive => 'No Scanning Device Available';

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
  String get remotePassword => 'Password (Optional)';

  @override
  String remotePasswordIoVersionRequirement(String version) {
    return 'When a password is enabled, only IO version $version or later can receive cards.';
  }

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
  String get systemCode => 'System Codes';

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
  String get nfcFelicaOnlyLongPressHint =>
      'Long-press the scan area to read a Japanese transit card or Hong Kong Octopus from another iPhone';

  @override
  String get nfcIosFelicaOnlyPrompt =>
      'FeliCa-only: Hold the top of this iPhone near the other iPhone';

  @override
  String get nfcIosFelicaOnlyAlert =>
      'FeliCa-only mode: Hold this iPhone near the other iPhone to scan a Japanese transit card or Hong Kong Octopus';

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
      'Enter a valid 20-digit Aime or Banapass access code';

  @override
  String get hardwareDevice => 'Device';

  @override
  String get firmwareUpdate => 'Firmware Update';

  @override
  String get windowsFirmwareUpdateUnavailable =>
      'Windows browsers cannot update HINATA reader firmware. Use HINATA Client, or use HINATA Go on macOS, Linux, or Android.';

  @override
  String get openHinataClient => 'Open HINATA Client';

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
  String get newFirmwareAvailable => 'New firmware available';

  @override
  String get firmwareUpdateUnconnectedTitle => 'Device Not Connected';

  @override
  String get firmwareUpdateUnconnectedSubtitle =>
      'Please connect a device first to check for firmware updates.';

  @override
  String get firmwareUpdateFetchErrorTitle => 'Update Check Failed';

  @override
  String get firmwareUpdateFetchErrorSubtitle =>
      'Unable to connect to the update server. Please check your network and try again.';

  @override
  String get firmwareUpdateLoadingText => 'Checking for updates...';

  @override
  String get firmwareUpdateVersionHeader => 'Firmware Version';

  @override
  String get firmwareUpdateChannelStable => 'Stable';

  @override
  String get firmwareUpdateChannelCanary => 'Canary';

  @override
  String get firmwareUpdateChangelogTitle => 'Changelog';

  @override
  String get firmwareUpdateLatestBadge => 'Up to Date';

  @override
  String get firmwareUpdateInstallButton => 'Install Firmware';

  @override
  String get firmwareUpdateSuccessMessage => 'Update complete! Reconnecting...';

  @override
  String get firmwareUpdateBusyWarning =>
      'Please wait until firmware update is complete.';

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

  @override
  String get unknownCardType => 'Unknown';

  @override
  String get unusableMifareCardWarning => 'This card cannot be used in games.';

  @override
  String get transitBalance => 'Balance';

  @override
  String get cardNumber => 'Card Number';

  @override
  String get transactionHistory => 'Transaction History';

  @override
  String get snapshotTime => 'Snapshot Time';

  @override
  String get noTransactions => 'No transaction history';

  @override
  String get transitTypeRide => 'Ride';

  @override
  String get transitTypeTopup => 'Top-up';

  @override
  String get transitTypeShopping => 'Shopping';

  @override
  String get transitTypeAdjustment => 'Adjustment';

  @override
  String get transitTypeRefund => 'Refund';

  @override
  String get transitTypeIssue => 'Issue';

  @override
  String get transitTypeDeduction => 'Deduction';

  @override
  String get transitTypeReissue => 'Reissue';

  @override
  String get transitTypeOther => 'Other';

  @override
  String get duplicateCardTitle => 'Card Already Saved';

  @override
  String get duplicateCardPrompt => 'Same card already exists. Overwrite?';

  @override
  String get overwrite => 'Confirm';

  @override
  String get renameCard => 'Rename Card';

  @override
  String get cardNameLabel => 'New Card Name';

  @override
  String get deleteCard => 'Delete Card';

  @override
  String get confirmDeleteCard =>
      'Are you sure you want to delete this card? This action cannot be undone.';

  @override
  String get renameSuccess => 'Renamed successfully';

  @override
  String get deleteSuccess => 'Deleted successfully';

  @override
  String get nfcReadIncomplete =>
      'Card reading was interrupted. Please scan it again.';

  @override
  String get tagTUnion => 'China T-Union';

  @override
  String get tagJapanTransit => 'Japan Transit IC';

  @override
  String get transitCardType => 'Card Type';

  @override
  String get transitExpiryDate => 'Valid Until';

  @override
  String get transitIssueDate => 'Issue Date';

  @override
  String get transitCardTypeStandard => 'Standard Card';

  @override
  String get transitCardTypeStudent => 'Student Card';

  @override
  String get transitCardTypeSenior => 'Senior Card';

  @override
  String get transitCardTypeMilitary => 'Military Card';

  @override
  String transitCardTypeOther(String code) {
    return 'Other ($code)';
  }

  @override
  String get nesicaSerial => 'NESiCA Serial';

  @override
  String get cardWrite => 'Write';

  @override
  String get cardWriteTitle => 'Write to MIFARE card';

  @override
  String get cardWriteWarningWritable =>
      'Not every card can be written. The actual result depends on the target card.';

  @override
  String get cardWriteWarningUid =>
      'Writing does not replace the card\'s original UID.';

  @override
  String get cardWriteWarningCompatibility =>
      'The written card is not guaranteed to work on every machine or server.';

  @override
  String get cardWriteMode => 'Access after writing';

  @override
  String get cardWriteRewritable => 'Rewritable';

  @override
  String get cardWriteRewritableDescription =>
      'The supported key can update the card again.';

  @override
  String get cardWritePermanent => 'Read-only';

  @override
  String get cardWritePermanentDescription =>
      'Access control is locked and cannot be restored.';

  @override
  String get cardWritePermanentConfirmTitle => 'Permanently lock this card?';

  @override
  String get cardWritePermanentConfirmBody =>
      'This changes the sector access control irreversibly. The affected blocks and keys cannot be rewritten afterward.';

  @override
  String get cardWriteStart => 'Start writing';

  @override
  String get cardWriteConfirmPermanent => 'Lock and write';

  @override
  String get cardWriteWaitingForCard =>
      'Hold the target tag near your phone or reader';

  @override
  String get cardWriteCheckingCard => 'Checking card type';

  @override
  String get cardWriteCheckingPermissions => 'Checking keys and access control';

  @override
  String get cardWriteWritingData => 'Writing card data';

  @override
  String get cardWriteLockingCard => 'Writing access control';

  @override
  String get cardWriteVerifying => 'Verifying written data';

  @override
  String get cardWriteSuccess => 'Card written and verified';

  @override
  String get cardWriteFailed => 'Card writing failed';

  @override
  String get cardWriteUnsupportedSavedCard =>
      'Only supported saved Aime and Banapass cards can be written';

  @override
  String get cardWriteNoBackend =>
      'Card writing requires Android NFC or a connected HINATA reader';

  @override
  String get cardWriteUnsupportedTarget =>
      'Use a MIFARE Classic 1K card with a 4-byte UID';

  @override
  String get cardWriteUnknownKey =>
      'The card could not be authenticated with a supported key';

  @override
  String get cardWriteInvalidAccessBits =>
      'The card has invalid MIFARE access bits';

  @override
  String get cardWritePermissionDenied =>
      'The current access control does not allow this write';

  @override
  String get cardWriteCardRemoved =>
      'The card was removed or no card was detected in time';

  @override
  String get cardWriteVerificationFailed =>
      'Written data could not be verified';

  @override
  String get cardWriteDone => 'Done';

  @override
  String get cardWriteCancelled =>
      'Card writing was cancelled before any data was changed';

  @override
  String get ndefCreate => 'New NDEF dataset';

  @override
  String get ndefEdit => 'Edit NDEF dataset';

  @override
  String get addAimeBanapass => 'Add Aime/Banapass';

  @override
  String get addFelicaCard => 'Add FeliCa card';

  @override
  String get felicaBytesHint => '8 bytes as 16 hex digits';

  @override
  String get felicaInvalidBytes => 'Enter exactly 16 hex digits';

  @override
  String get felicaSystemCodesHint =>
      '4 hex digits each, separated by commas, e.g. 0003, FE00';

  @override
  String felicaInvalidSystemCodes(int count) {
    return 'Each system code needs 4 hex digits; up to $count, without repeats';
  }

  @override
  String get ndefAddRecord => 'Add record';

  @override
  String get ndefRecord => 'NDEF record';

  @override
  String get ndefText => 'Text';

  @override
  String get ndefExternal => 'External type';

  @override
  String get ndefRaw => 'Raw record';

  @override
  String get ndefTypeHex => 'Type (hex)';

  @override
  String get ndefPayloadHex => 'Payload (hex)';

  @override
  String get ndefIdHex => 'Record ID (hex, optional)';

  @override
  String get ndefLanguage => 'Language code';

  @override
  String get ndefContent => 'Content';

  @override
  String get ndefEmpty => 'Enter a name and add at least one record';

  @override
  String get ndefInvalidRecord =>
      'Invalid record. Check the type, content and hex fields';

  @override
  String get ndefCapacityExceeded =>
      'NDEF data exceeds the target tag capacity';

  @override
  String get ndefWriteWarning =>
      'This overwrites the target NDEF data. An unformatted MIFARE Classic will be formatted and its existing data erased. Capacity, keys and write permissions are checked before writing. Keep the tag in place until completion. iPhone MIFARE Classic support depends on the system; formatting is unavailable.';

  @override
  String get ndefUnsupportedTarget =>
      'Incompatible target. Use a writable NDEF tag. Formatting MIFARE Classic requires a compatible Android phone or HINATA reader.';

  @override
  String get ndefNoBackend =>
      'NDEF writing requires an NFC phone or connected HINATA reader';

  @override
  String get ndefName => 'Dataset name';

  @override
  String get ndefFolder => 'Save to';

  @override
  String get ndefLink => 'Link';

  @override
  String get ndefLinkHint =>
      'Web addresses can leave out https://; tel:, mailto:, geo: and other links work too';

  @override
  String get ndefPhone => 'Phone';

  @override
  String get ndefEmail => 'Email';

  @override
  String get ndefSms => 'SMS';

  @override
  String get ndefLocation => 'Location';

  @override
  String get ndefWifi => 'Wi-Fi';

  @override
  String get ndefContact => 'Contact';

  @override
  String get ndefAndroidApp => 'Android app';

  @override
  String get ndefPhoneNumber => 'Phone number';

  @override
  String get ndefEmailAddress => 'Email address';

  @override
  String get ndefEmailSubject => 'Subject';

  @override
  String get ndefMessageBody => 'Message';

  @override
  String get ndefLatitude => 'Latitude';

  @override
  String get ndefLongitude => 'Longitude';

  @override
  String get ndefWifiSsid => 'Network name (SSID)';

  @override
  String get ndefWifiSecurity => 'Security';

  @override
  String get ndefWifiOpen => 'None (open network)';

  @override
  String get ndefWifiWpa2 => 'WPA/WPA2 Personal';

  @override
  String get ndefWifiWpa3 => 'WPA3 Personal';

  @override
  String get ndefWifiPassword => 'Password';

  @override
  String get ndefWifiHint =>
      'Android can join the network when it scans the tag; iPhone cannot join Wi-Fi over NFC.';

  @override
  String get ndefContactName => 'Name';

  @override
  String get ndefPackageName => 'Package name';

  @override
  String get ndefAndroidAppHint =>
      'Android opens this app, or its store page when it is not installed. Usually the last record.';

  @override
  String get ndefAdvanced => 'Advanced options';

  @override
  String get ndefRecordKind => 'Content type';

  @override
  String get ndefRecordAdd => 'Add record';

  @override
  String get ndefRecordEdit => 'Edit record';

  @override
  String get ndefMimeType => 'Media type (MIME)';

  @override
  String get ndefExternalTypeName => 'External type name';

  @override
  String get ndefTnf => 'Type name format (TNF)';

  @override
  String get ndefTnfEmpty => 'Empty record';

  @override
  String get ndefTnfWellKnown => 'NFC well-known type';

  @override
  String get ndefTnfUnknown => 'Unknown type';

  @override
  String get ndefTnfUnchanged => 'Continuation chunk';

  @override
  String get ndefDetails => 'Dataset details';

  @override
  String get ndefSaveCopy => 'Save a copy';

  @override
  String get ndefSaveAsDataset => 'Save as NDEF dataset';

  @override
  String get ndefWriteTitle => 'Write NDEF tag';

  @override
  String get ndefWriteOverwrite =>
      'Existing NDEF content on the target tag will be replaced.';

  @override
  String get ndefWriteClassicWarning =>
      'Android or a HINATA reader may format MIFARE Classic, erasing its existing data.';

  @override
  String get ndefWriteKeepTag =>
      'Keep the tag in place until writing and verification finish.';

  @override
  String get ndefWriteIosLimit =>
      'iPhone cannot format MIFARE Classic. Formatted cards also require system support.';

  @override
  String get ndefWriteSuccess => 'NDEF content written and verified';

  @override
  String get ndefWriteChecking => 'Checking the tag';

  @override
  String get ndefWriteData => 'Writing NDEF content';

  @override
  String get ndefWriteVerifying => 'Reading back to verify';

  @override
  String get ndefWriteRewritableDescription =>
      'The tag can be written again later.';

  @override
  String get ndefWritePermanentDescription =>
      'The tag is locked read-only after writing. NTAG sets its lock bits and MIFARE Classic locks its sector access control. This cannot be undone.';

  @override
  String get ndefWritePermanentConfirmTitle => 'Permanently lock this tag?';

  @override
  String get ndefWritePermanentConfirmBody =>
      'After writing, the tag becomes read-only on every device. Its NDEF content can never be changed or erased again.';

  @override
  String get ndefWriteLocking => 'Locking the tag';

  @override
  String get ndefLockUnsupported =>
      'This tag cannot be made read-only. Nothing was written.';

  @override
  String get cardEmulate => 'Emulate';

  @override
  String get ndefEmulateTitle => 'Emulate NDEF tag';

  @override
  String get cardEmulatePreparing => 'Preparing the reader';

  @override
  String get ndefEmulateWaiting => 'Hold a phone to the reader';

  @override
  String get ndefEmulateConnected => 'Phone connected, reading';

  @override
  String get cardEmulateStopping => 'Stopping';

  @override
  String get cardEmulateStopped => 'Emulation stopped';

  @override
  String cardEmulateReadCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Read $count times',
      one: 'Read once',
    );
    return '$_temp0';
  }

  @override
  String get cardEmulateStop => 'Stop';

  @override
  String get ndefEmulateReadOnly =>
      'Phones read it as a read-only tag and cannot write to it.';

  @override
  String get cardEmulatePollingPaused =>
      'The reader stops reading cards while emulating.';

  @override
  String get ndefEmulateIosLimit =>
      'iPhone background reading mainly handles links; other records may need an NFC app.';

  @override
  String get cardEmulateFirmware =>
      'Requires reader firmware with emulation support.';

  @override
  String get cardEmulateFailed =>
      'Emulation failed. Check that the reader firmware supports emulation.';

  @override
  String get cardEmulateNoReader =>
      'Emulation requires a connected HINATA reader';

  @override
  String get cardEmulateReaderDisconnected => 'The reader was disconnected';

  @override
  String get ndefEmulateUnsupported => 'This dataset cannot be emulated';

  @override
  String get cardEmulateTitle => 'Emulate card';

  @override
  String get cardEmulateWaiting => 'Waiting for a reader';

  @override
  String get cardEmulateConnected => 'A reader is reading the card';

  @override
  String get cardEmulateOfficialWarning =>
      'Emulated cards cannot be used with official servers.';

  @override
  String get cardEmulateFelicaData => 'Emulates the saved card data.';

  @override
  String get cardEmulatePollOnly =>
      'A reader that only reads the card number is not shown here.';

  @override
  String get cardEmulateNdef =>
      'The card\'s NDEF data is emulated too, for phones and other NFC devices to read.';

  @override
  String get cardEmulateUnsupported => 'This card cannot be emulated';

  @override
  String get ndefRecordCount => 'NDEF record count';

  @override
  String get ndefDataSize => 'NDEF dataset size';

  @override
  String get ndefTagCapacity => 'NDEF capacity';

  @override
  String get ndefRecords => 'NDEF dataset';

  @override
  String ndefBytes(int bytes) {
    return '$bytes bytes';
  }

  @override
  String get banapassAccessCodeCannotCreate =>
      'This Banapass access code cannot be used to create a card.';

  @override
  String get cardEmulatePartial =>
      'This card was not fully read. The emulation may be incomplete.';

  @override
  String get cardEmulateNoChallenge => 'MAC authentication cannot be emulated.';

  @override
  String get cardReadIncomplete => 'This card was not fully read.';

  @override
  String get rawData => 'Raw data';

  @override
  String rawDataBlockCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count blocks',
      one: '1 block',
    );
    return '$_temp0';
  }

  @override
  String get rawDataComplete => 'This card was fully read.';

  @override
  String get rawDataNoBlocks =>
      'No data saved. Scan the card again to save it.';

  @override
  String rawDataService(String code) {
    return 'Service $code';
  }

  @override
  String get rawDataNoServiceBlocks => 'No blocks';

  @override
  String get rawDataCopyAll => 'Copy all';

  @override
  String get rawDataCopied => 'Raw data copied to clipboard';

  @override
  String get cardNotFullyRead => 'Not fully read';

  @override
  String rawDataSystem(String code) {
    return 'System $code';
  }

  @override
  String get ndefRecordsTitle => 'Records';

  @override
  String get ndefRecordsEmpty => 'No records yet';

  @override
  String get ndefRecordsEmptyHint =>
      'Add a link, text, Wi-Fi network or other content.';

  @override
  String get ndefRecordsMissing => 'Add at least one record';

  @override
  String get ndefOrderHint =>
      'Phones handle records in order and usually act on the first one. Drag the handle to reorder.';

  @override
  String get ndefChooseKind => 'Choose a record type';

  @override
  String get ndefKindsCommon => 'Common';

  @override
  String get ndefKindsAdvanced => 'Advanced';

  @override
  String get ndefKindUrlDescription => 'Opens a web page or another link';

  @override
  String get ndefKindTextDescription => 'Plain text, shown when read';

  @override
  String get ndefKindPhoneDescription => 'Calls a phone number';

  @override
  String get ndefKindEmailDescription => 'Drafts an email';

  @override
  String get ndefKindSmsDescription => 'Drafts a text message';

  @override
  String get ndefKindLocationDescription => 'Opens a place in maps';

  @override
  String get ndefKindWifiDescription => 'Joins a Wi-Fi network on Android';

  @override
  String get ndefKindContactDescription => 'Saves a contact';

  @override
  String get ndefKindAndroidAppDescription => 'Opens an app on Android';

  @override
  String get ndefKindMimeDescription => 'Text content with a media type';

  @override
  String get ndefKindExternalDescription => 'A record type an app defines';

  @override
  String get ndefKindRawDescription => 'The type and payload, byte by byte';

  @override
  String get ndefFieldRequired => 'Required';

  @override
  String get ndefFieldInvalid => 'Invalid format';

  @override
  String get ndefFieldOptional => 'Optional';

  @override
  String get ndefWifiPasswordShort => 'At least 8 characters';

  @override
  String get ndefLatitudeRange => 'Between -90 and 90';

  @override
  String get ndefLongitudeRange => 'Between -180 and 180';

  @override
  String get ndefTextPlaceholder => 'Text to show';

  @override
  String get ndefLanguageHint => 'A language tag, such as en, zh or ja';

  @override
  String get ndefHexHint => 'Hex bytes, such as 0A 1B 2C';

  @override
  String get ndefWifiOpenShort => 'Open';

  @override
  String get ndefRecordDone => 'Done';

  @override
  String get ndefRecordDelete => 'Delete record';

  @override
  String get ndefDiscardTitle => 'Discard changes?';

  @override
  String get ndefDiscardMessage => 'Your unsaved changes will be lost.';

  @override
  String get ndefDiscard => 'Discard';

  @override
  String get cardEmulateMifareTimeout =>
      'Only readers with lenient timeouts can read it; phones usually cannot.';
}
