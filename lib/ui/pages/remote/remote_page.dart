import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../app_layout.dart';

class RemotePage extends HookConsumerWidget {
  const RemotePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = context.appLayout;

    return Scaffold(
      appBar: layout.isLandscape
          ? null
          : AppBar(
              title: Text(context.l10n.remoteHub),
            ),
      body: SafeArea(
        top: layout.isLandscape,
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Center(
              child: Text(context.l10n.remoteHub),
            ),
          ),
        ),
      ),
    );
  }
}
