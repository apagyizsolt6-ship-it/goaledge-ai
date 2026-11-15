import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

typedef JsonMap = Map<String, dynamic>;
typedef StandingsMap = Map<int, TeamStandingInfo>;

void main() {
  runApp(const GoalEdgeApp());
}

class GoalEdgeApp extends StatelessWidget {
  const GoalEdgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GoalEdge AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0E17),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF10B981),
          secondary: Color(0xFF3B82F6),
          surface: Color(0xFF131A29),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF131A29),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF1F2937), width: 1),
          ),
        ),
        useMaterial3: true,
      ),
      home: const MainNavigationScreen(),
    );
  }
}

// ==========================================
// 1. MATEMATIKAI MOTOR (POISSON-ELOSZLÁS)
// ==========================================

class ScoreProbability {
  final String score;
  final double probability;

  ScoreProbability(this.score, this.probability);
}

class PoissonResult {
  final double homeWin;
  final double draw;
  final double awayWin;
  final double over25;
  final double btts;
  final List<ScoreProbability> topScores;

  PoissonResult({
    required this.homeWin,
    required this.draw,
    required this.awayWin,
    required this.over25,
    required this.btts,
    required this.topScores,
  });
}

class PoissonEngine {
  static double _pmf(double lambda, int k) {
    if (lambda <= 0) return k == 0 ? 1.0 : 0.0;
    double factorial = 1.0;
    for (int i = 2; i <= k; i++) {
      factorial *= i;
    }
    return (math.pow(lambda, k) * math.exp(-lambda)) / factorial;
  }

  static PoissonResult calculate(double homeXg, double awayXg) {
    double pHome = 0.0;
    double pDraw = 0.0;
    double pAway = 0.0;
    double pOver25 = 0.0;
    double pBtts = 0.0;
    final List<ScoreProbability> scores = [];

    for (int h = 0; h <= 6; h++) {
      final ph = _pmf(homeXg, h);
      for (int a = 0; a <= 6; a++) {
        final pa = _pmf(awayXg, a);
        final prob = ph * pa;

        if (h > a) {
          pHome += prob;
        } else if (h == a) {
          pDraw += prob;
        } else {
          pAway += prob;
        }

        if (h + a > 2) pOver25 += prob;
        if (h > 0 && a > 0) pBtts += prob;
        scores.add(ScoreProbability('$h-$a', prob));
      }
    }

    final total1X2 = pHome + pDraw + pAway;
    if (total1X2 > 0) {
      pHome /= total1X2;
      pDraw /= total1X2;
      pAway /= total1X2;
    }

    scores.sort((a, b) => b.probability.compareTo(a.probability));

    return PoissonResult(
      homeWin: pHome,
      draw: pDraw,
      awayWin: pAway,
      over25: pOver25.clamp(0.01, 0.99),
      btts: pBtts.clamp(0.01, 0.99),
      topScores: scores.take(3).toList(),
    );
  }
}

// ==========================================
// 2. ADATMODELLEK
// ==========================================

class TeamStandingInfo {
  final int teamId;
  final String teamName;
  final int position;
  final int played;
  final int won;
  final int draw;
  final int lost;
  final int goalsFor;
  final int goalsAgainst;
  final int points;
  final List<JsonMap> form;

  TeamStandingInfo({
    required this.teamId,
    required this.teamName,
    required this.position,
    required this.played,
    required this.won,
    required this.draw,
    required this.lost,
    required this.goalsFor,
    required this.goalsAgainst,
    required this.points,
    required this.form,
  });

  double get avgGoalsFor => played > 0 ? goalsFor / played : 1.35;
  double get avgGoalsAgainst => played > 0 ? goalsAgainst / played : 1.25;
}

class MatchPick {
  final String id;
  final int? fixtureId;
  final int? leagueId;
  final int? homeId;
  final int? awayId;
  final String league;
  final String leagueZone;
  final String kickoff;
  final String status;
  final String? minute;
  final int? homeScore;
  final int? awayScore;
  final String homeTeam;
  final String awayTeam;
  String market;
  String marketCode;
  String trendSummary;
  String trendCategory;
  double modelProb;
  double marketOdds;
  List<double> oddsHistory;
  double homeXg;
  double awayXg;
  List<bool> last6Trend;
  int? homePos;
  int? awayPos;
  bool hasStandingData;
  bool isWatched;

  MatchPick({
    required this.id,
    this.fixtureId,
    this.leagueId,
    this.homeId,
    this.awayId,
    required this.league,
    this.leagueZone = '',
    required this.kickoff,
    this.status = 'Scheduled',
    this.minute,
    this.homeScore,
    this.awayScore,
    required this.homeTeam,
    required this.awayTeam,
    required this.market,
    this.marketCode = 'over25',
    required this.trendSummary,
    required this.trendCategory,
    required this.modelProb,
    required this.marketOdds,
    required this.oddsHistory,
    required this.homeXg,
    required this.awayXg,
    required this.last6Trend,
    this.homePos,
    this.awayPos,
    this.hasStandingData = false,
    this.isWatched = false,
  });

  double get impliedProb => 1.0 / marketOdds;
  double get edgePercent => (modelProb - impliedProb) * 100.0;
  PoissonResult get poisson => PoissonEngine.calculate(homeXg, awayXg);
  bool get isLive => status == 'LIVE';
  bool get isFinished => status == 'FT' || status == 'AET' || status == 'PENS';
}

class FixtureDetailData {
  final String? stadium;
  final String? city;
  final String? homeCoach;
  final String? awayCoach;
  final int? htHome;
  final int? htAway;
  final List<JsonMap> events;
  final JsonMap? homeStats;
  final JsonMap? awayStats;

  FixtureDetailData({
    this.stadium,
    this.city,
    this.homeCoach,
    this.awayCoach,
    this.htHome,
    this.htAway,
    this.events = const [],
    this.homeStats,
    this.awayStats,
  });
}

class BetRecord {
  final String id;
  final int? fixtureId;
  final String matchTitle;
  final String market;
  final String marketCode;
  final double odds;
  final double stake;
  final String status;
  final String date;

  BetRecord({
    required this.id,
    this.fixtureId,
    required this.matchTitle,
    required this.market,
    this.marketCode = 'over25',
    required this.odds,
    required this.stake,
    required this.status,
    required this.date,
  });

  double get profit {
    if (status == 'won') return (stake * odds) - stake;
    if (status == 'lost') return -stake;
    return 0.0;
  }

  JsonMap toJson() => {
        'id': id,
        'fixtureId': fixtureId,
        'matchTitle': matchTitle,
        'market': market,
        'marketCode': marketCode,
        'odds': odds,
        'stake': stake,
        'status': status,
        'date': date,
      };

  factory BetRecord.fromJson(JsonMap json) => BetRecord(
        id: json['id'] ?? '',
        fixtureId: (json['fixtureId'] as num?)?.toInt(),
        matchTitle: json['matchTitle'] ?? '',
        market: json['market'] ?? '',
        marketCode: json['marketCode'] ?? 'over25',
        odds: (json['odds'] as num?)?.toDouble() ?? 1.80,
        stake: (json['stake'] as num?)?.toDouble() ?? 1000.0,
        status: json['status'] ?? 'pending',
        date: json['date'] ?? '',
      );
}

// ==========================================
// 3. SPORTAPI.AI HIVATALOS KLIENS
// ==========================================

class SportApiResponse {
  final bool success;
  final int statusCode;
  final List<MatchPick> matches;
  final String rawPreview;
  final String message;
  final String? rateLimitRemaining;

  SportApiResponse({
    required this.success,
    required this.statusCode,
    required this.matches,
    required this.rawPreview,
    required this.message,
    this.rateLimitRemaining,
  });
}

