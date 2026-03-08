import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/constants.dart';
import 'app_update_state.dart';

final appUpdateProvider = NotifierProvider<AppUpdateNotifier, AppUpdateState>(
  () {
    return AppUpdateNotifier();
  },
);

class AppUpdateNotifier extends Notifier<AppUpdateState> {
  @override
  AppUpdateState build() {
    _init();
    return const AppUpdateState();
  }

  Future<void> _init() async {
    final packageInfo = await PackageInfo.fromPlatform();
    state = state.copyWith(currentVersion: packageInfo.version);
    await checkUpdate();
  }

  Future<void> checkUpdate() async {
    if (state.isChecking) return;
    state = state.copyWith(isChecking: true);

    try {
      final response = await http.get(Uri.parse(AppConstants.appReleaseUrl));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String tagName = data['tag_name'] as String;
        final String? htmlUrl = data['html_url'] as String?;
        final String? body = data['body'] as String?;

        bool hasUpdate = false;
        final currentVer = state.currentVersion.replaceAll('v', '');
        final latestVer = tagName.replaceAll('v', '');

        if (currentVer != 'Unknown') {
          final currentParts = currentVer
              .split('.')
              .map((e) => int.tryParse(e) ?? 0)
              .toList();
          final latestParts = latestVer
              .split('.')
              .map((e) => int.tryParse(e) ?? 0)
              .toList();

          for (int i = 0; i < 3; i++) {
            final c = i < currentParts.length ? currentParts[i] : 0;
            final l = i < latestParts.length ? latestParts[i] : 0;
            if (l > c) {
              hasUpdate = true;
              break;
            } else if (l < c) {
              break;
            }
          }
        }

        state = state.copyWith(
          isChecking: false,
          hasUpdate: hasUpdate,
          latestVersion: tagName,
          downloadUrl: htmlUrl,
          releaseNotes: body,
        );
      } else {
        state = state.copyWith(isChecking: false, hasUpdate: false);
      }
    } catch (e) {
      state = state.copyWith(isChecking: false);
    }
  }
}
