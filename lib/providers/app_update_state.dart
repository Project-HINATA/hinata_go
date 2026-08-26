import '../utils/constants.dart';

class AppUpdateState {
  final String currentVersion;
  final String commitHash;
  final String latestVersion;
  final bool isUpdateSupported;
  final bool hasUpdate;
  final bool isChecking;
  final String? downloadUrl;
  final String? releaseNotes;

  const AppUpdateState({
    this.currentVersion = 'Unknown',
    this.commitHash = '',
    this.latestVersion = 'Unknown',
    this.isUpdateSupported = false,
    this.hasUpdate = false,
    this.isChecking = false,
    this.downloadUrl,
    this.releaseNotes,
  });

  String get versionDisplay {
    final hash = commitHash.isNotEmpty ? commitHash : AppConstants.gitCommitHash;
    final shortHash = hash.length > 7 ? hash.substring(0, 7) : hash;
    if (shortHash.isNotEmpty) {
      return 'HINATA Go v$currentVersion ($shortHash)';
    }
    return 'HINATA Go v$currentVersion';
  }

  AppUpdateState copyWith({
    String? currentVersion,
    String? commitHash,
    String? latestVersion,
    bool? isUpdateSupported,
    bool? hasUpdate,
    bool? isChecking,
    String? downloadUrl,
    String? releaseNotes,
  }) {
    return AppUpdateState(
      currentVersion: currentVersion ?? this.currentVersion,
      commitHash: commitHash ?? this.commitHash,
      latestVersion: latestVersion ?? this.latestVersion,
      isUpdateSupported: isUpdateSupported ?? this.isUpdateSupported,
      hasUpdate: hasUpdate ?? this.hasUpdate,
      isChecking: isChecking ?? this.isChecking,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      releaseNotes: releaseNotes ?? this.releaseNotes,
    );
  }
}