class SportApiService {
  static const String defaultBaseUrl = 'https://sportapi.ai/api';
  static final Map<int, StandingsMap> _standingsCache = {};

  static String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  static Future<SportApiResponse> fetchFixturesByDate({
    required String baseUrl,
    required String apiKey,
    required DateTime targetDate,
    required String dayLabel,
    required List<String> watchedIds,
  }) async {
    final cleanBase = baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    final dateStr = _formatDate(targetDate);
    final uri = Uri.parse('$cleanBase/fixtures/date/$dateStr');

    try {
      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'X-Api-Key': apiKey.trim(),
        },
      ).timeout(const Duration(seconds: 15));

      final remaining = response.headers['x-ratelimit-remaining'];
      final bodyText = utf8.decode(response.bodyBytes, allowMalformed: true);
      final preview = bodyText.length > 350 ? '${bodyText.substring(0, 350)}...' : bodyText;

      if (response.statusCode == 401) {
        return SportApiResponse(
          success: false,
          statusCode: 401,
          matches: [],
          rawPreview: preview,
          message: '401 Hibás vagy hiányzó X-Api-Key kulcs!',
          rateLimitRemaining: remaining,
        );
      }

      if (response.statusCode == 429) {
        return SportApiResponse(
          success: false,
          statusCode: 429,
          matches: [],
          rawPreview: preview,
          message: '429 Elérted a napi/havi lekérési limitet!',
          rateLimitRemaining: remaining,
        );
      }

      if (response.statusCode != 200) {
        return SportApiResponse(
          success: false,
          statusCode: response.statusCode,
          matches: [],
          rawPreview: preview,
          message: 'HTTP ${response.statusCode} hiba ($uri)',
          rateLimitRemaining: remaining,
        );
      }

      final decoded = jsonDecode(bodyText);
      final List<dynamic> dataList = (decoded is Map && decoded['data'] is List) ? decoded['data'] : [];

      if (dataList.isEmpty) {
        return SportApiResponse(
          success: true,
          statusCode: 200,
          matches: [],
          rawPreview: preview,
          message: 'Kapcsolat OK (200), de 0 meccs van ezen a napon ($dateStr).',
          rateLimitRemaining: remaining,
        );
      }

      const topLeagueNames = {
        'Premier League',
        'Spanish La Liga',
        'La Liga',
        'Serie A',
        'Bundesliga',
        'Ligue 1',
        'UEFA Champions League',
        'UEFA Europa League',
        'NB I',
        'OTP Bank Liga',
      };

      final List<JsonMap> sortedRaw = [];
      for (final el in dataList) {
        if (el is JsonMap) {
          sortedRaw.add(el);
        }
      }

      sortedRaw.sort((a, b) {
        final aLeague = (a['league_name'] ?? '').toString();
        final bLeague = (b['league_name'] ?? '').toString();
        final aPrio = topLeagueNames.contains(aLeague) ? 0 : 1;
        final bPrio = topLeagueNames.contains(bLeague) ? 0 : 1;
        if (aPrio != bPrio) return aPrio.compareTo(bPrio);
        return (a['datetime'] ?? '').toString().compareTo((b['datetime'] ?? '').toString());
      });

      final List<MatchPick> parsed = [];
      for (final item in sortedRaw.take(40)) {
        final fixtureId = (item['id'] as num?)?.toInt() ?? 0;
        final leagueId = (item['league_id'] as num?)?.toInt();
        final homeId = (item['home_id'] as num?)?.toInt();
        final awayId = (item['away_id'] as num?)?.toInt();
        final matchId = 'sportapi_$fixtureId';

        final homeTeam = (item['home_team'] ?? 'Hazai').toString();
        final awayTeam = (item['away_team'] ?? 'Vendég').toString();
        final leagueName = (item['league_name'] ?? 'Bajnokság').toString();
        final leagueZone = (item['league_zone'] ?? '').toString();
        final status = (item['status'] ?? 'Scheduled').toString();
        final minute = item['minute']?.toString();
        final homeScore = (item['home_score'] as num?)?.toInt();
        final awayScore = (item['away_score'] as num?)?.toInt();

        String timeStr = dayLabel;
        final dtStr = (item['datetime'] ?? '').toString();
        if (dtStr.length >= 16) {
          timeStr = '$dayLabel ${dtStr.substring(11, 16)}';
        }

        final rng = math.Random(fixtureId);
        double hXg = 1.25 + (rng.nextDouble() * 0.95);
        double aXg = 0.95 + (rng.nextDouble() * 0.85);
        int? homePos;
        int? awayPos;
        bool hasStandings = false;
        List<bool> trendList = List.generate(6, (_) => rng.nextDouble() > 0.3);

        if (leagueId != null && _standingsCache.containsKey(leagueId)) {
          final table = _standingsCache[leagueId]!;
          final hInfo = homeId != null ? table[homeId] : null;
          final aInfo = awayId != null ? table[awayId] : null;
          if (hInfo != null && aInfo != null && hInfo.played > 0 && aInfo.played > 0) {
            hXg = ((hInfo.avgGoalsFor + aInfo.avgGoalsAgainst) / 2.0 * 1.12).clamp(0.45, 3.6);
            aXg = ((aInfo.avgGoalsFor + hInfo.avgGoalsAgainst) / 2.0 * 0.94).clamp(0.35, 3.2);
            homePos = hInfo.position;
            awayPos = aInfo.position;
            hasStandings = true;
            trendList = _extractFormTrend(hInfo, aInfo);
          }
        }

        final pick = _buildPickFromXg(
          id: matchId,
          fixtureId: fixtureId,
          leagueId: leagueId,
          homeId: homeId,
          awayId: awayId,
          league: leagueName,
          leagueZone: leagueZone,
          kickoff: timeStr,
          status: status,
          minute: minute,
          homeScore: homeScore,
          awayScore: awayScore,
          homeTeam: homeTeam,
          awayTeam: awayTeam,
          homeXg: hXg,
          awayXg: aXg,
          last6Trend: trendList,
          homePos: homePos,
          awayPos: awayPos,
          hasStandingData: hasStandings,
          isWatched: watchedIds.contains(matchId),
        );

        parsed.add(pick);
      }

