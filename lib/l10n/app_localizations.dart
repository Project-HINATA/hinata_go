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

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'SEGA NFC'**
  String get appTitle;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @secondaryConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Secondary Confirmation'**
  String get secondaryConfirmation;

  /// No description provided for @secondaryConfirmationDescription.
  ///
  /// In en, this message translates to:
  /// **'Ask for confirmation before sending card data'**
  String get secondaryConfirmationDescription;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @updateToVersion.
  ///
  /// In en, this message translates to:
  /// **'UPDATE TO {version}'**
  String updateToVersion(Object version);

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose app display language'**
  String get languageDescription;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// No description provided for @languageEnglishNative.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglishNative;

  /// No description provided for @languageChineseNative.
  ///
  /// In en, this message translates to:
  /// **'简体中文'**
  String get languageChineseNative;

  /// No description provided for @reader.
  ///
  /// In en, this message translates to:
  /// **'Reader'**
  String get reader;

  /// No description provided for @cards.
  ///
  /// In en, this message translates to:
  /// **'Cards'**
  String get cards;

  /// No description provided for @scanQrCode.
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get scanQrCode;

  /// No description provided for @scanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning...'**
  String get scanning;

  /// No description provided for @tapToScan.
  ///
  /// In en, this message translates to:
  /// **'Tap to Scan'**
  String get tapToScan;

  /// No description provided for @readyToScan.
  ///
  /// In en, this message translates to:
  /// **'Ready to Scan'**
  String get readyToScan;

  /// No description provided for @nfcInactive.
  ///
  /// In en, this message translates to:
  /// **'NFC Inactive'**
  String get nfcInactive;

  /// No description provided for @holdCardNearTop.
  ///
  /// In en, this message translates to:
  /// **'Hold your card near the top of your iPhone.'**
  String get holdCardNearTop;

  /// No description provided for @tapToActivateNfc.
  ///
  /// In en, this message translates to:
  /// **'Tap this area to activate the NFC reader.'**
  String get tapToActivateNfc;

  /// No description provided for @holdCardNearReader.
  ///
  /// In en, this message translates to:
  /// **'Hold your card near the NFC reader area of your device.'**
  String get holdCardNearReader;

  /// No description provided for @nfcUnavailable.
  ///
  /// In en, this message translates to:
  /// **'NFC service is currently unavailable or disabled.'**
  String get nfcUnavailable;

  /// No description provided for @noActiveInstanceSelectedTap.
  ///
  /// In en, this message translates to:
  /// **'No active instance selected.\nTap to select.'**
  String get noActiveInstanceSelectedTap;

  /// No description provided for @noRecentScans.
  ///
  /// In en, this message translates to:
  /// **'No recent scans.'**
  String get noRecentScans;

  /// No description provided for @recentScans.
  ///
  /// In en, this message translates to:
  /// **'Recent Scans'**
  String get recentScans;

  /// No description provided for @viewAllLogs.
  ///
  /// In en, this message translates to:
  /// **'View All Logs'**
  String get viewAllLogs;

  /// No description provided for @resendToActiveInstance.
  ///
  /// In en, this message translates to:
  /// **'Resend to active instance'**
  String get resendToActiveInstance;

  /// No description provided for @scanHistoryLogs.
  ///
  /// In en, this message translates to:
  /// **'Scan History Logs'**
  String get scanHistoryLogs;

  /// No description provided for @clearHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear History'**
  String get clearHistory;

  /// No description provided for @noScanHistoryYet.
  ///
  /// In en, this message translates to:
  /// **'No scan history yet.'**
  String get noScanHistoryYet;

  /// No description provided for @savedCardsSource.
  ///
  /// In en, this message translates to:
  /// **'Saved Cards'**
  String get savedCardsSource;

  /// No description provided for @sourceLine.
  ///
  /// In en, this message translates to:
  /// **'Source: {source}'**
  String sourceLine(Object source);

  /// No description provided for @timeLine.
  ///
  /// In en, this message translates to:
  /// **'Time: {time}'**
  String timeLine(Object time);

  /// No description provided for @saveToSavedCards.
  ///
  /// In en, this message translates to:
  /// **'Save to Saved Cards'**
  String get saveToSavedCards;

  /// No description provided for @savedCards.
  ///
  /// In en, this message translates to:
  /// **'Saved Cards'**
  String get savedCards;

  /// No description provided for @newFolder.
  ///
  /// In en, this message translates to:
  /// **'New Folder'**
  String get newFolder;

  /// No description provided for @noCardsInFolder.
  ///
  /// In en, this message translates to:
  /// **'No cards in this folder.'**
  String get noCardsInFolder;

  /// No description provided for @addCard.
  ///
  /// In en, this message translates to:
  /// **'Add Card'**
  String get addCard;

  /// No description provided for @cannotDeleteDefaultFolders.
  ///
  /// In en, this message translates to:
  /// **'Cannot delete default folders.'**
  String get cannotDeleteDefaultFolders;

  /// No description provided for @deleteFolder.
  ///
  /// In en, this message translates to:
  /// **'Delete Folder?'**
  String get deleteFolder;

  /// No description provided for @deleteFolderMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{folderName}\" and all cards inside it?'**
  String deleteFolderMessage(Object folderName);

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @quickSend.
  ///
  /// In en, this message translates to:
  /// **'Quick Send'**
  String get quickSend;

  /// No description provided for @addCardManually.
  ///
  /// In en, this message translates to:
  /// **'Add Card Manually'**
  String get addCardManually;

  /// No description provided for @nameDescription.
  ///
  /// In en, this message translates to:
  /// **'Name / Description'**
  String get nameDescription;

  /// No description provided for @folder.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get folder;

  /// No description provided for @newFolderOption.
  ///
  /// In en, this message translates to:
  /// **'+ New Folder'**
  String get newFolderOption;

  /// No description provided for @accessCode.
  ///
  /// In en, this message translates to:
  /// **'Access Code'**
  String get accessCode;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @folderName.
  ///
  /// In en, this message translates to:
  /// **'Folder Name'**
  String get folderName;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @confirmSend.
  ///
  /// In en, this message translates to:
  /// **'Confirm Send'**
  String get confirmSend;

  /// No description provided for @confirmSendWithValue.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to send this card?\nValue: {value}'**
  String confirmSendWithValue(Object value);

  /// No description provided for @remoteInstances.
  ///
  /// In en, this message translates to:
  /// **'Remote Instances'**
  String get remoteInstances;

  /// No description provided for @noInstancesConfigured.
  ///
  /// In en, this message translates to:
  /// **'No instances configured.'**
  String get noInstancesConfigured;

  /// No description provided for @addInstance.
  ///
  /// In en, this message translates to:
  /// **'Add Instance'**
  String get addInstance;

  /// No description provided for @instanceNowActive.
  ///
  /// In en, this message translates to:
  /// **'{name} is now active'**
  String instanceNowActive(Object name);

  /// No description provided for @invalidUrl.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid URL (http/https)'**
  String get invalidUrl;

  /// No description provided for @invalidEndpoint.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid address'**
  String get invalidEndpoint;

  /// No description provided for @editInstance.
  ///
  /// In en, this message translates to:
  /// **'Edit Instance'**
  String get editInstance;

  /// No description provided for @nameExample.
  ///
  /// In en, this message translates to:
  /// **'Name (e.g. maimaiDX)'**
  String get nameExample;

  /// No description provided for @webhookUrl.
  ///
  /// In en, this message translates to:
  /// **'Webhook URL (http://...)'**
  String get webhookUrl;

  /// No description provided for @endpointLabel.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get endpointLabel;

  /// No description provided for @instanceType.
  ///
  /// In en, this message translates to:
  /// **'Instance Type'**
  String get instanceType;

  /// No description provided for @instanceTypeHinataIo.
  ///
  /// In en, this message translates to:
  /// **'HINATA IO'**
  String get instanceTypeHinataIo;

  /// No description provided for @instanceTypeSpiceApi.
  ///
  /// In en, this message translates to:
  /// **'SpiceAPI (TcpSocket)'**
  String get instanceTypeSpiceApi;

  /// No description provided for @instanceTypeSpiceApiWebSocket.
  ///
  /// In en, this message translates to:
  /// **'SpiceAPI (WebSocket)'**
  String get instanceTypeSpiceApiWebSocket;

  /// No description provided for @spiceApiUnit.
  ///
  /// In en, this message translates to:
  /// **'SpiceAPI Unit'**
  String get spiceApiUnit;

  /// No description provided for @spiceApiPassword.
  ///
  /// In en, this message translates to:
  /// **'Password (Optional)'**
  String get spiceApiPassword;

  /// No description provided for @selectIcon.
  ///
  /// In en, this message translates to:
  /// **'Select Icon:'**
  String get selectIcon;

  /// No description provided for @confirmSendToActiveInstance.
  ///
  /// In en, this message translates to:
  /// **'Send this {cardName} card to the active instance?'**
  String confirmSendToActiveInstance(Object cardName);

  /// No description provided for @cardDetails.
  ///
  /// In en, this message translates to:
  /// **'{cardName} Details'**
  String cardDetails(Object cardName);

  /// No description provided for @valueCopiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Value copied to clipboard'**
  String get valueCopiedToClipboard;

  /// No description provided for @copyValue.
  ///
  /// In en, this message translates to:
  /// **'Copy Value'**
  String get copyValue;

  /// No description provided for @amusementIcInfo.
  ///
  /// In en, this message translates to:
  /// **'Amusement IC Information'**
  String get amusementIcInfo;

  /// No description provided for @manufacturer.
  ///
  /// In en, this message translates to:
  /// **'Manufacturer'**
  String get manufacturer;

  /// No description provided for @aimeInfo.
  ///
  /// In en, this message translates to:
  /// **'Aime Information'**
  String get aimeInfo;

  /// No description provided for @felicaDetails.
  ///
  /// In en, this message translates to:
  /// **'FeliCa Technical Details'**
  String get felicaDetails;

  /// No description provided for @idm.
  ///
  /// In en, this message translates to:
  /// **'IDm'**
  String get idm;

  /// No description provided for @pmm.
  ///
  /// In en, this message translates to:
  /// **'PMm'**
  String get pmm;

  /// No description provided for @systemCode.
  ///
  /// In en, this message translates to:
  /// **'System Code'**
  String get systemCode;

  /// No description provided for @banapassData.
  ///
  /// In en, this message translates to:
  /// **'Banapassport Data'**
  String get banapassData;

  /// No description provided for @block1.
  ///
  /// In en, this message translates to:
  /// **'Block 1'**
  String get block1;

  /// No description provided for @block2.
  ///
  /// In en, this message translates to:
  /// **'Block 2'**
  String get block2;

  /// No description provided for @iso14443Details.
  ///
  /// In en, this message translates to:
  /// **'ISO14443 Technical Details'**
  String get iso14443Details;

  /// No description provided for @uid.
  ///
  /// In en, this message translates to:
  /// **'UID'**
  String get uid;

  /// No description provided for @sak.
  ///
  /// In en, this message translates to:
  /// **'SAK'**
  String get sak;

  /// No description provided for @atqa.
  ///
  /// In en, this message translates to:
  /// **'ATQA'**
  String get atqa;

  /// No description provided for @technicalDetails.
  ///
  /// In en, this message translates to:
  /// **'Technical Details'**
  String get technicalDetails;

  /// No description provided for @idOrValue.
  ///
  /// In en, this message translates to:
  /// **'ID / Value'**
  String get idOrValue;

  /// No description provided for @savingUpper.
  ///
  /// In en, this message translates to:
  /// **'SAVING...'**
  String get savingUpper;

  /// No description provided for @saveUpper.
  ///
  /// In en, this message translates to:
  /// **'SAVE'**
  String get saveUpper;

  /// No description provided for @sendingUpper.
  ///
  /// In en, this message translates to:
  /// **'SENDING...'**
  String get sendingUpper;

  /// No description provided for @sendUpper.
  ///
  /// In en, this message translates to:
  /// **'SEND'**
  String get sendUpper;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @saveToFolder.
  ///
  /// In en, this message translates to:
  /// **'Save to Folder'**
  String get saveToFolder;

  /// No description provided for @savedToFolder.
  ///
  /// In en, this message translates to:
  /// **'Saved \"{name}\" to {folder}.'**
  String savedToFolder(Object name, Object folder);

  /// No description provided for @cameraScanInstruction.
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get cameraScanInstruction;

  /// No description provided for @historyFolder.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyFolder;

  /// No description provided for @favoritesFolder.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favoritesFolder;

  /// No description provided for @sourceNfcWithType.
  ///
  /// In en, this message translates to:
  /// **'NFC ({displayType})'**
  String sourceNfcWithType(Object displayType);

  /// No description provided for @nfcDeviceNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Your device does not support NFC'**
  String get nfcDeviceNotSupported;

  /// No description provided for @nfcEnablePrompt.
  ///
  /// In en, this message translates to:
  /// **'Please enable NFC'**
  String get nfcEnablePrompt;

  /// No description provided for @nfcListening.
  ///
  /// In en, this message translates to:
  /// **'Listening for NFC...'**
  String get nfcListening;

  /// No description provided for @nfcError.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String nfcError(Object error);

  /// No description provided for @nfcIosAlert.
  ///
  /// In en, this message translates to:
  /// **'Hold your card near the top of your iPhone'**
  String get nfcIosAlert;

  /// No description provided for @noActiveInstanceSelected.
  ///
  /// In en, this message translates to:
  /// **'No active instance selected.'**
  String get noActiveInstanceSelected;

  /// No description provided for @sendingToInstance.
  ///
  /// In en, this message translates to:
  /// **'Sending to {name}...'**
  String sendingToInstance(Object name);

  /// No description provided for @successSentToInstance.
  ///
  /// In en, this message translates to:
  /// **'Success: Sent to {name}'**
  String successSentToInstance(Object name);

  /// No description provided for @failedSentToInstance.
  ///
  /// In en, this message translates to:
  /// **'Failed: Could not send to {name}'**
  String failedSentToInstance(Object name);

  /// No description provided for @dataManagement.
  ///
  /// In en, this message translates to:
  /// **'Data Management'**
  String get dataManagement;

  /// No description provided for @dataManagementDescription.
  ///
  /// In en, this message translates to:
  /// **'Import or export cards and instances'**
  String get dataManagementDescription;

  /// No description provided for @exportData.
  ///
  /// In en, this message translates to:
  /// **'Export Data'**
  String get exportData;

  /// No description provided for @importData.
  ///
  /// In en, this message translates to:
  /// **'Import Data'**
  String get importData;

  /// No description provided for @exportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Export successful'**
  String get exportSuccess;

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String exportFailed(Object error);

  /// No description provided for @importSuccess.
  ///
  /// In en, this message translates to:
  /// **'Import successful'**
  String get importSuccess;

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String importFailed(Object error);

  /// No description provided for @exportToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy to Clipboard'**
  String get exportToClipboard;

  /// No description provided for @exportToFile.
  ///
  /// In en, this message translates to:
  /// **'Save to File'**
  String get exportToFile;

  /// No description provided for @importFromClipboard.
  ///
  /// In en, this message translates to:
  /// **'Paste from Clipboard'**
  String get importFromClipboard;

  /// No description provided for @importFromFile.
  ///
  /// In en, this message translates to:
  /// **'Load from File'**
  String get importFromFile;

  /// No description provided for @selectExportMethod.
  ///
  /// In en, this message translates to:
  /// **'Select Export Method'**
  String get selectExportMethod;

  /// No description provided for @selectImportMethod.
  ///
  /// In en, this message translates to:
  /// **'Select Import Method'**
  String get selectImportMethod;

  /// No description provided for @invalidDataFormat.
  ///
  /// In en, this message translates to:
  /// **'Invalid data format'**
  String get invalidDataFormat;

  /// No description provided for @importPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Preview'**
  String get importPreviewTitle;

  /// No description provided for @importPreviewMessage.
  ///
  /// In en, this message translates to:
  /// **'The following data will be imported:'**
  String get importPreviewMessage;

  /// No description provided for @itemCountCards.
  ///
  /// In en, this message translates to:
  /// **'Cards: {count}'**
  String itemCountCards(Object count);

  /// No description provided for @itemCountFolders.
  ///
  /// In en, this message translates to:
  /// **'Folders: {count}'**
  String itemCountFolders(Object count);

  /// No description provided for @itemCountInstances.
  ///
  /// In en, this message translates to:
  /// **'Instances: {count}'**
  String itemCountInstances(Object count);

  /// No description provided for @confirmImport.
  ///
  /// In en, this message translates to:
  /// **'Confirm Import'**
  String get confirmImport;

  /// No description provided for @importMerge.
  ///
  /// In en, this message translates to:
  /// **'Merge Import'**
  String get importMerge;

  /// No description provided for @importOverwrite.
  ///
  /// In en, this message translates to:
  /// **'Overwrite Import'**
  String get importOverwrite;

  /// No description provided for @confirmOverwriteTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm Overwrite'**
  String get confirmOverwriteTitle;

  /// No description provided for @confirmOverwriteMessage.
  ///
  /// In en, this message translates to:
  /// **'This will overwrite your local data irrecoverably. Are you sure?'**
  String get confirmOverwriteMessage;

  /// No description provided for @invalidAccessCodeLength.
  ///
  /// In en, this message translates to:
  /// **'Access code must be 20 digits and not start with 3'**
  String get invalidAccessCodeLength;
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
