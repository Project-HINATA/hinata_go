import '../l10n/l10n.dart';
import '../models/scan_log.dart';

String folderDisplayName(String folderId, String name) {
  if (folderId == 'history_folder') {
    return l10n.historyFolder;
  }
  if (folderId == 'favorites_folder') {
    return l10n.favoritesFolder;
  }
  return name;
}

String scanSourceDisplayName(ScanLog log) {
  if (log.source == 'NFC') {
    if (log.apiType != 'nfc') {
      return l10n.sourceNfcWithType(log.displayType);
    }
    return 'NFC';
  }
  if (log.source == 'Direct') {
    return l10n.savedCardsSource;
  }
  return log.source;
}
