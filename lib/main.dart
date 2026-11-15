import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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
typedef SlipItemList = List<SlipItem>;
typedef ScoreProbList = List<ScoreProbability>;
typedef MarketOptionList = List<MarketOption>;
typedef StringDoubleMap = Map<String, double>;
typedef StringStringMap = Map<String, String>;
typedef RoiBreakdownList = List<RoiBreakdownItem>;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  runApp(const GoalEdgeApp());
}

// ==========================================
// 0. ANDROID PUSH ÉRTESÍTÉS SZOLGÁLTATÁS
// ==========================================

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);
      await _plugin.initialize(initSettings);
      final androidImpl =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();
      _initialized = true;
    } catch (_) {}
  }

  static Future<void> showAlert(int id, String title, String body) async {
    try {
      if (!_initialized) await init();
      const androidDetails = AndroidNotificationDetails(
        'goaledge_live_alerts',
        'GoalEdge Élő Riasztások',
        channelDescription: 'Értesítések gólokról és élő gólnyomásról',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      );
      const details = NotificationDetails(android: androidDetails);
      await _plugin.show(id, title, body, details);
    } catch (_) {}
  }
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
// 1. DIXON-COLES (PRE-MATCH & IN-PLAY) MOTOR
// ==========================================

class ScoreProbability {
  final String score;
  final double probability;

  ScoreProbability(this.score, this.probability);
}

class MarketOption {
  final String code;
  final String label;
  final String category;
  final double probability;
  final double fairOdds;
  final double refOdds;
  final double edgePercent;

