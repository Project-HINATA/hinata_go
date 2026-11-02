import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';

/// Marks data the card did not give up in full, such as when it left the
/// reader before every block or record was read.
class IncompleteReadBadge extends StatelessWidget {
  const IncompleteReadBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline_rounded, size: 16, color: colorScheme.error),
        const SizedBox(width: 4),
        Text(
          l10n.cardNotFullyRead,
          style: context.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.error,
          ),
        ),
      ],
    );
  }
}
