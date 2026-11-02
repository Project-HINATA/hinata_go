import 'dart:typed_data';
import 'package:hinata_go/core/data/ekicode_data.dart';
import 'card.dart';
import 'felica.dart';
import 'felica_dump.dart';
import 'transit.dart';

class Suica extends Felica with TransitCard {
  /// The history service, one 16-byte record per block, newest first.
  static const historyService = 0x090F;

  @override
  final double balance;

  @override
  final List<TransitTransaction> transactions;

  @override
  final DateTime? snapshotTime;

  Suica(
    super.id,
    super.pmm,
    super.systemCode, {
    required this.balance,
    required this.transactions,
    this.snapshotTime,
    super.tags,
    super.dump,
  });

  /// A card whose balance and history come from [dump]'s history service.
  factory Suica.fromDump(
    Uint8List id,
    Uint8List pmm,
    Uint16List systemCode,
    FelicaDump dump, {
    DateTime? snapshotTime,
    List<CardTag> tags = const [],
  }) {
    final history = dump.services[historyService] ?? const {};
    double? balanceOf(int block) {
      final data = history[block];
      return data == null ? null : (data[10] | data[11] << 8).toDouble();
    }

    final transactions = <TransitTransaction>[];
    for (final MapEntry(key: number, value: data) in history.entries) {
      // Unused records are all zeros or all 0xFF, or have no sequence number.
      if (data.every((b) => b == 0 || b == 0xFF)) continue;
      if ((data[13] << 8 | data[14]) == 0) continue;
      // A record's amount is the balance change since the record before it.
      final previous = balanceOf(number + 1);
      final amount = previous == null ? 0.0 : balanceOf(number)! - previous;
      transactions.add(parseTransaction(data, amount));
    }

    return Suica(
      id,
      pmm,
      systemCode,
      balance: balanceOf(0) ?? 0,
      transactions: transactions,
      snapshotTime: snapshotTime,
      tags: tags,
      dump: dump,
    );
  }

  @override
  bool get isHistoryComplete => isFullyRead;

  @override
  String get balanceFormatted => "${balance.toInt()} JPY";

  @override
  String? get cardNumber => null; // Suica doesn't expose public card number in RF

  @override
  String get name => "Suica";

  @override
  String? get logoPath => null; // Falls back to beautiful M3 icon avatar

  @override
  String? get type => "suica";

  /// Map process type code to readable process type
  static String getProcessType(int processType) {
    switch (processType) {
      case 0x01:
        return 'Ride';
      case 0x02:
        return 'Top-up';
      case 0x03:
      case 0x04:
      case 0x05:
      case 0x06:
        return 'Adjustment';
      case 0x07:
        return 'Issue';
      case 0x08:
      case 0x0c:
        return 'Deduction';
      case 0x0d:
      case 0x0f:
        return 'Ride';
      case 0x10:
      case 0x11:
        return 'Reissue';
      case 0x13:
        return 'Top-up';
      case 0x46:
      case 0x4b:
        return 'Shopping';
      case 0x48:
        return 'Top-up';
      default:
        return 'Other';
    }
  }

  /// Decode station details from region, line, and station bytes using ekicode database
  static String formatStation(int region, int line, int station) {
    final key = "$region,$line,$station";
    final value = ekicodeMap[key];
    if (value != null) {
      final parts = value.split('|');
      if (parts.length >= 2) {
        final lineName = parts[0].replaceAll(RegExp(r'^\d+号[線线]'), '');
        final suffix =
            (lineName.endsWith('線') ||
                lineName.endsWith('鉄道') ||
                lineName.contains('モバイル') ||
                lineName.contains('Suica') ||
                lineName.contains('Mobile'))
            ? ''
            : '線';
        return "${parts[1]} ($lineName$suffix)";
      }
    }
    return "Line 0x${line.toRadixString(16).toUpperCase().padLeft(2, '0')}, Station 0x${station.toRadixString(16).toUpperCase().padLeft(2, '0')}";
  }

  /// Parse a raw 16-byte FeliCa history block into a structured TransitTransaction
  static TransitTransaction parseTransaction(
    Uint8List blockData,
    double amount,
  ) {
    final consoleType = blockData[0];
    final processType = blockData[1];

    // Bytes 4-5 are the Date (stored in packed big-endian format)
    final dateRaw = (blockData[4] << 8) | blockData[5];
    final year = (dateRaw >> 9) & 0x7F;
    final month = (dateRaw >> 5) & 0x0F;
    final day = dateRaw & 0x1F;
    final fullYear = 2000 + year;

    // Entry and Exit line/station bytes
    final entryLine = blockData[6];
    final entryStation = blockData[7];
    final exitLine = blockData[8];
    final exitStation = blockData[9];

    // Bytes 13-14: Sequence Number (big-endian)
    final seq = (blockData[13] << 8) | blockData[14];

    final isShopping =
        processType == 0x46 ||
        processType == 0x4b ||
        consoleType == 0x46 ||
        consoleType == 0x4b;
    final typeStr = getProcessType(processType);

    final region = blockData[15] >> 4;

    final detailsStr = isShopping
        ? "Store/Time: ${entryLine.toString().padLeft(2, '0')}:${entryStation.toString().padLeft(2, '0')}"
        : (typeStr == 'Top-up'
              ? formatStation(region, entryLine, entryStation)
              : "${formatStation(region, entryLine, entryStation)} ──► ${formatStation(region, exitLine, exitStation)}");

    final txDate = DateTime(fullYear, month, day);

    return TransitTransaction(
      date: txDate,
      type: typeStr,
      amount: amount,
      details: detailsStr,
      seq: seq,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'type': 'suica',
      'balance': balance,
      'transactions': transactions.map((t) => t.toJson()).toList(),
      if (snapshotTime != null) 'snapshotTime': snapshotTime!.toIso8601String(),
    };
  }

  factory Suica.fromJson(Map<String, dynamic> json) {
    final felica = Felica.fromJson(json);
    final snapshotTime = json['snapshotTime'] != null
        ? DateTime.tryParse(json['snapshotTime'] as String)
        : null;
    final dump = felica.dump;
    if (dump != null && dump.services[historyService]?.isNotEmpty == true) {
      return Suica.fromDump(
        felica.id,
        felica.pmm,
        felica.systemCode,
        dump,
        snapshotTime: snapshotTime,
        tags: felica.tags,
      );
    }
    // Saved before cards kept their blocks.
    final transactionsJson = json['transactions'] as List<dynamic>? ?? [];
    return Suica(
      felica.id,
      felica.pmm,
      felica.systemCode,
      balance: (json['balance'] as num? ?? 0.0).toDouble(),
      transactions: transactionsJson
          .map((e) => TransitTransaction.fromJson(e as Map<String, dynamic>))
          .toList(),
      snapshotTime: snapshotTime,
      tags: felica.tags,
      dump: dump,
    );
  }
}