  MarketOption({
    required this.code,
    required this.label,
    required this.category,
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
  final double ahHomeMinus05;
  final double ahHomeMinus10;
  final double ahAwayPlus05;
  final double htOver05;
  final double htOver15;
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
    required this.ahHomeMinus05,
    required this.ahHomeMinus10,
    required this.ahAwayPlus05,
    required this.htOver05,
    required this.htOver15,
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

  static PoissonResult calculate(
    double remHomeXg,
    double remAwayXg, {
    double rho = -0.085,
    int baseHomeScore = 0,
    int baseAwayScore = 0,
    double fullPreMatchTotalXg = 2.65,
  }) {
    final CurveList grid = List.generate(8, (_) => List.filled(8, 0.0));
    double totalMass = 0.0;

    for (int dh = 0; dh <= 7; dh++) {
      final ph = _pmf(remHomeXg, dh);
      for (int da = 0; da <= 7; da++) {
        final pa = _pmf(remAwayXg, da);
        final tau = _dixonColesTau(dh, da, remHomeXg, remAwayXg, rho);
        final p = ph * pa * tau;
        grid[dh][da] = p;
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
    double pAhM10Win = 0.0;
    double pAhM10Push = 0.0;
    final ScoreProbList scores = [];

    final norm = totalMass > 0 ? totalMass : 1.0;

    for (int dh = 0; dh <= 7; dh++) {
      for (int da = 0; da <= 7; da++) {
        final prob = grid[dh][da] / norm;
        final fh = baseHomeScore + dh;
        final fa = baseAwayScore + da;

        if (fh > fa) {
          pHome += prob;
        } else if (fh == fa) {
          pDraw += prob;
        } else {
          pAway += prob;
        }

        if ((fh - fa) >= 2) {
          pAhM10Win += prob;
        } else if ((fh - fa) == 1) {
          pAhM10Push += prob;
        }

        if (fh + fa > 1) pOver15 += prob;
        if (fh + fa > 2) pOver25 += prob;
        if (fh > 0 && fa > 0) pBtts += prob;
        if (fh > 1) pHomeOver15 += prob;
        if (fh <= 6 && fa <= 6) {
          scores.add(ScoreProbability('$fh-$fa', prob));
        }
      }
    }

    scores.sort((a, b) => b.probability.compareTo(a.probability));

    final p1 = pHome.clamp(0.02, 0.97);
    final pX = pDraw.clamp(0.02, 0.92);
    final p2 = pAway.clamp(0.02, 0.97);
    final p1X = (p1 + pX).clamp(0.05, 0.98);
    final pX2 = (pX + p2).clamp(0.05, 0.98);
    final pDnbHome = (p1 / (p1 + p2)).clamp(0.05, 0.97);
    final pO15 = pOver15.clamp(0.04, 0.98);
    final pO25 = pOver25.clamp(0.03, 0.97);
    final pU25 = (1.0 - pO25).clamp(0.03, 0.97);
    final pGg = pBtts.clamp(0.03, 0.97);
    final pHo15 = pHomeOver15.clamp(0.03, 0.97);

    final pAhM05 = p1;
    final nonPushMass = (1.0 - pAhM10Push).clamp(0.15, 1.0);
    final pAhM10 = (pAhM10Win / nonPushMass).clamp(0.04, 0.95);
    final pAhP05 = pX2;

    final htLambda = (fullPreMatchTotalXg * 0.44).clamp(0.35, 2.4);
    final pHt0 = _pmf(htLambda, 0);
    final pHt1 = _pmf(htLambda, 1);
    final pHtO05 = (1.0 - pHt0).clamp(0.15, 0.95);
    final pHtO15 = (1.0 - pHt0 - pHt1).clamp(0.05, 0.85);

    MarketOption buildOpt(String code, String label, String cat, double prob, double edgeBoost) {
      final fair = 1.0 / prob;
      final ref = double.parse((fair * edgeBoost).clamp(1.16, 5.80).toStringAsFixed(2));
      final edge = (prob - (1.0 / ref)) * 100.0;
      return MarketOption(
        code: code,
        label: label,
        category: cat,
        probability: prob,
        fairOdds: double.parse(fair.toStringAsFixed(2)),
        refOdds: ref,
        edgePercent: edge,
      );
    }

    final MarketOptionList options = [
      buildOpt('home', 'Hazai győzelem (1)', '1X2 & Dupla', p1, 1.07),
      buildOpt('draw', 'Döntetlen (X)', '1X2 & Dupla', pX, 1.06),
      buildOpt('away', 'Vendég győzelem (2)', '1X2 & Dupla', p2, 1.07),
      buildOpt('1x', 'Dupla esély (1X)', '1X2 & Dupla', p1X, 1.05),
      buildOpt('x2', 'Dupla esély (X2)', '1X2 & Dupla', pX2, 1.05),
      buildOpt('dnb_home', 'Hazai DNB (Tét visszajár)', '1X2 & Dupla', pDnbHome, 1.06),
      buildOpt('ah_home_m05', 'Ázsiai Hendikep Hazai -0.5', 'Ázsiai Hendikep', pAhM05, 1.08),
      buildOpt('ah_home_m10', 'Ázsiai Hendikep Hazai -1.0', 'Ázsiai Hendikep', pAhM10, 1.09),
      buildOpt('ah_away_p05', 'Ázsiai Hendikep Vendég +0.5', 'Ázsiai Hendikep', pAhP05, 1.06),
      buildOpt('over15', '1.5 gól felett', 'Gólok / BTTS', pO15, 1.05),
      buildOpt('over25', '2.5 gól felett', 'Gólok / BTTS', pO25, 1.09),
      buildOpt('under25', '2.5 gól alatt', 'Gólok / BTTS', pU25, 1.08),
      buildOpt('btts', 'Mindkét csapat szerez gólt (BTTS)', 'Gólok / BTTS', pGg, 1.09),
      buildOpt('home_over15', 'Hazai csapat 1.5 gól felett', 'Gólok / BTTS', pHo15, 1.08),
      buildOpt('ht_over05', '1. Félidő 0.5 gól felett', '1. Félidő', pHtO05, 1.06),
      buildOpt('ht_over15', '1. Félidő 1.5 gól felett', '1. Félidő', pHtO15, 1.09),
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
      ahHomeMinus05: pAhM05,
      ahHomeMinus10: pAhM10,
      ahAwayPlus05: pAhP05,
      htOver05: pHtO05,
      htOver15: pHtO15,
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

  double get blendedGoalsFor {
    if (form.isEmpty) return avgGoalsFor;
    int gf = 0;
    int cnt = 0;
    for (final f in form.take(5)) {
      final hg = (f['home_score'] as num?)?.toInt() ?? 0;
      final ag = (f['away_score'] as num?)?.toInt() ?? 0;
      final isHome = (f['home_team'] ?? '').toString() == teamName;
      gf += isHome ? hg : ag;
      cnt++;
    }
    if (cnt == 0) return avgGoalsFor;
    return (0.65 * avgGoalsFor) + (0.35 * (gf / cnt));
  }

  double get blendedGoalsAgainst {
    if (form.isEmpty) return avgGoalsAgainst;
    int ga = 0;
    int cnt = 0;
    for (final f in form.take(5)) {
      final hg = (f['home_score'] as num?)?.toInt() ?? 0;
      final ag = (f['away_score'] as num?)?.toInt() ?? 0;
      final isHome = (f['home_team'] ?? '').toString() == teamName;
      ga += isHome ? ag : hg;
      cnt++;
    }
    if (cnt == 0) return avgGoalsAgainst;
    return (0.65 * avgGoalsAgainst) + (0.35 * (ga / cnt));
  }
}

class SlipItem {
  final String key;
  final String matchId;
  final String matchTitle;
  final String league;
  final String kickoff;
  final String marketCode;
  final String marketLabel;
  final double odds;
  final double modelProb;

  SlipItem({
    required this.key,
    required this.matchId,
    required this.matchTitle,
    required this.league,
    required this.kickoff,
    required this.marketCode,
    required this.marketLabel,
    required this.odds,
    required this.modelProb,
  });
}

class RoiBreakdownItem {
  final String name;
  final int count;
  final double profit;
  final double roiPercent;
  final double winRatePercent;

  RoiBreakdownItem({
    required this.name,
    required this.count,
    required this.profit,
    required this.roiPercent,
    required this.winRatePercent,
  });
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
  String marketCategory;
  String trendSummary;
  String trendCategory;
  double modelProb;
  double marketOdds;
  bool isCustomOdds;
  DoubleList oddsHistory;
  double homeXg;
  double awayXg;
  int? liveHomeSot;
  int? liveAwaySot;
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
    this.marketCategory = 'Gólok / BTTS',
    required this.trendSummary,
    required this.trendCategory,
    required this.modelProb,
    required this.marketOdds,
    this.isCustomOdds = false,
    required this.oddsHistory,
    required this.homeXg,
    required this.awayXg,
    this.liveHomeSot,
    this.liveAwaySot,
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
  bool get isLive => status == 'LIVE';
  bool get isFinished => status == 'FT' || status == 'AET' || status == 'PENS';

  // Dropping Odds (Steam Move) számítás
  double get oddsDropPercent {
    if (oddsHistory.isEmpty) return 0.0;
    final openOdds = oddsHistory.first;
    if (openOdds <= 1.0) return 0.0;
    return ((openOdds - marketOdds) / openOdds) * 100.0;
  }

  bool get isSteamMove => oddsDropPercent >= 5.0;

  int get parsedMinute {
    if (minute == null) return 0;
    if (minute == 'HT') return 45;
    final clean = minute!.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(clean) ?? 0;
  }

  double get inPlayRemHomeXg {
    if (!isLive) return homeXg;
    final elapsed = parsedMinute.clamp(1, 89);
    final remFrac = ((90 - elapsed) / 90.0).clamp(0.06, 0.98);
    double factor = 1.0;
    if (liveHomeSot != null) {
      final expectedSot = 4.2 * (elapsed / 90.0);
      factor = ((liveHomeSot! + 1.2) / (expectedSot + 1.2)).clamp(0.65, 1.55);
    }
    return (homeXg * remFrac * factor).clamp(0.08, 3.2);
  }

  double get inPlayRemAwayXg {
    if (!isLive) return awayXg;
    final elapsed = parsedMinute.clamp(1, 89);
    final remFrac = ((90 - elapsed) / 90.0).clamp(0.06, 0.98);
    double factor = 1.0;
    if (liveAwaySot != null) {
      final expectedSot = 4.2 * (elapsed / 90.0);
      factor = ((liveAwaySot! + 1.2) / (expectedSot + 1.2)).clamp(0.65, 1.55);
    }
    return (awayXg * remFrac * factor).clamp(0.08, 3.2);
  }

  PoissonResult get poisson => PoissonEngine.calculate(
        isLive ? inPlayRemHomeXg : homeXg,
        isLive ? inPlayRemAwayXg : awayXg,
        baseHomeScore: isLive ? (homeScore ?? 0) : 0,
        baseAwayScore: isLive ? (awayScore ?? 0) : 0,
        fullPreMatchTotalXg: homeXg + awayXg,
      );

  int recommendedStake(double bankroll, String profile) {
    if (profile == 'fix_2') {
      return (bankroll * 0.02).round();
    }
    final kelly = ((modelProb * marketOdds) - 1.0) / (marketOdds - 1.0);
    if (kelly <= 0) return 0;
    final mult = profile == 'quarter_kelly' ? 0.25 : 0.50;
    final frac = (kelly * mult).clamp(0.005, 0.06);
    return (bankroll * frac).round();
  }

  bool get isHighPressure {
    if (!isLive) return false;
    final min = parsedMinute;
    final diff = ((homeScore ?? 0) - (awayScore ?? 0)).abs();
    final totalSot = (liveHomeSot ?? 0) + (liveAwaySot ?? 0);
    return min >= 60 && diff <= 1 && ((homeXg + awayXg) >= 2.35 || totalSot >= 7);
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
        'marketCategory': marketCategory,
        'trendSummary': trendSummary,
        'trendCategory': trendCategory,
        'modelProb': modelProb,
        'marketOdds': marketOdds,
        'isCustomOdds': isCustomOdds,
        'oddsHistory': oddsHistory,
        'homeXg': homeXg,
        'awayXg': awayXg,
        'liveHomeSot': liveHomeSot,
        'liveAwaySot': liveAwaySot,
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
        marketCategory: json['marketCategory'] ?? 'Gólok / BTTS',
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
        liveHomeSot: (json['liveHomeSot'] as num?)?.toInt(),
        liveAwaySot: (json['liveAwaySot'] as num?)?.toInt(),
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
  final JsonList h2hMatches;

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
    this.h2hMatches = const [],
  });
}

class BetRecord {
  final String id;
  final int? fixtureId;
  final String league;
  final String matchTitle;
  final String market;
  final String marketCode;
  final String marketCategory;
  final double odds;
  final double? closingOdds;
  final double? modelProb;
  final double stake;
  final String status;
  final String date;

  BetRecord({
    required this.id,
    this.fixtureId,
    this.league = 'Egyéb',
    required this.matchTitle,
    required this.market,
    this.marketCode = 'over25',
    this.marketCategory = 'Gólok / BTTS',
    required this.odds,
    this.closingOdds,
    this.modelProb,
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
        'league': league,
        'matchTitle': matchTitle,
        'market': market,
        'marketCode': marketCode,
        'marketCategory': marketCategory,
        'odds': odds,
        'closingOdds': closingOdds,
        'modelProb': modelProb,
        'stake': stake,
        'status': status,
        'date': date,
      };

  factory BetRecord.fromJson(JsonMap json) => BetRecord(
        id: json['id'] ?? '',
        fixtureId: (json['fixtureId'] as num?)?.toInt(),
        league: json['league'] ?? 'Egyéb',
        matchTitle: json['matchTitle'] ?? '',
        market: json['market'] ?? '',
        marketCode: json['marketCode'] ?? 'over25',
        marketCategory: json['marketCategory'] ?? 'Gólok / BTTS',
        odds: (json['odds'] as num?)?.toDouble() ?? 1.80,
        closingOdds: (json['closingOdds'] as num?)?.toDouble(),
        modelProb: (json['modelProb'] as num?)?.toDouble(),
        stake: (json['stake'] as num?)?.toDouble() ?? 1000.0,
        status: json['status'] ?? 'pending',
        date: json['date'] ?? '',
      );
}

// ==========================================
// 3. SPORTAPI.AI KLIENS (IN-PLAY + H2H + FORMA)
// ==========================================

class SportApiResponse {
  final bool success;
  final int statusCode;
  final MatchList matches;
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
  static final StringStringMap _etagCache = {};
  static final StringStringMap _bodyCache = {};

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
            final hAttack = hInfo.blendedGoalsFor / lAvg;
            final aDefense = aInfo.blendedGoalsAgainst / lAvg;
            final aAttack = aInfo.blendedGoalsFor / lAvg;
            final hDefense = hInfo.blendedGoalsAgainst / lAvg;

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
    int? liveHomeSot,
    int? liveAwaySot,
    required BoolList last6Trend,
    required StringList homeFormCodes,
    required StringList awayFormCodes,
    int? homePos,
    int? awayPos,
    required bool hasStandingData,
    required bool isWatched,
    double? customOdds,
  }) {
    final isLive = status == 'LIVE';
    int elapsed = 0;
    if (minute == 'HT') {
      elapsed = 45;
    } else if (minute != null) {
      elapsed = (int.tryParse(minute.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0).clamp(1, 89);
    }
    final remFrac = isLive ? ((90 - elapsed) / 90.0).clamp(0.06, 0.98) : 1.0;

    final poisson = PoissonEngine.calculate(
      isLive ? (homeXg * remFrac).clamp(0.08, 3.2) : homeXg,
      isLive ? (awayXg * remFrac).clamp(0.08, 3.2) : awayXg,
      baseHomeScore: isLive ? (homeScore ?? 0) : 0,
      baseAwayScore: isLive ? (awayScore ?? 0) : 0,
      fullPreMatchTotalXg: homeXg + awayXg,
    );

    MarketOption best = poisson.allMarkets.first;
    for (final opt in poisson.allMarkets) {
      if (isLive && opt.code.startsWith('ht_')) continue;
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
    if (isLive) {
      summary =
          'ÉLŐ In-Play Dixon-Coles ($minute\'): hátralévő xG ${(homeXg * remFrac).toStringAsFixed(2)} – ${(awayXg * remFrac).toStringAsFixed(2)} • Élő Fair szorzó: ${best.fairOdds}.';
    } else if (hasStandingData && homePos != null && awayPos != null) {
      summary =
          'Forma-súlyozott xG (${homeXg.toStringAsFixed(2)} – ${awayXg.toStringAsFixed(2)}) • Tabella: $homePos. vs $awayPos. hely • BTTS: ${(poisson.btts * 100).round()}%.';
    } else {
      summary =
          'Dixon-Coles 16-piacos modell: össz-xG ${(homeXg + awayXg).toStringAsFixed(2)}, 2.5+ gól ${(poisson.over25 * 100).round()}%, 1. Félidő 0.5+ ${(poisson.htOver05 * 100).round()}%.';
    }

    final DoubleList hist = [
      double.parse((best.refOdds + 0.14).toStringAsFixed(2)),
      double.parse((best.refOdds + 0.08).toStringAsFixed(2)),
      double.parse((best.refOdds + 0.03).toStringAsFixed(2)),
      best.refOdds,
    ];
    if (customOdds != null && customOdds != best.refOdds) {
      hist.add(customOdds);
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
      marketCategory: best.category,
      trendSummary: summary,
      trendCategory: category,
      modelProb: best.probability,
      marketOdds: finalOdds,
      isCustomOdds: customOdds != null,
      oddsHistory: hist,
      homeXg: double.parse(homeXg.toStringAsFixed(2)),
      awayXg: double.parse(awayXg.toStringAsFixed(2)),
      liveHomeSot: liveHomeSot,
      liveAwaySot: liveAwaySot,
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

  static Future<JsonList> fetchH2H({
    required String baseUrl,
    required String apiKey,
    required int fixtureId,
    int? homeId,
    int? awayId,
  }) async {
    final cleanBase = baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    final candidateUris = <Uri>[
      Uri.parse('$cleanBase/fixtures/$fixtureId/h2h'),
      if (homeId != null && awayId != null) Uri.parse('$cleanBase/teams/$homeId/h2h/$awayId'),
    ];

    for (final uri in candidateUris) {
      try {
        final res = await _getWithEtag(uri, apiKey);
        if (res.statusCode == 200) {
          final decoded = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
          final dynamic raw = (decoded is Map) ? (decoded['data'] ?? decoded['h2h']) : decoded;
          if (raw is List && raw.isNotEmpty) {
            final JsonList list = [];
            for (final item in raw) {
              if (item is JsonMap) list.add(item);
            }
            if (list.isNotEmpty) return list;
          }
        }
      } catch (_) {}
    }
    return [];
  }

  static Future<FixtureFullBundle?> fetchFullBundle({
    required String baseUrl,
    required String apiKey,
    required int fixtureId,
    int? leagueId,
    int? homeId,
    int? awayId,
  }) async {
    final cleanBase = baseUrl.trim().replaceAll(RegExp(r'/$'), '');

    try {
      final f0 = _getWithEtag(Uri.parse('$cleanBase/fixtures/$fixtureId'), apiKey);
      final f1 = _getWithEtag(Uri.parse('$cleanBase/fixtures/$fixtureId/stats'), apiKey);
      final f2 = _getWithEtag(Uri.parse('$cleanBase/fixtures/$fixtureId/lineups'), apiKey);
      final f3 = fetchH2H(
        baseUrl: baseUrl,
        apiKey: apiKey,
        fixtureId: fixtureId,
        homeId: homeId,
        awayId: awayId,
      );

      final r0 = await f0;
      final r1 = await f1;
      final r2 = await f2;
      final h2hList = await f3;

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
        h2hMatches: h2hList,
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
  bool _autoBankroll = true;
  String _stakeProfile = 'half_kelly';
  Timer? _liveTimer;

  String _apiKey = '';
  String _baseUrl = SportApiService.defaultBaseUrl;
  String _lastApiStatus = 'Még nem futott élő lekérés.';
  String? _rateLimitRemaining;

  double _bankroll = 50000;
  MatchList _matches = [];
  BetList _bets = [];
  final SlipItemList _slipItems = [];
  final StringDoubleMap _customOddsMap = {};
  final Set<String> _favoriteLeagues = {'Premier League', 'NB I', 'UEFA Champions League'};
  final StringStringMap _lastKnownScores = {};
  final Set<String> _notifiedPressureIds = {};

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
        const SnackBar(content: Text('Élő Radar aktiválva (75 mp ETag + Push értesítés).')),
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
        marketCategory: 'Gólok / BTTS',
        trendSummary: 'Forma-súlyozott xG: az utolsó 6 meccsből 5-ször mindkét fél betalált.',
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
        marketCategory: 'Gólok / BTTS',
        trendSummary: 'Forma-súlyozott xG: a Paks idegenben 3.4-es gólátlagot hoz, FTC hazai xG 2.35.',
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
        market: 'Ázsiai Hendikep Hazai -0.5',
        marketCode: 'ah_home_m05',
        marketCategory: 'Ázsiai Hendikep',
        trendSummary: 'Dixon-Coles 16-piacos előny: a Sociedad hazai pályán dominál (1.98 xG).',
        trendCategory: 'Tabella & Forma',
        modelProb: PoissonEngine.calculate(1.98, 1.05).ahHomeMinus05,
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
    final savedAutoBankroll = prefs.getBool('auto_bankroll') ?? true;
    final savedStakeProfile = prefs.getString('stake_profile') ?? 'half_kelly';
    final watchedIds = prefs.getStringList('watched_ids') ?? [];
    final favLeagues = prefs.getStringList('favorite_leagues');
    final betsJson = prefs.getString('logged_bets');
    final cachedMatchesJson = prefs.getString('cached_matches_v6');
    final customOddsJson = prefs.getString('custom_odds_map');

    setState(() {
      _apiKey = savedKey;
      _baseUrl = savedBase;
      _bankroll = savedBankroll;
      _autoBankroll = savedAutoBankroll;
      _stakeProfile = savedStakeProfile;

      if (favLeagues != null) {
        _favoriteLeagues
          ..clear()
          ..addAll(favLeagues);
      }

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
    await prefs.setBool('auto_bankroll', _autoBankroll);
    await prefs.setString('stake_profile', _stakeProfile);
    await prefs.setStringList('favorite_leagues', _favoriteLeagues.toList());
    final watchedIds = _matches.where((m) => m.isWatched).map((m) => m.id).toList();
    await prefs.setStringList('watched_ids', watchedIds);
    await prefs.setString('logged_bets', jsonEncode(_bets.map((b) => b.toJson()).toList()));
    await prefs.setString('custom_odds_map', jsonEncode(_customOddsMap));
    if (_isLiveMode && _matches.isNotEmpty) {
      await prefs.setString('cached_matches_v6', jsonEncode(_matches.map((m) => m.toJson()).toList()));
    }
  }

  void _toggleFavoriteLeague(String league) {
    if (league == 'Összes') return;
    setState(() {
      if (_favoriteLeagues.contains(league)) {
        _favoriteLeagues.remove(league);
      } else {
        _favoriteLeagues.add(league);
      }
    });
    _saveState();
  }

  String _exportBackupJson() {
    final backup = <String, dynamic>{
      'version': 6,
      'apiKey': _apiKey,
      'baseUrl': _baseUrl,
      'bankroll': _bankroll,
      'autoBankroll': _autoBankroll,
      'stakeProfile': _stakeProfile,
      'favoriteLeagues': _favoriteLeagues.toList(),
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
        if (decoded['autoBankroll'] is bool) _autoBankroll = decoded['autoBankroll'];
        if (decoded['stakeProfile'] is String) _stakeProfile = decoded['stakeProfile'];

        if (decoded['favoriteLeagues'] is List) {
          _favoriteLeagues
            ..clear()
            ..addAll((decoded['favoriteLeagues'] as List).map((e) => e.toString()));
        }

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

  void _checkAndFirePushNotifications(MatchList fresh) {
    for (final m in fresh) {
      if (m.homeScore != null && m.awayScore != null) {
        final scoreKey = '${m.homeScore}-${m.awayScore}';
        final prevScore = _lastKnownScores[m.id];
        if (prevScore != null && prevScore != scoreKey && (m.isWatched || m.isLive)) {
          NotificationService.showAlert(
            m.fixtureId ?? m.id.hashCode,
            '⚽ GÓL! ${m.homeTeam} $scoreKey ${m.awayTeam}',
            '${m.league} (${m.minute ?? "LIVE"}\') • Ajánlott piac: ${m.market}',
          );
        }
        _lastKnownScores[m.id] = scoreKey;
      }

      if (m.isHighPressure && !_notifiedPressureIds.contains(m.id)) {
        _notifiedPressureIds.add(m.id);
        NotificationService.showAlert(
          (m.fixtureId ?? m.id.hashCode) + 100000,
          '🔥 GÓLNYOMÁS: ${m.homeTeam} – ${m.awayTeam}',
          '${m.minute ?? "LIVE"}\' (${m.homeScore ?? 0}-${m.awayScore ?? 0}) • Magas élő xG nyomás!',
        );
      }
    }
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
        _checkAndFirePushNotifications(result.matches);
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
    final leagueIds = _matches.map((m) => m.leagueId).whereType<int>().toSet().take(6);

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
          final hAttack = hInfo.blendedGoalsFor / lAvg;
          final aDefense = aInfo.blendedGoalsAgainst / lAvg;
          final aAttack = aInfo.blendedGoalsFor / lAvg;
          final hDefense = hInfo.blendedGoalsAgainst / lAvg;

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
      if (bet.marketCode == 'ah_home_m05' && hs > as) newStatus = 'won';
      if (bet.marketCode == 'ah_away_p05' && as >= hs) newStatus = 'won';
      if (bet.marketCode == 'ah_home_m10') {
        if ((hs - as) >= 2) {
          newStatus = 'won';
        } else if ((hs - as) == 1) {
          newStatus = 'void';
        }
      }
      if (bet.marketCode == 'over15' && (hs + as) > 1) newStatus = 'won';
      if (bet.marketCode == 'over25' && (hs + as) > 2) newStatus = 'won';
      if (bet.marketCode == 'under25' && (hs + as) <= 2) newStatus = 'won';
      if (bet.marketCode == 'btts' && hs > 0 && as > 0) newStatus = 'won';
      if (bet.marketCode == 'home_over15' && hs > 1) newStatus = 'won';

      _updateBetStatus(bet.id, newStatus);
      changed = true;
    }

    if (changed) {
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

  bool _isMarketInSlip(String matchId, String marketCode) {
    return _slipItems.any((s) => s.matchId == matchId && s.marketCode == marketCode);
  }

  void _toggleSlipOption(MatchPick match, {MarketOption? chosenMarket}) {
    final code = chosenMarket?.code ?? match.marketCode;
    final label = chosenMarket?.label ?? match.market;
    final odds = chosenMarket?.refOdds ?? match.marketOdds;
    final prob = chosenMarket?.probability ?? match.modelProb;
    final key = '${match.id}_$code';

    setState(() {
      final existingIdx = _slipItems.indexWhere((s) => s.key == key);
      if (existingIdx != -1) {
        _slipItems.removeAt(existingIdx);
      } else {
        if (_slipItems.length >= 6) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Maximum 6 kötés tehető egy kombi szelvényre!')),
          );
          return;
        }
        _slipItems.removeWhere((s) => s.matchId == match.id);
        _slipItems.add(
          SlipItem(
            key: key,
            matchId: match.id,
            matchTitle: '${match.homeTeam} – ${match.awayTeam}',
            league: match.league,
            kickoff: match.kickoff,
            marketCode: code,
            marketLabel: label,
            odds: odds,
            modelProb: prob,
          ),
        );
        HapticFeedback.selectionClick();
      }
    });
  }

  void _generateAiSlip({required bool conservative}) {
    final candidates = _matches.where((m) => !m.isFinished && m.edgePercent > 0).toList();
    if (candidates.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nincs elég aktív mérkőzés a szelvénygeneráláshoz!')),
      );
      return;
    }

    final SlipItemList generated = [];
    if (conservative) {
      // Konzervatív Duplázó: legmagasabb valószínűségű 2 kötés
      final JsonList pool = [];
      for (final m in candidates) {
        for (final opt in m.poisson.allMarkets) {
          if (opt.probability >= 0.58 && opt.refOdds >= 1.28 && opt.refOdds <= 1.75) {
            pool.add({'match': m, 'opt': opt, 'score': opt.probability * 100 + opt.edgePercent});
          }
        }
      }
      pool.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
      final usedMatches = <String>{};
      for (final entry in pool) {
        final m = entry['match'] as MatchPick;
        final opt = entry['opt'] as MarketOption;
        if (usedMatches.contains(m.id)) continue;
        usedMatches.add(m.id);
        generated.add(
          SlipItem(
            key: '${m.id}_${opt.code}',
            matchId: m.id,
            matchTitle: '${m.homeTeam} – ${m.awayTeam}',
            league: m.league,
            kickoff: m.kickoff,
            marketCode: opt.code,
            marketLabel: opt.label,
            odds: opt.refOdds,
            modelProb: opt.probability,
          ),
        );
        if (generated.length == 2) break;
      }
    } else {
      // Value Tripla: legnagyobb matematikai előnyű 3 kötés
      candidates.sort((a, b) => b.edgePercent.compareTo(a.edgePercent));
      for (final m in candidates.take(3)) {
        generated.add(
          SlipItem(
            key: '${m.id}_${m.marketCode}',
            matchId: m.id,
            matchTitle: '${m.homeTeam} – ${m.awayTeam}',
            league: m.league,
            kickoff: m.kickoff,
            marketCode: m.marketCode,
            marketLabel: m.market,
            odds: m.marketOdds,
            modelProb: m.modelProb,
          ),
        );
      }
    }

    if (generated.isEmpty) return;
    setState(() {
      _slipItems
        ..clear()
        ..addAll(generated);
    });
    HapticFeedback.mediumImpact();
    _openComboSlipSheet();
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
                      league: bet.league,
                      matchTitle: bet.matchTitle,
                      market: bet.market,
                      marketCode: bet.marketCode,
                      marketCategory: bet.marketCategory,
                      odds: bet.odds,
                      closingOdds: parsed,
                      modelProb: bet.modelProb,
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

  String _formatSlipShareText(SlipItemList items, double totalOdds, double stake, bool isSystem) {
    final buf = StringBuffer();
    final modeTitle = isSystem
        ? (items.length == 3 ? 'System 2/3' : 'System 3/4')
        : 'Kombi (${items.length} kötés)';
    buf.writeln('📊 GoalEdge AI Szelvény – $modeTitle');
    buf.writeln('────────────────────');
    for (int i = 0; i < items.length; i++) {
      final it = items[i];
      buf.writeln('${i + 1}. ${it.matchTitle} (${it.league})');
      buf.writeln('   ▶ ${it.marketLabel} @ ${it.odds.toStringAsFixed(2)}');
    }
    buf.writeln('────────────────────');
    if (!isSystem) {
      buf.writeln('🔥 Eredő szorzó: ${totalOdds.toStringAsFixed(2)}x');
      buf.writeln('💰 Tét: ${stake.round()} Ft → Várható: ${(stake * totalOdds).round()} Ft');
    } else {
      buf.writeln('💰 Össztét: ${stake.round()} Ft ($modeTitle)');
    }
    return buf.toString();
  }

  void _openComboSlipSheet() {
    if (_slipItems.isEmpty) return;
    double comboStake = (_bankroll * 0.02).clamp(500, 30000).roundToDouble();
    bool useSystem = false;

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
            if (_slipItems.isEmpty) {
              Navigator.pop(context);
              return const SizedBox.shrink();
            }

            final canSystem = _slipItems.length == 3 || _slipItems.length == 4;
            if (!canSystem) useSystem = false;

            double totalOdds = 1.0;
            double combinedProb = 1.0;
            for (final it in _slipItems) {
              totalOdds *= it.odds;
              combinedProb *= it.modelProb;
            }
            final comboEv = (combinedProb * totalOdds) - 1.0;

            // System 2/3 vagy 3/4 számítás
            double sysMinWin = 0.0;
            double sysMaxWin = 0.0;
            final int sysCombos = _slipItems.length;
            if (canSystem && useSystem) {
              final lineStake = comboStake / sysCombos;
              final DoubleList subOdds = [];
              for (int skip = 0; skip < _slipItems.length; skip++) {
                double prod = 1.0;
                for (int j = 0; j < _slipItems.length; j++) {
                  if (j != skip) prod *= _slipItems[j].odds;
                }
                subOdds.add(prod);
              }
              subOdds.sort();
              sysMinWin = lineStake * subOdds.first;
              sysMaxWin = subOdds.fold<double>(0.0, (s, o) => s + (lineStake * o));
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Kombi Szelvény (${_slipItems.length} kötés)',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      TextButton(
                        onPressed: () {
                          setState(() => _slipItems.clear());
                          Navigator.pop(context);
                        },
                        child: const Text('Ürítés', style: TextStyle(color: Color(0xFFEF4444))),
                      ),
                    ],
                  ),
                  if (canSystem) ...[
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<bool>(
                        segments: [
                          const ButtonSegment(value: false, label: Text('Normál Kombi', style: TextStyle(fontSize: 11))),
                          ButtonSegment(
                            value: true,
                            label: Text(_slipItems.length == 3 ? 'System 2/3' : 'System 3/4',
                                style: const TextStyle(fontSize: 11)),
                          ),
                        ],
                        selected: {useSystem},
                        onSelectionChanged: (s) => setModalState(() => useSystem = s.first),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  ..._slipItems.map((it) {
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
                                Text(it.matchTitle,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                Text('${it.marketLabel} (${(it.modelProb * 100).round()}%)',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                              ],
                            ),
                          ),
                          Text('@ ${it.odds.toStringAsFixed(2)}',
                              style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                            onPressed: () {
                              setState(() => _slipItems.removeWhere((e) => e.key == it.key));
                              setModalState(() {});
                            },
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0E17),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: useSystem
                        ? Column(
                            children: [
                              _StatCompareRow(
                                label: 'Alaptét / oszlop ($sysCombos db)',
                                homeVal: '${(comboStake / sysCombos).round()} Ft',
                                awayVal: 'Összesen: ${comboStake.round()} Ft',
                              ),
                              _StatCompareRow(
                                label: 'Min / Max nyeremény',
                                homeVal: 'Min: ${sysMinWin.round()} Ft',
                                awayVal: 'Max: ${sysMaxWin.round()} Ft',
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              _StatCompareRow(
                                label: 'Eredő szorzó',
                                homeVal: '${(combinedProb * 100).toStringAsFixed(1)}% esély',
                                awayVal: '${totalOdds.toStringAsFixed(2)}x',
                              ),
                              _StatCompareRow(
                                label: 'Kombinált EV',
                                homeVal: 'Várható érték',
                                awayVal: '${comboEv >= 0 ? '+' : ''}${(comboEv * 100).toStringAsFixed(1)}%',
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    useSystem
                        ? 'Össztét: ${comboStake.round()} Ft → Max: ${sysMaxWin.round()} Ft'
                        : 'Tét: ${comboStake.round()} Ft → Várható: ${(comboStake * totalOdds).round()} Ft',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Slider(
                    value: comboStake,
                    min: 500,
                    max: 50000,
                    divisions: 99,
                    activeColor: const Color(0xFF10B981),
                    onChanged: (v) => setModalState(() => comboStake = v),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            final text = _formatSlipShareText(_slipItems, totalOdds, comboStake, useSystem);
                            Clipboard.setData(ClipboardData(text: text));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Formázott szelvény vágólapra másolva!')),
                            );
                          },
                          icon: const Icon(Icons.share, size: 16),
                          label: const Text('Másolás', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: () {
                            final now = DateTime.now();
                            final dateLabel =
                                '${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}.';
                            final prefix = useSystem
                                ? (_slipItems.length == 3 ? 'System 2/3' : 'System 3/4')
                                : 'Kombi (${_slipItems.length})';
                            final title =
                                '$prefix: ${_slipItems.map((e) => e.matchTitle.split(' – ').first).join(', ')}';
                            final effectiveOdds = useSystem ? (sysMaxWin / comboStake) : totalOdds;
                            setState(() {
                              _bets.insert(
                                0,
                                BetRecord(
                                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                                  league: useSystem ? 'System' : 'Kombi',
                                  matchTitle: title,
                                  market: _slipItems.map((e) => e.marketLabel).join(' + '),
                                  marketCode: useSystem ? 'system' : 'combo',
                                  marketCategory: useSystem ? 'System' : 'Kombi',
                                  odds: double.parse(effectiveOdds.toStringAsFixed(2)),
                                  modelProb: double.parse(combinedProb.toStringAsFixed(3)),
                                  stake: comboStake,
                                  status: 'pending',
                                  date: dateLabel,
                                ),
                              );
                              _slipItems.clear();
                            });
                            _saveState();
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Szelvény rögzítve a Tippnaplóba!')),
                            );
                          },
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('Szelvény naplózása'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                        ),
                      ),
                    ],
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
    final mCat = chosenMarket?.category ?? match.marketCategory;
    final mOdds = chosenMarket?.refOdds ?? match.marketOdds;
    final mProb = chosenMarket?.probability ?? match.modelProb;

    setState(() {
      _bets.insert(
        0,
        BetRecord(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          fixtureId: match.fixtureId,
          league: match.league,
          matchTitle: '${match.homeTeam} – ${match.awayTeam}',
          market: mLabel,
          marketCode: mCode,
          marketCategory: mCat,
          odds: mOdds,
          modelProb: mProb,
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
        final updated = BetRecord(
          id: old.id,
          fixtureId: old.fixtureId,
          league: old.league,
          matchTitle: old.matchTitle,
          market: old.market,
          marketCode: old.marketCode,
          marketCategory: old.marketCategory,
          odds: old.odds,
          closingOdds: old.closingOdds,
          modelProb: old.modelProb,
          stake: old.stake,
          status: newStatus,
          date: old.date,
        );
        if (_autoBankroll) {
          final delta = updated.profit - old.profit;
          _bankroll = (_bankroll + delta).clamp(1000, 10000000);
        }
        _bets[idx] = updated;
      }
    });
    _saveState();
  }

  void _deleteBet(String betId) {
    setState(() {
      final idx = _bets.indexWhere((b) => b.id == betId);
      if (idx != -1) {
        final old = _bets[idx];
        if (_autoBankroll) {
          _bankroll = (_bankroll - old.profit).clamp(1000, 10000000);
        }
        _bets.removeAt(idx);
      }
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
                    Row(
                      children: [
                        Expanded(
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
                                : const Icon(Icons.bolt, size: 16),
                            label: const Text('API Teszt', style: TextStyle(fontSize: 11)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              NotificationService.showAlert(
                                99999,
                                '⚽ GoalEdge AI Teszt Értesítés',
                                'A valódi Android Push riasztások aktívak és működnek!',
                              );
                            },
                            icon: const Icon(Icons.notifications_active, size: 16),
                            label: const Text('Push Teszt', style: TextStyle(fontSize: 11)),
                          ),
                        ),
                      ],
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
                    const Divider(height: 22, color: Color(0xFF1F2937)),
                    const Text(
                      'JSON Biztonsági Mentés (Újratelepítéshez)',
                      style: TextStyle(fontSize: 12, color: Color(0xFF3B82F6), fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          final jsonStr = _exportBackupJson();
                          Clipboard.setData(ClipboardData(text: jsonStr));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Teljes biztonsági mentés vágólapra másolva!')),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 15),
                        label: const Text('Mentés másolása vágólapra', style: TextStyle(fontSize: 11)),
                      ),
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
    final rec = match.recommendedStake(_bankroll, _stakeProfile);
    double stake = (rec > 0 ? rec.toDouble() : _bankroll * 0.02).clamp(500, 50000).roundToDouble();
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
        homeId: match.homeId,
        awayId: match.awayId,
      );
    }

    double homeModifier = 1.0;
    double awayModifier = 1.0;
    bool useInPlaySim = match.isLive;
    double simMinute = (match.isLive ? match.parsedMinute : 0).toDouble();
    int simHomeGoals = match.homeScore ?? 0;
    int simAwayGoals = match.awayScore ?? 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF131A29),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return DefaultTabController(
          length: 5,
          child: StatefulBuilder(
            builder: (context, setModalState) {
              final remFrac = useInPlaySim ? ((90.0 - simMinute) / 90.0).clamp(0.05, 1.0) : 1.0;
              final baseH = useInPlaySim ? (match.homeXg * remFrac) : match.homeXg;
              final baseA = useInPlaySim ? (match.awayXg * remFrac) : match.awayXg;
              final adjHomeXg = (baseH * homeModifier).clamp(0.06, 4.5);
              final adjAwayXg = (baseA * awayModifier).clamp(0.06, 4.5);
              final poisson = PoissonEngine.calculate(
                adjHomeXg,
                adjAwayXg,
                baseHomeScore: useInPlaySim ? simHomeGoals : 0,
                baseAwayScore: useInPlaySim ? simAwayGoals : 0,
                fullPreMatchTotalXg: match.homeXg + match.awayXg,
              );
              final fairMainOdds = 1.0 / match.modelProb;

              return SizedBox(
                height: MediaQuery.of(context).size.height * 0.89,
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
                                  match.isLive
                                      ? 'ÉLŐ IN-PLAY (${match.minute ?? "LIVE"}\')'
                                      : '+${match.edgePercent.toStringAsFixed(1)}% VALUE',
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
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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
                        Tab(text: '16 Piac & In-Play'),
                        Tab(text: 'Statisztika'),
                        Tab(text: 'Kezdőcsapatok'),
                        Tab(text: 'Tabella'),
                        Tab(text: 'H2H'),
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
                              // 1. FÜL: 16 PIAC, ODDS GRAFIKON & ÉLŐ SZIMULÁTOR
                              ListView(
                                padding: const EdgeInsets.all(20),
                                children: [
                                  // ODDS MOZGÁS GRAFIKON
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
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'Odds mozgás (${match.oddsHistory.first.toStringAsFixed(2)} → ${match.marketOdds.toStringAsFixed(2)})',
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                            ),
                                            Text(
                                              'Fair: ${fairMainOdds.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Color(0xFF3B82F6),
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        SizedBox(
                                          height: 54,
                                          width: double.infinity,
                                          child: CustomPaint(
                                            painter: OddsHistoryPainter(match.oddsHistory, fairMainOdds),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  // INTERAKTÍV ÉLŐ IN-PLAY SZIMULÁTOR
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
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text('Élő In-Play Szimulátor (Mi lenne ha...)',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: Color(0xFFF59E0B))),
                                            Switch(
                                              value: useInPlaySim,
                                              activeColor: const Color(0xFF10B981),
                                              onChanged: (v) => setModalState(() => useInPlaySim = v),
                                            ),
                                          ],
                                        ),
                                        if (useInPlaySim) ...[
                                          Text('Játékperc: ${simMinute.round()}. perc',
                                              style: const TextStyle(fontSize: 12)),
                                          Slider(
                                            value: simMinute,
                                            min: 0,
                                            max: 88,
                                            divisions: 44,
                                            activeColor: const Color(0xFF10B981),
                                            onChanged: (v) => setModalState(() => simMinute = v),
                                          ),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                                            children: [
                                              Row(
                                                children: [
                                                  const Text('Hazai gól: ', style: TextStyle(fontSize: 12)),
                                                  IconButton(
                                                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                                                    onPressed: simHomeGoals > 0
                                                        ? () => setModalState(() => simHomeGoals--)
                                                        : null,
                                                  ),
                                                  Text('$simHomeGoals',
                                                      style: const TextStyle(fontWeight: FontWeight.bold)),
                                                  IconButton(
                                                    icon: const Icon(Icons.add_circle_outline, size: 18),
                                                    onPressed: () => setModalState(() => simHomeGoals++),
                                                  ),
                                                ],
                                              ),
                                              Row(
                                                children: [
                                                  const Text('Vendég gól: ', style: TextStyle(fontSize: 12)),
                                                  IconButton(
                                                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                                                    onPressed: simAwayGoals > 0
                                                        ? () => setModalState(() => simAwayGoals--)
                                                        : null,
                                                  ),
                                                  Text('$simAwayGoals',
                                                      style: const TextStyle(fontWeight: FontWeight.bold)),
                                                  IconButton(
                                                    icon: const Icon(Icons.add_circle_outline, size: 18),
                                                    onPressed: () => setModalState(() => simAwayGoals++),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 14),

                                  Text(
                                    useInPlaySim
                                        ? 'Szimulált Élő 1X2 (${simMinute.round()}\' • $simHomeGoals-$simAwayGoals állásnál)'
                                        : 'Dixon-Coles 1X2 Valószínűség',
                                    style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
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
                                  const Text('Legvalószínűbb végeredmények',
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
                                  const SizedBox(height: 16),
                                  const Text('Mind a 16 kiszámolt piac (+ Szelvény / Napló)',
                                      style: TextStyle(
                                          fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                                  const SizedBox(height: 8),
                                  ...poisson.allMarkets.map((opt) {
                                    final inSlip = _isMarketInSlip(match.id, opt.code);
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0A0E17),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: inSlip
                                              ? const Color(0xFF10B981)
                                              : const Color(0xFF1F2937),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(opt.label,
                                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                                Text(
                                                  'Esély: ${(opt.probability * 100).round()}% • Fair: ${opt.fairOdds} • +${opt.edgePercent.toStringAsFixed(1)}% EV',
                                                  style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            icon: Icon(
                                              inSlip ? Icons.check_circle : Icons.playlist_add,
                                              size: 20,
                                              color: inSlip ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
                                            ),
                                            tooltip: 'Szelvénybe',
                                            onPressed: () {
                                              _toggleSlipOption(match, chosenMarket: opt);
                                              setModalState(() {});
                                            },
                                          ),
                                          GestureDetector(
                                            onTap: () {
                                              Navigator.pop(context);
                                              _openLogBetDialog(match, chosenMarket: opt);
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                              decoration: BoxDecoration(
                                                color: const Color.fromRGBO(16, 185, 129, 0.18),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                '@ ${opt.refOdds}',
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

                              // 5. FÜL: H2H (EGYMÁS ELLENI)
                              isLoadingBundle
                                  ? const Center(child: CircularProgressIndicator())
                                  : (bundle == null || bundle.h2hMatches.isEmpty)
                                      ? Center(
                                          child: Padding(
                                            padding: const EdgeInsets.all(24),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.history, size: 36, color: Color(0xFF9CA3AF)),
                                                const SizedBox(height: 10),
                                                const Text(
                                                  'Ehhez a párosításhoz nincs rögzített korábbi H2H eredménysor az API-ban.',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                                                ),
                                                const SizedBox(height: 12),
                                                Text(
                                                  'Becsült H2H gólátlag (Dixon-Coles): ${(match.homeXg + match.awayXg).toStringAsFixed(2)} gól / meccs',
                                                  style: const TextStyle(
                                                      color: Color(0xFF10B981),
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 12),
                                                ),
                                              ],
                                            ),
                                          ),
                                        )
                                      : ListView(
                                          padding: const EdgeInsets.all(16),
                                          children: [
                                            const Text('Korábbi egymás elleni találkozók',
                                                style: TextStyle(
                                                    fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                                            const SizedBox(height: 10),
                                            ...bundle.h2hMatches.take(10).map((h) {
                                              final ht = (h['home_team'] ?? match.homeTeam).toString();
                                              final at = (h['away_team'] ?? match.awayTeam).toString();
                                              final hs = (h['home_score'] as num?)?.toInt() ?? 0;
                                              final as = (h['away_score'] as num?)?.toInt() ?? 0;
                                              final dt = (h['datetime'] ?? '').toString();
                                              final dShort = dt.length >= 10 ? dt.substring(0, 10) : '';
                                              return Container(
                                                margin: const EdgeInsets.only(bottom: 8),
                                                padding: const EdgeInsets.all(12),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF0A0E17),
                                                  borderRadius: BorderRadius.circular(10),
                                                  border: Border.all(color: const Color(0xFF1F2937)),
                                                ),
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    Expanded(
                                                      child: Text('$ht – $at',
                                                          style: const TextStyle(fontSize: 12)),
                                                    ),
                                                    Text('$hs - $as',
                                                        style: const TextStyle(
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 13,
                                                            color: Color(0xFF10B981))),
                                                    if (dShort.isNotEmpty) ...[
                                                      const SizedBox(width: 8),
                                                      Text(dShort,
                                                          style: const TextStyle(
                                                              fontSize: 10, color: Color(0xFF9CA3AF))),
                                                    ],
                                                  ],
                                                ),
                                              );
                                            }),
                                          ],
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
        bankroll: _bankroll,
        stakeProfile: _stakeProfile,
        slipItems: _slipItems,
        favoriteLeagues: _favoriteLeagues,
        onToggleFavoriteLeague: _toggleFavoriteLeague,
        onGenerateAiSlip: _generateAiSlip,
        onDayChanged: _changeDayOffset,
        onRefresh: () => _syncSportApi(),
        onSelectMatch: _openMatchDetail,
        onToggleWatch: _toggleWatch,
        onToggleSlip: (m) => _toggleSlipOption(m),
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
        autoBankroll: _autoBankroll,
        stakeProfile: _stakeProfile,
        onBankrollChanged: (val) {
          setState(() => _bankroll = val);
          _saveState();
        },
        onAutoBankrollChanged: (val) {
          setState(() => _autoBankroll = val);
          _saveState();
        },
        onStakeProfileChanged: (val) {
          setState(() => _stakeProfile = val);
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
    for (final it in _slipItems) {
      slipOdds *= it.odds;
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
                _isLiveMode ? 'v6 PRO' : 'v6 DEMÓ',
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
            tooltip: 'Automata Élő Radar + Push (75 mp)',
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
      floatingActionButton: _slipItems.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _openComboSlipSheet,
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.black,
              icon: const Icon(Icons.receipt_long),
              label: Text(
                'Szelvény (${_slipItems.length}) • ${slipOdds.toStringAsFixed(2)}x',
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
// 6. FÜLEK (AJÁNLÁSOK + AI VARÁZSLÓ, TRENDEK, KALKULÁTOR + SUREBET, NAPLÓ + CSV)
// ==========================================

class ValueFeedTab extends StatefulWidget {
  final MatchList matches;
  final String baseUrl;
  final String apiKey;
  final int dayOffset;
  final double bankroll;
  final String stakeProfile;
  final SlipItemList slipItems;
  final Set<String> favoriteLeagues;
  final Function(String) onToggleFavoriteLeague;
  final Function({required bool conservative}) onGenerateAiSlip;
  final Function(int) onDayChanged;
  final Future<void> Function() onRefresh;
  final Function(MatchPick) onSelectMatch;
  final Function(String) onToggleWatch;
  final Function(MatchPick) onToggleSlip;
  final Function(MatchPick) onEditOdds;
  final Function(MatchPick) onLogBet;

  const ValueFeedTab({
    super.key,
    required this.matches,
    required this.baseUrl,
    required this.apiKey,
    required this.dayOffset,
    required this.bankroll,
    required this.stakeProfile,
    required this.slipItems,
    required this.favoriteLeagues,
    required this.onToggleFavoriteLeague,
    required this.onGenerateAiSlip,
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

  String get _profileLabel {
    if (widget.stakeProfile == 'quarter_kelly') return '1/4 Kelly';
    if (widget.stakeProfile == 'fix_2') return 'Fix 2%';
    return '1/2 Kelly';
  }

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

    final MatchList top3Safe = widget.matches
        .where((m) => !m.isFinished && m.modelProb >= 0.50)
        .toList()
      ..sort((a, b) {
        final scoreA = (a.edgePercent * 0.65) + ((a.modelProb * 100 - 50) * 0.35);
        final scoreB = (b.edgePercent * 0.65) + ((b.modelProb * 100 - 50) * 0.35);
        return scoreB.compareTo(scoreA);
      });
    final top3List = top3Safe.take(3).toList();

    final smartFilters = ['Mind', '⭐ Kedvencek', 'STEAM', '+5% EV felett', 'ÉLŐ'];

    final filtered = widget.matches.where((m) {
      if (_selectedLeague != 'Összes' && m.league != _selectedLeague) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchText = '${m.homeTeam} ${m.awayTeam} ${m.league}'.toLowerCase();
        if (!matchText.contains(q)) return false;
      }
      if (_smartFilter == '⭐ Kedvencek' && !widget.favoriteLeagues.contains(m.league)) return false;
      if (_smartFilter == 'STEAM' && !m.isSteamMove) return false;
      if (_smartFilter == '+5% EV felett' && m.edgePercent < 5.0) return false;
      if (_smartFilter == 'ÉLŐ' && !m.isLive) return false;
      return true;
    }).toList();

    filtered.sort((a, b) => _sortByValue
        ? b.edgePercent.compareTo(a.edgePercent)
        : b.modelProb.compareTo(a.modelProb));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
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
        // AI SZELVÉNYVARÁZSLÓ GOMBOK
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => widget.onGenerateAiSlip(conservative: true),
                  icon: const Icon(Icons.shield_outlined, size: 15, color: Color(0xFF10B981)),
                  label: const Text('AI Duplázó (~2.0x)', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    side: const BorderSide(color: Color(0xFF1F2937)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => widget.onGenerateAiSlip(conservative: false),
                  icon: const Icon(Icons.auto_awesome, size: 15, color: Color(0xFFF59E0B)),
                  label: const Text('AI Value Tripla', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    side: const BorderSide(color: Color(0xFF1F2937)),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (top3List.isNotEmpty) ...[
          SizedBox(
            height: 74,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: top3List.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, idx) {
                final m = top3List[idx];
                return GestureDetector(
                  onTap: () => widget.onSelectMatch(m),
                  child: Container(
                    width: 215,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF132A24), Color(0xFF131A29)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color.fromRGBO(16, 185, 129, 0.45)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('TOP #${idx + 1} AI SZÉF',
                                style: const TextStyle(
                                    fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                            Text('+${m.edgePercent.toStringAsFixed(1)}% EV',
                                style: const TextStyle(
                                    fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFF59E0B))),
                          ],
                        ),
                        Text(
                          '${m.homeTeam} – ${m.awayTeam}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${m.market} @ ${m.marketOdds.toStringAsFixed(2)}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10, color: Color(0xFFD1D5DB)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 36,
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
        const SizedBox(height: 4),
        SizedBox(
          height: 34,
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
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: leagues.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final league = leagues[index];
              final selected = league == _selectedLeague;
              final isFav = widget.favoriteLeagues.contains(league);
              return ChoiceChip(
                label: Text(isFav && league != 'Összes' ? '⭐ $league' : league),
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
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text('${filtered.length} meccs • ${widget.bankroll.round()} Ft',
                      style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11)),
                  if (_selectedLeague != 'Összes')
                    IconButton(
                      icon: Icon(
                        widget.favoriteLeagues.contains(_selectedLeague)
                            ? Icons.star
                            : Icons.star_border,
                        size: 18,
                        color: const Color(0xFFF59E0B),
                      ),
                      tooltip: 'Liga kedvencnek jelölése',
                      onPressed: () => widget.onToggleFavoriteLeague(_selectedLeague),
                    ),
                ],
              ),
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
                final inSlip = widget.slipItems.any((s) => s.matchId == match.id);
                final recStake = match.recommendedStake(widget.bankroll, widget.stakeProfile);

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
                                child: GestureDetector(
                                  onTap: () => widget.onToggleFavoriteLeague(match.league),
                                  child: Text(
                                    '${widget.favoriteLeagues.contains(match.league) ? "⭐ " : ""}${match.league} • ${match.kickoff}',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                                  ),
                                ),
                              ),
                              Row(
                                children: [
                                  if (match.isSteamMove) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color.fromRGBO(59, 130, 246, 0.22),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'STEAM -${match.oddsDropPercent.toStringAsFixed(0)}%',
                                        style: const TextStyle(
                                          color: Color(0xFF60A5FA),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                  ],
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
                                    Text(
                                      match.isLive
                                          ? 'Élő In-Play ajánlás'
                                          : 'Ajánlott piac (16-piacos)',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                                    ),
                                    Text(match.market,
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Ajánlott tét: $recStake Ft ($_profileLabel)',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFFF59E0B),
                                          fontWeight: FontWeight.w600),
                                    ),
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
                                  onPressed: () => widget.onToggleSlip(match),
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
                                tooltip: 'Push riasztás',
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
    final categories = ['Mind', 'Steam / Dropping', 'ÉLŐ & Nyomás', 'Tabella & Forma', 'Gólok / BTTS'];
    final list = widget.matches.where((m) {
      if (_category == 'Mind') return true;
      if (_category == 'Steam / Dropping') return m.isSteamMove;
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
                                    match.isSteamMove
                                        ? 'STEAM MOVE (-${match.oddsDropPercent.toStringAsFixed(1)}%)'
                                        : (match.isHighPressure ? 'ÉLŐ GÓLNYOMÁS' : match.trendCategory),
                                    style: TextStyle(
                                      color: match.isSteamMove
                                          ? const Color(0xFF60A5FA)
                                          : (match.isHighPressure
                                              ? const Color(0xFFF59E0B)
                                              : const Color(0xFF3B82F6)),
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
  final bool autoBankroll;
  final String stakeProfile;
  final Function(double) onBankrollChanged;
  final Function(bool) onAutoBankrollChanged;
  final Function(String) onStakeProfileChanged;

  const CalculatorTab({
    super.key,
    required this.matches,
    required this.bankroll,
    required this.autoBankroll,
    required this.stakeProfile,
    required this.onBankrollChanged,
    required this.onAutoBankrollChanged,
    required this.onStakeProfileChanged,
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

  double _mcWinRate = 0.56;
  double _mcAvgOdds = 1.92;
  double _mcStakePct = 0.03;

  // Surebet / Dutcher változók
  bool _threeWayDutch = false;
  double _arbOdds1 = 2.15;
  double _arbOddsX = 3.60;
  double _arbOdds2 = 2.05;
  double _arbTotalStake = 10000;

  @override
  Widget build(BuildContext context) {
    final ev = (_prob * _odds) - 1.0;
    final fairOdds = 1.0 / _prob;
    final fullKelly = ((_prob * _odds) - 1.0) / (_odds - 1.0);
    final halfKelly = fullKelly > 0 ? fullKelly * 0.5 : 0.0;
    final recommendedStake = (widget.bankroll * halfKelly).round();
    final simResult = PoissonEngine.calculate(_simHomeXg, _simAwayXg);

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

    // Surebet / Dutcher matek
    final inv1 = 1.0 / _arbOdds1;
    final invX = _threeWayDutch ? (1.0 / _arbOddsX) : 0.0;
    final inv2 = 1.0 / _arbOdds2;
    final invSum = inv1 + invX + inv2;
    final arbMarginPercent = (invSum - 1.0) * 100.0;
    final isSurebet = invSum < 1.0;
    final stake1 = (_arbTotalStake * (inv1 / invSum)).round();
    final stakeX = _threeWayDutch ? (_arbTotalStake * (invX / invSum)).round() : 0;
    final stake2 = (_arbTotalStake - stake1 - stakeX).round();
    final guaranteedReturn = (_arbTotalStake / invSum).round();
    final netArbProfit = guaranteedReturn - _arbTotalStake.round();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Auto-Bankroll (Napló szinkron)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    Switch(
                      value: widget.autoBankroll,
                      activeColor: const Color(0xFF10B981),
                      onChanged: widget.onAutoBankrollChanged,
                    ),
                  ],
                ),
                const Text('Alapértelmezett tétstratégia a meccskártyákon:',
                    style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'quarter_kelly', label: Text('1/4 Kelly', style: TextStyle(fontSize: 11))),
                      ButtonSegment(value: 'half_kelly', label: Text('1/2 Kelly', style: TextStyle(fontSize: 11))),
                      ButtonSegment(value: 'fix_2', label: Text('Fix 2%', style: TextStyle(fontSize: 11))),
                    ],
                    selected: {widget.stakeProfile},
                    onSelectionChanged: (s) => widget.onStakeProfileChanged(s.first),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('EV/Kelly', style: TextStyle(fontSize: 11))),
            ButtonSegment(value: 1, label: Text('Dixon', style: TextStyle(fontSize: 11))),
            ButtonSegment(value: 2, label: Text('M.Carlo', style: TextStyle(fontSize: 11))),
            ButtonSegment(value: 3, label: Text('Surebet', style: TextStyle(fontSize: 11))),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => setState(() => _mode = s.first),
        ),
        const SizedBox(height: 14),
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
                  Text('Bankroll (Aktuális tőke): ${widget.bankroll.round()} Ft',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Slider(
                    value: widget.bankroll.clamp(10000, 500000),
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
                    label: 'Hazai győzelem (1) / AH -0.5',
                    value:
                        '${(simResult.homeWin * 100).toStringAsFixed(1)}% (Fair: ${(1 / simResult.homeWin).toStringAsFixed(2)})',
                    valueColor: const Color(0xFF10B981),
                  ),
                  const Divider(height: 20, color: Color(0xFF1F2937)),
                  _CalcRow(
                    label: 'Ázsiai Hendikep Hazai -1.0',
                    value:
                        '${(simResult.ahHomeMinus10 * 100).toStringAsFixed(1)}% (Fair: ${(1 / simResult.ahHomeMinus10).toStringAsFixed(2)})',
                    valueColor: Colors.white,
                  ),
                  const Divider(height: 20, color: Color(0xFF1F2937)),
                  _CalcRow(
                    label: '1. Félidő 0.5+ / 1.5+ gól',
                    value: '${(simResult.htOver05 * 100).round()}% / ${(simResult.htOver15 * 100).round()}%',
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
        ] else if (_mode == 2) ...[
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
        ] else ...[
          // SUREBET / DUTCHER KALKULÁTOR
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Surebet / Dutcher Tételosztó',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('2-út', style: TextStyle(fontSize: 11))),
                          ButtonSegment(value: true, label: Text('3-út (1X2)', style: TextStyle(fontSize: 11))),
                        ],
                        selected: {_threeWayDutch},
                        onSelectionChanged: (s) => setState(() => _threeWayDutch = s.first),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('1. kimenetel oddsa: ${_arbOdds1.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Slider(
                    value: _arbOdds1,
                    min: 1.20,
                    max: 6.00,
                    activeColor: const Color(0xFF10B981),
                    onChanged: (v) => setState(() => _arbOdds1 = v),
                  ),
                  if (_threeWayDutch) ...[
                    Text('Döntetlen (X) oddsa: ${_arbOddsX.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    Slider(
                      value: _arbOddsX,
                      min: 2.00,
                      max: 7.00,
                      activeColor: const Color(0xFFF59E0B),
                      onChanged: (v) => setState(() => _arbOddsX = v),
                    ),
                  ],
                  Text('2. kimenetel oddsa: ${_arbOdds2.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Slider(
                    value: _arbOdds2,
                    min: 1.20,
                    max: 6.00,
                    activeColor: const Color(0xFF3B82F6),
                    onChanged: (v) => setState(() => _arbOdds2 = v),
                  ),
                  Text('Összes kiosztandó tét: ${_arbTotalStake.round()} Ft',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Slider(
                    value: _arbTotalStake,
                    min: 1000,
                    max: 100000,
                    divisions: 99,
                    activeColor: Colors.white,
                    onChanged: (v) => setState(() => _arbTotalStake = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _CalcRow(
                    label: isSurebet ? 'Garantált Surebet Profit' : 'Bukmékeri Árrés (Margin)',
                    value: isSurebet
                        ? '+${(-arbMarginPercent).toStringAsFixed(2)}% (+$netArbProfit Ft)'
                        : '${arbMarginPercent.toStringAsFixed(2)}% ($netArbProfit Ft)',
                    valueColor: isSurebet ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                  ),
                  const Divider(height: 18, color: Color(0xFF1F2937)),
                  _CalcRow(
                    label: 'Tét 1. kimenetelre (@ ${_arbOdds1.toStringAsFixed(2)})',
                    value: '$stake1 Ft',
                    valueColor: Colors.white,
                  ),
                  if (_threeWayDutch) ...[
                    const Divider(height: 18, color: Color(0xFF1F2937)),
                    _CalcRow(
                      label: 'Tét Döntetlenre (@ ${_arbOddsX.toStringAsFixed(2)})',
                      value: '$stakeX Ft',
                      valueColor: Colors.white,
                    ),
                  ],
                  const Divider(height: 18, color: Color(0xFF1F2937)),
                  _CalcRow(
                    label: 'Tét 2. kimenetelre (@ ${_arbOdds2.toStringAsFixed(2)})',
                    value: '$stake2 Ft',
                    valueColor: Colors.white,
                  ),
                  const Divider(height: 18, color: Color(0xFF1F2937)),
                  _CalcRow(
                    label: 'Kifizetés bármelyik kimenetelnél',
                    value: '$guaranteedReturn Ft',
                    valueColor: const Color(0xFF10B981),
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

  String _generateCsvReport() {
    final buf = StringBuffer();
    buf.writeln('Datum;Liga;Merkozes;Piac;Kategoria;Odds;ZaroOdds;CLV_Pct;Tet_Ft;Statusz;Profit_Ft');
    for (final b in widget.bets) {
      final clvStr = b.clvPercent != null ? b.clvPercent!.toStringAsFixed(2) : '';
      final closeStr = b.closingOdds != null ? b.closingOdds!.toStringAsFixed(2) : '';
      buf.writeln(
        '${b.date};${b.league};${b.matchTitle};${b.market};${b.marketCategory};${b.odds.toStringAsFixed(2)};$closeStr;$clvStr;${b.stake.round()};${b.status};${b.profit.round()}',
      );
    }
    return buf.toString();
  }

  RoiBreakdownList _buildBreakdown(BetList settled, bool byLeague) {
    final Map<String, BetList> grouped = {};
    for (final b in settled) {
      final key = byLeague ? b.league : b.marketCategory;
      grouped.putIfAbsent(key, () => []).add(b);
    }
    final RoiBreakdownList items = [];
    grouped.forEach((key, list) {
      final staked = list.fold<double>(0.0, (s, b) => s + b.stake);
      final profit = list.fold<double>(0.0, (s, b) => s + b.profit);
      final wins = list.where((b) => b.status == 'won').length;
      final roi = staked > 0 ? (profit / staked) * 100 : 0.0;
      final wr = list.isNotEmpty ? (wins / list.length) * 100 : 0.0;
      items.add(
        RoiBreakdownItem(
          name: key,
          count: list.length,
          profit: profit,
          roiPercent: roi,
          winRatePercent: wr,
        ),
      );
    });
    items.sort((a, b) => b.profit.compareTo(a.profit));
    return items;
  }

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

    final brierBets = settledBets.where((b) => b.modelProb != null).toList();
    double? brierScore;
    if (brierBets.isNotEmpty) {
      double sumSq = 0.0;
      for (final b in brierBets) {
        final actual = b.status == 'won' ? 1.0 : 0.0;
        final diff = b.modelProb! - actual;
        sumSq += diff * diff;
      }
      brierScore = sumSq / brierBets.length;
    }

    final marketBreakdown = _buildBreakdown(settledBets, false);
    final leagueBreakdown = _buildBreakdown(settledBets, true);

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
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
              children: [
                Card(
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
                            _KpiItem(
                              label: 'Brier',
                              value: brierScore == null ? '-' : brierScore.toStringAsFixed(2),
                              color: brierScore != null && brierScore <= 0.22
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFF59E0B),
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
                        if (widget.bets.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                final csv = _generateCsvReport();
                                Clipboard.setData(ClipboardData(text: csv));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('CSV / Excel riport vágólapra másolva!'),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.table_chart_outlined, size: 15),
                              label: const Text('CSV / Excel Riport másolása', style: TextStyle(fontSize: 11)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (marketBreakdown.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Piac- és Liga-szintű ROI bontás',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                          const SizedBox(height: 8),
                          ...marketBreakdown.map((item) => _BreakdownRow(item: item)),
                          if (leagueBreakdown.isNotEmpty) ...[
                            const Divider(height: 16, color: Color(0xFF1F2937)),
                            ...leagueBreakdown.take(4).map((item) => _BreakdownRow(item: item)),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                if (widget.bets.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Text(
                      'Még nincs rögzített tipped.\nKoppints a + ikonra bármelyik meccsnél!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF9CA3AF)),
                    ),
                  )
                else
                  ...widget.bets.map((bet) {
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
                  }),
              ],
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

class _BreakdownRow extends StatelessWidget {
  final RoiBreakdownItem item;

  const _BreakdownRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final pos = item.profit >= 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              '${item.name} (${item.count} tipp • ${item.winRatePercent.round()}%)',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFFD1D5DB)),
            ),
          ),
          Text(
            '${pos ? '+' : ''}${item.roiPercent.toStringAsFixed(1)}% ROI (${pos ? '+' : ''}${item.profit.round()} Ft)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: pos ? const Color(0xFF10B981) : const Color(0xFFEF4444),
            ),
          ),
        ],
      ),
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
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF))),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
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
// 7. GRAFIKON RAJZOLÓK (ODDS MOZGÁS, ROI & MONTE CARLO)
// ==========================================

class OddsHistoryPainter extends CustomPainter {
  final DoubleList values;
  final double fairOdds;

  OddsHistoryPainter(this.values, this.fairOdds);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final pts = values.length == 1 ? [values.first, values.first] : values;

    double minVal = math.min(fairOdds, pts.reduce((a, b) => a < b ? a : b)) - 0.05;
    double maxVal = math.max(fairOdds, pts.reduce((a, b) => a > b ? a : b)) + 0.05;
    final range = (maxVal - minVal) == 0 ? 1.0 : (maxVal - minVal);

    // Fair odds referencia vonal
    final fairY = size.height - (((fairOdds - minVal) / range) * size.height);
    final fairPaint = Paint()
      ..color = const Color(0xFF3B82F6)
      ..strokeWidth = 1.2;
    for (double x = 0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, fairY), Offset(math.min(x + 4, size.width), fairY), fairPaint);
    }

    // Odds görbe
    final dropping = pts.last <= pts.first;
    final linePaint = Paint()
      ..color = dropping ? const Color(0xFF10B981) : const Color(0xFFF59E0B)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = dropping ? const Color(0xFF10B981) : const Color(0xFFF59E0B)
      ..style = PaintingStyle.fill;

    final path = Path();
    for (int i = 0; i < pts.length; i++) {
      final x = (i / (pts.length - 1)) * size.width;
      final y = size.height - (((pts[i] - minVal) / range) * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 3.0, dotPaint);
    }
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

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
