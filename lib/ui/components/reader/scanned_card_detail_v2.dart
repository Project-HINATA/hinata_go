import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hinata_go/context_extensions.dart';
import '../../../models/card/card.dart';
import '../../../models/card/aic.dart';
import '../../../models/card/aime.dart';
import '../../../models/card/felica.dart';
import '../../../models/card/iso14443a.dart';
import '../../../models/card/banapass.dart';
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
          _TechnicalFieldsSection(children: _buildTechnicalFields(card)),
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

  List<Widget> _buildTechnicalFields(ICCard card) {
    return switch (card) {
      final Aic aic => _buildAicFields(aic),
      final Aime aime => _buildAimeFields(aime),
      final Felica felica => _buildFelicaFields(felica),
      final Banapass banapass => _buildBanapassFields(banapass),
      final Iso14443 iso14443 => _buildIso14443Fields(iso14443),
      _ => [_NativeInfoRow(label: 'ID', value: card.idString.toUpperCase())],
    };
  }

  List<Widget> _buildAicFields(Aic card) {
    return [
      _NativeInfoRow(label: 'Access Code', value: card.accessCodeString),
      _NativeInfoRow(label: 'Manufacturer', value: card.manufacturer),
      _NativeInfoRow(label: 'IDm', value: card.idString.toUpperCase()),
      _NativeInfoRow(label: 'PMm', value: card.pmmString.toUpperCase()),
      _NativeInfoRow(
        label: 'System Code',
        value: _formatSystemCode(card.systemCode),
      ),
    ];
  }

  List<Widget> _buildAimeFields(Aime card) {
    return [
      _NativeInfoRow(label: 'Access Code', value: card.accessCodeString),
      _NativeInfoRow(label: 'UID', value: card.idString.toUpperCase()),
      _NativeInfoRow(label: 'SAK', value: _formatHexByte(card.sak)),
      _NativeInfoRow(label: 'ATQA', value: _formatHexWord(card.atqa)),
    ];
  }

  List<Widget> _buildFelicaFields(Felica card) {
    return [
      _NativeInfoRow(label: 'IDm', value: card.idString.toUpperCase()),
      _NativeInfoRow(label: 'PMm', value: card.pmmString.toUpperCase()),
      _NativeInfoRow(
        label: 'System Code',
        value: _formatSystemCode(card.systemCode),
      ),
    ];
  }

  List<Widget> _buildBanapassFields(Banapass card) {
    return [
      _NativeInfoRow(
        label: 'Block 1',
        value: card.value?.substring(0, 32) ?? '',
      ),
    ];
  }

  List<Widget> _buildIso14443Fields(Iso14443 card) {
    return [
      _NativeInfoRow(label: 'UID', value: card.idString.toUpperCase()),
      _NativeInfoRow(label: 'SAK', value: _formatHexByte(card.sak)),
      _NativeInfoRow(label: 'ATQA', value: _formatHexWord(card.atqa)),
    ];
  }

  String _formatSystemCode(List<int> systemCode) {
    return systemCode
        .map((e) => e.toRadixString(16).padLeft(4, '0').toUpperCase())
        .join(', ');
  }

  String _formatHexByte(int value) {
    return '0x${value.toRadixString(16).padLeft(2, '0').toUpperCase()}';
  }

  String _formatHexWord(int value) {
    return '0x${value.toRadixString(16).padLeft(4, '0').toUpperCase()}';
  }
}

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
  const _NativeInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;

    // Grouping for better legibility
    final formattedValue = value
        .replaceAllMapped(RegExp(r".{4}"), (match) => "${match.group(0)} ")
        .trim();

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
}
