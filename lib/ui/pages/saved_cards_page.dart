import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/saved_card.dart';
import '../../providers/app_state_provider.dart';
import '../../services/api_service.dart';

class SavedCardsPage extends ConsumerStatefulWidget {
  const SavedCardsPage({super.key});

  @override
  ConsumerState<SavedCardsPage> createState() => _SavedCardsPageState();
}

class _SavedCardsPageState extends ConsumerState<SavedCardsPage> {
  bool _isProcessing = false;

  void _showAddCardDialog() {
    final nameController = TextEditingController();
    final valueController = TextEditingController();
    String selectedType = 'Manual';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Add Card Manually'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name / Description',
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: selectedType,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: ['Manual', 'NfcA', 'NfcF', 'QR'].map((type) {
                      return DropdownMenuItem(value: type, child: Text(type));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          selectedType = val;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: valueController,
                    decoration: const InputDecoration(
                      labelText: 'Card Value / UID',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    if (nameController.text.isNotEmpty &&
                        valueController.text.isNotEmpty) {
                      final newCard = SavedCard(
                        id: const Uuid().v4(),
                        name: nameController.text,
                        type: selectedType,
                        value: valueController.text,
                      );
                      ref.read(savedCardsProvider.notifier).addCard(newCard);
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _sendCardData(SavedCard card) async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
    });

    final activeInstance = ref.read(activeInstanceProvider);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    if (activeInstance == null) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text(
            'No active instance set. Please select one in Instances tab.',
          ),
        ),
      );
    } else {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Sending ${card.name} to ${activeInstance.name}...'),
        ),
      );

      final apiService = ref.read(apiServiceProvider);
      final success = await apiService.sendCardData(
        instance: activeInstance,
        type: card.type,
        value: card.value,
      );

      if (success) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Success: Data sent.')),
        );
      } else {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Failed: Could not send data.')),
        );
      }
    }

    if (mounted) {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final savedCards = ref.watch(savedCardsProvider);

    // Reverse to show newest first
    final reversedCards = savedCards.reversed.toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Saved Cards & History')),
      body: reversedCards.isEmpty
          ? const Center(child: Text('No saved cards yet.'))
          : ListView.builder(
              itemCount: reversedCards.length,
              itemBuilder: (context, index) {
                final card = reversedCards[index];
                return Dismissible(
                  key: ValueKey(card.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) {
                    ref.read(savedCardsProvider.notifier).removeCard(card.id);
                  },
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      child: Icon(
                        card.type.contains('Nfc') ? Icons.nfc : Icons.qr_code,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    title: Text(
                      card.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('${card.type} • ${card.value}'),
                    trailing: _isProcessing
                        ? const CircularProgressIndicator()
                        : IconButton(
                            icon: const Icon(Icons.send),
                            onPressed: () => _sendCardData(card),
                            tooltip: 'Send to active instance',
                          ),
                    onTap: () => _sendCardData(card),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddCardDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Card'),
      ),
    );
  }
}
