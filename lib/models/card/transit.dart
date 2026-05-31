import 'card.dart';

class TransitTransaction {
  final DateTime? date;
  final String type; // 'Ride', 'Top-up', 'Shopping', 'Refund', 'Other'
  final double amount; // amount in JPY or CNY
  final String details; // e.g. "Entry ──► Exit" or "Store/Time"
  final String? terminalId;
  final int? seq;

  TransitTransaction({
    this.date,
    required this.type,
    required this.amount,
    required this.details,
    this.terminalId,
    this.seq,
  });

  Map<String, dynamic> toJson() {
    return {
      if (date != null) 'date': date!.toIso8601String(),
      'type': type,
      'amount': amount,
      'details': details,
      if (terminalId != null) 'terminalId': terminalId,
      if (seq != null) 'seq': seq,
    };
  }

  factory TransitTransaction.fromJson(Map<String, dynamic> json) {
    return TransitTransaction(
      date: json['date'] != null
          ? DateTime.tryParse(json['date'] as String)
          : null,
      type: json['type'] as String? ?? 'Other',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      details: json['details'] as String? ?? '',
      terminalId: json['terminalId'] as String?,
      seq: json['seq'] as int?,
    );
  }
}

mixin TransitCard on ICCard {
  double get balance;
  String get balanceFormatted;
  List<TransitTransaction> get transactions;
  String? get cardNumber;
  DateTime? get snapshotTime;
}
