import 'felica.dart';
import 'transit.dart';

class Suica extends Felica with TransitCard {
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
    super.persistedEpass,
  });

  @override
  String get balanceFormatted => "${balance.toInt()} JPY";

  @override
  String? get cardNumber => null; // Suica doesn't expose public card number in RF

  @override
  String? get gamePayload => null;

  @override
  String get name => "Suica";

  @override
  String? get logoPath => null; // Falls back to beautiful M3 icon avatar

  @override
  String? get type => "suica";

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
    final transactionsJson = json['transactions'] as List<dynamic>? ?? [];
    return Suica(
      felica.id,
      felica.pmm,
      felica.systemCode,
      balance: (json['balance'] as num? ?? 0.0).toDouble(),
      transactions: transactionsJson
          .map((e) => TransitTransaction.fromJson(e as Map<String, dynamic>))
          .toList(),
      snapshotTime: json['snapshotTime'] != null
          ? DateTime.tryParse(json['snapshotTime'] as String)
          : null,
      persistedEpass: felica.epass,
    );
  }
}
