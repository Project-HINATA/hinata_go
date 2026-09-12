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
      'Hold a MIFARE Classic 1K card near the phone or reader';

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
  String get prismSelectCard => 'Select a card';

  @override
  String get prismSignOut => 'Sign out';

  @override
  String get prismSignOutConfirm => 'Sign out?';

  @override
  String get prismSignOutAction => 'Sign out';

  @override
  String get prismOk => 'OK';

  @override
  String get prismRetry => 'Retry';

  @override
  String get prismContinueLogin => 'Continue sign-in';

  @override
  String get prismConnectingMunet => 'Connecting to MuNET…';

  @override
  String get prismSignInMunet => 'Sign in with MuNET';

  @override
  String get prismVerifyingPasskey => 'Verifying passkey…';

  @override
  String get prismSignInPasskey => 'Sign in with a passkey';

  @override
  String get prismPasskeyOnWeb => 'Use a passkey on the web';

  @override
  String get prismReturnAfterAuth =>
      'After signing in, return here to reload your cards.';

  @override
  String get prismReloadCards => 'Reload cards';

  @override
  String get prismLoadingCards => 'Loading cards';

  @override
  String get prismCardsFailed => 'Could not load cards';

  @override
  String get prismNoCards => 'No cards available. Add a card in PRiSM first.';

  @override
  String get prismLoading => 'Loading';

  @override
  String get prismSessionFailed => 'Could not start machine session';

  @override
  String get prismExpired => 'This session has expired';

  @override
  String get prismScanAgain => 'Tap the NFC tag or scan the QR code again.';

  @override
  String get prismCompleted => 'Sign-in complete';

  @override
  String get prismClosePage => 'You can close this page';

  @override
  String get prismSignedIn => 'Signed in';

  @override
  String get prismSigningIn => 'Signing in…';

  @override
  String get prismLocating => 'Checking location…';

  @override
  String prismCardEnding(String digits) {
    return 'Ending in $digits';
  }

  @override
  String get prismBackHome => 'Back to home';

  @override
  String get prismMachineInfoFailed => 'Could not load machine information';

  @override
  String get prismOpenWebFailed =>
      'Could not open the web page. Please try again.';

  @override
  String get prismOpenMunetFailed => 'Could not open MuNET sign-in';

  @override
  String get prismLocationDenied =>
      'Allow location access to confirm you are at the arcade.';

  @override
  String get prismLocationFailed => 'Could not determine your location';

  @override
  String get prismLocationTimeout => 'Location timed out. Please try again.';

  @override
  String get prismLocationBusy =>
      'Getting your location. Please try again shortly.';

  @override
  String get prismAtArcade => 'Please sign in when you are at the arcade.';

  @override
  String get prismMachineUnavailable =>
      'This machine is unavailable. Please try again later.';

  @override
  String get prismNetworkFailed =>
      'Connection failed. Check your network and try again.';

  @override
  String get prismOperationFailed =>
      'Something went wrong. Please try again later.';

  @override
  String get prismRateLimited => 'Too many requests. Please try again later.';

  @override
  String get prismRestricted => 'This action is currently unavailable';

  @override
  String get prismAccountUnavailable => 'This account is currently unavailable';

  @override
  String get prismCardUnavailable => 'This card is unavailable or has expired';

  @override
  String get prismSignInRequired => 'Please sign in first';

  @override
  String get prismAuthExpired =>
      'Authorization code expired. Please sign in again.';

  @override
  String get prismMunetFailed => 'MuNET sign-in failed';

  @override
  String get prismPasskeyFailed => 'Passkey verification failed';

  @override
  String get prismPasskeyExpired => 'The passkey request has expired';

  @override
  String get prismPasskeyUnknown => 'Passkey not recognized';

  @override
  String get prismInvalidURL => 'Invalid PRiSM URL';

  @override
  String get prismInvalidResponse => 'Invalid response from PRiSM';

  @override
  String get prismRefresh => 'Refresh';

  @override
  String get prismBindQQ => 'Bind QQ';

  @override
  String get prismNewMember =>
      'A player profile will be created after verification.';

  @override
  String get prismExistingMember =>
      'This store accepts existing players only. Use your registered QQ account.';

  @override
  String get prismSendBot => 'Send in the QQ group';

  @override
  String get prismExpires => 'Expires at';

  @override
  String get prismCopy => 'Copy';

  @override
  String get prismGenerateCode => 'Generate code';

  @override
  String get prismVerifyBinding => 'Check verification';

  @override
  String get prismEnter => 'Check in';

  @override
  String get prismConsent =>
      'Start billing and check out before leaving. Closing this page does not stop billing.';

  @override
  String get prismDoorPassword => 'Door code';

  @override
  String get prismEnterPassword => 'Enter the code on the lock, then press #';

  @override
  String get prismEnterAndOpen => 'Check in and get door code';

  @override
  String get prismGetPassword => 'Get door code';

  @override
  String get prismPoweredOff => 'Device is powered off';

  @override
  String get prismPowerOn => 'Power on';

  @override
  String get prismCoin => 'Insert coin';

  @override
  String get prismMyVisit => 'My visit · Check out';

  @override
  String get prismInStore => 'Checked in';

  @override
  String get prismNotInStore => 'Not checked in';

  @override
  String get prismStarted => 'Started';

  @override
  String get prismPreviewCheckout => 'Preview checkout';

  @override
  String get prismCheckout => 'Checkout preview';

  @override
  String get prismTotal => 'Total';

  @override
  String get prismFinalAmount =>
      'The final amount is calculated at confirmation. Billing continues if funds or location checks fail.';

  @override
  String get prismConfirmCheckout => 'Check out';

  @override
  String get prismAssets => 'Store assets';

  @override
  String get prismRedeemCode => 'Redemption code';

  @override
  String get prismRedeem => 'Redeem';

  @override
  String get prismHistory => 'History';

  @override
  String get prismAllDay => 'All day';

  @override
  String get prismMinutes => 'minutes';

  @override
  String get prismGrace => 'Grace';

  @override
  String get prismCap => 'Cap';

  @override
  String get prismWeekdays => 'Weekdays (0 = Sunday)';

  @override
  String get prismCoinSent => 'Coin sent';

  @override
  String get prismPowerSent => 'Power-on requested';

  @override
  String get prismCheckedOut => 'Checked out';

  @override
  String get prismRedeemed => 'Redeemed';

  @override
  String get prismContinueDevice => 'Continue with device';

  @override
  String get prismSwipeAndCoin => 'Card sent and one coin inserted';

  @override
  String get prismCoinCooldown =>
      'Card sent. No coin was inserted because the cooldown is active.';

  @override
  String get prismCoinFailed =>
      'Card sent. The coin request failed. Please contact staff.';

  @override
  String get prismCoinUnknown =>
      'Card sent. The coin result is unknown. Check the machine before swiping again.';

  @override
  String get prismClose => 'Close';

  @override
  String get prismRegenerateCode => 'Generate a new code';

  @override
  String get prismWaitingPower => 'Waiting for power';

  @override
  String get prismMySpending => 'My spending';

  @override
  String get prismStillBilling => 'Billing continues until checkout succeeds.';

  @override
  String get prismBilling => 'Billing in progress';

  @override
  String get prismBackToDevice => 'Back to device';

  @override
  String get prismStoreDevices => 'Store devices';

  @override
  String get prismRefreshPassword => 'Get a new password';

  @override
  String get prismBill => 'Bill';

  @override
  String get prismWallet => 'Wallet';

  @override
  String get prismNoBill => 'No outstanding bill';

  @override
  String get prismNoAssets => 'No assets';

  @override
  String get prismNoRecords => 'No records';

  @override
  String get prismNow => 'Now';

  @override
  String get prismTimeSlots => 'Rates by time';

  @override
  String get prismPerEntry => 'Per entry';

  @override
  String get prismClosed => 'Entry unavailable';

  @override
  String get prismCombinedCap => 'Combined cap';

  @override
  String get prismSlotCap => 'Period cap';

  @override
  String get prismUnitGrace => 'Grace per unit';

  @override
  String get prismPricingExplanation =>
      'Charges are calculated per period, rounding up after the grace allowance. Caps accumulate within each rule period, including when that period crosses midnight.';

  @override
  String get prismNextDay => 'next day ';

  @override
  String get prismRuleOrder =>
      'When periods overlap, the first matching rule below applies.';

  @override
  String get prismContinuousPeriod => 'Continuous period';

  @override
  String get prismMahjongTable => 'Mahjong table';

  @override
  String get prismMahjongPlaying => 'Mahjong billing active';

  @override
  String get prismMahjongWaiting => 'Waiting to start';

  @override
  String get prismMahjongYou => 'You';

  @override
  String get prismMahjongJoin => 'Join table';

  @override
  String get prismMahjongLeave => 'Leave table';
}
