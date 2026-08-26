class AppConstants {
  static const String defaultHinataIoUrl = 'https://aime-ws.neri.moe/REPLACEME';
  static const String minimumHinataIoVersion = '1.1.0';
  static const String appReleaseUrl =
      'https://api.github.com/repos/nerimoe/hinata_go/releases/latest';
  static const String appUpdateChannel = 'moe.neri.hinatago/app_update';

  static const String googlePlayUrl =
      'https://play.google.com/store/apps/details?id=moe.neri.hinatago';
  static const String appStoreUrl =
      'https://apps.apple.com/app/id6760301105';
  static const String githubReleasesUrl =
      'https://github.com/nerimoe/hinata_go/releases/latest';

  static const String defaultGitCommitHash = '4d8ee97';
  static const String gitCommitHash = String.fromEnvironment(
    'GIT_COMMIT_HASH',
    defaultValue: String.fromEnvironment(
      'COMMIT_HASH',
      defaultValue: defaultGitCommitHash,
    ),
  );
}
