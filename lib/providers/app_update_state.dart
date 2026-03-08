class AppUpdateState {
  final String currentVersion;
  final String latestVersion;
  final bool hasUpdate;
  final bool isChecking;
  final String? downloadUrl;
  final String? releaseNotes;

  const AppUpdateState({
    this.currentVersion = 'Unknown',
    this.latestVersion = 'Unknown',
    this.hasUpdate = false,
    this.isChecking = false,
    this.downloadUrl,
    this.releaseNotes,
  });

  AppUpdateState copyWith({
    String? currentVersion,
    String? latestVersion,
    bool? hasUpdate,
    bool? isChecking,
    String? downloadUrl,
    String? releaseNotes,
  }) {
    return AppUpdateState(
      currentVersion: currentVersion ?? this.currentVersion,
      latestVersion: latestVersion ?? this.latestVersion,
      hasUpdate: hasUpdate ?? this.hasUpdate,
      isChecking: isChecking ?? this.isChecking,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      releaseNotes: releaseNotes ?? this.releaseNotes,
    );
  }
}
