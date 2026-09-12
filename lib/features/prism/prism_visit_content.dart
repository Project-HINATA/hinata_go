import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:hinata_go/l10n/l10n.dart';
import 'package:hinata_go/features/prism/providers/prism_visit_provider.dart';
import 'package:hinata_go/features/prism/services/prism_api.dart';
import 'package:hinata_go/features/prism/prism_machine_content.dart';

class PrismDeviceControls extends HookConsumerWidget {
  const PrismDeviceControls({
    required this.machine,
    this.cardBusy = false,
    super.key,
  });
  final PrismMachine machine;
  final bool cardBusy;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visit = ref.watch(prismVisitProvider);
    final controller = ref.read(prismVisitProvider.notifier);
    final consent = useState(false);
    final l = context.l10n;
    final theme = Theme.of(context);
    final busy = visit.busy || cardBusy;
    final heading = theme.textTheme.headlineSmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (visit.gate == 'loading')
          PrismAction(
            label: l.prismRefresh,
            onPressed: busy ? null : controller.refresh,
            secondary: true,
          ),
        if (visit.gate == 'qq') ...[
          Text(l.prismBindQQ, textAlign: TextAlign.center, style: heading),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 18,
              children: [
                Text(l.prismSendBot),
                if (visit.binding != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          'prism.bind ${visit.binding!['code']}',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontSize: 20,
                            fontFamily: 'monospace',
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: l.prismCopy,
                        onPressed: () => Clipboard.setData(
                          ClipboardData(
                            text: 'prism.bind ${visit.binding!['code']}',
                          ),
                        ),
                        icon: const Icon(Icons.content_copy, size: 20),
                      ),
                    ],
                  ),
                  Text(
                    '${l.prismExpires} ${prismTime(visit.binding!['expiresAt'])}',
                    style: theme.textTheme.bodySmall,
                  ),
                ] else if (visit.error != null)
                  PrismAction(
                    label: l.prismRefresh,
                    onPressed: controller.bindQQ,
                  )
                else
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        ],
        if (visit.gate == 'entry') ...[
          Text(l.prismEnter, textAlign: TextAlign.center, style: heading),
          const SizedBox(height: 24),
          PrismPricing(info: visit.shop!),
          const SizedBox(height: 24),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: consent.value,
            onChanged: busy ? null : (v) => consent.value = v ?? false,
            title: Text(l.prismConsent, style: theme.textTheme.bodyMedium),
          ),
          const SizedBox(height: 16),
          if (!machine.has('door'))
            PrismAction(
              label: l.prismEnter,
              busy: visit.busy,
              onPressed: busy || !consent.value ? null : controller.enter,
            ),
        ],
        if (machine.has('door') && ['ready', 'entry'].contains(visit.gate)) ...[
          if (visit.password != null) ...[
            Text(
              l.prismDoorPassword,
              textAlign: TextAlign.center,
              style: heading,
            ),
            const SizedBox(height: 16),
            Card.filled(
              margin: EdgeInsets.zero,
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SelectableText(
                      visit.password!['temporaryPassword'] as String,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        letterSpacing: 4,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${l.prismExpires} ${prismTime(visit.password!['expiresAt'])}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l.prismEnterPassword,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
          ],
          PrismAction(
            label: visit.password != null
                ? l.prismRefreshPassword
                : visit.gate == 'entry'
                ? l.prismEnterAndOpen
                : l.prismGetPassword,
            busy: visit.busy,
            icon: const Icon(Icons.door_front_door_outlined, size: 22),
            onPressed: busy || (visit.gate == 'entry' && !consent.value)
                ? null
                : () => controller.device('door.open', consent: consent.value),
          ),
          if (machine.has('card') || machine.has('power'))
            const SizedBox(height: 28),
        ],
        if (visit.gate == 'ready' &&
            visit.power != 'off' &&
            visit.mahjong != null)
          PrismMahjongTable(table: visit.mahjong!, busy: busy),
        if (visit.gate == 'ready' && visit.power == 'off') ...[
          Text(l.prismPoweredOff, textAlign: TextAlign.center, style: heading),
          const SizedBox(height: 28),
          PrismAction(
            label: l.prismPowerOn,
            busy: visit.busy || visit.notice == '已发送开机请求',
            icon: const Icon(Icons.power_settings_new, size: 22),
            onPressed: busy || visit.notice == '已发送开机请求'
                ? null
                : () => controller.device('power.on'),
          ),
        ],
      ],
    );
  }
}

