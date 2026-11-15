import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

typedef JsonMap = Map<String, dynamic>;
typedef JsonList = List<JsonMap>;
typedef StandingsMap = Map<int, TeamStandingInfo>;
typedef StandingRowList = List<TeamStandingInfo>;
typedef StringList = List<String>;
typedef DoubleList = List<double>;
typedef CurveList = List<DoubleList>;
typedef BoolList = List<bool>;
typedef MatchList = List<MatchPick>;
typedef BetList = List<BetRecord>;
typedef ScoreProbList = List<ScoreProbability>;
typedef MarketOptionList = List<MarketOption>;
typedef StringDoubleMap = Map<String, double>;

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
// 1. DIXON-COLES & POISSON MATEMATIKAI MOTOR
// ==========================================

class ScoreProbability {
  final String score;
  final double probability;

  ScoreProbability(this.score, this.probability);
}

class MarketOption {
  final String code;
  final String label;
  final double probability;
  final double fairOdds;
  final double refOdds;
  final double edgePercent;

  MarketOption({
    required this.code,
    required this.label,
    required this.probability,
    required this.fairOdds,
    required this.refOdds,
    required this.edgePercent,
  });
}

class PoissonResult {
  final double homeWin;
  final double draw;
  final double awayWin;
  final double doubleChance1X;
  final double doubleChanceX2;
  final double dnbHome;
  final double over15;
  final double over25;
  final double under25;
  final double btts;
  final double homeOver15;
  final ScoreProbList topScores;
  final MarketOptionList allMarkets;

