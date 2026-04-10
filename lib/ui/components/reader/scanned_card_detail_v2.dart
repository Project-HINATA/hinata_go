import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_go/context_extensions.dart';

import '../../../models/card/aic.dart';
import '../../../models/card/banapass.dart';
import '../../../models/card/card.dart';
import '../../../models/card/felica.dart';
import '../../../models/card/iso15693.dart';
import '../../../models/card/iso14443a.dart';
import '../../../services/notification_service.dart';

class ScannedCardDetailV2 extends ConsumerWidget {
  final ICCard card;
  final String? source;
  final bool showHeader;
  final bool showCloseButtonSpace;

  const ScannedCardDetailV2({
    required this.card,
    this.source,
    this.showHeader = true,
    this.showCloseButtonSpace = false,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader)
            _CardDetailHeader(
              logo: _buildLogo(context, colorScheme),
              name: card.name,
              source: source,
              showCloseButtonSpace: showCloseButtonSpace,
            ),
          _TechnicalFieldsSection(children: _buildTechnicalFields()),
        ],
      ),
    );
  }

  Widget _buildLogo(BuildContext context, ColorScheme colorScheme) {
    if (card.logoPath != null) {
      return Container(
        width: 40,
        height: 28,
        alignment: Alignment.centerLeft,
        child: SvgPicture.asset(
          card.logoPath!,
          fit: BoxFit.contain,
          colorFilter: ColorFilter.mode(colorScheme.primary, BlendMode.srcIn),
          placeholderBuilder: (context) => Icon(
            Icons.credit_card_rounded,
            color: colorScheme.primary,
            size: 24,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.credit_card_rounded,
        size: 20,
        color: colorScheme.primary,
      ),
    );
  }

  List<Widget> _buildTechnicalFields() {
    return _buildCardDetailFields(card)
        .map(
          (field) => _NativeInfoRow(
            label: field.label,
            value: field.value,
            groupInFours: field.groupInFours,
          ),
        )
        .toList();
  }
}

class _CardDetailField {
  const _CardDetailField({
    required this.label,
    required this.value,
    this.groupInFours = false,
  });

  final String label;
  final String value;
  final bool groupInFours;
}

class _CardFieldDefinition<T> {
  const _CardFieldDefinition({
    required this.label,
    required this.extractor,
    this.groupInFours = false,
  });

  final String label;
  final String? Function(T card) extractor;
  final bool groupInFours;
}

List<_CardDetailField> _buildCardDetailFields(ICCard card) {
  final fields = [
    ..._extractFields<HasAccessCode>(card, _accessCodeFieldDefinitions),
    ..._extractFields<Aic>(card, _aicFieldDefinitions),
    ..._extractFields<Banapass>(card, _banapassFieldDefinitions),
    ..._extractFields<Felica>(card, _felicaPrimaryFieldDefinitions),
    ..._extractFields<Iso14443>(card, _iso14443FieldDefinitions),
    ..._extractFields<Iso15693>(card, _iso15693FieldDefinitions),
    ..._extractFields<HasEPass>(card, _epassFieldDefinitions),
    ..._extractFields<Felica>(card, _felicaSecondaryFieldDefinitions),
  ];

  if (fields.isNotEmpty) {
    return fields;
  }

  return [
    _CardDetailField(
      label: 'ID',
      value: card.idString.toUpperCase(),
      groupInFours: true,
    ),
  ];
}

List<_CardDetailField> _extractFields<T>(
  Object card,
  List<_CardFieldDefinition<T>> definitions,
) {
  if (card is! T) {
    return const [];
  }

  final typedCard = card as T;

  return definitions
      .map(
        (definition) => _buildCardDetailField(
          label: definition.label,
          value: definition.extractor(typedCard),
          groupInFours: definition.groupInFours,
        ),
      )
      .whereType<_CardDetailField>()
      .toList();
}

_CardDetailField? _buildCardDetailField({
  required String label,
  required String? value,
  bool groupInFours = false,
}) {
  if (value == null || value.isEmpty) {
    return null;
  }

  return _CardDetailField(
    label: label,
    value: value,
    groupInFours: groupInFours,
  );
}

const List<_CardFieldDefinition<HasAccessCode>> _accessCodeFieldDefinitions = [
  _CardFieldDefinition(
    label: 'Access Code',
    extractor: _accessCodeValue,
    groupInFours: true,
  ),
];

const List<_CardFieldDefinition<Aic>> _aicFieldDefinitions = [
  _CardFieldDefinition(label: 'Manufacturer', extractor: _aicManufacturer),
];

const List<_CardFieldDefinition<Banapass>> _banapassFieldDefinitions = [
  _CardFieldDefinition(label: 'Block 1', extractor: _banapassFallbackBlock1),
];

const List<_CardFieldDefinition<Felica>> _felicaPrimaryFieldDefinitions = [
  _CardFieldDefinition(label: 'IDm', extractor: _felicaIdm, groupInFours: true),
];

const List<_CardFieldDefinition<HasEPass>> _epassFieldDefinitions = [
  _CardFieldDefinition(
    label: 'EPass',
    extractor: _epassValue,
    groupInFours: true,
  ),
];

const List<_CardFieldDefinition<Felica>> _felicaSecondaryFieldDefinitions = [
  _CardFieldDefinition(label: 'PMm', extractor: _felicaPmm, groupInFours: true),
  _CardFieldDefinition(label: 'System Code', extractor: _felicaSystemCode),
];

const List<_CardFieldDefinition<Iso14443>> _iso14443FieldDefinitions = [
  _CardFieldDefinition(
    label: 'UID',
    extractor: _iso14443Uid,
    groupInFours: true,
  ),
  _CardFieldDefinition(label: 'SAK', extractor: _iso14443Sak),
  _CardFieldDefinition(label: 'ATQA', extractor: _iso14443Atqa),
];

const List<_CardFieldDefinition<Iso15693>> _iso15693FieldDefinitions = [
  _CardFieldDefinition(
    label: 'UID',
    extractor: _iso15693Uid,
    groupInFours: true,
  ),
];

String _upperHex(String value) => value.toUpperCase();

String? _accessCodeValue(HasAccessCode card) => card.accessCodeString;
String? _aicManufacturer(Aic card) => card.manufacturer;
String? _banapassFallbackBlock1(Banapass card) =>
    card.accessCodeString == null ? card.block1Hex : null;
String? _felicaIdm(Felica card) => _upperHex(card.idString);
String? _epassValue(HasEPass card) => card.epass;
String? _felicaPmm(Felica card) => _upperHex(card.pmmString);
String? _felicaSystemCode(Felica card) => card.systemCodeDisplay;
String? _iso14443Uid(Iso14443 card) => _upperHex(card.idString);
String? _iso14443Sak(Iso14443 card) => card.sakDisplay;
String? _iso14443Atqa(Iso14443 card) => card.atqaDisplay;
String? _iso15693Uid(Iso15693 card) => _upperHex(card.idString);

class _CardDetailHeader extends StatelessWidget {
  const _CardDetailHeader({
    required this.logo,
    required this.name,
    required this.source,
    required this.showCloseButtonSpace,
  });

  final Widget logo;
  final String name;
  final String? source;
  final bool showCloseButtonSpace;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      color: colorScheme.primaryContainer.withValues(alpha: 0.2),
      child: Row(
        children: [
          logo,
          const SizedBox(width: 12),
          Expanded(
            child: _CardTitleBlock(name: name, source: source),
          ),
          if (showCloseButtonSpace) const SizedBox(width: 32),
        ],
      ),
    );
  }
}