class PrismMahjongTable extends ConsumerWidget {
  const PrismMahjongTable({required this.table, required this.busy, super.key});
  final Map<String, dynamic> table;
  final bool busy;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final seats = (table['seats'] as List).cast<Map<String, dynamic>>();
    final mine = seats.any((s) => s['mine'] == true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        Text(
          l.prismMahjongTable,
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        Text(
          "${seats.length} / ${table['capacity']}",
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        Text(
          seats.any((s) => s['playing'] == true)
              ? l.prismMahjongPlaying
              : l.prismMahjongWaiting,
          textAlign: TextAlign.center,
        ),
        if (seats.isNotEmpty)
          Card.filled(
            child: Column(
              children: [
                for (final seat in seats)
                  ListTile(
                    title: Text(seat['name'] as String),
                    trailing: seat['mine'] == true
                        ? Text(l.prismMahjongYou)
                        : null,
                  ),
              ],
            ),
          ),
        PrismAction(
          label: mine ? l.prismMahjongLeave : l.prismMahjongJoin,
          busy: busy,
          onPressed:
              busy || (!mine && seats.length >= (table['capacity'] as int))
              ? null
              : () => ref
                    .read(prismVisitProvider.notifier)
                    .device(mine ? 'mahjong.leave' : 'mahjong.join'),
        ),
      ],
    );
  }
}

class PrismDeviceFooter extends ConsumerWidget {
  const PrismDeviceFooter({
    required this.machine,
    required this.cardBusy,
    super.key,
  });
  final PrismMachine machine;
  final bool cardBusy;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visit = ref.watch(prismVisitProvider);
    if (visit.gate != 'ready' ||
        visit.power == 'off' ||
        !machine.has('coin') ||
        machine.coinAfterSwipe) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: PrismAction(
        label: visit.coinUsed
            ? context.l10n.prismCoinSent
            : context.l10n.prismCoin,
        busy: visit.busy,
        icon: Icon(visit.coinUsed ? Icons.check : Icons.toll, size: 22),
        onPressed: cardBusy || visit.busy || visit.coinUsed
            ? null
            : () => ref.read(prismVisitProvider.notifier).device('coin'),
      ),
    );
  }
}

class PrismAccountMenu extends ConsumerWidget {
  const PrismAccountMenu({
    required this.onLogout,
    this.busy = false,
    super.key,
  });
  final VoidCallback onLogout;
  final bool busy;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visit = ref.watch(prismVisitProvider);
    final user = visit.user;
    if (user == null) return const SizedBox.shrink();
    final l = context.l10n;
    final labels = [l.prismBill, l.prismRedeem, l.prismHistory, l.prismWallet];
    final colors = Theme.of(context).colorScheme;
    final name =
        (user['displayName'] ?? user['username'] ?? user['id']) as String;
    return FilledButton.tonal(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        backgroundColor: colors.surfaceContainerHigh,
        foregroundColor: colors.onSurface,
      ),
      onPressed: busy || visit.busy
          ? null
          : () async {
              final section = await showModalBottomSheet<int>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                showDragHandle: true,
                builder: (sheetContext) => SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: Theme.of(
                                  sheetContext,
                                ).textTheme.titleLarge,
                              ),
                            ),
                            const CloseButton(),
                          ],
                        ),
                        if (visit.billing) ...[
                          const SizedBox(height: 8),
                          for (var index = 0; index < labels.length; index++)
                            ListTile(
                              title: Text(labels[index]),
                              onTap: () => Navigator.pop(sheetContext, index),
                            ),
                          const Divider(),
                        ],
                        ListTile(
                          title: Text(l.prismSignOutAction),
                          onTap: () => Navigator.pop(sheetContext, 4),
                        ),
                      ],
                    ),
                  ),
                ),
              );
              if (!context.mounted || section == null) return;
              if (section == 4) {
                onLogout();
                return;
              }
              final container = ProviderScope.containerOf(context);
              await showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                showDragHandle: true,
                builder: (_) => UncontrolledProviderScope(
                  container: container,
                  child: PrismAccountSheet(section: section),
                ),
              );
            },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more, size: 20),
        ],
      ),
    );
  }
}

