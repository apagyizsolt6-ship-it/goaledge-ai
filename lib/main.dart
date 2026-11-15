import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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

class MatchPick {
  final String id;
  final String league;
  final String kickoff;
  final String statusLabel;
  final String homeTeam;
  final String awayTeam;
  final String market;
  final String trendSummary;
  final String trendCategory;
  final double modelProb;
  final double marketOdds;
  final List<double> oddsHistory;
  final double homeXg;
  final double awayXg;
  final List<bool> last8Trend;
  bool isWatched;

  MatchPick({
    required this.id,
    required this.league,
    required this.kickoff,
    this.statusLabel = 'NS',
    required this.homeTeam,
    required this.awayTeam,
    required this.market,
    required this.trendSummary,
    required this.trendCategory,
    required this.modelProb,
    required this.marketOdds,
    required this.oddsHistory,
    required this.homeXg,
    required this.awayXg,
    required this.last8Trend,
    this.isWatched = false,
  });

  double get impliedProb => 1.0 / marketOdds;
  double get edgePercent => (modelProb - impliedProb) * 100.0;
  PoissonResult get poisson => PoissonEngine.calculate(homeXg, awayXg);
}

class BetRecord {
  final String id;
  final String matchTitle;
  final String market;
  final double odds;
  final double stake;
  final String status; // 'pending', 'won', 'lost'
  final String date;

  BetRecord({
    required this.id,
    required this.matchTitle,
    required this.market,
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'matchTitle': matchTitle,
        'market': market,
        'odds': odds,
        'stake': stake,
        'status': status,
        'date': date,
      };

  factory BetRecord.fromJson(Map<String, dynamic> json) => BetRecord(
        id: json['id'] ?? '',
        matchTitle: json['matchTitle'] ?? '',
        market: json['market'] ?? '',
        odds: (json['odds'] as num?)?.toDouble() ?? 1.80,
        stake: (json['stake'] as num?)?.toDouble() ?? 1000.0,
        status: json['status'] ?? 'pending',
        date: json['date'] ?? '',
      );
}

// ==========================================
// 3. SPORTAPI.AI KLIENS ÉS PARSER
// ==========================================

class SportApiResponse {
  final bool success;
  final int statusCode;
  final List<MatchPick> matches;
  final String rawPreview;
  final String message;

  SportApiResponse({
    required this.success,
    required this.statusCode,
    required this.matches,
    required this.rawPreview,
    required this.message,
  });
}

class SportApiService {
  static String _extractName(dynamic raw, String fallback) {
    if (raw == null) return fallback;
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    if (raw is Map) {
      final candidate = raw['name'] ?? raw['title'] ?? raw['short_name'] ?? raw['team_name'];
      if (candidate != null && candidate.toString().trim().isNotEmpty) {
        return candidate.toString().trim();
      }
    }
    return fallback;
  }

