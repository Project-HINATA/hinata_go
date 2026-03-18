import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import 'storage_provider.dart';
import 'app_state_provider.dart';
import '../models/scan_log.dart';
import '../models/card/saved_card.dart';
import '../models/card_folder.dart';

final dataManagementProvider = Provider<DataManagementService>((ref) {
  return DataManagementService(ref);
});

class DataManagementService {
  final Ref _ref;

  DataManagementService(this._ref);

  Map<String, dynamic> _getRawData() {
    final storage = _ref.read(storageProvider);
    return {
      'scan_logs': storage.getScanLogs().map((e) => e.toJson()).toList(),
      'card_folders': storage.getCardFolders().map((e) => e.toJson()).toList(),
      'saved_cards': storage.getSavedCards().map((e) => e.toJson()).toList(),
    };
  }

  Future<void> applyImport(Map<String, dynamic> data) async {
    final storage = _ref.read(storageProvider);

    if (data.containsKey('card_folders')) {
      final folders = (data['card_folders'] as List)
          .map((e) => CardFolder.fromJson(e as Map<String, dynamic>))
          .toList();
      await storage.saveCardFolders(folders);
      _ref.invalidate(cardFoldersProvider);
    }

    if (data.containsKey('saved_cards')) {
      final cards = (data['saved_cards'] as List)
          .map((e) => SavedCard.fromJson(e as Map<String, dynamic>))
          .toList();
      await storage.saveSavedCards(cards);
      _ref.invalidate(savedCardsProvider);
    }

    if (data.containsKey('scan_logs')) {
      final logs = (data['scan_logs'] as List)
          .map((e) => ScanLog.fromJson(e as Map<String, dynamic>))
          .toList();
      await storage.saveScanLogs(logs);
      _ref.invalidate(scanLogsProvider);
    }
  }

  Future<void> exportToClipboard() async {
    final rawData = _getRawData();
    final jsonString = jsonEncode(rawData);
    final base64String = base64Encode(utf8.encode(jsonString));
    await Clipboard.setData(ClipboardData(text: base64String));
  }

  Future<Map<String, dynamic>?> importFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      try {
        final jsonString = utf8.decode(base64Decode(data.text!.trim()));
        final Map<String, dynamic> decodedData = jsonDecode(jsonString);
        return decodedData;
      } catch (e) {
        throw Exception('invalidDataFormat');
      }
    } else {
      throw Exception('invalidDataFormat');
    }
  }

  Future<void> exportToFile() async {
    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Backup',
      fileName: 'sega_nfc_backup.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (outputFile != null) {
      final file = File(outputFile);
      final rawData = _getRawData();
      await file.writeAsString(jsonEncode(rawData));
    }
  }

  Future<Map<String, dynamic>?> importFromFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final content = await file.readAsString();

      try {
        final Map<String, dynamic> decodedData = jsonDecode(content);
        return decodedData;
      } catch (e) {
        try {
          // Fallback if the user somehow pasted base64 into the file
          final jsonString = utf8.decode(base64Decode(content.trim()));
          final Map<String, dynamic> decodedData = jsonDecode(jsonString);
          return decodedData;
        } catch (e2) {
          throw Exception('invalidDataFormat');
        }
      }
    }
    return null;
  }
}