import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/card/card.dart';
import '../../models/card/aic.dart';
import '../../models/card/aime.dart';
import '../../models/card/banapass.dart';
import '../../models/card/felica.dart';
import '../../models/card/iso14443a.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/api_service.dart';
import '../../utils/snackbar_utils.dart';

class CardDetailPage extends ConsumerStatefulWidget {
  final ICCard card;

  const CardDetailPage({super.key, required this.card});

  @override
  ConsumerState<CardDetailPage> createState() => _CardDetailPageState();
}

class _CardDetailPageState extends ConsumerState<CardDetailPage> {
  bool _isSending = false;

  Future<void> _sendCard() async {
    if (_isSending) return;

    final enableSecondaryConfirmation = ref
        .read(settingsProvider)
        .enableSecondaryConfirmation;
    if (enableSecondaryConfirmation) {
      final shouldSend = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Send'),
          content: Text(
            'Send this ${widget.card.name} card to the active instance?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Send'),
            ),
          ],
        ),
      );
      if (shouldSend != true) return;
    }

    setState(() => _isSending = true);

    final activeInstance = ref.read(activeInstanceProvider);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    if (activeInstance == null) {
      if (mounted) {
        scaffoldMessenger.showQuickSnackBar(
          const SnackBar(content: Text('No active instance selected.')),
        );
      }
    } else {
      if (mounted) {
        scaffoldMessenger.showQuickSnackBar(
          SnackBar(content: Text('Sending to ${activeInstance.name}...')),
        );
      }

      final apiService = ref.read(apiServiceProvider);
      final success = await apiService.sendCardData(
        instance: activeInstance,
        type: widget.card.type ?? 'unknown',
        value: widget.card.value ?? '',
      );

      if (mounted) {
        if (success) {
          scaffoldMessenger.showQuickSnackBar(
            const SnackBar(content: Text('Success: Sent.')),
          );
        } else {
          scaffoldMessenger.showQuickSnackBar(
            const SnackBar(content: Text('Failed to send.')),
          );
        }
      }
    }

    if (mounted) setState(() => _isSending = false);
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;

    return Scaffold(
      appBar: AppBar(
        title: Text('${card.name} Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: card.value ?? ''));
              ScaffoldMessenger.of(context).showQuickSnackBar(
                const SnackBar(content: Text('Value copied to clipboard')),
              );
            },
            tooltip: 'Copy Value',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HeaderCard(card: card),
                  const SizedBox(height: 24),
                  ..._buildCardSections(card),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
          _BottomAction(onSend: _sendCard, isSending: _isSending),
        ],
      ),
    );
  }

  List<Widget> _buildCardSections(ICCard card) {
    final List<Widget> sections = [];

    if (card is Aic) {
      sections.add(
        _InfoSection(
          title: 'Amusement IC Information',
          children: [
            _InfoRow(label: 'Access Code', value: card.accessCodeString),
            _InfoRow(label: 'Manufacturer', value: card.manufacturer),
          ],
        ),
      );
    }

    if (card is Aime && card is! Aic) {
      sections.add(
        _InfoSection(
          title: 'Aime Information',
          children: [
            _InfoRow(label: 'Access Code', value: card.accessCodeString),
          ],
        ),
      );
    }

    if (card is Felica) {
      sections.add(
        _InfoSection(
          title: 'FeliCa Technical Details',
          children: [
            _InfoRow(label: 'IDm', value: card.idString),
            _InfoRow(label: 'PMm', value: card.pmmString),
            _InfoRow(
              label: 'System Code',
              value: card.systemCode
                  .map((e) => e.toRadixString(16).padLeft(4, '0').toUpperCase())
                  .join(', '),
            ),
          ],
        ),
      );
    }

    if (card is Banapass) {
      sections.add(
        _InfoSection(
          title: 'Banapassport Data',
          children: [
            _InfoRow(
              label: 'Block 1',
              value: card.value?.substring(0, 32) ?? '',
            ),
            if (card.block2 != null)
              _InfoRow(
                label: 'Block 2',
                value: card.value?.substring(32) ?? '',
              ),
          ],
        ),
      );
    }

    if (card is Iso14443) {
      sections.add(
        _InfoSection(
          title: 'ISO14443 Technical Details',
          children: [
            _InfoRow(label: 'UID', value: card.idString),
            _InfoRow(
              label: 'SAK',
              value:
                  '0x${card.sak.toRadixString(16).padLeft(2, '0').toUpperCase()}',
            ),
            _InfoRow(
              label: 'ATQA',
              value:
                  '0x${card.atqa.toRadixString(16).padLeft(4, '0').toUpperCase()}',
            ),
          ],
        ),
      );
    }

    if (card is! Felica && card is! Iso14443) {
      sections.add(
        _InfoSection(
          title: 'Technical Details',
          children: [
            _InfoRow(label: 'ID / Value', value: card.value ?? card.idString),
          ],
        ),
      );
    }

    return sections;
  }
}

class _InfoSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _InfoSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(children: children),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final ICCard card;

  const _HeaderCard({required this.card});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 4,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.onPrimaryContainer.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.credit_card,
                size: 48,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              card.name,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomAction extends StatelessWidget {
  final VoidCallback onSend;
  final bool isSending;

  const _BottomAction({required this.onSend, required this.isSending});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final padding = MediaQuery.of(context).padding;

    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: padding.bottom > 0 ? padding.bottom : 24,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: FilledButton.icon(
        onPressed: isSending ? null : onSend,
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: isSending
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.send),
        label: Text(isSending ? 'SENDING...' : 'SEND CARD TO INSTANCE'),
      ),
    );
  }
}
