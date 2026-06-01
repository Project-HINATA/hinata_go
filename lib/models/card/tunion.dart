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

  TUnion(
    super.id,
    super.sak,
    super.atqa, {
    required this.cardNumber,
    required this.balance,
    required this.transactions,
    this.snapshotTime,
  });

  @override
  String get balanceFormatted => "${balance.toStringAsFixed(2)} CNY";

  @override
  String get showedValue => cardNumber;

  @override
  String get name => "China T-Union";

  @override
  String? get logoPath => null; // Falls back to beautiful M3 icon avatar

  @override
  String? get type => "tunion";

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'type': 'tunion',
      'cardNumber': cardNumber,
      'balance': balance,
      'transactions': transactions.map((t) => t.toJson()).toList(),
      if (snapshotTime != null) 'snapshotTime': snapshotTime!.toIso8601String(),
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
    );
  }
}
