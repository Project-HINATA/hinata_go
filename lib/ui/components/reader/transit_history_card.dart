import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hinata_go/context_extensions.dart';
import 'package:intl/intl.dart';

import '../../../models/card/transit.dart';
import '../../../models/card/suica.dart';
import '../../../l10n/l10n.dart';

class TransitHistoryCard extends HookWidget {
  final TransitCard card;

  const TransitHistoryCard({required this.card, super.key});

  String _localizeType(BuildContext context, String type) {
    switch (type) {
      case 'Ride':
        return context.l10n.transitTypeRide;
      case 'Top-up':
        return context.l10n.transitTypeTopup;
      case 'Shopping':
        return context.l10n.transitTypeShopping;
      case 'Adjustment':
        return context.l10n.transitTypeAdjustment;
      case 'Refund':
        return context.l10n.transitTypeRefund;
      case 'Issue':
        return context.l10n.transitTypeIssue;
      case 'Deduction':
        return context.l10n.transitTypeDeduction;
      case 'Reissue':
        return context.l10n.transitTypeReissue;
      default:
        return context.l10n.transitTypeOther;
    }
  }

  IconData _getIconForType(String type) {
    switch (type) {
      case 'Ride':
        return Icons.directions_subway_filled_rounded;
      case 'Top-up':
        return Icons.add_card_rounded;
      case 'Shopping':
        return Icons.shopping_bag_rounded;
      case 'Adjustment':
        return Icons.build_circle_rounded;
      case 'Refund':
        return Icons.settings_backup_restore_rounded;
      case 'Issue':
      case 'Reissue':
        return Icons.credit_card_rounded;
      default:
        return Icons.receipt_long_rounded;
    }
  }

  Color _getColorForType(ColorScheme colorScheme, String type) {
    switch (type) {
      case 'Top-up':
      case 'Refund':
        return Colors.green;
      case 'Ride':
        return Colors.orangeAccent;
      case 'Shopping':
        return colorScheme.primary;
      default:
        return colorScheme.outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final isExpanded = useState(false);
    final transactions = card.transactions;

    if (transactions.isEmpty) {
      return const SizedBox.shrink();
    }

    final currencySymbol = card is Suica ? '¥' : '¥';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Toggle Area
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => isExpanded.value = !isExpanded.value,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.history_rounded,
                      color: colorScheme.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        context.l10n.transactionHistory,
                        style: context.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${transactions.length}',
                        style: context.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: isExpanded.value ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.fastOutSlowIn,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Expanded Records List
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: [
                const Divider(height: 1),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: transactions.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1, indent: 64),
                  itemBuilder: (context, index) {
                    final tx = transactions[index];
                    final txColor = _getColorForType(colorScheme, tx.type);
                    final isPositive =
                        tx.type == 'Top-up' || tx.type == 'Refund';

                    String amountText = '';
                    if (tx.amount != 0.0) {
                      final amountVal = tx.amount.abs();
                      final formattedAmt = card is Suica
                          ? amountVal.toInt().toString()
                          : amountVal.toStringAsFixed(2);
                      amountText =
                          '${isPositive ? "+" : "-"}$currencySymbol$formattedAmt';
                    } else {
                      amountText = card is Suica ? '0' : '0.00';
                      amountText = '$currencySymbol$amountText';
                    }

                    String dateStr = '';
                    if (tx.date != null) {
                      dateStr = DateFormat(
                        'yyyy/MM/dd HH:mm:ss',
                      ).format(tx.date!);
                    }

                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: txColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _getIconForType(tx.type),
                          color: txColor,
                          size: 18,
                        ),
                      ),
                      title: Row(
                        children: [
                          Text(
                            _localizeType(context, tx.type),
                            style: context.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          if (tx.seq != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              '#${tx.seq}',
                              style: context.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.6,
                                ),
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                          const Spacer(),
                          Text(
                            amountText,
                            style: context.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isPositive
                                  ? Colors.green
                                  : colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (tx.details.isNotEmpty)
                                    Text(
                                      tx.details,
                                      style: context.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  if (dateStr.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        dateStr,
                                        style: context.textTheme.labelSmall
                                            ?.copyWith(
                                              color: colorScheme
                                                  .onSurfaceVariant
                                                  .withValues(alpha: 0.6),
                                              fontFamily: 'monospace',
                                            ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            crossFadeState: isExpanded.value
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 300),
            sizeCurve: Curves.easeInOutCubic,
          ),
        ],
      ),
    );
  }
}
