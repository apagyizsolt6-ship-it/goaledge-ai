class AppConstants {
  static const String appName = 'GoalEdge AI';
  static const String version = '7.1.2';

  /// GitHub repo for in-app updates (Releases API)
  static const String githubOwner = 'apagyizsolt6-ship-it';
  static const String githubRepo = 'goaledge-ai';

  static const String githubReleasesApi =
      'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest';

  static const Duration liveRadarInterval = Duration(seconds: 75);
  static const double defaultBankroll = 50000;
  static const Set<String> defaultFavoriteLeagues = {
    'Premier League',
    'NB I',
    'UEFA Champions League',
  };
}