class _CardTitleBlock extends StatelessWidget {
  const _CardTitleBlock({required this.name, required this.source});

  final String name;
  final String? source;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: context.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        if (source != null) ...[
          const SizedBox(height: 2),
          _SourceBadge(source: source!),
        ],
      ],
    );
  }
}

class _TechnicalFieldsSection extends StatelessWidget {
  const _TechnicalFieldsSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  final String source;
  const _SourceBadge({required this.source});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        source.toUpperCase(),
        style: context.textTheme.labelSmall?.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
          color: colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _NativeInfoRow extends ConsumerWidget {
  final String label;
  final String value;
  final bool groupInFours;

  const _NativeInfoRow({
    required this.label,
    required this.value,
    this.groupInFours = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final formattedValue = groupInFours ? _groupIntoFours(value) : value;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: value));
          if (context.mounted) {
            ref
                .read(notificationServiceProvider)
                .showSuccess('$label copied to clipboard');
          }
        },
        splashColor: colorScheme.primary.withValues(alpha: 0.1),
        highlightColor: colorScheme.primary.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: SizedBox(
            width: double.infinity, // Ensure full width clickability
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Determine layout mode based on width and content length
                final bool isNarrow =
                    constraints.maxWidth < 360 || formattedValue.length > 24;

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: context.textTheme.labelLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        formattedValue,
                        style: context.textTheme.bodyLarge?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          color: colorScheme.onSurface,
                          height: 1.2,
                        ),
                      ),
                    ],
                  );
                } else {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 120, // Constant width for label alignment
                        child: Text(
                          label,
                          style: context.textTheme.labelLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          formattedValue,
                          style: context.textTheme.bodyLarge?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: colorScheme.onSurface,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  );
                }
              },
            ),
          ),
        ),
      ),
    );
  }

  String _groupIntoFours(String input) {
    return input.replaceAllMapped(RegExp(r'.{1,4}'), (match) {
      return '${match.group(0)} ';
    }).trim();
  }
}
