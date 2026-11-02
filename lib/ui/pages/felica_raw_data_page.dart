import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:hinata_go/context_extensions.dart';

import '../../core/engine/felica_dump_reader.dart';
import '../../l10n/l10n.dart';
import '../../models/card/felica.dart';
import '../../models/card/felica_dump.dart';
import '../../services/notification_service.dart';
import '../widgets/app_scaffold.dart';

/// The names of the Lite-S blocks, by address.
const _liteBlockNames = {
  0x0E: 'REG',
  0x80: 'RC',
  0x81: 'MAC',
  0x82: 'ID',
  0x83: 'D_ID',
  0x84: 'SER_C',
  0x85: 'SYS_C',
  0x86: 'CKV',
  0x87: 'CK',
  0x88: 'MC',
  0x90: 'WCNT',
  0x91: 'MAC_A',
  0x92: 'STATE',
  0xA0: 'CRC_CHECK',
};

String _hex(int value, int digits) =>
    value.toRadixString(16).padLeft(digits, '0').toUpperCase();

String _bytes(Uint8List bytes) => bytes.map((b) => _hex(b, 2)).join(' ');

/// The blocks saved with a FeliCa card, by service.
class FelicaRawDataPage extends ConsumerWidget {
  final Felica card;

  const FelicaRawDataPage({super.key, required this.card});

  String _blockLabel(int service, int number) {
    if (card.isLite && service == FelicaDumpReader.liteService) {
      return _liteBlockNames[number] ??
          (number <= 0x0D ? 'S_PAD$number' : _hex(number, 2));
    }
    return _hex(number, number > 0xFF ? 4 : 2);
  }

  /// The dump as text: the card's identity, then each service's blocks.
  String _dumpText(FelicaDump? dump) {
    final buffer = StringBuffer()
      ..writeln('IDm: ${card.idString.toUpperCase()}')
      ..writeln('PMm: ${card.pmmString.toUpperCase()}')
      ..writeln('System codes: ${card.systemCodeDisplay}')
      ..writeln('Complete: ${card.isFullyRead}');
    for (final MapEntry(key: service, value: blocks)
        in dump?.services.entries ??
            const <MapEntry<int, Map<int, Uint8List>>>[]) {
      buffer.writeln('Service ${_hex(service, 4)}');
      for (final MapEntry(key: number, value: data) in blocks.entries) {
        buffer.writeln('  ${_blockLabel(service, number)}: ${_bytes(data)}');
      }
    }
    return buffer.toString();
  }

  Future<void> _copy(WidgetRef ref, String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    ref.read(notificationServiceProvider).showSuccess(message);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dump = card.dump;
    final media = MediaQuery.of(context);

    return AppScaffold(
      title: l10n.rawData,
      actions: [
        AdaptiveAppBarAction(
          iosSymbol: 'doc.on.doc',
          icon: Icons.copy_all_outlined,
          label: l10n.rawDataCopyAll,
          onPressed: () => _copy(ref, _dumpText(dump), l10n.rawDataCopied),
        ),
      ],
      // Scrolls under the native iOS bar, padding itself below it, as the
      // card detail does.
      body: SafeArea(
        top: false,
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            20 + media.padding.top,
            20,
            20 + media.padding.bottom,
          ),
          children: [
            _Notice(
              text: card.isFullyRead
                  ? l10n.rawDataComplete
                  : l10n.cardReadIncomplete,
              warning: !card.isFullyRead,
            ),
            if (dump == null || dump.services.isEmpty)
              _Notice(text: l10n.rawDataNoBlocks)
            else
              for (final MapEntry(key: service, value: blocks)
                  in dump.services.entries)
                _ServiceSection(
                  service: service,
                  blocks: [
                    for (final MapEntry(key: number, value: data)
                        in blocks.entries)
                      _BlockRow(
                        label: _blockLabel(service, number),
                        data: data,
                        onCopy: () => _copy(
                          ref,
                          _bytes(data).replaceAll(' ', ''),
                          l10n.valueCopiedToClipboard,
                        ),
                      ),
                  ],
                ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;
  final bool warning;

  const _Notice({required this.text, this.warning = false});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final foreground = warning
        ? colorScheme.onErrorContainer
        : colorScheme.onSecondaryContainer;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warning
            ? colorScheme.errorContainer.withValues(alpha: 0.55)
            : colorScheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            warning ? Icons.warning_amber_rounded : Icons.info_outline,
            size: 20,
            color: foreground,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: context.textTheme.bodyMedium?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceSection extends StatelessWidget {
  final int service;
  final List<Widget> blocks;

  const _ServiceSection({required this.service, required this.blocks});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
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
      // The rows' ink needs a Material above the container's fill.
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.rawDataService(_hex(service, 4)),
                      style: context.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    blocks.isEmpty
                        ? l10n.rawDataNoServiceBlocks
                        : l10n.rawDataBlockCount(blocks.length),
                    style: context.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            ...blocks,
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _BlockRow extends StatelessWidget {
  final String label;
  final Uint8List data;
  final VoidCallback onCopy;

  const _BlockRow({
    required this.label,
    required this.data,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final mono = context.textTheme.bodyMedium?.copyWith(
      fontFamily: 'monospace',
      height: 1.3,
    );
    // Eight bytes to a line keeps a block readable on a phone.
    final halves = [data.sublist(0, 8), data.sublist(8)];
    return InkWell(
      onTap: onCopy,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Narrow enough to leave eight bytes a line, with a label font
            // small enough for the longest Lite-S name, CRC_CHECK.
            SizedBox(
              width: 84,
              child: Text(
                label,
                style: mono?.copyWith(
                  fontSize: context.textTheme.labelMedium?.fontSize,
                  height: 1.6,
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Text(
                halves.map(_bytes).join('\n'),
                style: mono?.copyWith(color: colorScheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
