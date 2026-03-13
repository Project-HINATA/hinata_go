class AppUpdateState {
  final String currentVersion;
  final String latestVersion;
  final bool isUpdateSupported;
  final bool hasUpdate;
  final bool isChecking;
  final String? downloadUrl;
  final String? releaseNotes;

  const AppUpdateState({
    this.currentVersion = 'Unknown',
    this.latestVersion = 'Unknown',
    this.isUpdateSupported = false,
    this.hasUpdate = false,
    this.isChecking = false,
    this.downloadUrl,
    this.releaseNotes,
  });

  AppUpdateState copyWith({
    String? currentVersion,
    String? latestVersion,
    bool? isUpdateSupported,
    bool? hasUpdate,
    bool? isChecking,
    String? downloadUrl,
    String? releaseNotes,
  }) {
    return AppUpdateState(
      currentVersion: currentVersion ?? this.currentVersion,
      latestVersion: latestVersion ?? this.latestVersion,
      isUpdateSupported: isUpdateSupported ?? this.isUpdateSupported,
      hasUpdate: hasUpdate ?? this.hasUpdate,
      isChecking: isChecking ?? this.isChecking,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      releaseNotes: releaseNotes ?? this.releaseNotes,
    );
  }
}
