import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import 'storage_provider.dart';
import 'app_state_provider.dart';
import '../models/remote_instance.dart';
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
      'instances': storage.getInstances().map((e) => e.toJson()).toList(),
      'card_folders': storage.getCardFolders().map((e) => e.toJson()).toList(),
      'saved_cards': storage.getSavedCards().map((e) => e.toJson()).toList(),
    };
  }

  Future<void> applyImport(
    Map<String, dynamic> data, {
    required bool merge,
  }) async {
    final storage = _ref.read(storageProvider);

    if (data.containsKey('instances')) {
      final importedInstances = (data['instances'] as List)
          .map((e) => RemoteInstance.fromJson(e as Map<String, dynamic>))
          .toList();
      if (merge) {
        final localInstances = storage.getInstances();
        for (final imported in importedInstances) {
          final isDuplicate = localInstances.any(
            (local) =>
                local.icon == imported.icon &&
                local.url == imported.url &&
                local.type == imported.type &&
                local.unit == imported.unit &&
                local.password == imported.password,
          );
          if (!isDuplicate) {
            localInstances.add(imported);
          }
        }
        await storage.saveInstances(localInstances);
      } else {
        await storage.saveInstances(importedInstances);
      }
      _ref.invalidate(instancesProvider);
    }

    if (data.containsKey('card_folders')) {
      final importedFolders = (data['card_folders'] as List)
          .map((e) => CardFolder.fromJson(e as Map<String, dynamic>))
          .toList();
      if (merge) {
        final localFolders = storage.getCardFolders();
        for (final imported in importedFolders) {
          final isDuplicate = localFolders.any(
            (local) => local.id == imported.id,
          );
          if (!isDuplicate) {
            localFolders.add(imported);
          }
        }
        await storage.saveCardFolders(localFolders);
      } else {
        await storage.saveCardFolders(importedFolders);
      }
      _ref.invalidate(cardFoldersProvider);
    }

    if (data.containsKey('saved_cards')) {
      final importedCards = (data['saved_cards'] as List)
          .map((e) => SavedCard.fromJson(e as Map<String, dynamic>))
          .toList();
      if (merge) {
        final localCards = storage.getSavedCards();
        for (final imported in importedCards) {
          final isDuplicate = localCards.any(
            (local) =>
                jsonEncode(local.card.toJson()) ==
                    jsonEncode(imported.card.toJson()) &&
                local.folderId == imported.folderId &&
                local.source == imported.source,
          );
          if (!isDuplicate) {
            localCards.add(imported);
          }
        }
        await storage.saveSavedCards(localCards);
      } else {
        await storage.saveSavedCards(importedCards);
      }
      _ref.invalidate(savedCardsProvider);
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
