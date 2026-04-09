import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// The name of the application
  ///
  /// In en, this message translates to:
  /// **'HINATA Go'**
  String get appTitle;

  /// Title for the settings page
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// Setting for how long a scanned card remains visible
  ///
  /// In en, this message translates to:
  /// **'Card Display Duration'**
  String get cardExpiration;

  /// Description of the card display duration setting
  ///
  /// In en, this message translates to:
  /// **'Duration in seconds before a scanned card is automatically cleared'**
  String get cardExpirationDescription;

  /// Display value for the duration
  ///
  /// In en, this message translates to:
  /// **'{seconds} seconds'**
  String cardExpirationValue(String seconds);

  /// Setting to enable a confirmation dialog before sending
  ///
  /// In en, this message translates to:
  /// **'Secondary Confirmation'**
  String get secondaryConfirmation;

  /// Description of the secondary confirmation setting
  ///
  /// In en, this message translates to:
  /// **'Ask for confirmation before sending card data'**
  String get secondaryConfirmationDescription;

  /// Entry for the about page
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// Button text to initiate a firmware/software update
  ///
  /// In en, this message translates to:
  /// **'UPDATE TO {version}'**
  String updateToVersion(String version);

  /// Language selection setting
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// Description for the language setting
  ///
  /// In en, this message translates to:
  /// **'Choose app display language'**
  String get languageDescription;

  /// Option to follow system language
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// Native name for English
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglishNative;

  /// Native name for Simplified Chinese
  ///
  /// In en, this message translates to:
  /// **'简体中文'**
  String get languageChineseNative;

  /// Navigation label for scanning
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get scan;

  /// Navigation label for card library
  ///
  /// In en, this message translates to:
  /// **'Cards'**
  String get cards;

  /// Feature to scan QR codes
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get scanQrCode;

  /// Status message while scanning
  ///
  /// In en, this message translates to:
  /// **'Scanning...'**
  String get scanning;

  /// Instruction to start scanning
  ///
  /// In en, this message translates to:
  /// **'Tap to Scan'**
  String get tapToScan;

  /// Status indicating the scanner is ready
  ///
  /// In en, this message translates to:
  /// **'Ready to Scan'**
  String get readyToScan;

  /// Status when NFC hardware is disabled
  ///
  /// In en, this message translates to:
  /// **'NFC Inactive'**
  String get nfcInactive;

  /// iOS-specific instruction for NFC scanning
  ///
  /// In en, this message translates to:
  /// **'Hold your card near the top of your iPhone.'**
  String get holdCardNearTop;

  /// Prompt to manually start NFC
  ///
  /// In en, this message translates to:
  /// **'Tap this area to activate the NFC reader.'**
  String get tapToActivateNfc;

  /// General NFC instruction
  ///
  /// In en, this message translates to:
  /// **'Hold your card near the NFC reader area of your device.'**
  String get holdCardNearReader;

  /// Error message for NFC state
  ///
  /// In en, this message translates to:
  /// **'NFC service is currently unavailable or disabled.'**
  String get nfcUnavailable;

  /// Prompt to choose a target server
  ///
  /// In en, this message translates to:
  /// **'No active instance selected.\nTap to select.'**
  String get noActiveInstanceSelectedTap;

  /// Empty state message for recent scans
  ///
  /// In en, this message translates to:
  /// **'No recent scans.'**
  String get noRecentScans;

  /// Title for the recent scans list
  ///
  /// In en, this message translates to:
  /// **'Recent Scans'**
  String get recentScans;

  /// Button to see full scan history
  ///
  /// In en, this message translates to:
  /// **'View All Logs'**
  String get viewAllLogs;

  /// Button to retry sending data
  ///
  /// In en, this message translates to:
  /// **'Resend to active instance'**
  String get resendToActiveInstance;

  /// Title for the history logs page
  ///
  /// In en, this message translates to:
  /// **'Scan History Logs'**
  String get scanHistoryLogs;

  /// Button to delete all history
  ///
  /// In en, this message translates to:
  /// **'Clear History'**
  String get clearHistory;

  /// Empty state for history logs
  ///
  /// In en, this message translates to:
  /// **'No scan history yet.'**
  String get noScanHistoryYet;

  /// Identifier for the source of a card
  ///
  /// In en, this message translates to:
  /// **'Saved Cards'**
  String get savedCardsSource;

  /// Detail line for card source
  ///
  /// In en, this message translates to:
  /// **'Source: {source}'**
  String sourceLine(String source);

  /// Detail line for scan time
  ///
  /// In en, this message translates to:
  /// **'Time: {time}'**
  String timeLine(String time);

  /// Action to save a card record
  ///
  /// In en, this message translates to:
  /// **'Save to Saved Cards'**
  String get saveToSavedCards;

  /// Title for the saved cards page
  ///
  /// In en, this message translates to:
  /// **'Saved Cards'**
  String get savedCards;

  /// Button to create a new folder
  ///
  /// In en, this message translates to:
  /// **'New Folder'**
  String get newFolder;

  /// Empty state for a folder
  ///
  /// In en, this message translates to:
  /// **'No cards in this folder.'**
  String get noCardsInFolder;

  /// Button to manually add a card
  ///
  /// In en, this message translates to:
  /// **'Add Card'**
  String get addCard;

  /// Error message for folder restrictions
  ///
  /// In en, this message translates to:
  /// **'Cannot delete default folders.'**
  String get cannotDeleteDefaultFolders;

  /// Title for delete confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Delete Folder?'**
  String get deleteFolder;

  /// Message for folder deletion warning
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{folderName}\" and all cards inside it?'**
  String deleteFolderMessage(String folderName);

  /// Standard cancel button
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Standard delete button
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Shortcut action for sending
  ///
  /// In en, this message translates to:
  /// **'Quick Send'**
  String get quickSend;

  /// Title for the manual card entry form
  ///
  /// In en, this message translates to:
  /// **'Add Card Manually'**
  String get addCardManually;

  /// Label for the card name input
  ///
  /// In en, this message translates to:
  /// **'Name / Description'**
  String get nameDescription;

  /// Label for folder selection
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get folder;

  /// Dropdown option to create a folder
  ///
  /// In en, this message translates to:
  /// **'+ New Folder'**
  String get newFolderOption;

  /// Field for the card's 20-digit access code
  ///
  /// In en, this message translates to:
  /// **'Access Code'**
  String get accessCode;

  /// Save action button
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Label for folder name input
  ///
  /// In en, this message translates to:
  /// **'Folder Name'**
  String get folderName;

  /// Confirmation to create
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// Title for the send confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Confirm Send'**
  String get confirmSend;

  /// Message showing the value being sent
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to send this card?\nValue: {value}'**
  String confirmSendWithValue(String value);

  /// Title for the instance management page
  ///
  /// In en, this message translates to:
  /// **'Remote Instances'**
  String get remoteInstances;

  /// Empty state for instances
  ///
  /// In en, this message translates to:
  /// **'No instances configured.'**
  String get noInstancesConfigured;

  /// Button to add a new server instance
  ///
  /// In en, this message translates to:
  /// **'Add Instance'**
  String get addInstance;

  /// Feedback when an instance is set as active
  ///
  /// In en, this message translates to:
  /// **'{name} is now active'**
  String instanceNowActive(String name);

  /// URL validation error
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid URL (http/https)'**
  String get invalidUrl;

  /// Endpoint validation error
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid address'**
  String get invalidEndpoint;

  /// Title for editing an instance
  ///
  /// In en, this message translates to:
  /// **'Edit Instance'**
  String get editInstance;

  /// Input placeholder for instance name
  ///
  /// In en, this message translates to:
  /// **'Name (e.g. maimaiDX)'**
  String get nameExample;

  /// Input placeholder for URL
  ///
  /// In en, this message translates to:
  /// **'Webhook URL (http://...)'**
  String get webhookUrl;

  /// Label for the address field
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get endpointLabel;

  /// Selection for server protocol type
  ///
  /// In en, this message translates to:
  /// **'Instance Type'**
  String get instanceType;

  /// HINATA IO instance type
  ///
  /// In en, this message translates to:
  /// **'HINATA IO'**
  String get instanceTypeHinataIo;

  /// SpiceAPI via TCP type
  ///
  /// In en, this message translates to:
  /// **'SpiceAPI (TcpSocket)'**
  String get instanceTypeSpiceApi;

  /// SpiceAPI via WebSocket type
  ///
  /// In en, this message translates to:
  /// **'SpiceAPI (WebSocket)'**
  String get instanceTypeSpiceApiWebSocket;

  /// Specific unit number for SpiceAPI
  ///
  /// In en, this message translates to:
  /// **'SpiceAPI Unit'**
  String get spiceApiUnit;

  /// Password field for SpiceAPI
  ///
  /// In en, this message translates to:
  /// **'Password (Optional)'**
  String get spiceApiPassword;

  /// Label for icon picker
  ///
  /// In en, this message translates to:
  /// **'Select Icon:'**
  String get selectIcon;

  /// Specific send confirmation
  ///
  /// In en, this message translates to:
  /// **'Send this {cardName} card to the active instance?'**
  String confirmSendToActiveInstance(String cardName);

  /// Header for card details page
  ///
  /// In en, this message translates to:
  /// **'{cardName} Details'**
  String cardDetails(String cardName);

  /// Success feedback for copy action
  ///
  /// In en, this message translates to:
  /// **'Value copied to clipboard'**
  String get valueCopiedToClipboard;

  /// Action to copy card ID/Access Code
  ///
  /// In en, this message translates to:
  /// **'Copy Value'**
  String get copyValue;

  /// Category for Amusement IC cards
  ///
  /// In en, this message translates to:
  /// **'Amusement IC Information'**
  String get amusementIcInfo;

  /// Card manufacturer label
  ///
  /// In en, this message translates to:
  /// **'Manufacturer'**
  String get manufacturer;

  /// Category for SEGA Aime cards
  ///
  /// In en, this message translates to:
  /// **'Aime Information'**
  String get aimeInfo;

  /// Details for FeliCa technology
  ///
  /// In en, this message translates to:
  /// **'FeliCa Technical Details'**
  String get felicaDetails;

  /// FeliCa IDm field
  ///
  /// In en, this message translates to:
  /// **'IDm'**
  String get idm;

  /// FeliCa PMm field
  ///
  /// In en, this message translates to:
  /// **'PMm'**
  String get pmm;

  /// FeliCa system code
  ///
  /// In en, this message translates to:
  /// **'System Code'**
  String get systemCode;

  /// Bandai Namco Banapassport data
  ///
  /// In en, this message translates to:
  /// **'Banapassport Data'**
  String get banapassData;

  /// Technical data block 1
  ///
  /// In en, this message translates to:
  /// **'Block 1'**
  String get block1;

  /// Technical data block 2
  ///
  /// In en, this message translates to:
  /// **'Block 2'**
  String get block2;

  /// Details for ISO14443 technology
  ///
  /// In en, this message translates to:
  /// **'ISO14443 Technical Details'**
  String get iso14443Details;

  /// Unique Identifier
  ///
  /// In en, this message translates to:
  /// **'UID'**
  String get uid;

  /// Select Acknowledge code
  ///
  /// In en, this message translates to:
  /// **'SAK'**
  String get sak;

  /// Answer to Request code
  ///
  /// In en, this message translates to:
  /// **'ATQA'**
  String get atqa;

  /// General technical info category
  ///
  /// In en, this message translates to:
  /// **'Technical Details'**
  String get technicalDetails;

  /// The main data value of the card
  ///
  /// In en, this message translates to:
  /// **'ID / Value'**
  String get idOrValue;

  /// Status text in uppercase
  ///
  /// In en, this message translates to:
  /// **'SAVING...'**
  String get savingUpper;

  /// Button text in uppercase
  ///
  /// In en, this message translates to:
  /// **'SAVE'**
  String get saveUpper;

  /// Status text in uppercase
  ///
  /// In en, this message translates to:
  /// **'SENDING...'**
  String get sendingUpper;

  /// Button text in uppercase
  ///
  /// In en, this message translates to:
  /// **'SEND'**
  String get sendUpper;

  /// Send action
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// Action to archive card
  ///
  /// In en, this message translates to:
  /// **'Save to Folder'**
  String get saveToFolder;

  /// Title for instance selection
  ///
  /// In en, this message translates to:
  /// **'Select Instance'**
  String get selectInstance;

  /// Empty state for instance list
  ///
  /// In en, this message translates to:
  /// **'No instances configured.'**
  String get noInstances;

  /// Success feedback for saving to folder
  ///
  /// In en, this message translates to:
  /// **'Saved \"{name}\" to {folder}.'**
  String savedToFolder(String name, String folder);

  /// Instruction for camera scanner
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get cameraScanInstruction;

  /// Default folder for history
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyFolder;

  /// Default folder for favorites
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favoritesFolder;

  /// Source identifier for NFC scans
  ///
  /// In en, this message translates to:
  /// **'NFC ({displayType})'**
  String sourceNfcWithType(String displayType);

  /// Hardware unsupported error
  ///
  /// In en, this message translates to:
  /// **'Your device does not support NFC'**
  String get nfcDeviceNotSupported;

  /// System settings prompt
  ///
  /// In en, this message translates to:
  /// **'Please enable NFC'**
  String get nfcEnablePrompt;

  /// Status indicating scanning is active
  ///
  /// In en, this message translates to:
  /// **'Listening for NFC...'**
  String get nfcListening;

  /// NFC error feedback
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String nfcError(String error);

  /// iOS system-style scanning message
  ///
  /// In en, this message translates to:
  /// **'Hold your card near the top of your iPhone'**
  String get nfcIosAlert;

  /// Error before sending
  ///
  /// In en, this message translates to:
  /// **'No active instance selected.'**
  String get noActiveInstanceSelected;

  /// Progress message for sending
  ///
  /// In en, this message translates to:
  /// **'Sending to {name}...'**
  String sendingToInstance(String name);

  /// Success feedback for sending
  ///
  /// In en, this message translates to:
  /// **'Success: Sent to {name}'**
  String successSentToInstance(String name);

  /// Failure feedback for sending
  ///
  /// In en, this message translates to:
  /// **'Failed: Could not send to {name}'**
  String failedSentToInstance(String name);

  /// Title for data management page
  ///
  /// In en, this message translates to:
  /// **'Data Management'**
  String get dataManagement;

  /// Description of data management features
  ///
  /// In en, this message translates to:
  /// **'Import or export cards and instances'**
  String get dataManagementDescription;

  /// Button to export data
  ///
  /// In en, this message translates to:
  /// **'Export Data'**
  String get exportData;

  /// Button to import data
  ///
  /// In en, this message translates to:
  /// **'Import Data'**
  String get importData;

  /// Success message for export
  ///
  /// In en, this message translates to:
  /// **'Export successful'**
  String get exportSuccess;

  /// Failure message for export
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String exportFailed(String error);

  /// Success message for import
  ///
  /// In en, this message translates to:
  /// **'Import successful'**
  String get importSuccess;

  /// Failure message for import
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String importFailed(String error);

  /// Method to export data to clipboard
  ///
  /// In en, this message translates to:
  /// **'Copy to Clipboard'**
  String get exportToClipboard;

  /// Method to export data to a file
  ///
  /// In en, this message translates to:
  /// **'Save to File'**
  String get exportToFile;

  /// Method to import from clipboard
  ///
  /// In en, this message translates to:
  /// **'Paste from Clipboard'**
  String get importFromClipboard;

  /// Method to import from a file
  ///
  /// In en, this message translates to:
  /// **'Load from File'**
  String get importFromFile;

  /// Title for export selection menu
  ///
  /// In en, this message translates to:
  /// **'Select Export Method'**
  String get selectExportMethod;

  /// Title for import selection menu
  ///
  /// In en, this message translates to:
  /// **'Select Import Method'**
  String get selectImportMethod;

  /// Error when parsing imported data
  ///
  /// In en, this message translates to:
  /// **'Invalid data format'**
  String get invalidDataFormat;

  /// Title for data import summary
  ///
  /// In en, this message translates to:
  /// **'Import Preview'**
  String get importPreviewTitle;

  /// Guidance text for import preview
  ///
  /// In en, this message translates to:
  /// **'The following data will be imported:'**
  String get importPreviewMessage;

  /// No description provided for @itemCountCards.
  ///
  /// In en, this message translates to:
  /// **'Cards: {count}'**
  String itemCountCards(int count);

  /// No description provided for @itemCountFolders.
  ///
  /// In en, this message translates to:
  /// **'Folders: {count}'**
  String itemCountFolders(int count);

  /// No description provided for @itemCountInstances.
  ///
  /// In en, this message translates to:
  /// **'Instances: {count}'**
  String itemCountInstances(int count);

  /// Final import confirmation button
  ///
  /// In en, this message translates to:
  /// **'Confirm Import'**
  String get confirmImport;

  /// Import mode: keep existing data
  ///
  /// In en, this message translates to:
  /// **'Merge Import'**
  String get importMerge;

  /// Import mode: delete existing data
  ///
  /// In en, this message translates to:
  /// **'Overwrite Import'**
  String get importOverwrite;

  /// Title for overwrite warning dialog
  ///
  /// In en, this message translates to:
  /// **'Confirm Overwrite'**
  String get confirmOverwriteTitle;

  /// Warning message for data loss
  ///
  /// In en, this message translates to:
  /// **'This will overwrite your local data irrecoverably. Are you sure?'**
  String get confirmOverwriteMessage;

  /// Validation rule for Aime codes
  ///
  /// In en, this message translates to:
  /// **'Access code must be 20 digits and not start with 3'**
  String get invalidAccessCodeLength;

  /// Title for hardware management
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get hardwareDevice;

  /// OTA firmware feature
  ///
  /// In en, this message translates to:
  /// **'Firmware Update'**
  String get firmwareUpdate;

  /// Hardware lighting configuration
  ///
  /// In en, this message translates to:
  /// **'LED Settings'**
  String get ledSettings;

  /// Main entry for hardware management
  ///
  /// In en, this message translates to:
  /// **'Device Hub'**
  String get deviceHub;

  /// Status when USB reader is not found
  ///
  /// In en, this message translates to:
  /// **'No Device Connected'**
  String get noDeviceConnected;

  /// Action to search for hardware
  ///
  /// In en, this message translates to:
  /// **'Scan for HINATA USB readers'**
  String get scanForDevices;

  /// Button to scan for USB hardware
  ///
  /// In en, this message translates to:
  /// **'Scan USB Device'**
  String get scanUsbDevice;

  /// Commit settings to non-volatile memory
  ///
  /// In en, this message translates to:
  /// **'Save to Flash Storage'**
  String get saveToFlash;

  /// Success feedback for flash writing
  ///
  /// In en, this message translates to:
  /// **'Configuration saved to Flash successfully!'**
  String get configSavedSuccess;

  /// Failure message for flash writing
  ///
  /// In en, this message translates to:
  /// **'Error saving to flash: {error}'**
  String errorSavingFlash(String error);

  /// Status when no firmware updates are found
  ///
  /// In en, this message translates to:
  /// **'Your device is up to date!'**
  String get upToDate;

  /// Alert for a new firmware version
  ///
  /// In en, this message translates to:
  /// **'Update Available'**
  String get updateAvailable;

  /// No description provided for @latestVersion.
  ///
  /// In en, this message translates to:
  /// **'Latest Version: {version}'**
  String latestVersion(String version);

  /// Button to start firmware update
  ///
  /// In en, this message translates to:
  /// **'Start Update'**
  String get startUpdate;

  /// Button to retry a failed update
  ///
  /// In en, this message translates to:
  /// **'Retry Update'**
  String get retryUpdate;

  /// Network or connection error during check
  ///
  /// In en, this message translates to:
  /// **'Failed to check firmware status.'**
  String get failedToCheckFirmware;

  /// Header for device control page
  ///
  /// In en, this message translates to:
  /// **'Settings & Controls'**
  String get settingsAndControls;

  /// Expert-level hardware settings
  ///
  /// In en, this message translates to:
  /// **'Advanced Config'**
  String get advancedConfig;

  /// Description of the firmware check feature
  ///
  /// In en, this message translates to:
  /// **'Check for the latest software version'**
  String get checkLatestSoftware;

  /// Description of the lighting feature
  ///
  /// In en, this message translates to:
  /// **'Configure lighting effects'**
  String get configureLighting;

  /// Display of current firmware version
  ///
  /// In en, this message translates to:
  /// **'Firmware: {version}'**
  String firmwareVersion(String version);

  /// Button to initiate connection to reader
  ///
  /// In en, this message translates to:
  /// **'Tap to Connect'**
  String get tapToConnect;

  /// Common hardware configurations
  ///
  /// In en, this message translates to:
  /// **'Global Settings'**
  String get globalSettings;

  /// Low-level protocol parameters
  ///
  /// In en, this message translates to:
  /// **'SEGA Serial Protocol Settings'**
  String get segaSerialSettings;

  /// Parameters for the card reading module
  ///
  /// In en, this message translates to:
  /// **'CardIO Settings'**
  String get cardioSettings;

  /// Reset hardware to factory settings
  ///
  /// In en, this message translates to:
  /// **'Restore Defaults'**
  String get restoreDefaults;

  /// Status while hardware is busy
  ///
  /// In en, this message translates to:
  /// **'Processing'**
  String get processing;

  /// Write settings to hardware to take effect
  ///
  /// In en, this message translates to:
  /// **'Apply Settings'**
  String get applySettings;

  /// Label for the tips section
  ///
  /// In en, this message translates to:
  /// **'Tips:'**
  String get tipsTitle;

  /// Warning about hardware memory durability
  ///
  /// In en, this message translates to:
  /// **'If you don\'t click Apply Settings, the reader will revert to the original settings after power cycling. However, since the flash chip has limited write cycles (hundreds at most), please apply settings only after confirming everything works correctly.'**
  String get flashWarning;

  /// Warning about changing USB identifiers
  ///
  /// In en, this message translates to:
  /// **'USB Descriptor uniqueness takes effect only after applying settings and power cycling the reader. After modification, the OS will treat it as a new device, SEGA games will require reassigning ports, and PC host apps may need to pair again.'**
  String get usbDescriptorNote;

  /// Switch to ignore specific card types
  ///
  /// In en, this message translates to:
  /// **'Disable ISO14443-A Card'**
  String get cardioDisableIso14443a;

  /// Rule for ID modification
  ///
  /// In en, this message translates to:
  /// **'Fill E004 to head when scanned ISO14443-A Card'**
  String get cardioIso14443aE004;

  /// Switch for USB unique identification
  ///
  /// In en, this message translates to:
  /// **'USB Descriptor Unique'**
  String get uniqueDescriptor;

  /// Animated rainbow lighting mode
  ///
  /// In en, this message translates to:
  /// **'Rainbow Light'**
  String get ledRainbow;

  /// Hardware and firmware version strings
  ///
  /// In en, this message translates to:
  /// **'HW/FW'**
  String get segaFwHw;

  /// Performance toggle for card reading
  ///
  /// In en, this message translates to:
  /// **'Rapid Scan'**
  String get segaFastRead;

  /// Slider/Setting for LED intensity
  ///
  /// In en, this message translates to:
  /// **'LED Brightness'**
  String get segaBrightness;

  /// Color when device is waiting
  ///
  /// In en, this message translates to:
  /// **'Idle Light Color'**
  String get idleRGB;

  /// Color when a card is swiped
  ///
  /// In en, this message translates to:
  /// **'Busy Light Color'**
  String get busyRGB;

  /// Color picker guidance
  ///
  /// In en, this message translates to:
  /// **'Pick a favorite color~'**
  String get pickFavoriteColor;

  /// Confirm button for color selection
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirmColorChoice;

  /// Status when scanning is suspended
  ///
  /// In en, this message translates to:
  /// **'Scan Pause'**
  String get scanPaused;

  /// Explanation for paused scan
  ///
  /// In en, this message translates to:
  /// **'App is out of focus, scanning paused'**
  String get scanPausedDescription;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
