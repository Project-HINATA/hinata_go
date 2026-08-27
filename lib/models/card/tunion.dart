import 'dart:typed_data';

import '../../l10n/l10n.dart';
import '../../utils/tunion_data.dart';
import 'iso14443a.dart';
import 'transit.dart';

class TUnion extends Iso14443 with TransitCard {
  @override
  final String cardNumber;

  @override
  final double balance;

  @override
  final List<TransitTransaction> transactions;

  @override
  final DateTime? snapshotTime;

  final String? issueDate;
  final String? expiryDate;
  final String? cardType;
  final bool? isInterchangeEnabled;

  final List<Uint8List?> rawBlocks;

  TUnion(
    super.id,
    super.sak,
    super.atqa, {
    required this.cardNumber,
    required this.balance,
    required this.transactions,
    this.snapshotTime,
    this.issueDate,
    this.expiryDate,
    this.cardType,
    this.isInterchangeEnabled,
    super.tags,
    this.rawBlocks = const [],
  });

  @override
  String get balanceFormatted => "${balance.toStringAsFixed(2)} CNY";

  @override
  String get showedValue => cardNumber;

  String? get issuerName => lookupTUnionIssuer(cardNumber);

  @override
  String get name => issuerName ?? "China T-Union";

  @override
  String? get logoPath => null; // Falls back to beautiful M3 icon avatar

  @override
  String? get type => "tunion";

  /// Localized card type string (e.g. Standard Card, Student Card, etc.)
  String? get localizedCardType => getLocalizedCardType();

  String? getLocalizedCardType([AppLocalizations? customL10n]) {
    final activeL10n = customL10n ?? l10n;
    if (cardType == null || cardType!.isEmpty) return null;
    final code = cardType!.trim();
    if (code == '01' || code == '1' || code.startsWith('普通卡') || code.contains('(01)')) {
      return activeL10n.transitCardTypeStandard;
    }
    if (code == '02' || code == '2' || code.startsWith('学生卡') || code.contains('(02)')) {
      return activeL10n.transitCardTypeStudent;
    }
    if (code == '03' || code == '3' || code.startsWith('老人卡') || code.contains('(03)')) {
      return activeL10n.transitCardTypeSenior;
    }
    if (code == '04' || code == '4' || code.startsWith('军人卡') || code.contains('(04)')) {
      return activeL10n.transitCardTypeMilitary;
    }
    // Extract hex code if formatted like "其他 (05)" or raw "05"
    final hexMatch = RegExp(r'([0-9a-fA-F]{2})').firstMatch(code);
    final displayCode = hexMatch != null ? hexMatch.group(1)!.toUpperCase() : code;
    return activeL10n.transitCardTypeOther(displayCode);
  }

  /// Decode station details using T-Union station database
  static String formatStation(String cityCode, String code) {
    final info = lookupTUnionStation(cityCode: cityCode, stationCode: code);
    return info?.formatted ?? (cityCode.isNotEmpty ? '[$cityCode] $code' : code);
  }

  /// Decode transaction details from city, station, and terminal information
  static String formatTransactionDetails({
    required String cityCode,
    String? stationCode,
    String? terminalId,
    String? industryCode,
    int typeCode = 0,
    String? entryCityCode,
    String? entryStationCode,
    String? entryIndustryCode,
    double amount = 0.0,
  }) {
    final formatted = formatTUnionDetails(
      cityCode: cityCode,
      stationCode: stationCode,
      terminalId: terminalId,
      industryCode: industryCode,
      typeCode: typeCode,
      entryCityCode: entryCityCode,
      entryStationCode: entryStationCode,
      entryIndustryCode: entryIndustryCode,
      amount: amount,
    );
    if (formatted.isNotEmpty) return formatted;
    if (terminalId != null && terminalId.isNotEmpty) {
      return "Terminal: $terminalId";
    }
    return cityCode.isNotEmpty ? "City: $cityCode" : "";
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'type': 'tunion',
      'cardNumber': cardNumber,
      'balance': balance,
      'transactions': transactions.map((t) => t.toJson()).toList(),
      if (snapshotTime != null) 'snapshotTime': snapshotTime!.toIso8601String(),
      if (issueDate != null) 'issueDate': issueDate,
      if (expiryDate != null) 'expiryDate': expiryDate,
      if (cardType != null) 'cardType': cardType,
      if (isInterchangeEnabled != null) 'isInterchangeEnabled': isInterchangeEnabled,
    };
  }

  factory TUnion.fromJson(Map<String, dynamic> json) {
    final iso = Iso14443.fromJson(json);
    final transactionsJson = json['transactions'] as List<dynamic>? ?? [];
    return TUnion(
      iso.id,
      iso.sak,
      iso.atqa,
      cardNumber: json['cardNumber'] as String? ?? '',
      balance: (json['balance'] as num? ?? 0.0).toDouble(),
      transactions: transactionsJson
          .map((e) => TransitTransaction.fromJson(e as Map<String, dynamic>))
          .toList(),
      snapshotTime: json['snapshotTime'] != null
          ? DateTime.tryParse(json['snapshotTime'] as String)
          : null,
      issueDate: json['issueDate'] as String?,
      expiryDate: json['expiryDate'] as String?,
      cardType: json['cardType'] as String?,
      isInterchangeEnabled: json['isInterchangeEnabled'] as bool?,
      tags: iso.tags,
    );
  }
}
