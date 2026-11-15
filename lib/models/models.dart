import '../services/poisson_engine.dart';

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

class SgpResult {
  final String leg1Code;
  final String leg1Label;
  final String leg2Code;
  final String leg2Label;
  final double independentProb;
  final double correlatedProb;
  final double correlationFactor;
  final double fairOdds;

  SgpResult({
    required this.leg1Code,
    required this.leg1Label,
    required this.leg2Code,
    required this.leg2Label,
    required this.independentProb,
    required this.correlatedProb,
    required this.correlationFactor,
    required this.fairOdds,
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
  final CurveList matrix;
  final int baseHomeScore;
  final int baseAwayScore;

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
    required this.matrix,
    required this.baseHomeScore,
    required this.baseAwayScore,
  });
}

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
    this.marketCategory = 'G贸lok / BTTS',
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
        league: json['league'] ?? 'Bajnoks谩g',
        leagueZone: json['leagueZone'] ?? '',
        kickoff: json['kickoff'] ?? 'Ma',
        status: json['status'] ?? 'Scheduled',
        minute: json['minute']?.toString(),
        homeScore: (json['homeScore'] as num?)?.toInt(),
        awayScore: (json['awayScore'] as num?)?.toInt(),
        homeTeam: json['homeTeam'] ?? 'Hazai',
        awayTeam: json['awayTeam'] ?? 'Vend茅g',
        market: json['market'] ?? '2.5 g贸l felett',
        marketCode: json['marketCode'] ?? 'over25',
        marketCategory: json['marketCategory'] ?? 'G贸lok / BTTS',
        trendSummary: json['trendSummary'] ?? '',
        trendCategory: json['trendCategory'] ?? 'G贸lok / BTTS',
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
  final String note;

  BetRecord({
    required this.id,
    this.fixtureId,
    this.league = 'Egy茅b',
    required this.matchTitle,
    required this.market,
    this.marketCode = 'over25',
    this.marketCategory = 'G贸lok / BTTS',
    required this.odds,
    this.closingOdds,
    this.modelProb,
    required this.stake,
    required this.status,
    required this.date,
    this.note = '',
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
        'note': note,
      };

  factory BetRecord.fromJson(JsonMap json) => BetRecord(
        id: json['id'] ?? '',
        fixtureId: (json['fixtureId'] as num?)?.toInt(),
        league: json['league'] ?? 'Egy茅b',
        matchTitle: json['matchTitle'] ?? '',
        market: json['market'] ?? '',
        marketCode: json['marketCode'] ?? 'over25',
        marketCategory: json['marketCategory'] ?? 'G贸lok / BTTS',
        odds: (json['odds'] as num?)?.toDouble() ?? 1.80,
        closingOdds: (json['closingOdds'] as num?)?.toDouble(),
        modelProb: (json['modelProb'] as num?)?.toDouble(),
        stake: (json['stake'] as num?)?.toDouble() ?? 1000.0,
        status: json['status'] ?? 'pending',
        date: json['date'] ?? '',
        note: (json['note'] ?? '').toString(),
      );
}
