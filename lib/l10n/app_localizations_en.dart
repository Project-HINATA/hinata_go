// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'SEGA NFC';

  @override
  String get settings => 'Settings';

  @override
  String get secondaryConfirmation => 'Secondary Confirmation';

  @override
  String get secondaryConfirmationDescription =>
      'Ask for confirmation before sending card data';

  @override
  String get about => 'About';

  @override
  String updateToVersion(Object version) {
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
  String get reader => 'Reader';

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
  String sourceLine(Object source) {
    return 'Source: $source';
  }

  @override
  String timeLine(Object time) {
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
  String deleteFolderMessage(Object folderName) {
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
  String confirmSendWithValue(Object value) {
    return 'Are you sure you want to send this card?\nValue: $value';
  }

  @override
  String get remoteInstances => 'Remote Instances';

  @override
  String get noInstancesConfigured => 'No instances configured.';

  @override
  String get addInstance => 'Add Instance';

  @override
  String instanceNowActive(Object name) {
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
  String confirmSendToActiveInstance(Object cardName) {
    return 'Send this $cardName card to the active instance?';
  }

  @override
  String cardDetails(Object cardName) {
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
  String savedToFolder(Object name, Object folder) {
    return 'Saved \"$name\" to $folder.';
  }

  @override
  String get cameraScanInstruction => 'Scan QR Code';

  @override
  String get historyFolder => 'History';

  @override
  String get favoritesFolder => 'Favorites';

  @override
  String sourceNfcWithType(Object displayType) {
    return 'NFC ($displayType)';
  }

  @override
  String get nfcDeviceNotSupported => 'Your device does not support NFC';

  @override
  String get nfcEnablePrompt => 'Please enable NFC';

  @override
  String get nfcListening => 'Listening for NFC...';

  @override
  String nfcError(Object error) {
    return 'Error: $error';
  }

  @override
  String get nfcIosAlert => 'Hold your card near the top of your iPhone';

  @override
  String get noActiveInstanceSelected => 'No active instance selected.';

  @override
  String sendingToInstance(Object name) {
    return 'Sending to $name...';
  }

  @override
  String successSentToInstance(Object name) {
    return 'Success: Sent to $name';
  }

  @override
  String failedSentToInstance(Object name) {
    return 'Failed: Could not send to $name';
  }
}