  PoissonResult({
    required this.homeWin,
    required this.draw,
    required this.awayWin,
    required this.doubleChance1X,
    required this.doubleChanceX2,
    required this.dnbHome,
    required this.over15,
    required this.over25,
    required this.under25,
    required this.btts,
    required this.homeOver15,
    required this.topScores,
    required this.allMarkets,
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

  static double _dixonColesTau(int h, int a, double lambdaH, double lambdaA, double rho) {
    if (h == 0 && a == 0) return (1.0 - (lambdaH * lambdaA * rho)).clamp(0.15, 2.2);
    if (h == 0 && a == 1) return (1.0 + (lambdaH * rho)).clamp(0.15, 2.2);
    if (h == 1 && a == 0) return (1.0 + (lambdaA * rho)).clamp(0.15, 2.2);
    if (h == 1 && a == 1) return (1.0 - rho).clamp(0.15, 2.2);
    return 1.0;
  }

  static PoissonResult calculate(double homeXg, double awayXg, {double rho = -0.085}) {
    final CurveList grid = List.generate(8, (_) => List.filled(8, 0.0));
    double totalMass = 0.0;

    for (int h = 0; h <= 7; h++) {
      final ph = _pmf(homeXg, h);
      for (int a = 0; a <= 7; a++) {
        final pa = _pmf(awayXg, a);
        final tau = _dixonColesTau(h, a, homeXg, awayXg, rho);
        final p = ph * pa * tau;
        grid[h][a] = p;
        totalMass += p;
      }
    }

    double pHome = 0.0;
    double pDraw = 0.0;
    double pAway = 0.0;
    double pOver15 = 0.0;
    double pOver25 = 0.0;
    double pBtts = 0.0;
    double pHomeOver15 = 0.0;
    final ScoreProbList scores = [];

    final norm = totalMass > 0 ? totalMass : 1.0;

    for (int h = 0; h <= 7; h++) {
      for (int a = 0; a <= 7; a++) {
        final prob = grid[h][a] / norm;
        if (h > a) {
          pHome += prob;
        } else if (h == a) {
          pDraw += prob;
        } else {
          pAway += prob;
        }
        if (h + a > 1) pOver15 += prob;
        if (h + a > 2) pOver25 += prob;
        if (h > 0 && a > 0) pBtts += prob;
        if (h > 1) pHomeOver15 += prob;
        if (h <= 5 && a <= 5) {
          scores.add(ScoreProbability('$h-$a', prob));
        }
      }
    }

    scores.sort((a, b) => b.probability.compareTo(a.probability));

    final p1 = pHome.clamp(0.02, 0.96);
    final pX = pDraw.clamp(0.02, 0.90);
    final p2 = pAway.clamp(0.02, 0.96);
    final p1X = (p1 + pX).clamp(0.05, 0.98);
    final pX2 = (pX + p2).clamp(0.05, 0.98);
    final pDnbHome = (p1 / (p1 + p2)).clamp(0.05, 0.96);
    final pO15 = pOver15.clamp(0.05, 0.98);
    final pO25 = pOver25.clamp(0.03, 0.96);
    final pU25 = (1.0 - pO25).clamp(0.03, 0.96);
    final pGg = pBtts.clamp(0.03, 0.96);
    final pHo15 = pHomeOver15.clamp(0.03, 0.96);

    MarketOption buildOpt(String code, String label, double prob, double edgeBoost) {
      final fair = 1.0 / prob;
      final ref = double.parse((fair * edgeBoost).clamp(1.18, 5.50).toStringAsFixed(2));
      final edge = (prob - (1.0 / ref)) * 100.0;
      return MarketOption(
        code: code,
        label: label,
        probability: prob,
        fairOdds: double.parse(fair.toStringAsFixed(2)),
        refOdds: ref,
        edgePercent: edge,
      );
    }

    final MarketOptionList options = [
      buildOpt('home', 'Hazai győzelem (1)', p1, 1.07),
      buildOpt('draw', 'Döntetlen (X)', pX, 1.06),
      buildOpt('away', 'Vendég győzelem (2)', p2, 1.07),
      buildOpt('1x', 'Dupla esély (1X)', p1X, 1.05),
      buildOpt('x2', 'Dupla esély (X2)', pX2, 1.05),
      buildOpt('dnb_home', 'Hazai DNB (Tét visszajár)', pDnbHome, 1.06),
      buildOpt('over15', '1.5 gól felett', pO15, 1.05),
      buildOpt('over25', '2.5 gól felett', pO25, 1.09),
      buildOpt('under25', '2.5 gól alatt', pU25, 1.08),
      buildOpt('btts', 'Mindkét csapat szerez gólt (BTTS)', pGg, 1.09),
      buildOpt('home_over15', 'Hazai csapat 1.5 gól felett', pHo15, 1.08),
    ];

    return PoissonResult(
      homeWin: p1,
      draw: pX,
      awayWin: p2,
      doubleChance1X: p1X,
      doubleChanceX2: pX2,
      dnbHome: pDnbHome,
      over15: pO15,
      over25: pO25,
      under25: pU25,
      btts: pGg,
      homeOver15: pHo15,
      topScores: scores.take(3).toList(),
      allMarkets: options,
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
  final JsonList form;

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
  int get goalDiff => goalsFor - goalsAgainst;
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
  bool isCustomOdds;
  DoubleList oddsHistory;
  double homeXg;
  double awayXg;
  BoolList last6Trend;
  StringList homeFormCodes;
  StringList awayFormCodes;
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
    this.isCustomOdds = false,
    required this.oddsHistory,
    required this.homeXg,
    required this.awayXg,
    required this.last6Trend,
    this.homeFormCodes = const ['W', 'W', 'D', 'W', 'L'],
    this.awayFormCodes = const ['L', 'W', 'D', 'W', 'W'],
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

  int get parsedMinute {
    if (minute == null) return 0;
    if (minute == 'HT') return 45;
    final clean = minute!.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(clean) ?? 0;
  }

  bool get isHighPressure {
    if (!isLive) return false;
    final min = parsedMinute;
    final diff = ((homeScore ?? 0) - (awayScore ?? 0)).abs();
    return min >= 60 && diff <= 1 && (homeXg + awayXg) >= 2.35;
  }

  JsonMap toJson() => {
        'id': id,
        'fixtureId': fixtureId,
        'leagueId': leagueId,
        'homeId': homeId,
        'awayId': awayId,
        'league': league,
        'leagueZone': leagueZone,
        'kickoff': kickoff,
        'status': status,
        'minute': minute,
        'homeScore': homeScore,
        'awayScore': awayScore,
        'homeTeam': homeTeam,
        'awayTeam': awayTeam,
        'market': market,
        'marketCode': marketCode,
        'trendSummary': trendSummary,
        'trendCategory': trendCategory,
        'modelProb': modelProb,
        'marketOdds': marketOdds,
        'isCustomOdds': isCustomOdds,
        'oddsHistory': oddsHistory,
        'homeXg': homeXg,
        'awayXg': awayXg,
        'last6Trend': last6Trend,
        'homeFormCodes': homeFormCodes,
        'awayFormCodes': awayFormCodes,
        'homePos': homePos,
        'awayPos': awayPos,
        'hasStandingData': hasStandingData,
        'isWatched': isWatched,
      };

  factory MatchPick.fromJson(JsonMap json) => MatchPick(
        id: json['id'] ?? '',
        fixtureId: (json['fixtureId'] as num?)?.toInt(),
        leagueId: (json['leagueId'] as num?)?.toInt(),
        homeId: (json['homeId'] as num?)?.toInt(),
        awayId: (json['awayId'] as num?)?.toInt(),
        league: json['league'] ?? 'Bajnokság',
        leagueZone: json['leagueZone'] ?? '',
        kickoff: json['kickoff'] ?? 'Ma',
        status: json['status'] ?? 'Scheduled',
        minute: json['minute']?.toString(),
        homeScore: (json['homeScore'] as num?)?.toInt(),
        awayScore: (json['awayScore'] as num?)?.toInt(),
        homeTeam: json['homeTeam'] ?? 'Hazai',
        awayTeam: json['awayTeam'] ?? 'Vendég',
        market: json['market'] ?? '2.5 gól felett',
        marketCode: json['marketCode'] ?? 'over25',
        trendSummary: json['trendSummary'] ?? '',
        trendCategory: json['trendCategory'] ?? 'Gólok / BTTS',
        modelProb: (json['modelProb'] as num?)?.toDouble() ?? 0.55,
        marketOdds: (json['marketOdds'] as num?)?.toDouble() ?? 1.85,
        isCustomOdds: json['isCustomOdds'] == true,
        oddsHistory: (json['oddsHistory'] is List)
            ? (json['oddsHistory'] as List).map((e) => (e as num).toDouble()).toList()
            : [1.90, 1.85],
        homeXg: (json['homeXg'] as num?)?.toDouble() ?? 1.50,
        awayXg: (json['awayXg'] as num?)?.toDouble() ?? 1.20,
        last6Trend: (json['last6Trend'] is List)
            ? (json['last6Trend'] as List).map((e) => e == true).toList()
            : [true, true, false, true, true, true],
        homeFormCodes: (json['homeFormCodes'] is List)
            ? (json['homeFormCodes'] as List).map((e) => e.toString()).toList()
            : ['W', 'W', 'D', 'W', 'L'],
        awayFormCodes: (json['awayFormCodes'] is List)
            ? (json['awayFormCodes'] as List).map((e) => e.toString()).toList()
            : ['L', 'W', 'D', 'W', 'W'],
        homePos: (json['homePos'] as num?)?.toInt(),
        awayPos: (json['awayPos'] as num?)?.toInt(),
        hasStandingData: json['hasStandingData'] == true,
        isWatched: json['isWatched'] == true,
      );
}

class FixtureFullBundle {
  final String? stadium;
  final String? city;
  final String? homeCoach;
  final String? awayCoach;
  final int? htHome;
  final int? htAway;
  final JsonList events;
  final JsonMap? homeStats;
  final JsonMap? awayStats;
  final bool lineupsAvailable;
  final JsonList homeStarters;
  final JsonList homeSubs;
  final JsonList awayStarters;
  final JsonList awaySubs;
  final StandingRowList standings;

  FixtureFullBundle({
    this.stadium,
    this.city,
    this.homeCoach,
    this.awayCoach,
    this.htHome,
    this.htAway,
    this.events = const [],
    this.homeStats,
    this.awayStats,
    this.lineupsAvailable = false,
    this.homeStarters = const [],
    this.homeSubs = const [],
    this.awayStarters = const [],
    this.awaySubs = const [],
    this.standings = const [],
  });
}

class BetRecord {
  final String id;
  final int? fixtureId;
  final String matchTitle;
  final String market;
  final String marketCode;
  final double odds;
  final double? closingOdds;
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
    this.closingOdds,
    required this.stake,
    required this.status,
    required this.date,
  });

  double get profit {
    if (status == 'won') return (stake * odds) - stake;
    if (status == 'lost') return -stake;
    return 0.0;
  }

  double? get clvPercent {
    if (closingOdds == null || closingOdds! <= 1.0) return null;
    return ((odds / closingOdds!) - 1.0) * 100.0;
  }

  JsonMap toJson() => {
        'id': id,
        'fixtureId': fixtureId,
        'matchTitle': matchTitle,
        'market': market,
        'marketCode': marketCode,
        'odds': odds,
        'closingOdds': closingOdds,
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
        closingOdds: (json['closingOdds'] as num?)?.toDouble(),
        stake: (json['stake'] as num?)?.toDouble() ?? 1000.0,
        status: json['status'] ?? 'pending',
        date: json['date'] ?? '',
      );
}

// ==========================================
// 3. SPORTAPI.AI KLIENS (ETAG + KALIBRÁCIÓ)
// ==========================================

class SportApiResponse {
  final bool success;
  final int statusCode;
  final MatchList matches;
  final String rawPreview;
  final String message;
  final String? rateLimitRemaining;
  final bool fromEtagCache;

  SportApiResponse({
    required this.success,
    required this.statusCode,
    required this.matches,
    required this.rawPreview,
    required this.message,
    this.rateLimitRemaining,
    this.fromEtagCache = false,
  });
}

class SportApiService {
  static const String defaultBaseUrl = 'https://sportapi.ai/api';
  static final Map<int, StandingsMap> _standingsCache = {};
  static final Map<String, String> _etagCache = {};
  static final Map<String, String> _bodyCache = {};

  static String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  static Future<http.Response> _getWithEtag(Uri uri, String apiKey) async {
    final key = uri.toString();
    final headers = <String, String>{
      'Accept': 'application/json',
      'X-Api-Key': apiKey.trim(),
    };
    if (_etagCache.containsKey(key) && _bodyCache.containsKey(key)) {
      headers['If-None-Match'] = _etagCache[key]!;
    }

    final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
    if (res.statusCode == 304 && _bodyCache.containsKey(key)) {
      return http.Response(_bodyCache[key]!, 200, headers: res.headers);
    }
    if (res.statusCode == 200) {
      final etag = res.headers['etag'];
      if (etag != null && etag.isNotEmpty) {
        _etagCache[key] = etag;
        _bodyCache[key] = utf8.decode(res.bodyBytes, allowMalformed: true);
      }
    }
    return res;
  }

  static double leagueAvgGoals(StandingsMap table) {
    if (table.isEmpty) return 1.38;
    int totalGoals = 0;
    int totalMatches = 0;
    for (final row in table.values) {
      totalGoals += row.goalsFor;
      totalMatches += row.played;
    }
    if (totalMatches == 0) return 1.38;
    return (totalGoals / totalMatches).clamp(0.95, 2.15);
  }

  static StringList extractWdlCodes(TeamStandingInfo info) {
    final StringList codes = [];
    for (final f in info.form.take(5)) {
      final res = (f['result'] ?? '').toString().toUpperCase();
      if (res == 'W' || res == 'D' || res == 'L') {
        codes.add(res);
      } else {
        final hg = (f['home_score'] as num?)?.toInt() ?? 0;
        final ag = (f['away_score'] as num?)?.toInt() ?? 0;
        final isHome = (f['home_team'] ?? '').toString() == info.teamName;
        if (hg == ag) {
          codes.add('D');
        } else if ((isHome && hg > ag) || (!isHome && ag > hg)) {
          codes.add('W');
        } else {
          codes.add('L');
        }
      }
    }
    if (codes.isEmpty) return ['W', 'D', 'W', 'L', 'W'];
    return codes;
  }

  static Future<SportApiResponse> fetchFixturesByDate({
    required String baseUrl,
    required String apiKey,
    required DateTime targetDate,
    required String dayLabel,
    required StringList watchedIds,
    required StringDoubleMap customOddsMap,
  }) async {
    final cleanBase = baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    final dateStr = _formatDate(targetDate);
    final uri = Uri.parse('$cleanBase/fixtures/date/$dateStr');

    try {
      final response = await _getWithEtag(uri, apiKey);
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

      final JsonList sortedRaw = [];
      for (final el in dataList) {
        if (el is JsonMap) {
          sortedRaw.add(el);
        }
      }

      sortedRaw.sort((a, b) {
        final aLive = a['status'] == 'LIVE' ? 0 : 1;
        final bLive = b['status'] == 'LIVE' ? 0 : 1;
        if (aLive != bLive) return aLive.compareTo(bLive);

        final aLeague = (a['league_name'] ?? '').toString();
        final bLeague = (b['league_name'] ?? '').toString();
        final aPrio = topLeagueNames.contains(aLeague) ? 0 : 1;
        final bPrio = topLeagueNames.contains(bLeague) ? 0 : 1;
        if (aPrio != bPrio) return aPrio.compareTo(bPrio);
        return (a['datetime'] ?? '').toString().compareTo((b['datetime'] ?? '').toString());
      });

      final MatchList parsed = [];
      for (final item in sortedRaw.take(50)) {
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
        BoolList trendList = List.generate(6, (_) => rng.nextDouble() > 0.3);
        StringList hForm = ['W', 'D', 'W', 'W', 'L'];
        StringList aForm = ['L', 'W', 'D', 'L', 'W'];

        if (leagueId != null && _standingsCache.containsKey(leagueId)) {
          final table = _standingsCache[leagueId]!;
          final hInfo = homeId != null ? table[homeId] : null;
          final aInfo = awayId != null ? table[awayId] : null;
          if (hInfo != null && aInfo != null && hInfo.played > 0 && aInfo.played > 0) {
            final lAvg = leagueAvgGoals(table);
            final hAttack = hInfo.avgGoalsFor / lAvg;
            final aDefense = aInfo.avgGoalsAgainst / lAvg;
            final aAttack = aInfo.avgGoalsFor / lAvg;
            final hDefense = hInfo.avgGoalsAgainst / lAvg;

            hXg = (hAttack * aDefense * lAvg * 1.12).clamp(0.45, 3.6);
            aXg = (aAttack * hDefense * lAvg * 0.94).clamp(0.35, 3.2);
            homePos = hInfo.position;
            awayPos = aInfo.position;
            hasStandings = true;
            trendList = _extractFormTrend(hInfo, aInfo);
            hForm = extractWdlCodes(hInfo);
            aForm = extractWdlCodes(aInfo);
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
          homeFormCodes: hForm,
          awayFormCodes: aForm,
          homePos: homePos,
          awayPos: awayPos,
          hasStandingData: hasStandings,
          isWatched: watchedIds.contains(matchId),
          customOdds: customOddsMap[matchId],
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

  static BoolList _extractFormTrend(TeamStandingInfo home, TeamStandingInfo away) {
    final BoolList hits = [];
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
    required BoolList last6Trend,
    required StringList homeFormCodes,
    required StringList awayFormCodes,
    int? homePos,
    int? awayPos,
    required bool hasStandingData,
    required bool isWatched,
    double? customOdds,
  }) {
    final poisson = PoissonEngine.calculate(homeXg, awayXg);

    // Legjobb piaci opció kiválasztása Dixon-Coles alapján
    MarketOption best = poisson.allMarkets.first;
    for (final opt in poisson.allMarkets) {
      if (opt.probability >= 0.48 && opt.edgePercent > best.edgePercent) {
        best = opt;
      }
    }

    String category = 'xG eltérés';
    if (best.code.contains('over') || best.code.contains('under') || best.code == 'btts') {
      category = 'Gólok / BTTS';
    } else if (hasStandingData) {
      category = 'Tabella & Forma';
    }

    final finalOdds = customOdds ?? best.refOdds;

    String summary;
    if (hasStandingData && homePos != null && awayPos != null) {
      summary =
          'Dixon-Coles • Tabella: $homePos. hely vs $awayPos. hely • Liga-kalibrált xG: ${homeXg.toStringAsFixed(2)} – ${awayXg.toStringAsFixed(2)} (BTTS: ${(poisson.btts * 100).round()}%).';
    } else {
      summary =
          'Dixon-Coles modell: várható összgól ${(homeXg + awayXg).toStringAsFixed(2)}, 2.5+ gól ${(poisson.over25 * 100).round()}%, BTTS ${(poisson.btts * 100).round()}%.';
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
      market: best.label,
      marketCode: best.code,
      trendSummary: summary,
      trendCategory: category,
      modelProb: best.probability,
      marketOdds: finalOdds,
      isCustomOdds: customOdds != null,
      oddsHistory: [
        double.parse((best.refOdds + 0.14).toStringAsFixed(2)),
        double.parse((best.refOdds + 0.08).toStringAsFixed(2)),
        double.parse((best.refOdds + 0.03).toStringAsFixed(2)),
        finalOdds,
      ],
      homeXg: double.parse(homeXg.toStringAsFixed(2)),
      awayXg: double.parse(awayXg.toStringAsFixed(2)),
      last6Trend: last6Trend,
      homeFormCodes: homeFormCodes,
      awayFormCodes: awayFormCodes,
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
      final response = await _getWithEtag(uri, apiKey);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
        final List<dynamic> rows = (decoded is Map && decoded['data'] is List) ? decoded['data'] : [];
        final StandingsMap map = {};

        for (final row in rows) {
          if (row is! Map) continue;
          final teamObj = row['team'];
          final teamId = (teamObj is Map ? (teamObj['id'] as num?)?.toInt() : null) ?? 0;
          if (teamId == 0) continue;

          final JsonList formList = [];
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

  static Future<FixtureFullBundle?> fetchFullBundle({
    required String baseUrl,
    required String apiKey,
    required int fixtureId,
    int? leagueId,
  }) async {
    final cleanBase = baseUrl.trim().replaceAll(RegExp(r'/$'), '');

    try {
      final f0 = _getWithEtag(Uri.parse('$cleanBase/fixtures/$fixtureId'), apiKey);
      final f1 = _getWithEtag(Uri.parse('$cleanBase/fixtures/$fixtureId/stats'), apiKey);
      final f2 = _getWithEtag(Uri.parse('$cleanBase/fixtures/$fixtureId/lineups'), apiKey);

      final r0 = await f0;
      final r1 = await f1;
      final r2 = await f2;

      JsonMap? fixtureObj;
      if (r0.statusCode == 200) {
        final d0 = jsonDecode(utf8.decode(r0.bodyBytes, allowMalformed: true));
        if (d0 is Map && d0['fixture'] is JsonMap) {
          fixtureObj = d0['fixture'];
        }
      }

      JsonMap? homeStats;
      JsonMap? awayStats;
      if (r1.statusCode == 200) {
        final d1 = jsonDecode(utf8.decode(r1.bodyBytes, allowMalformed: true));
        if (d1 is Map && d1['available'] == true && d1['data'] is Map) {
          homeStats = d1['data']['home'] as JsonMap?;
          awayStats = d1['data']['away'] as JsonMap?;
        }
      }

      bool lineupsAvail = false;
      final JsonList homeStarters = [];
      final JsonList homeSubs = [];
      final JsonList awayStarters = [];
      final JsonList awaySubs = [];

      if (r2.statusCode == 200) {
        final d2 = jsonDecode(utf8.decode(r2.bodyBytes, allowMalformed: true));
        if (d2 is Map && d2['available'] == true && d2['data'] is Map) {
          lineupsAvail = true;
          final hObj = d2['data']['home'];
          final aObj = d2['data']['away'];
          if (hObj is Map && hObj['starters'] is List) {
            for (final p in hObj['starters']) {
              if (p is JsonMap) homeStarters.add(p);
            }
          }
          if (hObj is Map && hObj['subs'] is List) {
            for (final p in hObj['subs']) {
              if (p is JsonMap) homeSubs.add(p);
            }
          }
          if (aObj is Map && aObj['starters'] is List) {
            for (final p in aObj['starters']) {
              if (p is JsonMap) awayStarters.add(p);
            }
          }
          if (aObj is Map && aObj['subs'] is List) {
            for (final p in aObj['subs']) {
              if (p is JsonMap) awaySubs.add(p);
            }
          }
        }
      }

      final JsonList eventsList = [];
      if (fixtureObj?['events'] is List) {
        for (final ev in fixtureObj!['events']) {
          if (ev is JsonMap) {
            eventsList.add(ev);
          }
        }
      }

      StandingRowList standingRows = [];
      if (leagueId != null) {
        final tableMap = await fetchStandings(
          baseUrl: baseUrl,
          apiKey: apiKey,
          leagueId: leagueId,
        );
        standingRows = tableMap.values.toList()..sort((a, b) => a.position.compareTo(b.position));
      }

      return FixtureFullBundle(
        stadium: fixtureObj?['home_stadium']?.toString(),
        city: fixtureObj?['home_city']?.toString(),
        homeCoach: fixtureObj?['home_coach']?.toString(),
        awayCoach: fixtureObj?['away_coach']?.toString(),
        htHome: (fixtureObj?['ht_home'] as num?)?.toInt(),
        htAway: (fixtureObj?['ht_away'] as num?)?.toInt(),
        events: eventsList,
        homeStats: homeStats,
        awayStats: awayStats,
        lineupsAvailable: lineupsAvail,
        homeStarters: homeStarters,
        homeSubs: homeSubs,
        awayStarters: awayStarters,
        awaySubs: awaySubs,
        standings: standingRows,
      );
    } catch (_) {
      return null;
    }
  }
}

// ==========================================
// 4. CSAPATLOGÓ & W-D-L FORMA KOMPONENSEK
// ==========================================

class TeamLogoBadge extends StatelessWidget {
  final int? teamId;
  final String teamName;
  final String baseUrl;
  final String apiKey;
  final double size;

  const TeamLogoBadge({
    super.key,
    required this.teamId,
    required this.teamName,
    required this.baseUrl,
    required this.apiKey,
    this.size = 24,
  });

  String get _initials {
    final parts = teamName.trim().split(' ');
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return teamName.length >= 2 ? teamName.substring(0, 2).toUpperCase() : 'FC';
  }

  Widget _fallback() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF374151), width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        _initials,
        style: TextStyle(fontSize: size * 0.38, fontWeight: FontWeight.bold, color: const Color(0xFF9CA3AF)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (teamId == null || teamId == 0 || apiKey.trim().isEmpty) {
      return _fallback();
    }
    final cleanBase = baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    final logoUrl = '$cleanBase/teams/$teamId/logo';

    return ClipOval(
      child: Image.network(
        logoUrl,
        width: size,
        height: size,
        fit: BoxFit.contain,
        headers: {'X-Api-Key': apiKey.trim()},
        errorBuilder: (_, __, ___) => _fallback(),
      ),
    );
  }
}

class WdlStrip extends StatelessWidget {
  final StringList codes;

  const WdlStrip({super.key, required this.codes});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: codes.take(5).map((c) {
        final up = c.toUpperCase();
        Color bg = const Color(0xFF374151);
        String hu = 'D';
        if (up == 'W') {
          bg = const Color(0xFF10B981);
          hu = 'GY';
        } else if (up == 'L') {
          bg = const Color(0xFFEF4444);
          hu = 'V';
        }
        return Container(
          margin: const EdgeInsets.only(right: 3),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
          child: Text(
            hu,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: up == 'W' ? Colors.black : Colors.white,
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ==========================================
// 5. FŐ KÉPERNYŐ ÉS ÁLLAPOTKEZELÉS
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
  bool _autoLiveRadar = false;
  Timer? _liveTimer;

  String _apiKey = '';
  String _baseUrl = SportApiService.defaultBaseUrl;
  String _lastApiStatus = 'Még nem futott élő lekérés.';
  String? _rateLimitRemaining;

  double _bankroll = 50000;
  MatchList _matches = [];
  BetList _bets = [];
  final StringList _slipMatchIds = [];
  final StringDoubleMap _customOddsMap = {};

  @override
  void initState() {
    super.initState();
    _matches = _buildDemoMatches();
    _loadSavedData();
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  void _toggleAutoLiveRadar() {
    setState(() {
      _autoLiveRadar = !_autoLiveRadar;
    });
    _liveTimer?.cancel();
    if (_autoLiveRadar) {
      _liveTimer = Timer.periodic(const Duration(seconds: 75), (_) {
        if (_apiKey.isNotEmpty && !_isLoadingApi) {
          _syncSportApi(silent: true);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Élő Radar aktiválva (75 mp ETag frissítés).')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Élő Radar kikapcsolva.')),
      );
    }
  }

  MatchList _buildDemoMatches() {
    return [
      MatchPick(
        id: 'm1',
        league: 'Premier League',
        kickoff: 'Ma 18:30',
        homeTeam: 'Arsenal',
        awayTeam: 'Aston Villa',
        market: 'Mindkét csapat szerez gólt (BTTS)',
        marketCode: 'btts',
        trendSummary: 'Dixon-Coles: az utolsó 6 bajnoki meccsből 5-ször mindkét fél betalált.',
        trendCategory: 'Gólok / BTTS',
        modelProb: PoissonEngine.calculate(2.15, 1.48).btts,
        marketOdds: 1.72,
        oddsHistory: [1.88, 1.84, 1.80, 1.76, 1.72],
        homeXg: 2.15,
        awayXg: 1.48,
        last6Trend: [true, true, true, false, true, true],
        homeFormCodes: ['W', 'W', 'D', 'W', 'W'],
        awayFormCodes: ['W', 'L', 'W', 'D', 'W'],
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
        trendSummary: 'Dixon-Coles: a Paks idegenbeli meccsein 3.4-es a gólátlag, az FTC hazai xG-je 2.35.',
        trendCategory: 'Gólok / BTTS',
        modelProb: PoissonEngine.calculate(2.35, 1.32).over25,
        marketOdds: 1.65,
        oddsHistory: [1.78, 1.75, 1.70, 1.68, 1.65],
        homeXg: 2.35,
        awayXg: 1.32,
        last6Trend: [true, true, true, true, false, true],
        homeFormCodes: ['W', 'W', 'W', 'D', 'W'],
        awayFormCodes: ['W', 'W', 'L', 'W', 'D'],
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
        trendSummary: 'Dixon-Coles & xG előny: a Sociedad hazai pályán dominál, 1.98-as várható góllal.',
        trendCategory: 'Tabella & Forma',
        modelProb: PoissonEngine.calculate(1.98, 1.05).homeWin,
        marketOdds: 2.15,
        oddsHistory: [2.35, 2.28, 2.22, 2.18, 2.15],
        homeXg: 1.98,
        awayXg: 1.05,
        last6Trend: [true, false, true, true, true, true],
        homeFormCodes: ['W', 'D', 'W', 'W', 'L'],
        awayFormCodes: ['L', 'D', 'L', 'W', 'D'],
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
    final watchedIds = prefs.getStringList('watched_ids') ?? [];
    final betsJson = prefs.getString('logged_bets');
    final cachedMatchesJson = prefs.getString('cached_matches_v4');
    final customOddsJson = prefs.getString('custom_odds_map');

    setState(() {
      _apiKey = savedKey;
      _baseUrl = savedBase;
      _bankroll = savedBankroll;

      if (customOddsJson != null) {
        final decodedOdds = jsonDecode(customOddsJson);
        if (decodedOdds is Map) {
          decodedOdds.forEach((k, v) {
            if (v is num) _customOddsMap[k.toString()] = v.toDouble();
          });
        }
      }

      if (cachedMatchesJson != null && savedKey.isNotEmpty) {
        final List<dynamic> decodedCached = jsonDecode(cachedMatchesJson);
        final MatchList restored = [];
        for (final item in decodedCached) {
          if (item is JsonMap) {
            final m = MatchPick.fromJson(item);
            m.isWatched = watchedIds.contains(m.id);
            if (_customOddsMap.containsKey(m.id)) {
              m.marketOdds = _customOddsMap[m.id]!;
              m.isCustomOdds = true;
            }
            restored.add(m);
          }
        }
        if (restored.isNotEmpty) {
          _matches = restored;
          _isLiveMode = true;
        }
      } else {
        for (final m in _matches) {
          m.isWatched = watchedIds.contains(m.id);
        }
      }

      if (betsJson != null) {
        final List<dynamic> decoded = jsonDecode(betsJson);
        final BetList loadedBets = [];
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
    await prefs.setString('custom_odds_map', jsonEncode(_customOddsMap));
    if (_isLiveMode && _matches.isNotEmpty) {
      await prefs.setString('cached_matches_v4', jsonEncode(_matches.map((m) => m.toJson()).toList()));
    }
  }

  String _exportBackupJson() {
    final backup = <String, dynamic>{
      'version': 4,
      'apiKey': _apiKey,
      'baseUrl': _baseUrl,
      'bankroll': _bankroll,
      'customOdds': _customOddsMap,
      'watchedIds': _matches.where((m) => m.isWatched).map((m) => m.id).toList(),
      'bets': _bets.map((b) => b.toJson()).toList(),
    };
    return jsonEncode(backup);
  }

  Future<bool> _importBackupJson(String rawJson) async {
    try {
      final decoded = jsonDecode(rawJson.trim());
      if (decoded is! Map) return false;

      final prefs = await SharedPreferences.getInstance();
      setState(() {
        if (decoded['apiKey'] is String) _apiKey = decoded['apiKey'];
        if (decoded['baseUrl'] is String) _baseUrl = decoded['baseUrl'];
        if (decoded['bankroll'] is num) _bankroll = (decoded['bankroll'] as num).toDouble();

        if (decoded['customOdds'] is Map) {
          _customOddsMap.clear();
          (decoded['customOdds'] as Map).forEach((k, v) {
            if (v is num) _customOddsMap[k.toString()] = v.toDouble();
          });
        }

        if (decoded['bets'] is List) {
          final BetList imported = [];
          for (final item in decoded['bets']) {
            if (item is JsonMap) {
              imported.add(BetRecord.fromJson(item));
            }
          }
          _bets = imported;
        }
      });

      if (decoded['watchedIds'] is List) {
        final StringList wList = (decoded['watchedIds'] as List).map((e) => e.toString()).toList();
        await prefs.setStringList('watched_ids', wList);
      }

      await _saveState();
      if (_apiKey.isNotEmpty) {
        _syncSportApi(silent: true);
      }
      return true;
    } catch (_) {
      return false;
    }
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
      customOddsMap: _customOddsMap,
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

      if (result.success && result.matches.isNotEmpty) {
        if (result.matches.any((m) => m.isHighPressure)) {
          HapticFeedback.heavyImpact();
        }
        _saveState();
        _autoSettlePendingBets(result.matches);
        _enrichMatchesWithStandings();
      }

      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
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

      final lAvg = SportApiService.leagueAvgGoals(table);

      for (int i = 0; i < _matches.length; i++) {
        final m = _matches[i];
        if (m.leagueId != lid || m.hasStandingData) continue;
        final hInfo = m.homeId != null ? table[m.homeId!] : null;
        final aInfo = m.awayId != null ? table[m.awayId!] : null;

        if (hInfo != null && aInfo != null && hInfo.played > 0 && aInfo.played > 0) {
          final hAttack = hInfo.avgGoalsFor / lAvg;
          final aDefense = aInfo.avgGoalsAgainst / lAvg;
          final aAttack = aInfo.avgGoalsFor / lAvg;
          final hDefense = hInfo.avgGoalsAgainst / lAvg;

          final realHomeXg = (hAttack * aDefense * lAvg * 1.12).clamp(0.45, 3.6);
          final realAwayXg = (aAttack * hDefense * lAvg * 0.94).clamp(0.35, 3.2);
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
            homeFormCodes: SportApiService.extractWdlCodes(hInfo),
            awayFormCodes: SportApiService.extractWdlCodes(aInfo),
            homePos: hInfo.position,
            awayPos: aInfo.position,
            hasStandingData: true,
            isWatched: m.isWatched,
            customOdds: _customOddsMap[m.id],
          );
          anyUpdated = true;
        }
      }
      if (anyUpdated && mounted) {
        setState(() {});
        _saveState();
      }
    }
  }

  void _autoSettlePendingBets(MatchList freshMatches) {
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
      String newStatus = 'lost';

      if (bet.marketCode == 'home' && hs > as) newStatus = 'won';
      if (bet.marketCode == 'away' && as > hs) newStatus = 'won';
      if (bet.marketCode == 'draw' && hs == as) newStatus = 'won';
      if (bet.marketCode == '1x' && hs >= as) newStatus = 'won';
      if (bet.marketCode == 'x2' && as >= hs) newStatus = 'won';
      if (bet.marketCode == 'dnb_home') {
        if (hs > as) {
          newStatus = 'won';
        } else if (hs == as) {
          newStatus = 'void';
        }
      }
      if (bet.marketCode == 'over15' && (hs + as) > 1) newStatus = 'won';
      if (bet.marketCode == 'over25' && (hs + as) > 2) newStatus = 'won';
      if (bet.marketCode == 'under25' && (hs + as) <= 2) newStatus = 'won';
      if (bet.marketCode == 'btts' && hs > 0 && as > 0) newStatus = 'won';
      if (bet.marketCode == 'home_over15' && hs > 1) newStatus = 'won';

      _bets[i] = BetRecord(
        id: bet.id,
        fixtureId: bet.fixtureId,
        matchTitle: bet.matchTitle,
        market: bet.market,
        marketCode: bet.marketCode,
        odds: bet.odds,
        closingOdds: bet.closingOdds,
        stake: bet.stake,
        status: newStatus,
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

  void _toggleSlipMatch(String matchId) {
    setState(() {
      if (_slipMatchIds.contains(matchId)) {
        _slipMatchIds.remove(matchId);
      } else {
        if (_slipMatchIds.length >= 6) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Maximum 6 mérkőzés tehető egy kombi szelvényre!')),
          );
          return;
        }
        _slipMatchIds.add(matchId);
        HapticFeedback.selectionClick();
      }
    });
  }

  void _openEditOddsDialog(MatchPick match) {
    final controller = TextEditingController(text: match.marketOdds.toStringAsFixed(2));
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF131A29),
          title: const Text('Saját bukmékeri szorzó', style: TextStyle(fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${match.homeTeam} – ${match.awayTeam}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text('Piac: ${match.market} (Modell: ${(match.modelProb * 100).round()}%)',
                  style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Aktuális szorzó (pl. 1.95)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  _customOddsMap.remove(match.id);
                  final fair = 1.0 / match.modelProb;
                  match.marketOdds = double.parse((fair * 1.08).clamp(1.20, 5.20).toStringAsFixed(2));
                  match.isCustomOdds = false;
                });
                _saveState();
                Navigator.pop(context);
              },
              child: const Text('Alaphelyzet'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = double.tryParse(controller.text.replaceAll(',', '.'));
                if (parsed != null && parsed >= 1.05 && parsed <= 50.0) {
                  setState(() {
                    _customOddsMap[match.id] = parsed;
                    match.marketOdds = parsed;
                    match.isCustomOdds = true;
                    match.oddsHistory.add(parsed);
                  });
                  _saveState();
                }
                Navigator.pop(context);
              },
              child: const Text('Alkalmaz'),
            ),
          ],
        );
      },
    );
  }

  void _openEditClosingOddsDialog(BetRecord bet) {
    final controller = TextEditingController(
      text: bet.closingOdds != null ? bet.closingOdds!.toStringAsFixed(2) : '',
    );
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF131A29),
          title: const Text('Záró odds (CLV mérés)', style: TextStyle(fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(bet.matchTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text('Megtett szorzó: ${bet.odds.toStringAsFixed(2)}',
                  style: const TextStyle(color: Color(0xFF10B981), fontSize: 12)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Kezdés előtti záró szorzó (pl. 1.72)',
                  border: OutlineInputBorder(),
                ),
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
                final parsed = double.tryParse(controller.text.replaceAll(',', '.'));
                setState(() {
                  final idx = _bets.indexWhere((b) => b.id == bet.id);
                  if (idx != -1) {
                    _bets[idx] = BetRecord(
                      id: bet.id,
                      fixtureId: bet.fixtureId,
                      matchTitle: bet.matchTitle,
                      market: bet.market,
                      marketCode: bet.marketCode,
                      odds: bet.odds,
                      closingOdds: parsed,
                      stake: bet.stake,
                      status: bet.status,
                      date: bet.date,
                    );
                  }
                });
                _saveState();
                Navigator.pop(context);
              },
              child: const Text('Mentés'),
            ),
          ],
        );
      },
    );
  }

  void _openComboSlipSheet() {
    final slipMatches = _matches.where((m) => _slipMatchIds.contains(m.id)).toList();
    if (slipMatches.isEmpty) return;

    double comboStake = (_bankroll * 0.02).clamp(500, 30000).roundToDouble();

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
            final currentPicks = _matches.where((m) => _slipMatchIds.contains(m.id)).toList();
            if (currentPicks.isEmpty) {
              Navigator.pop(context);
              return const SizedBox.shrink();
            }

            double totalOdds = 1.0;
            double combinedProb = 1.0;
            for (final m in currentPicks) {
              totalOdds *= m.marketOdds;
              combinedProb *= m.modelProb;
            }
            final comboEv = (combinedProb * totalOdds) - 1.0;
            final riskLabel = currentPicks.length <= 2
                ? 'Mérsékelt kockázat'
                : (currentPicks.length <= 4 ? 'Közepes variancia' : 'Magas kockázat');

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Kombi Szelvény (${currentPicks.length} kötés)',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      TextButton(
                        onPressed: () {
                          setState(() => _slipMatchIds.clear());
                          Navigator.pop(context);
                        },
                        child: const Text('Ürítés', style: TextStyle(color: Color(0xFFEF4444))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...currentPicks.map((m) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A0E17),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF1F2937)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${m.homeTeam} – ${m.awayTeam}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                Text('${m.market} (${(m.modelProb * 100).round()}%)',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                              ],
                            ),
                          ),
                          Text('@ ${m.marketOdds.toStringAsFixed(2)}',
                              style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                            onPressed: () {
                              _toggleSlipMatch(m.id);
                              setModalState(() {});
                            },
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0E17),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _StatCompareRow(
                          label: 'Eredő szorzó',
                          homeVal: riskLabel,
                          awayVal: '${totalOdds.toStringAsFixed(2)}x',
                        ),
                        _StatCompareRow(
                          label: 'Kombinált esély / EV',
                          homeVal: '${(combinedProb * 100).toStringAsFixed(1)}%',
                          awayVal: '${comboEv >= 0 ? '+' : ''}${(comboEv * 100).toStringAsFixed(1)}% EV',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Tét: ${comboStake.round()} Ft → Várható: ${(comboStake * totalOdds).round()} Ft',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  Slider(
                    value: comboStake,
                    min: 500,
                    max: 50000,
                    divisions: 99,
                    activeColor: const Color(0xFF10B981),
                    onChanged: (v) => setModalState(() => comboStake = v),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        final now = DateTime.now();
                        final dateLabel =
                            '${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}.';
                        final title =
                            'Kombi (${currentPicks.length} meccs): ${currentPicks.map((e) => e.homeTeam).join(', ')}';
                        setState(() {
                          _bets.insert(
                            0,
                            BetRecord(
                              id: DateTime.now().millisecondsSinceEpoch.toString(),
                              matchTitle: title,
                              market: 'Kombi szelvény',
                              marketCode: 'combo',
                              odds: double.parse(totalOdds.toStringAsFixed(2)),
                              stake: comboStake,
                              status: 'pending',
                              date: dateLabel,
                            ),
                          );
                          _slipMatchIds.clear();
                        });
                        _saveState();
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Kombi szelvény rögzítve a Tippnaplóba!')),
                        );
                      },
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Kombi szelvény naplózása'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _addBet(MatchPick match, double stake, {MarketOption? chosenMarket}) {
    final now = DateTime.now();
    final dateLabel = '${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}.';
    final mLabel = chosenMarket?.label ?? match.market;
    final mCode = chosenMarket?.code ?? match.marketCode;
    final mOdds = chosenMarket?.refOdds ?? match.marketOdds;

    setState(() {
      _bets.insert(
        0,
        BetRecord(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          fixtureId: match.fixtureId,
          matchTitle: '${match.homeTeam} – ${match.awayTeam}',
          market: mLabel,
          marketCode: mCode,
          odds: mOdds,
          stake: stake,
          status: 'pending',
          date: dateLabel,
        ),
      );
    });
    _saveState();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Tipp rögzítve: $mLabel (${stake.round()} Ft)!')),
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
          closingOdds: old.closingOdds,
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
    final backupController = TextEditingController();
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
                  Text('Beállítások & Mentés', style: TextStyle(fontSize: 18)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SportAPI.ai (X-Api-Key + ETag gyorsítótár)',
                      style: TextStyle(fontSize: 12, color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                    ),
                    if (_rateLimitRemaining != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Maradék napi keret: $_rateLimitRemaining lekérés',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                      ),
                    ],
                    const SizedBox(height: 10),
                    TextField(
                      controller: keyController,
                      decoration: const InputDecoration(
                        labelText: 'X-Api-Key (sk_live_...)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: baseController,
                      decoration: const InputDecoration(
                        labelText: 'Base URL',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
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
                    const Divider(height: 24, color: Color(0xFF1F2937)),
                    const Text(
                      'JSON Biztonsági Mentés (Újratelepítéshez)',
                      style: TextStyle(fontSize: 12, color: Color(0xFF3B82F6), fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              final jsonStr = _exportBackupJson();
                              Clipboard.setData(ClipboardData(text: jsonStr));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Teljes biztonsági mentés vágólapra másolva!')),
                              );
                            },
                            icon: const Icon(Icons.copy, size: 15),
                            label: const Text('Mentés másolása', style: TextStyle(fontSize: 11)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: backupController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'JSON visszaállítás beillesztése...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final ok = await _importBackupJson(backupController.text);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(ok
                                    ? 'Adatok sikeresen visszaállítva!'
                                    : 'Hibás JSON formátum!'),
                              ),
                            );
                            if (ok) Navigator.pop(context);
                          }
                        },
                        icon: const Icon(Icons.restore, size: 15),
                        label: const Text('Adatok visszaállítása', style: TextStyle(fontSize: 11)),
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

  void _openLogBetDialog(MatchPick match, {MarketOption? chosenMarket}) {
    double stake = (_bankroll * 0.03).clamp(500, 50000).roundToDouble();
    final label = chosenMarket?.label ?? match.market;
    final odds = chosenMarket?.refOdds ?? match.marketOdds;

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
                  Text('$label @ $odds', style: const TextStyle(color: Color(0xFF10B981), fontSize: 13)),
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
                    'Várható nyeremény: ${(stake * odds).round()} Ft',
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
                    _addBet(match, stake, chosenMarket: chosenMarket);
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
    Future<FixtureFullBundle?>? bundleFuture;
    if (_apiKey.isNotEmpty && match.fixtureId != null && match.fixtureId! > 0) {
      bundleFuture = SportApiService.fetchFullBundle(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        fixtureId: match.fixtureId!,
        leagueId: match.leagueId,
      );
    }

    double homeModifier = 1.0;
    double awayModifier = 1.0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF131A29),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return DefaultTabController(
          length: 4,
          child: StatefulBuilder(
            builder: (context, setModalState) {
              final adjHomeXg = (match.homeXg * homeModifier).clamp(0.25, 4.5);
              final adjAwayXg = (match.awayXg * awayModifier).clamp(0.25, 4.5);
              final poisson = PoissonEngine.calculate(adjHomeXg, adjAwayXg);

              return SizedBox(
                height: MediaQuery.of(context).size.height * 0.86,
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade700,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  '${match.league} • ${match.kickoff}',
                                  style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color.fromRGBO(16, 185, 129, 0.16),
                                  borderRadius: BorderRadius.circular(8),
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
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    TeamLogoBadge(
                                      teamId: match.homeId,
                                      teamName: match.homeTeam,
                                      baseUrl: _baseUrl,
                                      apiKey: _apiKey,
                                      size: 28,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        match.homeTeam,
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (match.homeScore != null && match.awayScore != null)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: Text(
                                    '${match.homeScore} - ${match.awayScore}',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: match.isLive ? const Color(0xFFEF4444) : Colors.white,
                                    ),
                                  ),
                                )
                              else
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8),
                                  child: Text('vs', style: TextStyle(color: Colors.grey)),
                                ),
                              Expanded(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        match.awayTeam,
                                        textAlign: TextAlign.end,
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    TeamLogoBadge(
                                      teamId: match.awayId,
                                      teamName: match.awayTeam,
                                      baseUrl: _baseUrl,
                                      apiKey: _apiKey,
                                      size: 28,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const TabBar(
                      isScrollable: true,
                      indicatorColor: Color(0xFF10B981),
                      labelColor: Color(0xFF10B981),
                      unselectedLabelColor: Color(0xFF9CA3AF),
                      tabs: [
                        Tab(text: 'Dixon-Coles & Piacok'),
                        Tab(text: 'Statisztika'),
                        Tab(text: 'Kezdőcsapatok'),
                        Tab(text: 'Tabella'),
                      ],
                    ),
                    Expanded(
                      child: FutureBuilder<FixtureFullBundle?>(
                        future: bundleFuture,
                        builder: (context, snapshot) {
                          final bundle = snapshot.data;
                          final isLoadingBundle = snapshot.connectionState == ConnectionState.waiting;

                          return TabBarView(
                            children: [
                              // 1. FÜL: DIXON-COLES & ÖSSZES PIAC
                              ListView(
                                padding: const EdgeInsets.all(20),
                                children: [
                                  const Text('Dixon-Coles 1X2 Valószínűség',
                                      style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
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
                                              style: const TextStyle(
                                                  fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
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
                                  const Text('Legvalószínűbb pontos végeredmények',
                                      style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
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
                                              Text(s.score,
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
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
                                      Text('Kalibrált xG: ${adjHomeXg.toStringAsFixed(2)}',
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                      Text(adjAwayXg.toStringAsFixed(2),
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: LinearProgressIndicator(
                                      value: adjHomeXg / (adjHomeXg + adjAwayXg),
                                      minHeight: 8,
                                      backgroundColor: const Color(0xFF3B82F6),
                                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text('Összes kiszámolt piac (Koppints a naplózáshoz)',
                                      style: TextStyle(
                                          fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                                  const SizedBox(height: 8),
                                  ...poisson.allMarkets.map((opt) {
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0A0E17),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: const Color(0xFF1F2937)),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(opt.label,
                                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                                Text(
                                                  'Esély: ${(opt.probability * 100).round()}% • Fair: ${opt.fairOdds}',
                                                  style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                                                ),
                                              ],
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: () {
                                              Navigator.pop(context);
                                              _openLogBetDialog(match, chosenMarket: opt);
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                              decoration: BoxDecoration(
                                                color: const Color.fromRGBO(16, 185, 129, 0.18),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                '+ ${opt.refOdds}',
                                                style: const TextStyle(
                                                  color: Color(0xFF10B981),
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () {
                                            _toggleSlipMatch(match.id);
                                            setModalState(() {});
                                          },
                                          icon: Icon(_slipMatchIds.contains(match.id)
                                              ? Icons.check
                                              : Icons.playlist_add),
                                          label: Text(_slipMatchIds.contains(match.id) ? 'Szelvényen' : '+ Szelvény'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: FilledButton.icon(
                                          onPressed: () {
                                            Navigator.pop(context);
                                            _openLogBetDialog(match);
                                          },
                                          icon: const Icon(Icons.add_chart),
                                          label: const Text('Fő tipp naplózása'),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: const Color(0xFF10B981),
                                            foregroundColor: Colors.black,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),

                              // 2. FÜL: STATISZTIKA & ESEMÉNYEK
                              isLoadingBundle
                                  ? const Center(child: CircularProgressIndicator())
                                  : ListView(
                                      padding: const EdgeInsets.all(20),
                                      children: [
                                        if (bundle?.stadium != null)
                                          Text(
                                            'Stadion: ${bundle!.stadium}${bundle.city != null ? " (${bundle.city})" : ""}',
                                            style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                                          ),
                                        if (bundle?.homeCoach != null && bundle?.awayCoach != null)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(
                                              'Edzők: ${bundle!.homeCoach} vs ${bundle.awayCoach}',
                                              style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                                            ),
                                          ),
                                        const SizedBox(height: 14),
                                        if (bundle?.homeStats != null && bundle?.awayStats != null) ...[
                                          const Text('Csapat statisztikák',
                                              style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                                          const SizedBox(height: 8),
                                          _StatCompareRow(
                                            label: 'Összes lövés',
                                            homeVal: '${bundle!.homeStats!['shots'] ?? 0}',
                                            awayVal: '${bundle.awayStats!['shots'] ?? 0}',
                                          ),
                                          _StatCompareRow(
                                            label: 'Kaput eltaláló lövés',
                                            homeVal: '${bundle.homeStats!['shots_on_target'] ?? 0}',
                                            awayVal: '${bundle.awayStats!['shots_on_target'] ?? 0}',
                                          ),
                                          _StatCompareRow(
                                            label: 'Passzpontosság',
                                            homeVal: '${bundle.homeStats!['pass_accuracy'] ?? 0}%',
                                            awayVal: '${bundle.awayStats!['pass_accuracy'] ?? 0}%',
                                          ),
                                          _StatCompareRow(
                                            label: 'Szabálytalanságok',
                                            homeVal: '${bundle.homeStats!['fouls'] ?? 0}',
                                            awayVal: '${bundle.awayStats!['fouls'] ?? 0}',
                                          ),
                                          _StatCompareRow(
                                            label: 'Sárga lapok',
                                            homeVal: '${bundle.homeStats!['yellow_cards'] ?? 0}',
                                            awayVal: '${bundle.awayStats!['yellow_cards'] ?? 0}',
                                          ),
                                        ] else
                                          const Text(
                                            'A részletes élő meccsstatisztika a mérkőzés kezdete után érhető el.',
                                            style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                                          ),
                                        if (bundle != null && bundle.events.isNotEmpty) ...[
                                          const Divider(height: 24, color: Color(0xFF1F2937)),
                                          const Text('Meccs események',
                                              style: TextStyle(fontWeight: FontWeight.bold)),
                                          const SizedBox(height: 8),
                                          ...bundle.events.map((ev) {
                                            final type = ev['event_type'] ?? '';
                                            final icon =
                                                type == 'goal' ? '⚽' : (type == 'yellow_card' ? '🟨' : '🔄');
                                            return Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 3),
                                              child: Text(
                                                "$icon ${ev['minute'] ?? ''} ${ev['player_name'] ?? ''} (${ev['team_side'] == 'home' ? match.homeTeam : match.awayTeam})",
                                                style: const TextStyle(fontSize: 13),
                                              ),
                                            );
                                          }),
                                        ],
                                      ],
                                    ),

                              // 3. FÜL: KEZDŐCSAPATOK & HIÁNYZÓ-MÓDOSÍTÓ
                              isLoadingBundle
                                  ? const Center(child: CircularProgressIndicator())
                                  : ListView(
                                      padding: const EdgeInsets.all(20),
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF0A0E17),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: const Color(0xFF1F2937)),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text('Kezdőcsapat / Hiányzó hatás szimulátor',
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                      color: Color(0xFFF59E0B))),
                                              const SizedBox(height: 8),
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text('${match.homeTeam} xG:', style: const TextStyle(fontSize: 12)),
                                                  SegmentedButton<double>(
                                                    segments: const [
                                                      ButtonSegment(value: 0.85, label: Text('-15%')),
                                                      ButtonSegment(value: 1.0, label: Text('0%')),
                                                      ButtonSegment(value: 1.10, label: Text('+10%')),
                                                    ],
                                                    selected: {homeModifier},
                                                    onSelectionChanged: (s) =>
                                                        setModalState(() => homeModifier = s.first),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text('${match.awayTeam} xG:', style: const TextStyle(fontSize: 12)),
                                                  SegmentedButton<double>(
                                                    segments: const [
                                                      ButtonSegment(value: 0.85, label: Text('-15%')),
                                                      ButtonSegment(value: 1.0, label: Text('0%')),
                                                      ButtonSegment(value: 1.10, label: Text('+10%')),
                                                    ],
                                                    selected: {awayModifier},
                                                    onSelectionChanged: (s) =>
                                                        setModalState(() => awayModifier = s.first),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        if (bundle == null || !bundle.lineupsAvailable)
                                          const Padding(
                                            padding: EdgeInsets.symmetric(vertical: 20),
                                            child: Text(
                                              'A hivatalos kezdőcsapatok általában 45-60 perccel a kezdés előtt jelennek meg itt.',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                                            ),
                                          )
                                        else ...[
                                          Text('${match.homeTeam} – Kezdő XI',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                                          const SizedBox(height: 6),
                                          ...bundle.homeStarters.map((p) => _PlayerLineupTile(player: p)),
                                          const SizedBox(height: 16),
                                          Text('${match.awayTeam} – Kezdő XI',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold, color: Color(0xFF3B82F6))),
                                          const SizedBox(height: 6),
                                          ...bundle.awayStarters.map((p) => _PlayerLineupTile(player: p)),
                                        ],
                                      ],
                                    ),

                              // 4. FÜL: TABELLA
                              isLoadingBundle
                                  ? const Center(child: CircularProgressIndicator())
                                  : (bundle == null || bundle.standings.isEmpty)
                                      ? const Center(
                                          child: Text(
                                            'Ehhez a sorozathoz nem érhető el bajnoki tabella.',
                                            style: TextStyle(color: Color(0xFF9CA3AF)),
                                          ),
                                        )
                                      : ListView.builder(
                                          padding: const EdgeInsets.all(14),
                                          itemCount: bundle.standings.length,
                                          itemBuilder: (context, idx) {
                                            final row = bundle.standings[idx];
                                            final isHome = row.teamId == match.homeId;
                                            final isAway = row.teamId == match.awayId;
                                            return Container(
                                              margin: const EdgeInsets.only(bottom: 4),
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: isHome
                                                    ? const Color.fromRGBO(16, 185, 129, 0.16)
                                                    : (isAway
                                                        ? const Color.fromRGBO(59, 130, 246, 0.16)
                                                        : Colors.transparent),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Row(
                                                children: [
                                                  SizedBox(
                                                    width: 24,
                                                    child: Text('${row.position}.',
                                                        style: const TextStyle(
                                                            fontWeight: FontWeight.bold, fontSize: 12)),
                                                  ),
                                                  Expanded(
                                                    child: Text(
                                                      row.teamName,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        fontWeight: (isHome || isAway)
                                                            ? FontWeight.bold
                                                            : FontWeight.normal,
                                                      ),
                                                    ),
                                                  ),
                                                  SizedBox(
                                                    width: 34,
                                                    child: Text('${row.played}m',
                                                        textAlign: TextAlign.center,
                                                        style: const TextStyle(
                                                            fontSize: 11, color: Color(0xFF9CA3AF))),
                                                  ),
                                                  SizedBox(
                                                    width: 40,
                                                    child: Text(
                                                        '${row.goalDiff >= 0 ? "+" : ""}${row.goalDiff}',
                                                        textAlign: TextAlign.center,
                                                        style: const TextStyle(fontSize: 11)),
                                                  ),
                                                  SizedBox(
                                                    width: 32,
                                                    child: Text('${row.points}p',
                                                        textAlign: TextAlign.end,
                                                        style: const TextStyle(
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 12,
                                                            color: Color(0xFF10B981))),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      ValueFeedTab(
        matches: _matches,
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        dayOffset: _dayOffset,
        slipIds: _slipMatchIds,
        onDayChanged: _changeDayOffset,
        onRefresh: () => _syncSportApi(),
        onSelectMatch: _openMatchDetail,
        onToggleWatch: _toggleWatch,
        onToggleSlip: _toggleSlipMatch,
        onEditOdds: _openEditOddsDialog,
        onLogBet: _openLogBetDialog,
      ),
      TrendRadarTab(
        matches: _matches,
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        onSelectMatch: _openMatchDetail,
      ),
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
        onEditClosingOdds: _openEditClosingOddsDialog,
        onDeleteBet: _deleteBet,
      ),
    ];

    double slipOdds = 1.0;
    for (final m in _matches) {
      if (_slipMatchIds.contains(m.id)) {
        slipOdds *= m.marketOdds;
      }
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E17),
        title: Row(
          children: [
            const Icon(Icons.insights, color: Color(0xFF10B981)),
            const SizedBox(width: 6),
            const Text('GoalEdge AI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _isLiveMode
                    ? const Color.fromRGBO(16, 185, 129, 0.2)
                    : const Color.fromRGBO(59, 130, 246, 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _isLiveMode ? 'API' : 'DEMÓ',
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
          IconButton(
            icon: Icon(
              _autoLiveRadar ? Icons.podcasts : Icons.sensors_off,
              color: _autoLiveRadar ? const Color(0xFFEF4444) : Colors.grey,
            ),
            tooltip: 'Automata Élő Radar (75 mp)',
            onPressed: _toggleAutoLiveRadar,
          ),
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
            tooltip: 'Beállítások & Mentés',
            onPressed: _openSettingsDialog,
          ),
        ],
      ),
      body: pages[_selectedIndex],
      floatingActionButton: _slipMatchIds.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _openComboSlipSheet,
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.black,
              icon: const Icon(Icons.receipt_long),
              label: Text(
                'Szelvény (${_slipMatchIds.length}) • ${slipOdds.toStringAsFixed(2)}x',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
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

class _PlayerLineupTile extends StatelessWidget {
  final JsonMap player;

  const _PlayerLineupTile({required this.player});

  @override
  Widget build(BuildContext context) {
    final shirt = player['shirt'] ?? '-';
    final name = player['name'] ?? '';
    final pos = player['position'] ?? '';
    final isCap = player['is_captain'] == true;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: const Color(0xFF1F2937),
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text('$shirt', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$name${isCap ? " (C)" : ""}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Text(pos.toString(), style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
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
// 6. FÜLEK (AJÁNLÁSOK, TRENDEK, KALKULÁTOR, NAPLÓ)
// ==========================================

class ValueFeedTab extends StatefulWidget {
  final MatchList matches;
  final String baseUrl;
  final String apiKey;
  final int dayOffset;
  final StringList slipIds;
  final Function(int) onDayChanged;
  final Future<void> Function() onRefresh;
  final Function(MatchPick) onSelectMatch;
  final Function(String) onToggleWatch;
  final Function(String) onToggleSlip;
  final Function(MatchPick) onEditOdds;
  final Function(MatchPick) onLogBet;

  const ValueFeedTab({
    super.key,
    required this.matches,
    required this.baseUrl,
    required this.apiKey,
    required this.dayOffset,
    required this.slipIds,
    required this.onDayChanged,
    required this.onRefresh,
    required this.onSelectMatch,
    required this.onToggleWatch,
    required this.onToggleSlip,
    required this.onEditOdds,
    required this.onLogBet,
  });

  @override
  State<ValueFeedTab> createState() => _ValueFeedTabState();
}

class _ValueFeedTabState extends State<ValueFeedTab> {
  String _selectedLeague = 'Összes';
  String _smartFilter = 'Mind';
  String _searchQuery = '';
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

    final smartFilters = ['Mind', '+5% EV felett', 'Odds 1.50-2.30', 'ÉLŐ'];

    final filtered = widget.matches.where((m) {
      if (_selectedLeague != 'Összes' && m.league != _selectedLeague) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchText = '${m.homeTeam} ${m.awayTeam} ${m.league}'.toLowerCase();
        if (!matchText.contains(q)) return false;
      }
      if (_smartFilter == '+5% EV felett' && m.edgePercent < 5.0) return false;
      if (_smartFilter == 'Odds 1.50-2.30' && (m.marketOdds < 1.50 || m.marketOdds > 2.30)) return false;
      if (_smartFilter == 'ÉLŐ' && !m.isLive) return false;
      return true;
    }).toList();

    filtered.sort((a, b) => _sortByValue
        ? b.edgePercent.compareTo(a.edgePercent)
        : b.modelProb.compareTo(a.modelProb));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: -1, label: Text('Tegnap', style: TextStyle(fontSize: 12))),
                    ButtonSegment(value: 0, label: Text('Ma', style: TextStyle(fontSize: 12))),
                    ButtonSegment(value: 1, label: Text('Holnap', style: TextStyle(fontSize: 12))),
                  ],
                  selected: {widget.dayOffset},
                  onSelectionChanged: (s) => widget.onDayChanged(s.first),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 38,
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Keresés csapatra vagy ligára...',
                hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF9CA3AF)),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                filled: true,
                fillColor: const Color(0xFF131A29),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF1F2937)),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: smartFilters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final sf = smartFilters[index];
              final sel = sf == _smartFilter;
              return FilterChip(
                label: Text(sf, style: TextStyle(fontSize: 11, color: sel ? Colors.black : Colors.white)),
                selected: sel,
                selectedColor: const Color(0xFF3B82F6),
                onSelected: (_) => setState(() => _smartFilter = sf),
              );
            },
          ),
        ),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: leagues.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
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
                  fontSize: 11,
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${filtered.length} mérkőzés', style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
              TextButton.icon(
                onPressed: () => setState(() => _sortByValue = !_sortByValue),
                icon: const Icon(Icons.sort, size: 15),
                label: Text(_sortByValue ? 'Value %' : 'Esély %', style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: widget.onRefresh,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final match = filtered[index];
                final inSlip = widget.slipIds.contains(match.id);
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
                                  if (match.isHighPressure) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color.fromRGBO(245, 158, 11, 0.22),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'GÓLNYOMÁS',
                                        style: TextStyle(
                                          color: Color(0xFFF59E0B),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                  ],
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
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              TeamLogoBadge(
                                teamId: match.homeId,
                                teamName: match.homeTeam,
                                baseUrl: widget.baseUrl,
                                apiKey: widget.apiKey,
                                size: 24,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${match.homeTeam} – ${match.awayTeam}',
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 8),
                              TeamLogoBadge(
                                teamId: match.awayId,
                                teamName: match.awayTeam,
                                baseUrl: widget.baseUrl,
                                apiKey: widget.apiKey,
                                size: 24,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              WdlStrip(codes: match.homeFormCodes),
                              WdlStrip(codes: match.awayFormCodes),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            match.trendSummary,
                            style: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 12),
                          ),
                          const Divider(height: 20, color: Color(0xFF1F2937)),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Ajánlott piac (Dixon-Coles)',
                                        style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                                    Text(match.market,
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                  ],
                                ),
                              ),
                              Row(
                                children: [
                                  _StatBadge(label: 'Modell', value: '${(match.modelProb * 100).round()}%'),
                                  const SizedBox(width: 6),
                                  GestureDetector(
                                    onTap: () => widget.onEditOdds(match),
                                    child: _StatBadge(
                                      label: match.isCustomOdds ? 'Saját ✎' : 'Odds ✎',
                                      value: match.marketOdds.toStringAsFixed(2),
                                      isPrimary: true,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => widget.onToggleSlip(match.id),
                                  icon: Icon(inSlip ? Icons.check : Icons.playlist_add, size: 16),
                                  label: Text(inSlip ? 'Szelvényen' : '+ Szelvény',
                                      style: const TextStyle(fontSize: 12)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: inSlip ? const Color(0xFF10B981) : Colors.white,
                                    side: BorderSide(
                                        color: inSlip ? const Color(0xFF10B981) : const Color(0xFF374151)),
                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: () => widget.onLogBet(match),
                                icon: const Icon(Icons.add_circle_outline, color: Color(0xFF3B82F6)),
                                tooltip: 'Naplózás',
                              ),
                              IconButton(
                                onPressed: () => widget.onToggleWatch(match.id),
                                icon: Icon(
                                  match.isWatched ? Icons.notifications_active : Icons.notifications_none,
                                  color: match.isWatched ? const Color(0xFFF59E0B) : Colors.grey,
                                ),
                                tooltip: 'Riasztás',
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
  final MatchList matches;
  final String baseUrl;
  final String apiKey;
  final Function(MatchPick) onSelectMatch;

  const TrendRadarTab({
    super.key,
    required this.matches,
    required this.baseUrl,
    required this.apiKey,
    required this.onSelectMatch,
  });

  @override
  State<TrendRadarTab> createState() => _TrendRadarTabState();
}

class _TrendRadarTabState extends State<TrendRadarTab> {
  String _category = 'Mind';

  @override
  Widget build(BuildContext context) {
    final categories = ['Mind', 'ÉLŐ & Nyomás', 'Tabella & Forma', 'Gólok / BTTS', 'xG eltérés'];
    final list = widget.matches.where((m) {
      if (_category == 'Mind') return true;
      if (_category == 'ÉLŐ & Nyomás') return m.isLive || m.isHighPressure;
      return m.trendCategory == _category;
    }).toList();

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
                selectedColor: cat == 'ÉLŐ & Nyomás' ? const Color(0xFFEF4444) : const Color(0xFF3B82F6),
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
          child: list.isEmpty
              ? const Center(
                  child: Text(
                    'Nincs aktív meccs ebben a szűrőben.',
                    style: TextStyle(color: Color(0xFF9CA3AF)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
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
                                  Text(
                                    match.isHighPressure ? 'ÉLŐ GÓLNYOMÁS' : match.trendCategory,
                                    style: TextStyle(
                                      color: match.isHighPressure
                                          ? const Color(0xFFF59E0B)
                                          : const Color(0xFF3B82F6),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text('$hits / 6 forma-találat (${((hits / 6) * 100).round()}%)',
                                      style: const TextStyle(
                                          color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 12)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  TeamLogoBadge(
                                    teamId: match.homeId,
                                    teamName: match.homeTeam,
                                    baseUrl: widget.baseUrl,
                                    apiKey: widget.apiKey,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text('${match.homeTeam} – ${match.awayTeam}',
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 8),
                                  TeamLogoBadge(
                                    teamId: match.awayId,
                                    teamName: match.awayTeam,
                                    baseUrl: widget.baseUrl,
                                    apiKey: widget.apiKey,
                                    size: 22,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(match.trendSummary,
                                  style: const TextStyle(fontSize: 13, color: Color(0xFFD1D5DB))),
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
  final MatchList matches;
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

  // Monte Carlo paraméterek
  double _mcWinRate = 0.56;
  double _mcAvgOdds = 1.92;
  double _mcStakePct = 0.03;

  @override
  Widget build(BuildContext context) {
    final ev = (_prob * _odds) - 1.0;
    final fairOdds = 1.0 / _prob;
    final fullKelly = ((_prob * _odds) - 1.0) / (_odds - 1.0);
    final halfKelly = fullKelly > 0 ? fullKelly * 0.5 : 0.0;
    final recommendedStake = (widget.bankroll * halfKelly).round();
    final simResult = PoissonEngine.calculate(_simHomeXg, _simAwayXg);

    // Monte Carlo 40 szimuláció (100 fogadásra)
    final CurveList mcCurves = [];
    final DoubleList finalBalances = [];
    for (int sim = 0; sim < 40; sim++) {
      final rng = math.Random(1000 + sim);
      double b = widget.bankroll;
      final DoubleList path = [b];
      for (int step = 0; step < 100; step++) {
        final stake = b * _mcStakePct;
        if (rng.nextDouble() < _mcWinRate) {
          b += stake * (_mcAvgOdds - 1.0);
        } else {
          b -= stake;
        }
        path.add(b);
      }
      mcCurves.add(path);
      finalBalances.add(b);
    }
    finalBalances.sort();
    final mcWorst10 = finalBalances[4].round();
    final mcMedian = finalBalances[20].round();
    final mcBest10 = finalBalances[36].round();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('EV & Kelly', style: TextStyle(fontSize: 12))),
            ButtonSegment(value: 1, label: Text('Dixon-Coles', style: TextStyle(fontSize: 12))),
            ButtonSegment(value: 2, label: Text('Monte Carlo', style: TextStyle(fontSize: 12))),
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
                    value: ev > 0
                        ? '$recommendedStake Ft (${(halfKelly * 100).toStringAsFixed(1)}%)'
                        : '0 Ft (Nincs előny)',
                    valueColor: ev > 0 ? const Color(0xFF10B981) : const Color(0xFF9CA3AF),
                  ),
                ],
              ),
            ),
          ),
        ] else if (_mode == 1) ...[
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
                    value:
                        '${(simResult.homeWin * 100).toStringAsFixed(1)}% (Fair: ${(1 / simResult.homeWin).toStringAsFixed(2)})',
                    valueColor: const Color(0xFF10B981),
                  ),
                  const Divider(height: 20, color: Color(0xFF1F2937)),
                  _CalcRow(
                    label: 'Döntetlen (X - Dixon-Coles)',
                    value:
                        '${(simResult.draw * 100).toStringAsFixed(1)}% (Fair: ${(1 / simResult.draw).toStringAsFixed(2)})',
                    valueColor: Colors.white,
                  ),
                  const Divider(height: 20, color: Color(0xFF1F2937)),
                  _CalcRow(
                    label: 'Vendég győzelem (2)',
                    value:
                        '${(simResult.awayWin * 100).toStringAsFixed(1)}% (Fair: ${(1 / simResult.awayWin).toStringAsFixed(2)})',
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
        ] else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Monte Carlo Tőkeszimulátor (100 fogadás)',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                  const SizedBox(height: 10),
                  Text('Találati arány: ${(_mcWinRate * 100).round()}%',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Slider(
                    value: _mcWinRate,
                    min: 0.35,
                    max: 0.78,
                    activeColor: const Color(0xFF10B981),
                    onChanged: (v) => setState(() => _mcWinRate = v),
                  ),
                  Text('Átlagos szorzó: ${_mcAvgOdds.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Slider(
                    value: _mcAvgOdds,
                    min: 1.35,
                    max: 3.20,
                    activeColor: const Color(0xFF3B82F6),
                    onChanged: (v) => setState(() => _mcAvgOdds = v),
                  ),
                  Text('Tétméret: ${(_mcStakePct * 100).toStringAsFixed(1)}% / tipp',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Slider(
                    value: _mcStakePct,
                    min: 0.01,
                    max: 0.08,
                    activeColor: const Color(0xFFF59E0B),
                    onChanged: (v) => setState(() => _mcStakePct = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Container(
                    height: 130,
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0E17),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: CustomPaint(painter: MonteCarloPainter(mcCurves, widget.bankroll)),
                  ),
                  const SizedBox(height: 12),
                  _CalcRow(
                    label: 'Medián tőke (100 tipp után)',
                    value: '$mcMedian Ft',
                    valueColor: const Color(0xFF10B981),
                  ),
                  const Divider(height: 16, color: Color(0xFF1F2937)),
                  _CalcRow(
                    label: 'Optimista sáv (Top 10%)',
                    value: '$mcBest10 Ft',
                    valueColor: const Color(0xFF3B82F6),
                  ),
                  const Divider(height: 16, color: Color(0xFF1F2937)),
                  _CalcRow(
                    label: 'Pesszimista sáv (Alsó 10%)',
                    value: '$mcWorst10 Ft',
                    valueColor: const Color(0xFFEF4444),
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
  final MatchList matches;
  final BetList bets;
  final Function(String) onToggleWatch;
  final Function(MatchPick) onSelectMatch;
  final Function(String, String) onUpdateBetStatus;
  final Function(BetRecord) onEditClosingOdds;
  final Function(String) onDeleteBet;

  const TrackerAndWatchlistTab({
    super.key,
    required this.matches,
    required this.bets,
    required this.onToggleWatch,
    required this.onSelectMatch,
    required this.onUpdateBetStatus,
    required this.onEditClosingOdds,
    required this.onDeleteBet,
  });

  @override
  State<TrackerAndWatchlistTab> createState() => _TrackerAndWatchlistTabState();
}

class _TrackerAndWatchlistTabState extends State<TrackerAndWatchlistTab> {
  int _subTab = 0;

  @override
  Widget build(BuildContext context) {
    final settledBets = widget.bets.where((b) => b.status == 'won' || b.status == 'lost').toList();
    final totalStaked = settledBets.fold<double>(0.0, (sum, b) => sum + b.stake);
    final totalProfit = settledBets.fold<double>(0.0, (sum, b) => sum + b.profit);
    final wonCount = settledBets.where((b) => b.status == 'won').length;
    final winRate = settledBets.isEmpty ? 0.0 : (wonCount / settledBets.length) * 100;
    final roi = totalStaked == 0 ? 0.0 : (totalProfit / totalStaked) * 100;

    final clvBets = widget.bets.where((b) => b.clvPercent != null).toList();
    final avgClv = clvBets.isEmpty
        ? null
        : clvBets.fold<double>(0.0, (sum, b) => sum + b.clvPercent!) / clvBets.length;

    final DoubleList equityCurve = [0.0];
    double running = 0.0;
    for (final b in settledBets.reversed) {
      running += b.profit;
      equityCurve.add(running);
    }

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
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _KpiItem(
                          label: 'Profit',
                          value: '${totalProfit >= 0 ? '+' : ''}${totalProfit.round()} Ft',
                          color: totalProfit >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                        ),
                        _KpiItem(
                          label: 'ROI',
                          value: '${roi >= 0 ? '+' : ''}${roi.toStringAsFixed(1)}%',
                          color: roi >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                        ),
                        _KpiItem(
                          label: 'Találat',
                          value: '${winRate.round()}%',
                          color: Colors.white,
                        ),
                        _KpiItem(
                          label: 'Átl. CLV',
                          value: avgClv == null
                              ? '-'
                              : '${avgClv >= 0 ? '+' : ''}${avgClv.toStringAsFixed(1)}%',
                          color: avgClv != null && avgClv >= 0
                              ? const Color(0xFF10B981)
                              : const Color(0xFF3B82F6),
                        ),
                      ],
                    ),
                    if (equityCurve.length >= 2) ...[
                      const SizedBox(height: 12),
                      Container(
                        height: 60,
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A0E17),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: CustomPaint(painter: RoiCurvePainter(equityCurve)),
                      ),
                    ],
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
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                    itemCount: widget.bets.length,
                    itemBuilder: (context, index) {
                      final bet = widget.bets[index];
                      final clv = bet.clvPercent;
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
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text('${bet.market} • Odds: ${bet.odds} • Tét: ${bet.stake.round()} Ft',
                                        style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                                  ),
                                  GestureDetector(
                                    onTap: () => widget.onEditClosingOdds(bet),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1F2937),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        clv != null
                                            ? 'CLV: ${clv >= 0 ? '+' : ''}${clv.toStringAsFixed(1)}%'
                                            : '+ Záró odds',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: clv != null && clv >= 0
                                              ? const Color(0xFF10B981)
                                              : const Color(0xFF3B82F6),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  _StatusChip(
                                    label: 'Nyert',
                                    active: bet.status == 'won',
                                    color: const Color(0xFF10B981),
                                    onTap: () => widget.onUpdateBetStatus(bet.id, 'won'),
                                  ),
                                  const SizedBox(width: 6),
                                  _StatusChip(
                                    label: 'Veszített',
                                    active: bet.status == 'lost',
                                    color: const Color(0xFFEF4444),
                                    onTap: () => widget.onUpdateBetStatus(bet.id, 'lost'),
                                  ),
                                  const SizedBox(width: 6),
                                  _StatusChip(
                                    label: 'Függőben',
                                    active: bet.status == 'pending',
                                    color: const Color(0xFFF59E0B),
                                    onTap: () => widget.onUpdateBetStatus(bet.id, 'pending'),
                                  ),
                                  const SizedBox(width: 6),
                                  _StatusChip(
                                    label: 'Tét vissza',
                                    active: bet.status == 'void',
                                    color: const Color(0xFF9CA3AF),
                                    onTap: () => widget.onUpdateBetStatus(bet.id, 'void'),
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
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
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
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? color : const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: active ? Colors.black : Colors.white,
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 7. GRAFIKON RAJZOLÓK (SPARKLINE, ROI, MONTE CARLO)
// ==========================================

class RoiCurvePainter extends CustomPainter {
  final DoubleList values;

  RoiCurvePainter(this.values);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final minVal = math.min(0.0, values.reduce((a, b) => a < b ? a : b));
    final maxVal = math.max(0.0, values.reduce((a, b) => a > b ? a : b));
    final range = (maxVal - minVal) == 0 ? 1.0 : (maxVal - minVal);

    final zeroY = size.height - (((0.0 - minVal) / range) * size.height);
    final zeroPaint = Paint()
      ..color = const Color(0xFF374151)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, zeroY), Offset(size.width, zeroY), zeroPaint);

    final isPositive = values.last >= 0;
    final linePaint = Paint()
      ..color = isPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final x = (i / (values.length - 1)) * size.width;
      final y = size.height - (((values[i] - minVal) / range) * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class MonteCarloPainter extends CustomPainter {
  final CurveList curves;
  final double initialBankroll;

  MonteCarloPainter(this.curves, this.initialBankroll);

  @override
  void paint(Canvas canvas, Size size) {
    if (curves.isEmpty || curves.first.length < 2) return;

    double minVal = initialBankroll;
    double maxVal = initialBankroll;
    for (final c in curves) {
      for (final v in c) {
        if (v < minVal) minVal = v;
        if (v > maxVal) maxVal = v;
      }
    }
    final range = (maxVal - minVal) == 0 ? 1.0 : (maxVal - minVal);

    final baseY = size.height - (((initialBankroll - minVal) / range) * size.height);
    final basePaint = Paint()
      ..color = const Color(0xFF374151)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, baseY), Offset(size.width, baseY), basePaint);

    final faintPaint = Paint()
      ..color = const Color.fromRGBO(59, 130, 246, 0.22)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;

    final sortedCurves = List<DoubleList>.from(curves)
      ..sort((a, b) => a.last.compareTo(b.last));

    for (final c in sortedCurves) {
      final path = Path();
      for (int i = 0; i < c.length; i++) {
        final x = (i / (c.length - 1)) * size.width;
        final y = size.height - (((c[i] - minVal) / range) * size.height);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, faintPaint);
    }

    // Medián pálya kiemelése zölddel
    final medianCurve = sortedCurves[sortedCurves.length ~/ 2];
    final medPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke;
    final medPath = Path();
    for (int i = 0; i < medianCurve.length; i++) {
      final x = (i / (medianCurve.length - 1)) * size.width;
      final y = size.height - (((medianCurve[i] - minVal) / range) * size.height);
      if (i == 0) {
        medPath.moveTo(x, y);
      } else {
        medPath.lineTo(x, y);
      }
    }
    canvas.drawPath(medPath, medPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