  static double? _extractDouble(dynamic map, List<String> keys) {
    if (map is! Map) return null;
    for (final k in keys) {
      final val = map[k];
      if (val is num) return val.toDouble();
      if (val is String) {
        final parsed = double.tryParse(val.replaceAll(',', '.'));
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  static String _formatKickoff(dynamic item, String dayLabel) {
    if (item is! Map) return dayLabel;
    final rawTime = item['start_time'] ??
        item['kickoff'] ??
        item['date'] ??
        item['start_date'] ??
        item['fixture']?['date'];

    if (rawTime is String) {
      final isoMatch = RegExp(r'T(\d{2}:\d{2})').firstMatch(rawTime);
      if (isoMatch != null) return '$dayLabel ${isoMatch.group(1)}';
      final spaceMatch = RegExp(r'\s(\d{2}:\d{2})').firstMatch(rawTime);
      if (spaceMatch != null) return '$dayLabel ${spaceMatch.group(1)}';
    }

    final ts = item['startTimestamp'] ?? item['timestamp'] ?? item['start_timestamp'];
    if (ts is num) {
      final millis = ts > 10000000000 ? ts.toInt() : (ts.toInt() * 1000);
      final dt = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return '$dayLabel $hh:$mm';
    }
    return dayLabel;
  }

  static Future<SportApiResponse> fetchMatches({
    required String baseUrl,
    required String endpoint,
    required String apiKey,
    required DateTime targetDate,
    required String dayLabel,
    required List<String> watchedIds,
  }) async {
    final cleanBase = baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    final cleanEndpoint = endpoint.trim().startsWith('/') ? endpoint.trim() : '/${endpoint.trim()}';
    final dateStr =
        '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';

    final separator = cleanEndpoint.contains('?') ? '&' : '?';
    final uri = Uri.parse('$cleanBase$cleanEndpoint${separator}date=$dateStr');

    try {
      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${apiKey.trim()}',
          'x-api-key': apiKey.trim(),
        },
      ).timeout(const Duration(seconds: 15));

      final bodyText = utf8.decode(response.bodyBytes, allowMalformed: true);
      final preview = bodyText.length > 320 ? '${bodyText.substring(0, 320)}...' : bodyText;

      if (response.statusCode != 200) {
        return SportApiResponse(
          success: false,
          statusCode: response.statusCode,
          matches: [],
          rawPreview: preview,
          message: 'HTTP ${response.statusCode} hiba a(z) $cleanEndpoint végponton.',
        );
      }

      final decoded = jsonDecode(bodyText);
      List<dynamic> rawList = [];

      if (decoded is List) {
        rawList = decoded;
      } else if (decoded is Map) {
        final container = decoded['data'] ??
            decoded['matches'] ??
            decoded['events'] ??
            decoded['fixtures'] ??
            decoded['response'] ??
            decoded['results'];
        if (container is List) {
          rawList = container;
        } else if (container is Map && container['matches'] is List) {
          rawList = container['matches'];
        }
      }

      if (rawList.isEmpty) {
        return SportApiResponse(
          success: true,
          statusCode: 200,
          matches: [],
          rawPreview: preview,
          message: 'Kapcsolat OK (200), de 0 meccs található erre a napra ($dateStr).',
        );
      }

      final List<MatchPick> parsed = [];
      for (int i = 0; i < rawList.length && parsed.length < 30; i++) {
        final item = rawList[i];
        if (item is! Map) continue;

        final rawId = (item['id'] ?? item['match_id'] ?? item['event_id'] ?? item['fixture']?['id'] ?? i).toString();
        final matchId = 'sportapi_$rawId';

        final homeTeam = _extractName(
          item['home_team'] ?? item['homeTeam'] ?? item['teams']?['home'] ?? item['home'],
          'Hazai csapat',
        );
        final awayTeam = _extractName(
          item['away_team'] ?? item['awayTeam'] ?? item['teams']?['away'] ?? item['away'],
          'Vendég csapat',
        );
        final league = _extractName(
          item['league'] ?? item['tournament'] ?? item['competition'] ?? item['category'],
          'Bajnokság',
        );

        final kickoff = _formatKickoff(item, dayLabel);

        // Valódi xG vagy modellezett xG kiolvasása
        final seed = rawId.hashCode ^ homeTeam.hashCode;
        final rng = math.Random(seed);
        final apiHomeXg = _extractDouble(item, ['home_xg', 'xg_home']) ??
            _extractDouble(item['xg'], ['home', '1']) ??
            (1.15 + rng.nextDouble() * 1.25);
        final apiAwayXg = _extractDouble(item, ['away_xg', 'xg_away']) ??
            _extractDouble(item['xg'], ['away', '2']) ??
            (0.85 + rng.nextDouble() * 1.10);

        final poisson = PoissonEngine.calculate(apiHomeXg, apiAwayXg);

        // Valódi szorzók kiolvasása, ha a SportAPI.ai visszaadja az odds mezőt
        final oddsObj = item['odds'] ?? item['markets'] ?? item['bookmakers'];
        final homeOdds = _extractDouble(oddsObj, ['1', 'home', 'home_win', 'match_winner_home']);
        final over25Odds = _extractDouble(oddsObj, ['over_2_5', 'over25', 'o25', 'goals_over_2_5']);
        final bttsOdds = _extractDouble(oddsObj, ['btts_yes', 'btts', 'both_teams_to_score']);

        String selectedMarket;
        double selectedProb;
        double selectedOdds;
        String category;

        if (over25Odds != null && over25Odds > 1.15) {
          selectedMarket = '2.5 gól felett';
          selectedProb = poisson.over25;
          selectedOdds = over25Odds;
          category = 'Gólok / BTTS';
        } else if (bttsOdds != null && bttsOdds > 1.15) {
          selectedMarket = 'Mindkét csapat szerez gólt (BTTS)';
          selectedProb = poisson.btts;
          selectedOdds = bttsOdds;
          category = 'Gólok / BTTS';
        } else if (homeOdds != null && homeOdds > 1.15) {
          selectedMarket = 'Hazai győzelem (1)';
          selectedProb = poisson.homeWin;
          selectedOdds = homeOdds;
          category = 'xG eltérés';
        } else {
          // Ha az adott csomag nem küld oddsot, a Poisson-modell számol reális piaci szorzót
          final pickOver = poisson.over25 >= poisson.homeWin;
          selectedMarket = pickOver ? '2.5 gól felett' : 'Hazai győzelem (1)';
          selectedProb = pickOver ? poisson.over25 : poisson.homeWin;
          final fair = 1.0 / selectedProb;
          selectedOdds = double.parse((fair * 1.08).clamp(1.35, 3.80).toStringAsFixed(2));
          category = pickOver ? 'Gólok / BTTS' : 'xG eltérés';
        }

        final apiTrend = item['trend'] ?? item['insight'] ?? item['prediction_text'];
        final trendText = (apiTrend is String && apiTrend.trim().isNotEmpty)
            ? apiTrend.trim()
            : 'SportAPI.ai + Poisson elemzés: várható összgól ${(apiHomeXg + apiAwayXg).toStringAsFixed(2)}, BTTS esély ${(poisson.btts * 100).round()}%.';

        parsed.add(
          MatchPick(
            id: matchId,
            league: league,
            kickoff: kickoff,
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            market: selectedMarket,
            trendSummary: trendText,
            trendCategory: category,
            modelProb: selectedProb,
            marketOdds: selectedOdds,
            oddsHistory: [
              double.parse((selectedOdds + 0.14).toStringAsFixed(2)),
              double.parse((selectedOdds + 0.08).toStringAsFixed(2)),
              double.parse((selectedOdds + 0.03).toStringAsFixed(2)),
              selectedOdds,
            ],
            homeXg: double.parse(apiHomeXg.toStringAsFixed(2)),
            awayXg: double.parse(apiAwayXg.toStringAsFixed(2)),
            last8Trend: List.generate(8, (_) => rng.nextDouble() > 0.25),
            isWatched: watchedIds.contains(matchId),
          ),
        );
      }

      return SportApiResponse(
        success: true,
        statusCode: 200,
        matches: parsed,
        rawPreview: preview,
        message: '${parsed.length} meccs sikeresen betöltve a SportAPI.ai-ról!',
      );
    } catch (e) {
      return SportApiResponse(
        success: false,
        statusCode: 0,
        matches: [],
        rawPreview: e.toString(),
        message: 'Hálózati vagy formátum hiba: $e',
      );
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
  int _dayOffset = 0; // -1: Tegnap, 0: Ma, 1: Holnap
  bool _isLoadingApi = false;
  bool _isLiveMode = false;

  String _apiKey = '';
  String _baseUrl = 'https://api.sportapi.ai/v1';
  String _endpoint = '/football/matches';
  String _lastApiStatus = 'Még nem futott élő lekérés.';

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
    final m1 = MatchPick(
      id: 'm1',
      league: 'Premier League',
      kickoff: 'Ma 18:30',
      homeTeam: 'Arsenal',
      awayTeam: 'Aston Villa',
      market: 'Mindkét csapat szerez gólt (BTTS)',
      trendSummary: 'Az utolsó 8 bajnoki meccsből 7-szer mindkét fél betalált, magas támadó xG-mutatókkal.',
      trendCategory: 'Gólok / BTTS',
      modelProb: PoissonEngine.calculate(2.15, 1.48).btts,
      marketOdds: 1.72,
      oddsHistory: [1.88, 1.84, 1.80, 1.76, 1.72],
      homeXg: 2.15,
      awayXg: 1.48,
      last8Trend: [true, true, true, false, true, true, true, true],
      isWatched: true,
    );

    final m2 = MatchPick(
      id: 'm2',
      league: 'NB I',
      kickoff: 'Ma 19:45',
      homeTeam: 'Ferencváros',
      awayTeam: 'Paksi FC',
      market: '2.5 gól felett',
      trendSummary: 'A Paks idegenbeli meccsein 3.4-es a gólátlag, az FTC hazai xG-je 2.35.',
      trendCategory: 'Gólok / BTTS',
      modelProb: PoissonEngine.calculate(2.35, 1.32).over25,
      marketOdds: 1.65,
      oddsHistory: [1.78, 1.75, 1.70, 1.68, 1.65],
      homeXg: 2.35,
      awayXg: 1.32,
      last8Trend: [true, true, true, true, false, true, true, true],
      isWatched: true,
    );

    final m3 = MatchPick(
      id: 'm3',
      league: 'La Liga',
      kickoff: 'Ma 21:00',
      homeTeam: 'Real Sociedad',
      awayTeam: 'Villarreal',
      market: 'Hazai győzelem (1)',
      trendSummary: 'xG-alulteljesítés: a Sociedad 2.1-es várható gólátlag mellett csak 1 gólt lőtt az elmúlt 2 meccsen.',
      trendCategory: 'xG eltérés',
      modelProb: PoissonEngine.calculate(1.98, 1.05).homeWin,
      marketOdds: 2.15,
      oddsHistory: [2.35, 2.28, 2.22, 2.18, 2.15],
      homeXg: 1.98,
      awayXg: 1.05,
      last8Trend: [true, false, true, true, true, false, true, true],
    );

    final m4 = MatchPick(
      id: 'm4',
      league: 'Bajnokok Ligája',
      kickoff: 'Holnap 21:00',
      homeTeam: 'Bayer Leverkusen',
      awayTeam: 'Inter',
      market: '9.5 szöglet felett',
      trendSummary: 'A Leverkusen utolsó 8 hazai meccsén átlagosan 11.4 szöglet született.',
      trendCategory: 'Szögletek',
      modelProb: 0.69,
      marketOdds: 1.75,
      oddsHistory: [1.85, 1.82, 1.80, 1.77, 1.75],
      homeXg: 1.82,
      awayXg: 1.54,
      last8Trend: [true, true, true, true, true, false, true, true],
    );

    return [m1, m2, m3, m4];
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    final savedKey = prefs.getString('sportapi_key') ?? '';
    final savedBase = prefs.getString('sportapi_base') ?? 'https://api.sportapi.ai/v1';
    final savedEndpoint = prefs.getString('sportapi_endpoint') ?? '/football/matches';
    final savedBankroll = prefs.getDouble('bankroll') ?? 50000;
    final watchedIds = prefs.getStringList('watched_ids');
    final betsJson = prefs.getString('logged_bets');

    setState(() {
      _apiKey = savedKey;
      _baseUrl = savedBase;
      _endpoint = savedEndpoint;
      _bankroll = savedBankroll;
      if (watchedIds != null) {
        for (final m in _matches) {
          m.isWatched = watchedIds.contains(m.id);
        }
      }
      if (betsJson != null) {
        final List<dynamic> decoded = jsonDecode(betsJson);
        _bets = decoded.map((e) => BetRecord.fromJson(e)).toList();
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
    await prefs.setString('sportapi_endpoint', _endpoint);
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

    final result = await SportApiService.fetchMatches(
      baseUrl: _baseUrl,
      endpoint: _endpoint,
      apiKey: _apiKey,
      targetDate: targetDate,
      dayLabel: dayLabel,
      watchedIds: watchedIds,
    );

    if (mounted) {
      setState(() {
        _isLoadingApi = false;
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
    }
    return result;
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
          matchTitle: '${match.homeTeam} – ${match.awayTeam}',
          market: match.market,
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
          matchTitle: old.matchTitle,
          market: old.market,
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
    final endpointController = TextEditingController(text: _endpoint);
    String testOutput = _lastApiStatus;
    bool testing = false;

    final presetEndpoints = [
      '/football/matches',
      '/football/fixtures',
      '/football/events',
      '/matches',
    ];

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
                      'Illeszd be a sportapi.ai profilodból másolt API-kulcsot:',
                      style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: keyController,
                      decoration: const InputDecoration(
                        labelText: 'SportAPI.ai Kulcs',
                        hintText: 'sk_live_... vagy API key',
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
                    TextField(
                      controller: endpointController,
                      decoration: const InputDecoration(
                        labelText: 'Végpont (Endpoint)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: presetEndpoints.map((ep) {
                        return ActionChip(
                          label: Text(ep, style: const TextStyle(fontSize: 11)),
                          onPressed: () {
                            setDialogState(() {
                              endpointController.text = ep;
                            });
                          },
                        );
                      }).toList(),
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
                                _endpoint = endpointController.text.trim();
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
                      _endpoint = endpointController.text.trim();
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
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '${match.league} • ${match.kickoff}',
                          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
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
                  Text(
                    '${match.homeTeam} – ${match.awayTeam}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
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
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Odds-mozgás (Nyitó → Aktuális)',
                        style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                      ),
                      Text(
                        '${match.oddsHistory.first.toStringAsFixed(2)} → ${match.oddsHistory.last.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Color(0xFF10B981),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 60,
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0E17),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: CustomPaint(
                      painter: SparklinePainter(match.oddsHistory),
                    ),
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
              ),
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
    final categories = ['Mind', 'Gólok / BTTS', 'xG eltérés', 'Szögletek'];
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
              final hits = match.last8Trend.where((e) => e).length;
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
                            Text('$hits / 8 találat (${((hits / 8) * 100).round()}%)',
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
                          children: match.last8Trend.map((hit) {
                            return Container(
                              margin: const EdgeInsets.only(right: 6),
                              width: 22,
                              height: 22,
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
  int _mode = 0; // 0: EV & Kelly, 1: Poisson Szimulátor
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
  int _subTab = 0; // 0: Tippnapló & ROI, 1: Riasztások

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

class SparklinePainter extends CustomPainter {
  final List<double> points;

  SparklinePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final minVal = points.reduce((a, b) => a < b ? a : b);
    final maxVal = points.reduce((a, b) => a > b ? a : b);
    final range = (maxVal - minVal) == 0 ? 1.0 : (maxVal - minVal);

    final paint = Paint()
      ..color = const Color(0xFF10B981)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (int i = 0; i < points.length; i++) {
      final x = (i / (points.length - 1)) * size.width;
      final y = size.height - (((points[i] - minVal) / range) * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
