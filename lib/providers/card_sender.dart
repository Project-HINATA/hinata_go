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
    final l10n = notificationService.l10n;

    if (activeInstance == null) {
      notificationService.showError(
        l10n?.noActiveInstanceSelected ?? 'No active instance selected.',
      );
      return false;
    }

    state = state.copyWith(isSending: true, triggerId: triggerId);
    try {
      notificationService.showInfo(
        l10n?.sendingToInstance(activeInstance.name) ??
            'Sending to ${activeInstance.name}...',
      );

      final result = await apiService.sendCardData(
        instance: activeInstance,
        card: card
      );

      if (result.success) {
        notificationService.showSuccess(
          l10n?.successSentToInstance(activeInstance.name) ??
              'Success: Sent to ${activeInstance.name}',
        );
      } else {
        notificationService.showError(
          (l10n?.failedSentToInstance(activeInstance.name) ??
              'Failed: Could not send to ${activeInstance.name}') + (result.errorMessage != null ? '\n${result.errorMessage}' : ''),
        );
      }
      return result.success;
    } finally {
      state = state.copyWith(isSending: false, triggerId: null);
    }
  }
}