class PrismAccountSheet extends HookConsumerWidget {
  const PrismAccountSheet({required this.section, super.key});
  final int section;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visit = ref.watch(prismVisitProvider);
    final controller = ref.read(prismVisitProvider.notifier);
    final code = useTextEditingController();
    useListenable(code);
    final done = useState(false);
    useEffect(() {
      Future.microtask(() async {
        await controller.refresh();
        if (section == 0 && ref.read(prismVisitProvider).active) {
          await controller.previewCheckout();
        }
      });
      return null;
    }, const []);
    final l = context.l10n;
    final labels = [l.prismBill, l.prismRedeem, l.prismHistory, l.prismWallet];
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final preview = visit.preview;
    final canCheckout = section == 0 && !done.value && preview != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 12, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      labels[section],
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  const CloseButton(),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24, 0, 24, canCheckout ? 0 : 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 16,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (visit.error != null)
                      Semantics(
                        liveRegion: true,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colors.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            prismError(visit.error!),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onErrorContainer,
                            ),
                          ),
                        ),
                      ),
                    if (visit.busy && preview == null)
                      const Center(child: CircularProgressIndicator()),
                    if (section == 0) ...[
                      if (done.value)
                        Text(l.prismCheckedOut)
                      else if (preview != null) ...[
                        Text(
                          '${prismDate(visit.summary?['activeSession']?['startedAt'], locale)} – ${l.prismNow}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        Column(
                          children: [
                            for (final item in [
                              ...?preview['chargeItems'] as List?,
                              ...?preview['adjustments'] as List?,
                            ])
                              PrismReceiptRow(
                                item['label'] as String,
                                (item['amount'] as num).toStringAsFixed(2),
                              ),
                          ],
                        ),
                      ] else if (!visit.busy && visit.error == null)
                        Text(l.prismNoBill),
                    ],
                    if (section == 1)
                      if (done.value)
                        Text(l.prismRedeemed)
                      else ...[
                        TextField(
                          controller: code,
                          autocorrect: false,
                          textCapitalization: TextCapitalization.none,
                          decoration: InputDecoration(
                            labelText: l.prismRedeemCode,
                            filled: true,
                            fillColor: colors.surfaceContainerHighest,
                            border: const UnderlineInputBorder(
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        PrismAction(
                          label: l.prismRedeem,
                          busy: visit.busy,
                          onPressed: visit.busy || code.text.trim().isEmpty
                              ? null
                              : () async {
                                  if (code.text.trim().isEmpty) return;
                                  await controller.redeem(code.text.trim());
                                  if (ref.read(prismVisitProvider).error ==
                                      null) {
                                    done.value = true;
                                  }
                                },
                        ),
                      ],
                    if (section == 2) ...[
                      if (visit.history.isEmpty && !visit.busy)
                        Text(l.prismNoRecords),
                      for (final item in visit.history)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            prismDate(item['startedAt'], locale),
                            style: theme.textTheme.bodyLarge,
                          ),
                          subtitle: Text(
                            item['endedAt'] == null
                                ? l.prismBilling
                                : prismDate(item['endedAt'], locale),
                          ),
                          trailing: Text(
                            (item['total'] as num?)?.toStringAsFixed(2) ?? '—',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                    ],
                    if (section == 3) ...[
                      if (visit.assets.isEmpty && !visit.busy)
                        Text(l.prismNoAssets),
                      for (final asset in visit.assets)
                        Card.filled(
                          margin: EdgeInsets.zero,
                          color: colors.secondaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    (asset['assetName'] ?? asset['assetCode'])
                                        as String,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: colors.onSecondaryContainer,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    '${asset['quantity']}',
                                    textAlign: TextAlign.end,
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(
                                          color: colors.onSecondaryContainer,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            if (canCheckout) ...[
              const Divider(height: 1),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l.prismTotal,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            (preview['settlementPreview']['total'] as num)
                                .toStringAsFixed(2),
                            textAlign: TextAlign.end,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    PrismAction(
                      label: l.prismConfirmCheckout,
                      busy: visit.busy,
                      onPressed: visit.busy
                          ? null
                          : () async {
                              await controller.checkout();
                              if (ref.read(prismVisitProvider).error == null) {
                                done.value = true;
                              }
                            },
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class PrismPricing extends StatelessWidget {
  const PrismPricing({required this.info, super.key});
  final Map<String, dynamic> info;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final plans = (info['entryPricing'] as List? ?? [])
        .where(
          (plan) => plan['enabled'] != false && plan['status'] != 'archived',
        )
        .toList();
    final weekday = DateFormat.E(Localizations.localeOf(context).languageCode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        for (final plan in plans)
          Card.filled(
            margin: EdgeInsets.zero,
            color: theme.colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    plan['name'] as String,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (plan['kind'] == 'charge.fixed')
                    Text('${l.prismPerEntry} · ${plan['provider']['amount']}')
                  else ...[
                    Text(
                      l.prismRuleOrder,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    for (final rule
                        in (plan['provider']['rules'] as List? ?? []).where(
                          (rule) => rule['status'] != 'archived',
                        )) ...[
                      const Divider(height: 32),
                      Text(
                        rule['label'] as String,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        rule['timeRange'] == null
                            ? l.prismContinuousPeriod
                            : rule['timeRange']['start'] ==
                                  rule['timeRange']['end']
                            ? l.prismAllDay
                            : '${rule['timeRange']['start']}–${(rule['timeRange']['start'] as String).compareTo(rule['timeRange']['end'] as String) > 0 ? l.prismNextDay : ''}${rule['timeRange']['end']}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if ((rule['weekdays'] as List?)?.isNotEmpty == true)
                        Text(
                          (rule['weekdays'] as List)
                              .map(
                                (day) => weekday.format(
                                  DateTime.utc(2026, 1, 4 + (day as int)),
                                ),
                              )
                              .join(' · '),
                          style: theme.textTheme.bodySmall,
                        ),
                      if ((rule['specificDates'] as List?)?.isNotEmpty == true)
                        Text(
                          (rule['specificDates'] as List).join(' · '),
                          style: theme.textTheme.bodySmall,
                        ),
                      if (rule['displayDateTimeRange'] != null)
                        Text(
                          '${rule['displayDateTimeRange']['start']} – ${rule['displayDateTimeRange']['end']}',
                          style: theme.textTheme.bodySmall,
                        ),
                      const SizedBox(height: 4),
                      Text(
                        rule['pricing'] != null
                            ? '${rule['pricing']['unitPrice']} / ${rule['pricing']['unitMinutes']} ${l.prismMinutes}'
                            : '${l.prismCombinedCap} ${rule['priceCap']}',
                        style: theme.textTheme.bodyLarge,
                      ),
                      if (rule['pricing'] != null) ...[
                        if ((rule['pricing']['priceCap'] as num) <
                            9007199254740991)
                          Text(
                            '${l.prismSlotCap} ${rule['pricing']['priceCap']}',
                            style: theme.textTheme.bodySmall,
                          ),
                        if ((rule['pricing']['roundGraceMinutes'] as num) > 0)
                          Text(
                            '${l.prismUnitGrace} ${rule['pricing']['roundGraceMinutes']} ${l.prismMinutes}',
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ],
                  ],
                ],
              ),
            ),
          ),
        if (plans.any((plan) => plan['kind'] != 'charge.fixed'))
          Text(
            l.prismPricingExplanation,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class PrismReceiptRow extends StatelessWidget {
  const PrismReceiptRow(this.label, this.value, {super.key});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    ),
  );
}

String prismTime(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  return date == null
      ? value?.toString() ?? ''
      : DateFormat.Hms().format(date.toLocal());
}

String prismDate(Object? value, [String? locale]) => value is String
    ? DateFormat.yMd(locale).add_Hm().format(DateTime.parse(value).toLocal())
    : '';
String prismError(Object error) =>
    error is PlatformException ? error.message ?? error.code : error.toString();
