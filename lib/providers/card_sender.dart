import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../models/card/card.dart';
import '../models/remote_instance.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import 'app_state_provider.dart';

class CardSenderState {
  final bool isSending;
  final String?
  triggerId; // Unique ID of the button/item that triggered the send

  CardSenderState({this.isSending = false, this.triggerId});

  CardSenderState copyWith({bool? isSending, String? triggerId}) {
    return CardSenderState(
      isSending: isSending ?? this.isSending,
      triggerId: triggerId ?? (isSending == false ? null : this.triggerId),
    );
  }
}

final cardSenderProvider = NotifierProvider<CardSender, CardSenderState>(() {
  return CardSender();
});

class CardSender extends Notifier<CardSenderState> {
  @override
  CardSenderState build() {
    return CardSenderState();
  }

  Future<bool> sendCard(
    ICCard card, {
    RemoteInstance? targetInstance,
    String? triggerId,
  }) async {
    if (state.isSending) return false;

    final activeInstance = targetInstance ?? ref.read(activeInstanceProvider);
    final notificationService = ref.read(notificationServiceProvider);
    final apiService = ref.read(apiServiceProvider);

    if (activeInstance == null) {
      notificationService.showError('No active instance selected.');
      return false;
    }

    state = state.copyWith(isSending: true, triggerId: triggerId);
    try {
      notificationService.showInfo('Sending to ${activeInstance.name}...');

      final success = await apiService.sendCardData(
        instance: activeInstance,
        type: card.type ?? 'unknown',
        value: card.value ?? '',
      );

      if (success) {
        notificationService.showSuccess(
          'Success: Sent to ${activeInstance.name}',
        );
      } else {
        notificationService.showError(
          'Failed: Could not send to ${activeInstance.name}',
        );
      }
      return success;
    } finally {
      state = state.copyWith(isSending: false, triggerId: null);
    }
  }
}