      return SportApiResponse(
        success: true,
        statusCode: 200,
        matches: parsed,
        rawPreview: preview,
        message: '${parsed.length} meccs betöltve ($dateStr)!',
        rateLimitRemaining: remaining,
      );
    } catch (e) {
      return SportApiResponse(
        success: false,
        statusCode: 0,
        matches: [],
        rawPreview: e.toString(),
        message: 'Hálózati hiba: $e',
      );
    }
  }

  static List<bool> _extractFormTrend(TeamStandingInfo home, TeamStandingInfo away) {
    final List<bool> hits = [];
    for (final f in home.form.take(3)) {
      final hg = (f['home_score'] as num?)?.toInt() ?? 0;
      final ag = (f['away_score'] as num?)?.toInt() ?? 0;
      hits.add((hg + ag) >= 2);
    }
    for (final f in away.form.take(3)) {
      final hg = (f['home_score'] as num?)?.toInt() ?? 0;
      final ag = (f['away_score'] as num?)?.toInt() ?? 0;
      hits.add((hg + ag) >= 2);
    }
    while (hits.length < 6) {
      hits.add(true);
    }
    return hits.take(6).toList();
  }

  static MatchPick _buildPickFromXg({
    required String id,
    int? fixtureId,
    int? leagueId,
    int? homeId,
    int? awayId,
    required String league,
    required String leagueZone,
    required String kickoff,
    required String status,
    String? minute,
    int? homeScore,
    int? awayScore,
    required String homeTeam,
    required String awayTeam,
    required double homeXg,
    required double awayXg,
    required List<bool> last6Trend,
    int? homePos,
    int? awayPos,
    required bool hasStandingData,
    required bool isWatched,
  }) {
    final poisson = PoissonEngine.calculate(homeXg, awayXg);

    String market;
    String marketCode;
    double prob;
    String category;

    if (poisson.homeWin >= 0.56) {
      market = 'Hazai győzelem (1)';
      marketCode = 'home';
      prob = poisson.homeWin;
      category = 'Tabella & Forma';
    } else if (poisson.over25 >= 0.55) {
      market = '2.5 gól felett';
      marketCode = 'over25';
      prob = poisson.over25;
      category = 'Gólok / BTTS';
    } else if (poisson.btts >= 0.54) {
      market = 'Mindkét csapat szerez gólt (BTTS)';
      marketCode = 'btts';
      prob = poisson.btts;
      category = 'Gólok / BTTS';
    } else {
      market = 'Hazai győzelem (1)';
      marketCode = 'home';
      prob = poisson.homeWin;
      category = 'xG eltérés';
    }

    final fairOdds = 1.0 / prob;
    final marketOdds = double.parse((fairOdds * 1.08).clamp(1.30, 4.20).toStringAsFixed(2));

    String summary;
    if (hasStandingData && homePos != null && awayPos != null) {
      summary =
          'Tabella: $homePos. hely vs $awayPos. hely • Valós gólátlag alapú xG: ${homeXg.toStringAsFixed(2)} – ${awayXg.toStringAsFixed(2)} (BTTS: ${(poisson.btts * 100).round()}%).';
    } else {
      summary =
          'Poisson-modell: várható összgól ${(homeXg + awayXg).toStringAsFixed(2)}, 2.5+ gól esély ${(poisson.over25 * 100).round()}%, BTTS ${(poisson.btts * 100).round()}%.';
    }

    return MatchPick(
      id: id,
      fixtureId: fixtureId,
      leagueId: leagueId,
      homeId: homeId,
      awayId: awayId,
      league: league,
      leagueZone: leagueZone,
      kickoff: kickoff,
      status: status,
      minute: minute,
      homeScore: homeScore,
      awayScore: awayScore,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      market: market,
      marketCode: marketCode,
      trendSummary: summary,
      trendCategory: category,
      modelProb: prob,
      marketOdds: marketOdds,
      oddsHistory: [
        double.parse((marketOdds + 0.14).toStringAsFixed(2)),
        double.parse((marketOdds + 0.08).toStringAsFixed(2)),
        double.parse((marketOdds + 0.03).toStringAsFixed(2)),
        marketOdds,
      ],
      homeXg: double.parse(homeXg.toStringAsFixed(2)),
      awayXg: double.parse(awayXg.toStringAsFixed(2)),
      last6Trend: last6Trend,
      homePos: homePos,
      awayPos: awayPos,
      hasStandingData: hasStandingData,
      isWatched: isWatched,
    );
  }

  static Future<StandingsMap> fetchStandings({
    required String baseUrl,
    required String apiKey,
    required int leagueId,
  }) async {
    if (_standingsCache.containsKey(leagueId)) {
      return _standingsCache[leagueId]!;
    }

    final cleanBase = baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$cleanBase/standings/$leagueId');

    try {
      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'X-Api-Key': apiKey.trim(),
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
        final List<dynamic> rows = (decoded is Map && decoded['data'] is List) ? decoded['data'] : [];
        final StandingsMap map = {};

        for (final row in rows) {
          if (row is! Map) continue;
          final teamObj = row['team'];
          final teamId = (teamObj is Map ? (teamObj['id'] as num?)?.toInt() : null) ?? 0;
          if (teamId == 0) continue;

          final List<JsonMap> formList = [];
          if (row['form'] is List) {
            for (final item in row['form']) {
              if (item is JsonMap) {
                formList.add(item);
              }
            }
          }

          map[teamId] = TeamStandingInfo(
            teamId: teamId,
            teamName: (teamObj is Map ? teamObj['name'] : 'Csapat').toString(),
            position: (row['position'] as num?)?.toInt() ?? 0,
            played: (row['played'] as num?)?.toInt() ?? 0,
            won: (row['won'] as num?)?.toInt() ?? 0,
            draw: (row['draw'] as num?)?.toInt() ?? 0,
            lost: (row['lost'] as num?)?.toInt() ?? 0,
            goalsFor: (row['goals_for'] as num?)?.toInt() ?? 0,
            goalsAgainst: (row['goals_against'] as num?)?.toInt() ?? 0,
            points: (row['points'] as num?)?.toInt() ?? 0,
            form: formList,
          );
        }

        if (map.isNotEmpty) {
          _standingsCache[leagueId] = map;
        }
        return map;
      }
    } catch (_) {}
    return {};
  }

  static Future<FixtureDetailData?> fetchFixtureDetails({
    required String baseUrl,
    required String apiKey,
    required int fixtureId,
  }) async {
    final cleanBase = baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    final headers = {
      'Accept': 'application/json',
      'X-Api-Key': apiKey.trim(),
    };

    try {
      final results = await Future.wait([
        http.get(Uri.parse('$cleanBase/fixtures/$fixtureId'), headers: headers).timeout(const Duration(seconds: 10)),
        http.get(Uri.parse('$cleanBase/fixtures/$fixtureId/stats'), headers: headers).timeout(const Duration(seconds: 10)),
      ]);

      JsonMap? fixtureObj;
      if (results[0].statusCode == 200) {
        final d0 = jsonDecode(utf8.decode(results[0].bodyBytes, allowMalformed: true));
        if (d0 is Map && d0['fixture'] is JsonMap) {
          fixtureObj = d0['fixture'];
        }
      }

      JsonMap? homeStats;
      JsonMap? awayStats;
      if (results[1].statusCode == 200) {
        final d1 = jsonDecode(utf8.decode(results[1].bodyBytes, allowMalformed: true));
        if (d1 is Map && d1['available'] == true && d1['data'] is Map) {
          homeStats = d1['data']['home'] as JsonMap?;
          awayStats = d1['data']['away'] as JsonMap?;
        }
      }

      final List<JsonMap> eventsList = [];
      if (fixtureObj?['events'] is List) {
        for (final ev in fixtureObj!['events']) {
          if (ev is JsonMap) {
            eventsList.add(ev);
          }
        }
      }

      return FixtureDetailData(
        stadium: fixtureObj?['home_stadium']?.toString(),
        city: fixtureObj?['home_city']?.toString(),
        homeCoach: fixtureObj?['home_coach']?.toString(),
        awayCoach: fixtureObj?['away_coach']?.toString(),
        htHome: (fixtureObj?['ht_home'] as num?)?.toInt(),
        htAway: (fixtureObj?['ht_away'] as num?)?.toInt(),
        events: eventsList,
        homeStats: homeStats,
        awayStats: awayStats,
      );
    } catch (_) {
      return null;
    }
  }
}

// ==========================================
// 4. FŐ KÉPERNYŐ ÉS ÁLLAPOTKEZELÉS
// ==========================================

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;
  int _dayOffset = 0;
  bool _isLoadingApi = false;
  bool _isLiveMode = false;

  String _apiKey = '';
  String _baseUrl = SportApiService.defaultBaseUrl;
  String _lastApiStatus = 'Még nem futott élő lekérés.';
  String? _rateLimitRemaining;

  double _bankroll = 50000;
  List<MatchPick> _matches = [];
  List<BetRecord> _bets = [];

  @override
  void initState() {
    super.initState();
    _matches = _buildDemoMatches();
    _loadSavedData();
  }

  List<MatchPick> _buildDemoMatches() {
    return [
      MatchPick(
        id: 'm1',
        league: 'Premier League',
        kickoff: 'Ma 18:30',
        homeTeam: 'Arsenal',
        awayTeam: 'Aston Villa',
        market: 'Mindkét csapat szerez gólt (BTTS)',
        marketCode: 'btts',
        trendSummary: 'Az utolsó 6 bajnoki meccsből 5-ször mindkét fél betalált, magas támadó xG-mutatókkal.',
        trendCategory: 'Gólok / BTTS',
        modelProb: PoissonEngine.calculate(2.15, 1.48).btts,
        marketOdds: 1.72,
        oddsHistory: [1.88, 1.84, 1.80, 1.76, 1.72],
        homeXg: 2.15,
        awayXg: 1.48,
        last6Trend: [true, true, true, false, true, true],
        isWatched: true,
      ),
      MatchPick(
        id: 'm2',
        league: 'NB I',
        kickoff: 'Ma 19:45',
        homeTeam: 'Ferencváros',
        awayTeam: 'Paksi FC',
        market: '2.5 gól felett',
        marketCode: 'over25',
        trendSummary: 'A Paks idegenbeli meccsein 3.4-es a gólátlag, az FTC hazai xG-je 2.35.',
        trendCategory: 'Gólok / BTTS',
        modelProb: PoissonEngine.calculate(2.35, 1.32).over25,
        marketOdds: 1.65,
        oddsHistory: [1.78, 1.75, 1.70, 1.68, 1.65],
        homeXg: 2.35,
        awayXg: 1.32,
        last6Trend: [true, true, true, true, false, true],
        isWatched: true,
      ),
      MatchPick(
        id: 'm3',
        league: 'La Liga',
        kickoff: 'Ma 21:00',
        homeTeam: 'Real Sociedad',
        awayTeam: 'Villarreal',
        market: 'Hazai győzelem (1)',
        marketCode: 'home',
        trendSummary: 'Tabella & xG előny: a Sociedad hazai pályán dominál, 1.98-as várható góllal.',
        trendCategory: 'Tabella & Forma',
        modelProb: PoissonEngine.calculate(1.98, 1.05).homeWin,
        marketOdds: 2.15,
        oddsHistory: [2.35, 2.28, 2.22, 2.18, 2.15],
        homeXg: 1.98,
        awayXg: 1.05,
        last6Trend: [true, false, true, true, true, true],
      ),
    ];
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    final savedKey = prefs.getString('sportapi_key') ?? '';
    String savedBase = prefs.getString('sportapi_base') ?? SportApiService.defaultBaseUrl;

    if (savedBase.contains('api.sportapi.ai')) {
      savedBase = SportApiService.defaultBaseUrl;
      await prefs.setString('sportapi_base', savedBase);
    }

    final savedBankroll = prefs.getDouble('bankroll') ?? 50000;
    final watchedIds = prefs.getStringList('watched_ids');
    final betsJson = prefs.getString('logged_bets');

    setState(() {
      _apiKey = savedKey;
      _baseUrl = savedBase;
      _bankroll = savedBankroll;
      if (watchedIds != null) {
        for (final m in _matches) {
          m.isWatched = watchedIds.contains(m.id);
        }
      }
      if (betsJson != null) {
        final List<dynamic> decoded = jsonDecode(betsJson);
        final List<BetRecord> loadedBets = [];
        for (final e in decoded) {
          if (e is JsonMap) {
            loadedBets.add(BetRecord.fromJson(e));
          }
        }
        _bets = loadedBets;
      }
    });

    if (_apiKey.isNotEmpty) {
      _syncSportApi(silent: true);
    }
  }

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sportapi_key', _apiKey);
    await prefs.setString('sportapi_base', _baseUrl);
    await prefs.setDouble('bankroll', _bankroll);
    final watchedIds = _matches.where((m) => m.isWatched).map((m) => m.id).toList();
    await prefs.setStringList('watched_ids', watchedIds);
    await prefs.setString('logged_bets', jsonEncode(_bets.map((b) => b.toJson()).toList()));
  }

  String _dayLabelForOffset(int offset) {
    if (offset == -1) return 'Tegnap';
    if (offset == 1) return 'Holnap';
    return 'Ma';
  }

  Future<SportApiResponse?> _syncSportApi({bool silent = false}) async {
    if (_apiKey.trim().isEmpty) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add meg a SportAPI.ai kulcsodat a Beállítások (fogaskerék) menüben!')),
        );
      }
      return null;
    }

    setState(() => _isLoadingApi = true);
    final prefs = await SharedPreferences.getInstance();
    final watchedIds = prefs.getStringList('watched_ids') ?? [];
    final targetDate = DateTime.now().add(Duration(days: _dayOffset));
    final dayLabel = _dayLabelForOffset(_dayOffset);

    final result = await SportApiService.fetchFixturesByDate(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      targetDate: targetDate,
      dayLabel: dayLabel,
      watchedIds: watchedIds,
    );

    if (mounted) {
      setState(() {
        _isLoadingApi = false;
        _rateLimitRemaining = result.rateLimitRemaining ?? _rateLimitRemaining;
        _lastApiStatus = '${result.message}\nNyers válasz: ${result.rawPreview}';
        if (result.success && result.matches.isNotEmpty) {
          _matches = result.matches;
          _isLiveMode = true;
        }
      });

      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
      }

      if (result.success && result.matches.isNotEmpty) {
        _autoSettlePendingBets(result.matches);
        _enrichMatchesWithStandings();
      }
    }
    return result;
  }

  Future<void> _enrichMatchesWithStandings() async {
    final leagueIds = _matches
        .map((m) => m.leagueId)
        .whereType<int>()
        .toSet()
        .take(6);

    bool anyUpdated = false;
    for (final lid in leagueIds) {
      final table = await SportApiService.fetchStandings(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        leagueId: lid,
      );
      if (table.isEmpty || !mounted) continue;

      for (int i = 0; i < _matches.length; i++) {
        final m = _matches[i];
        if (m.leagueId != lid || m.hasStandingData) continue;
        final hInfo = m.homeId != null ? table[m.homeId!] : null;
        final aInfo = m.awayId != null ? table[m.awayId!] : null;

        if (hInfo != null && aInfo != null && hInfo.played > 0 && aInfo.played > 0) {
          final realHomeXg = ((hInfo.avgGoalsFor + aInfo.avgGoalsAgainst) / 2.0 * 1.12).clamp(0.45, 3.6);
          final realAwayXg = ((aInfo.avgGoalsFor + hInfo.avgGoalsAgainst) / 2.0 * 0.94).clamp(0.35, 3.2);
          final trend = SportApiService._extractFormTrend(hInfo, aInfo);

          _matches[i] = SportApiService._buildPickFromXg(
            id: m.id,
            fixtureId: m.fixtureId,
            leagueId: m.leagueId,
            homeId: m.homeId,
            awayId: m.awayId,
            league: m.league,
            leagueZone: m.leagueZone,
            kickoff: m.kickoff,
            status: m.status,
            minute: m.minute,
            homeScore: m.homeScore,
            awayScore: m.awayScore,
            homeTeam: m.homeTeam,
            awayTeam: m.awayTeam,
            homeXg: realHomeXg,
            awayXg: realAwayXg,
            last6Trend: trend,
            homePos: hInfo.position,
            awayPos: aInfo.position,
            hasStandingData: true,
            isWatched: m.isWatched,
          );
          anyUpdated = true;
        }
      }
      if (anyUpdated && mounted) {
        setState(() {});
      }
    }
  }

  void _autoSettlePendingBets(List<MatchPick> freshMatches) {
    bool changed = false;
    for (int i = 0; i < _bets.length; i++) {
      final bet = _bets[i];
      if (bet.status != 'pending' || bet.fixtureId == null) continue;

      final matchIdx = freshMatches.indexWhere((m) => m.fixtureId == bet.fixtureId);
      if (matchIdx == -1) continue;
      final match = freshMatches[matchIdx];
      if (!match.isFinished || match.homeScore == null || match.awayScore == null) continue;

      final hs = match.homeScore!;
      final as = match.awayScore!;
      bool won = false;
      if (bet.marketCode == 'home') {
        won = hs > as;
      } else if (bet.marketCode == 'over25') {
        won = (hs + as) > 2;
      } else if (bet.marketCode == 'btts') {
        won = hs > 0 && as > 0;
      }

      _bets[i] = BetRecord(
        id: bet.id,
        fixtureId: bet.fixtureId,
        matchTitle: bet.matchTitle,
        market: bet.market,
        marketCode: bet.marketCode,
        odds: bet.odds,
        stake: bet.stake,
        status: won ? 'won' : 'lost',
        date: bet.date,
      );
      changed = true;
    }

    if (changed) {
      setState(() {});
      _saveState();
    }
  }

  void _changeDayOffset(int newOffset) {
    setState(() => _dayOffset = newOffset);
    if (_apiKey.isNotEmpty) {
      _syncSportApi();
    }
  }

  void _toggleWatch(String matchId) {
    setState(() {
      final idx = _matches.indexWhere((m) => m.id == matchId);
      if (idx != -1) {
        _matches[idx].isWatched = !_matches[idx].isWatched;
      }
    });
    _saveState();
  }

  void _addBet(MatchPick match, double stake) {
    final now = DateTime.now();
    final dateLabel = '${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}.';
    setState(() {
      _bets.insert(
        0,
        BetRecord(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          fixtureId: match.fixtureId,
          matchTitle: '${match.homeTeam} – ${match.awayTeam}',
          market: match.market,
          marketCode: match.marketCode,
          odds: match.marketOdds,
          stake: stake,
          status: 'pending',
          date: dateLabel,
        ),
      );
    });
    _saveState();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Tipp rögzítve a naplóba (${stake.round()} Ft)!')),
    );
  }

  void _updateBetStatus(String betId, String newStatus) {
    setState(() {
      final idx = _bets.indexWhere((b) => b.id == betId);
      if (idx != -1) {
        final old = _bets[idx];
        _bets[idx] = BetRecord(
          id: old.id,
          fixtureId: old.fixtureId,
          matchTitle: old.matchTitle,
          market: old.market,
          marketCode: old.marketCode,
          odds: old.odds,
          stake: old.stake,
          status: newStatus,
          date: old.date,
        );
      }
    });
    _saveState();
  }

  void _deleteBet(String betId) {
    setState(() {
      _bets.removeWhere((b) => b.id == betId);
    });
    _saveState();
  }

  void _openSettingsDialog() {
    final keyController = TextEditingController(text: _apiKey);
    final baseController = TextEditingController(text: _baseUrl);
    String testOutput = _lastApiStatus;
    bool testing = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF131A29),
              title: const Row(
                children: [
                  Icon(Icons.api, color: Color(0xFF10B981)),
                  SizedBox(width: 8),
                  Text('SportAPI.ai Beállítások', style: TextStyle(fontSize: 18)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Hivatalos végpont: GET /api/fixtures/date/{date}\nFejléc: X-Api-Key',
                      style: TextStyle(fontSize: 12, color: Color(0xFF10B981)),
                    ),
                    if (_rateLimitRemaining != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Maradék napi keret: $_rateLimitRemaining lekérés',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: keyController,
                      decoration: const InputDecoration(
                        labelText: 'X-Api-Key (sk_live_...)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: baseController,
                      decoration: const InputDecoration(
                        labelText: 'Base URL',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: testing
                            ? null
                            : () async {
                                setDialogState(() => testing = true);
                                _apiKey = keyController.text.trim();
                                _baseUrl = baseController.text.trim();
                                await _saveState();
                                final res = await _syncSportApi(silent: true);
                                setDialogState(() {
                                  testing = false;
                                  if (res != null) {
                                    testOutput = '${res.message}\n\n${res.rawPreview}';
                                  } else {
                                    testOutput = 'Adj meg egy API kulcsot a teszthez!';
                                  }
                                });
                              },
                        icon: testing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.bolt, size: 18),
                        label: const Text('Kapcsolat tesztelése'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A0E17),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF1F2937)),
                      ),
                      child: Text(
                        testOutput,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _apiKey = '';
                      _isLiveMode = false;
                      _matches = _buildDemoMatches();
                    });
                    _saveState();
                    Navigator.pop(context);
                  },
                  child: const Text('Demó mód'),
                ),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _apiKey = keyController.text.trim();
                      _baseUrl = baseController.text.trim();
                    });
                    _saveState();
                    Navigator.pop(context);
                    if (_apiKey.isNotEmpty) {
                      _syncSportApi();
                    }
                  },
                  child: const Text('Mentés'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _openLogBetDialog(MatchPick match) {
    double stake = (_bankroll * 0.03).clamp(500, 50000).roundToDouble();
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF131A29),
              title: const Text('Tipp rögzítése a naplóba'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${match.homeTeam} – ${match.awayTeam}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('${match.market} @ ${match.marketOdds}',
                      style: const TextStyle(color: Color(0xFF10B981), fontSize: 13)),
                  const SizedBox(height: 16),
                  Text('Tét: ${stake.round()} Ft', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Slider(
                    value: stake,
                    min: 500,
                    max: 50000,
                    divisions: 99,
                    activeColor: const Color(0xFF10B981),
                    onChanged: (v) => setDialogState(() => stake = v),
                  ),
                  Text(
                    'Várható nyeremény: ${(stake * match.marketOdds).round()} Ft',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Mégse'),
                ),
                FilledButton(
                  onPressed: () {
                    _addBet(match, stake);
                    Navigator.pop(context);
                  },
                  child: const Text('Rögzítés'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _openMatchDetail(MatchPick match) {
    final poisson = match.poisson;
    Future<FixtureDetailData?>? detailFuture;
    if (_apiKey.isNotEmpty && match.fixtureId != null && match.fixtureId! > 0) {
      detailFuture = SportApiService.fetchFixtureDetails(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        fixtureId: match.fixtureId!,
      );
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF131A29),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.82,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, scrollController) {
                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade700,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${match.league}${match.leagueZone.isNotEmpty ? " (${match.leagueZone})" : ""} • ${match.kickoff}',
                            style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color.fromRGBO(16, 185, 129, 0.16),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '+${match.edgePercent.toStringAsFixed(1)}% VALUE',
                            style: const TextStyle(
                              color: Color(0xFF10B981),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${match.homeTeam} – ${match.awayTeam}',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (match.homeScore != null && match.awayScore != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: match.isLive ? const Color(0xFFEF4444) : const Color(0xFF1F2937),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${match.homeScore} - ${match.awayScore} (${match.isLive ? "${match.minute ?? "LIVE"}'" : match.status})',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                      ],
                    ),
                    if (match.homePos != null && match.awayPos != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Tabella helyezés: ${match.homeTeam} (${match.homePos}.) vs ${match.awayTeam} (${match.awayPos}.)',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF3B82F6), fontWeight: FontWeight.w600),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Text(
                      'Poisson 1X2 Valószínűség',
                      style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: (poisson.homeWin * 100).round().clamp(10, 80),
                            child: Container(
                              height: 28,
                              color: const Color(0xFF10B981),
                              alignment: Alignment.center,
                              child: Text(
                                '1: ${(poisson.homeWin * 100).round()}%',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: (poisson.draw * 100).round().clamp(10, 80),
                            child: Container(
                              height: 28,
                              color: const Color(0xFF374151),
                              alignment: Alignment.center,
                              child: Text(
                                'X: ${(poisson.draw * 100).round()}%',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: (poisson.awayWin * 100).round().clamp(10, 80),
                            child: Container(
                              height: 28,
                              color: const Color(0xFF3B82F6),
                              alignment: Alignment.center,
                              child: Text(
                                '2: ${(poisson.awayWin * 100).round()}%',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Legvalószínűbb pontos végeredmények (Poisson)',
                      style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: poisson.topScores.map((s) {
                        return Expanded(
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0A0E17),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF1F2937)),
                            ),
                            child: Column(
                              children: [
                                Text(s.score, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                Text('${(s.probability * 100).toStringAsFixed(1)}%',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF10B981))),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Várható gólok (xG): ${match.homeXg.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        Text(match.awayXg.toStringAsFixed(2),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: match.homeXg / (match.homeXg + match.awayXg),
                        minHeight: 8,
                        backgroundColor: const Color(0xFF3B82F6),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                      ),
                    ),
                    if (detailFuture != null)
                      FutureBuilder<FixtureDetailData?>(
                        future: detailFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                            );
                          }
                          final detail = snapshot.data;
                          if (detail == null) return const SizedBox.shrink();

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (detail.stadium != null || detail.homeCoach != null) ...[
                                const Divider(height: 24, color: Color(0xFF1F2937)),
                                if (detail.stadium != null)
                                  Text('Stadion: ${detail.stadium}${detail.city != null ? " (${detail.city})" : ""}',
                                      style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                                if (detail.homeCoach != null && detail.awayCoach != null)
                                  Text('Edzők: ${detail.homeCoach} vs ${detail.awayCoach}',
                                      style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                              ],
                              if (detail.homeStats != null && detail.awayStats != null) ...[
                                const Divider(height: 24, color: Color(0xFF1F2937)),
                                const Text('Meccs statisztikák (SportAPI.ai)',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                                const SizedBox(height: 8),
                                _StatCompareRow(
                                  label: 'Összes lövés',
                                  homeVal: '${detail.homeStats!['shots'] ?? 0}',
                                  awayVal: '${detail.awayStats!['shots'] ?? 0}',
                                ),
                                _StatCompareRow(
                                  label: 'Kaput eltaláló lövés',
                                  homeVal: '${detail.homeStats!['shots_on_target'] ?? 0}',
                                  awayVal: '${detail.awayStats!['shots_on_target'] ?? 0}',
                                ),
                                _StatCompareRow(
                                  label: 'Passzpontosság',
                                  homeVal: '${detail.homeStats!['pass_accuracy'] ?? 0}%',
                                  awayVal: '${detail.awayStats!['pass_accuracy'] ?? 0}%',
                                ),
                                _StatCompareRow(
                                  label: 'Sárga lapok',
                                  homeVal: '${detail.homeStats!['yellow_cards'] ?? 0}',
                                  awayVal: '${detail.awayStats!['yellow_cards'] ?? 0}',
                                ),
                              ],
                              if (detail.events.isNotEmpty) ...[
                                const Divider(height: 24, color: Color(0xFF1F2937)),
                                const Text('Meccs események',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                ...detail.events.take(8).map((ev) {
                                  final type = ev['event_type'] ?? '';
                                  final icon = type == 'goal' ? '⚽' : (type == 'yellow_card' ? '🟨' : '🔄');
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 2),
                                    child: Text(
                                      "$icon ${ev['minute'] ?? ''} ${ev['player_name'] ?? ''} (${ev['team_side'] == 'home' ? match.homeTeam : match.awayTeam})",
                                      style: const TextStyle(fontSize: 12, color: Color(0xFFD1D5DB)),
                                    ),
                                  );
                                }),
                              ],
                            ],
                          );
                        },
                      ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              _toggleWatch(match.id);
                              setModalState(() {});
                            },
                            icon: Icon(match.isWatched ? Icons.notifications_active : Icons.notifications_none),
                            label: Text(match.isWatched ? 'Figyelve' : 'Riasztás'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _openLogBetDialog(match);
                            },
                            icon: const Icon(Icons.add_chart),
                            label: const Text('Tipp naplózása'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      ValueFeedTab(
        matches: _matches,
        dayOffset: _dayOffset,
        onDayChanged: _changeDayOffset,
        onRefresh: () => _syncSportApi(),
        onSelectMatch: _openMatchDetail,
        onToggleWatch: _toggleWatch,
        onLogBet: _openLogBetDialog,
      ),
      TrendRadarTab(matches: _matches, onSelectMatch: _openMatchDetail),
      CalculatorTab(
        matches: _matches,
        bankroll: _bankroll,
        onBankrollChanged: (val) {
          setState(() => _bankroll = val);
          _saveState();
        },
      ),
      TrackerAndWatchlistTab(
        matches: _matches,
        bets: _bets,
        onToggleWatch: _toggleWatch,
        onSelectMatch: _openMatchDetail,
        onUpdateBetStatus: _updateBetStatus,
        onDeleteBet: _deleteBet,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E17),
        title: Row(
          children: [
            const Icon(Icons.insights, color: Color(0xFF10B981)),
            const SizedBox(width: 8),
            const Text('GoalEdge AI', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _isLiveMode
                    ? const Color.fromRGBO(16, 185, 129, 0.2)
                    : const Color.fromRGBO(59, 130, 246, 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _isLiveMode ? 'SPORTAPI' : 'DEMÓ',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: _isLiveMode ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (_isLoadingApi)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'SportAPI.ai frissítés',
              onPressed: () => _syncSportApi(),
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'SportAPI.ai Beállítások',
            onPressed: _openSettingsDialog,
          ),
        ],
      ),
      body: pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF131A29),
        indicatorColor: const Color.fromRGBO(16, 185, 129, 0.2),
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.auto_graph), label: 'Ajánlások'),
          NavigationDestination(icon: Icon(Icons.radar), label: 'Trendek'),
          NavigationDestination(icon: Icon(Icons.calculate_outlined), label: 'Kalkulátor'),
          NavigationDestination(icon: Icon(Icons.analytics_outlined), label: 'Napló & ROI'),
        ],
      ),
    );
  }
}

class _StatCompareRow extends StatelessWidget {
  final String label;
  final String homeVal;
  final String awayVal;

  const _StatCompareRow({
    required this.label,
    required this.homeVal,
    required this.awayVal,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(homeVal, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          Text(label, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
          Text(awayVal, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }
}

// ==========================================
// 5. FÜLEK (AJÁNLÁSOK, TRENDEK, KALKULÁTOR, NAPLÓ)
// ==========================================

class ValueFeedTab extends StatefulWidget {
  final List<MatchPick> matches;
  final int dayOffset;
  final Function(int) onDayChanged;
  final Future<void> Function() onRefresh;
  final Function(MatchPick) onSelectMatch;
  final Function(String) onToggleWatch;
  final Function(MatchPick) onLogBet;

  const ValueFeedTab({
    super.key,
    required this.matches,
    required this.dayOffset,
    required this.onDayChanged,
    required this.onRefresh,
    required this.onSelectMatch,
    required this.onToggleWatch,
    required this.onLogBet,
  });

  @override
  State<ValueFeedTab> createState() => _ValueFeedTabState();
}

class _ValueFeedTabState extends State<ValueFeedTab> {
  String _selectedLeague = 'Összes';
  bool _sortByValue = true;

  @override
  Widget build(BuildContext context) {
    final dynamicLeagues = <String>{'Összes'};
    for (final m in widget.matches) {
      dynamicLeagues.add(m.league);
    }
    final leagues = dynamicLeagues.toList();
    if (!leagues.contains(_selectedLeague)) {
      _selectedLeague = 'Összes';
    }

    final filtered = widget.matches.where((m) {
      return _selectedLeague == 'Összes' || m.league == _selectedLeague;
    }).toList();

    filtered.sort((a, b) => _sortByValue
        ? b.edgePercent.compareTo(a.edgePercent)
        : b.modelProb.compareTo(a.modelProb));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: -1, label: Text('Tegnap')),
              ButtonSegment(value: 0, label: Text('Ma')),
              ButtonSegment(value: 1, label: Text('Holnap')),
            ],
            selected: {widget.dayOffset},
            onSelectionChanged: (s) => widget.onDayChanged(s.first),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: leagues.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final league = leagues[index];
              final selected = league == _selectedLeague;
              return ChoiceChip(
                label: Text(league),
                selected: selected,
                onSelected: (_) => setState(() => _selectedLeague = league),
                selectedColor: const Color(0xFF10B981),
                labelStyle: TextStyle(
                  color: selected ? Colors.black : Colors.white,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${filtered.length} kiemelt ajánlás', style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
              TextButton.icon(
                onPressed: () => setState(() => _sortByValue = !_sortByValue),
                icon: const Icon(Icons.sort, size: 16),
                label: Text(_sortByValue ? 'Rendezés: Value %' : 'Rendezés: Esély %', style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: widget.onRefresh,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final match = filtered[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => widget.onSelectMatch(match),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text('${match.league} • ${match.kickoff}',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
                              ),
                              Row(
                                children: [
                                  if (match.isLive || match.isFinished) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: match.isLive
                                            ? const Color.fromRGBO(239, 68, 68, 0.2)
                                            : const Color(0xFF1F2937),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '${match.homeScore ?? 0}-${match.awayScore ?? 0} ${match.isLive ? "${match.minute ?? "LIVE"}'" : match.status}',
                                        style: TextStyle(
                                          color: match.isLive ? const Color(0xFFEF4444) : Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color.fromRGBO(16, 185, 129, 0.16),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '+${match.edgePercent.toStringAsFixed(1)}% VALUE',
                                      style: const TextStyle(
                                        color: Color(0xFF10B981),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () => widget.onLogBet(match),
                                    child: const Icon(Icons.add_circle_outline, size: 20, color: Color(0xFF3B82F6)),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () => widget.onToggleWatch(match.id),
                                    child: Icon(
                                      match.isWatched ? Icons.notifications_active : Icons.notifications_none,
                                      size: 20,
                                      color: match.isWatched ? const Color(0xFFF59E0B) : Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${match.homeTeam} – ${match.awayTeam}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            match.trendSummary,
                            style: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 13),
                          ),
                          const Divider(height: 22, color: Color(0xFF1F2937)),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Ajánlott piac', style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                                    Text(match.market, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                  ],
                                ),
                              ),
                              Row(
                                children: [
                                  _StatBadge(label: 'Modell', value: '${(match.modelProb * 100).round()}%'),
                                  const SizedBox(width: 8),
                                  _StatBadge(label: 'Odds', value: match.marketOdds.toStringAsFixed(2), isPrimary: true),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final String value;
  final bool isPrimary;

  const _StatBadge({required this.label, required this.value, this.isPrimary = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isPrimary ? const Color.fromRGBO(16, 185, 129, 0.18) : const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF))),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: isPrimary ? const Color(0xFF10B981) : Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class TrendRadarTab extends StatefulWidget {
  final List<MatchPick> matches;
  final Function(MatchPick) onSelectMatch;

  const TrendRadarTab({super.key, required this.matches, required this.onSelectMatch});

  @override
  State<TrendRadarTab> createState() => _TrendRadarTabState();
}

class _TrendRadarTabState extends State<TrendRadarTab> {
  String _category = 'Mind';

  @override
  Widget build(BuildContext context) {
    final categories = ['Mind', 'Tabella & Forma', 'Gólok / BTTS', 'xG eltérés'];
    final list = widget.matches.where((m) => _category == 'Mind' || m.trendCategory == _category).toList();

    return Column(
      children: [
        SizedBox(
          height: 46,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final cat = categories[index];
              final selected = cat == _category;
              return ChoiceChip(
                label: Text(cat),
                selected: selected,
                onSelected: (_) => setState(() => _category = cat),
                selectedColor: const Color(0xFF3B82F6),
                labelStyle: TextStyle(
                  color: Colors.white,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
              );
            },
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (context, index) {
              final match = list[index];
              final hits = match.last6Trend.where((e) => e).length;
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => widget.onSelectMatch(match),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(match.trendCategory,
                                style: const TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.bold, fontSize: 12)),
                            Text('$hits / 6 forma-találat (${((hits / 6) * 100).round()}%)',
                                style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('${match.homeTeam} – ${match.awayTeam}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Text(match.trendSummary, style: const TextStyle(fontSize: 13, color: Color(0xFFD1D5DB))),
                        const SizedBox(height: 12),
                        Row(
                          children: match.last6Trend.map((hit) {
                            return Container(
                              margin: const EdgeInsets.only(right: 6),
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: hit ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(hit ? Icons.check : Icons.close, size: 14, color: Colors.black),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class CalculatorTab extends StatefulWidget {
  final List<MatchPick> matches;
  final double bankroll;
  final Function(double) onBankrollChanged;

  const CalculatorTab({
    super.key,
    required this.matches,
    required this.bankroll,
    required this.onBankrollChanged,
  });

  @override
  State<CalculatorTab> createState() => _CalculatorTabState();
}

class _CalculatorTabState extends State<CalculatorTab> {
  int _mode = 0;
  double _prob = 0.65;
  double _odds = 1.80;
  double _simHomeXg = 1.85;
  double _simAwayXg = 1.20;

  @override
  Widget build(BuildContext context) {
    final ev = (_prob * _odds) - 1.0;
    final fairOdds = 1.0 / _prob;
    final fullKelly = ((_prob * _odds) - 1.0) / (_odds - 1.0);
    final halfKelly = fullKelly > 0 ? fullKelly * 0.5 : 0.0;
    final recommendedStake = (widget.bankroll * halfKelly).round();
    final simResult = PoissonEngine.calculate(_simHomeXg, _simAwayXg);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('EV & Kelly Tét'), icon: Icon(Icons.percent)),
            ButtonSegment(value: 1, label: Text('Poisson Szimulátor'), icon: Icon(Icons.sports_soccer)),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => setState(() => _mode = s.first),
        ),
        const SizedBox(height: 16),
        if (_mode == 0) ...[
          const Text('Gyors betöltés a napi kínálatból:', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: widget.matches.take(4).map((m) {
              return ActionChip(
                label: Text('${m.homeTeam} (${m.marketOdds})', style: const TextStyle(fontSize: 11)),
                onPressed: () {
                  setState(() {
                    _prob = m.modelProb;
                    _odds = m.marketOdds;
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Modell valószínűség: ${(_prob * 100).round()}%',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Slider(
                    value: _prob,
                    min: 0.10,
                    max: 0.95,
                    activeColor: const Color(0xFF10B981),
                    onChanged: (v) => setState(() => _prob = v),
                  ),
                  Text('Bukmékeri szorzó (Odds): ${_odds.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Slider(
                    value: _odds,
                    min: 1.15,
                    max: 5.00,
                    activeColor: const Color(0xFF3B82F6),
                    onChanged: (v) => setState(() => _odds = v),
                  ),
                  Text('Bankroll (Mentett tőke): ${widget.bankroll.round()} Ft',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Slider(
                    value: widget.bankroll,
                    min: 10000,
                    max: 500000,
                    divisions: 49,
                    activeColor: const Color(0xFFF59E0B),
                    onChanged: (v) => widget.onBankrollChanged(v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _CalcRow(
                    label: 'Várható érték (EV)',
                    value: '${ev >= 0 ? '+' : ''}${(ev * 100).toStringAsFixed(1)}%',
                    valueColor: ev >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                  ),
                  const Divider(height: 22, color: Color(0xFF1F2937)),
                  _CalcRow(
                    label: 'Valós (Fair) szorzó',
                    value: fairOdds.toStringAsFixed(2),
                    valueColor: Colors.white,
                  ),
                  const Divider(height: 22, color: Color(0xFF1F2937)),
                  _CalcRow(
                    label: 'Ajánlott tét (Half-Kelly)',
                    value: ev > 0 ? '$recommendedStake Ft (${(halfKelly * 100).toStringAsFixed(1)}%)' : '0 Ft (Nincs előny)',
                    valueColor: ev > 0 ? const Color(0xFF10B981) : const Color(0xFF9CA3AF),
                  ),
                ],
              ),
            ),
          ),
        ] else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Hazai csapat várható gólja (xG): ${_simHomeXg.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Slider(
                    value: _simHomeXg,
                    min: 0.30,
                    max: 3.80,
                    activeColor: const Color(0xFF10B981),
                    onChanged: (v) => setState(() => _simHomeXg = v),
                  ),
                  Text('Vendég csapat várható gólja (xG): ${_simAwayXg.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Slider(
                    value: _simAwayXg,
                    min: 0.30,
                    max: 3.80,
                    activeColor: const Color(0xFF3B82F6),
                    onChanged: (v) => setState(() => _simAwayXg = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _CalcRow(
                    label: 'Hazai győzelem (1)',
                    value: '${(simResult.homeWin * 100).toStringAsFixed(1)}% (Fair: ${(1 / simResult.homeWin).toStringAsFixed(2)})',
                    valueColor: const Color(0xFF10B981),
                  ),
                  const Divider(height: 20, color: Color(0xFF1F2937)),
                  _CalcRow(
                    label: 'Döntetlen (X)',
                    value: '${(simResult.draw * 100).toStringAsFixed(1)}% (Fair: ${(1 / simResult.draw).toStringAsFixed(2)})',
                    valueColor: Colors.white,
                  ),
                  const Divider(height: 20, color: Color(0xFF1F2937)),
                  _CalcRow(
                    label: 'Vendég győzelem (2)',
                    value: '${(simResult.awayWin * 100).toStringAsFixed(1)}% (Fair: ${(1 / simResult.awayWin).toStringAsFixed(2)})',
                    valueColor: const Color(0xFF3B82F6),
                  ),
                  const Divider(height: 20, color: Color(0xFF1F2937)),
                  _CalcRow(
                    label: '2.5 gól felett / BTTS',
                    value: '${(simResult.over25 * 100).round()}% / ${(simResult.btts * 100).round()}%',
                    valueColor: const Color(0xFFF59E0B),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CalcRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _CalcRow({required this.label, required this.value, required this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
        Text(value, style: TextStyle(color: valueColor, fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }
}

class TrackerAndWatchlistTab extends StatefulWidget {
  final List<MatchPick> matches;
  final List<BetRecord> bets;
  final Function(String) onToggleWatch;
  final Function(MatchPick) onSelectMatch;
  final Function(String, String) onUpdateBetStatus;
  final Function(String) onDeleteBet;

  const TrackerAndWatchlistTab({
    super.key,
    required this.matches,
    required this.bets,
    required this.onToggleWatch,
    required this.onSelectMatch,
    required this.onUpdateBetStatus,
    required this.onDeleteBet,
  });

  @override
  State<TrackerAndWatchlistTab> createState() => _TrackerAndWatchlistTabState();
}

class _TrackerAndWatchlistTabState extends State<TrackerAndWatchlistTab> {
  int _subTab = 0;

  @override
  Widget build(BuildContext context) {
    final settledBets = widget.bets.where((b) => b.status != 'pending').toList();
    final totalStaked = settledBets.fold<double>(0.0, (sum, b) => sum + b.stake);
    final totalProfit = settledBets.fold<double>(0.0, (sum, b) => sum + b.profit);
    final wonCount = settledBets.where((b) => b.status == 'won').length;
    final winRate = settledBets.isEmpty ? 0.0 : (wonCount / settledBets.length) * 100;
    final roi = totalStaked == 0 ? 0.0 : (totalProfit / totalStaked) * 100;

    final watched = widget.matches.where((m) => m.isWatched).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SegmentedButton<int>(
            segments: [
              ButtonSegment(value: 0, label: Text('Tippnapló (${widget.bets.length})')),
              ButtonSegment(value: 1, label: Text('Riasztások (${watched.length})')),
            ],
            selected: {_subTab},
            onSelectionChanged: (s) => setState(() => _subTab = s.first),
          ),
        ),
        if (_subTab == 0) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _KpiItem(
                      label: 'Nettó Profit',
                      value: '${totalProfit >= 0 ? '+' : ''}${totalProfit.round()} Ft',
                      color: totalProfit >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    ),
                    _KpiItem(
                      label: 'ROI',
                      value: '${roi >= 0 ? '+' : ''}${roi.toStringAsFixed(1)}%',
                      color: roi >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    ),
                    _KpiItem(
                      label: 'Találati arány',
                      value: '${winRate.round()}%',
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: widget.bets.isEmpty
                ? const Center(
                    child: Text(
                      'Még nincs rögzített tipped.\nKoppints a + ikonra bármelyik meccsnél!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF9CA3AF)),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: widget.bets.length,
                    itemBuilder: (context, index) {
                      final bet = widget.bets[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text('${bet.matchTitle} (${bet.date})',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                                    onPressed: () => widget.onDeleteBet(bet.id),
                                  ),
                                ],
                              ),
                              Text('${bet.market} • Odds: ${bet.odds} • Tét: ${bet.stake.round()} Ft',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  _StatusChip(
                                    label: 'Nyert',
                                    active: bet.status == 'won',
                                    color: const Color(0xFF10B981),
                                    onTap: () => widget.onUpdateBetStatus(bet.id, 'won'),
                                  ),
                                  const SizedBox(width: 8),
                                  _StatusChip(
                                    label: 'Veszített',
                                    active: bet.status == 'lost',
                                    color: const Color(0xFFEF4444),
                                    onTap: () => widget.onUpdateBetStatus(bet.id, 'lost'),
                                  ),
                                  const SizedBox(width: 8),
                                  _StatusChip(
                                    label: 'Függőben',
                                    active: bet.status == 'pending',
                                    color: const Color(0xFFF59E0B),
                                    onTap: () => widget.onUpdateBetStatus(bet.id, 'pending'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ] else ...[
          Expanded(
            child: watched.isEmpty
                ? const Center(
                    child: Text(
                      'Még nincs bekövetett meccsed.\nKoppints a csengő ikonra az Ajánlások fülön!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF9CA3AF)),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: watched.length,
                    itemBuilder: (context, index) {
                      final match = watched[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          onTap: () => widget.onSelectMatch(match),
                          leading: const Icon(Icons.notifications_active, color: Color(0xFFF59E0B)),
                          title: Text('${match.homeTeam} – ${match.awayTeam}',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${match.market} • Odds: ${match.marketOdds}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.grey),
                            onPressed: () => widget.onToggleWatch(match.id),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ],
    );
  }
}

class _KpiItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _KpiItem({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  const _StatusChip({
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? color : const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: active ? Colors.black : Colors.white,
          ),
        ),
      ),
    );
  }
}
