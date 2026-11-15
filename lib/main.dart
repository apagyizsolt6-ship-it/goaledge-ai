import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'engine.dart';
import 'api_service.dart';
import 'charts.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
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
    final cachedMatchesJson = prefs.getString('cached_matches_v7');
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
      await prefs.setString('cached_matches_v7', jsonEncode(_matches.map((m) => m.toJson()).toList()));
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
      'version': 7,
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
          final trend = SportApiService.extractFormTrend(hInfo, aInfo);

          _matches[i] = SportApiService.buildPickFromXg(
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
                      note: bet.note,
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

  void _addBet(MatchPick match, double stake, {MarketOption? chosenMarket, String customLabel = '', double? customOddsVal, double? customProbVal, String note = ''}) {
    final now = DateTime.now();
    final dateLabel = '${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}.';
    final mLabel = customLabel.isNotEmpty ? customLabel : (chosenMarket?.label ?? match.market);
    final mCode = customLabel.isNotEmpty ? 'sgp' : (chosenMarket?.code ?? match.marketCode);
    final mCat = customLabel.isNotEmpty ? 'SGP Builder' : (chosenMarket?.category ?? match.marketCategory);
    final mOdds = customOddsVal ?? chosenMarket?.refOdds ?? match.marketOdds;
    final mProb = customProbVal ?? chosenMarket?.probability ?? match.modelProb;

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
          note: note,
        ),
      );
    });
    _saveState();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Tipp rögzítve: $mLabel (${stake.round()} Ft)!')),
    );
  }

  void _addManualBet(BetRecord record) {
    setState(() {
      _bets.insert(0, record);
      if (_autoBankroll) {
        _bankroll = (_bankroll + record.profit).clamp(1000, 10000000);
      }
    });
    _saveState();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Kézi tipp rögzítve: ${record.matchTitle}')),
    );
  }

  void _adjustBankrollCapital(double delta) {
    setState(() {
      _bankroll = (_bankroll + delta).clamp(1000, 10000000);
    });
    _saveState();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Új tőkeegyenleg: ${_bankroll.round()} Ft')),
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
          note: old.note,
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

  void _openLogBetDialog(MatchPick match, {MarketOption? chosenMarket, String customLabel = '', double? customOddsVal, double? customProbVal}) {
    final rec = match.recommendedStake(_bankroll, _stakeProfile);
    double stake = (rec > 0 ? rec.toDouble() : _bankroll * 0.02).clamp(500, 50000).roundToDouble();
    final label = customLabel.isNotEmpty ? customLabel : (chosenMarket?.label ?? match.market);
    final odds = customOddsVal ?? chosenMarket?.refOdds ?? match.marketOdds;
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF131A29),
              title: const Text('Tipp rögzítése a naplóba'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${match.homeTeam} – ${match.awayTeam}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('$label @ $odds', style: const TextStyle(color: Color(0xFF10B981), fontSize: 13)),
                    const SizedBox(height: 14),
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
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteController,
                      decoration: const InputDecoration(
                        labelText: 'Elemző jegyzet (opcionális)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Mégse'),
                ),
                FilledButton(
                  onPressed: () {
                    _addBet(
                      match,
                      stake,
                      chosenMarket: chosenMarket,
                      customLabel: customLabel,
                      customOddsVal: customOddsVal,
                      customProbVal: customProbVal,
                      note: noteController.text.trim(),
                    );
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

    // SGP (Fogadáskészítő) állapotok
    String sgpLeg1 = 'home';
    String sgpLeg2 = 'over25';
    double sgpBookieOdds = 3.10;

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

              const leg1Labels = <String, String>{
                'home': 'Hazai (1)',
                '1x': 'Dupla esély (1X)',
                'away': 'Vendég (2)',
                'x2': 'Dupla esély (X2)',
              };
              const leg2Labels = <String, String>{
                'over15': '1.5+ gól',
                'over25': '2.5+ gól',
                'under25': '2.5 alatt',
                'btts': 'BTTS (Igen)',
              };
              final sgp = PoissonEngine.calculateSgp(
                poisson,
                sgpLeg1,
                leg1Labels[sgpLeg1] ?? sgpLeg1,
                sgpLeg2,
                leg2Labels[sgpLeg2] ?? sgpLeg2,
              );
              final sgpEv = ((sgp.correlatedProb * sgpBookieOdds) - 1.0) * 100.0;

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
                        Tab(text: '16 Piac & SGP'),
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
                              // 1. FÜL: 16 PIAC, SGP FOGADÁSKÉSZÍTŐ, ODDS GRAFIKON & ÉLŐ SZIMULÁTOR
                              ListView(
                                padding: const EdgeInsets.all(20),
                                children: [
                                  // KORRELÁCIÓS SAME-GAME PARLAY (SGP / FOGADÁSKÉSZÍTŐ)
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0A0E17),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color.fromRGBO(59, 130, 246, 0.5)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text('Korrelációs Fogadáskészítő (SGP)',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: Color(0xFF60A5FA))),
                                            Text(
                                              'Korreláció: ${sgp.correlationFactor.toStringAsFixed(2)}x',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: sgp.correlationFactor >= 1.0
                                                    ? const Color(0xFF10B981)
                                                    : const Color(0xFFF59E0B),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 6,
                                          children: leg1Labels.entries.map((e) {
                                            final sel = sgpLeg1 == e.key;
                                            return ChoiceChip(
                                              label: Text(e.value, style: const TextStyle(fontSize: 10)),
                                              selected: sel,
                                              selectedColor: const Color(0xFF10B981),
                                              onSelected: (_) => setModalState(() {
                                                sgpLeg1 = e.key;
                                                final nextSgp = PoissonEngine.calculateSgp(
                                                    poisson, sgpLeg1, e.value, sgpLeg2, leg2Labels[sgpLeg2]!);
                                                sgpBookieOdds = double.parse(
                                                    (nextSgp.fairOdds * 1.05).clamp(1.25, 18.0).toStringAsFixed(2));
                                              }),
                                            );
                                          }).toList(),
                                        ),
                                        const SizedBox(height: 4),
                                        Wrap(
                                          spacing: 6,
                                          children: leg2Labels.entries.map((e) {
                                            final sel = sgpLeg2 == e.key;
                                            return ChoiceChip(
                                              label: Text(e.value, style: const TextStyle(fontSize: 10)),
                                              selected: sel,
                                              selectedColor: const Color(0xFF3B82F6),
                                              onSelected: (_) => setModalState(() {
                                                sgpLeg2 = e.key;
                                                final nextSgp = PoissonEngine.calculateSgp(
                                                    poisson, sgpLeg1, leg1Labels[sgpLeg1]!, sgpLeg2, e.value);
                                                sgpBookieOdds = double.parse(
                                                    (nextSgp.fairOdds * 1.05).clamp(1.25, 18.0).toStringAsFixed(2));
                                              }),
                                            );
                                          }).toList(),
                                        ),
                                        const SizedBox(height: 8),
                                        _StatCompareRow(
                                          label: 'Naiv vs. Valódi korrelált esély',
                                          homeVal: '${(sgp.independentProb * 100).toStringAsFixed(1)}%',
                                          awayVal: '${(sgp.correlatedProb * 100).toStringAsFixed(1)}% (Fair: ${sgp.fairOdds})',
                                        ),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text('Bukmékeri SGP szorzó: ${sgpBookieOdds.toStringAsFixed(2)}',
                                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                            Text(
                                              'EV: ${sgpEv >= 0 ? "+" : ""}${sgpEv.toStringAsFixed(1)}%',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: sgpEv >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                              ),
                                            ),
                                          ],
                                        ),
                                        Slider(
                                          value: sgpBookieOdds.clamp(1.20, 15.0),
                                          min: 1.20,
                                          max: 15.0,
                                          activeColor: const Color(0xFF3B82F6),
                                          onChanged: (v) => setModalState(
                                              () => sgpBookieOdds = double.parse(v.toStringAsFixed(2))),
                                        ),
                                        SizedBox(
                                          width: double.infinity,
                                          child: FilledButton.icon(
                                            onPressed: () {
                                              Navigator.pop(context);
                                              _openLogBetDialog(
                                                match,
                                                customLabel: 'SGP: ${sgp.leg1Label} + ${sgp.leg2Label}',
                                                customOddsVal: sgpBookieOdds,
                                                customProbVal: sgp.correlatedProb,
                                              );
                                            },
                                            icon: const Icon(Icons.add_task, size: 16),
                                            label: const Text('SGP kombináció naplózása', style: TextStyle(fontSize: 12)),
                                            style: FilledButton.styleFrom(
                                              backgroundColor: const Color(0xFF3B82F6),
                                              foregroundColor: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),

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

                              // 5. FÜL: H2H
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
        bankroll: _bankroll,
        onToggleWatch: _toggleWatch,
        onSelectMatch: _openMatchDetail,
        onUpdateBetStatus: _updateBetStatus,
        onEditClosingOdds: _openEditClosingOddsDialog,
        onAddManualBet: _addManualBet,
        onAdjustCapital: _adjustBankrollCapital,
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
                _isLiveMode ? 'v7 LAB' : 'v7 DEMÓ',
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

class ValueFeedTab extends StatefulWidget {
  final MatchList matches;
  final String baseUrl;
  final String apiKey;
  final int dayOffset;
  final double bankroll;
  final String stakeProfile;
  final SlipItemList slipItems;
  final Set<String> favoriteLeagues;
  final void Function(String) onToggleFavoriteLeague;
  final void Function({required bool conservative}) onGenerateAiSlip;
  final void Function(int) onDayChanged;
  final Future<void> Function() onRefresh;
  final void Function(MatchPick) onSelectMatch;
  final void Function(String) onToggleWatch;
  final void Function(MatchPick) onToggleSlip;
  final void Function(MatchPick) onEditOdds;
  final void Function(MatchPick) onLogBet;

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
  String _smartFilter = 'all';
  double _minEvThreshold = 0.0;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final leagueSet = <String>{'Összes', ...widget.favoriteLeagues};
    for (final m in widget.matches) {
      leagueSet.add(m.league);
    }
    final leagues = leagueSet.toList();
    if (!leagues.contains(_selectedLeague)) {
      _selectedLeague = 'Összes';
    }

    final liveCount = widget.matches.where((m) => m.isLive).length;
    final pressureCount = widget.matches.where((m) => m.isHighPressure).length;
    final steamCount = widget.matches.where((m) => m.isSteamMove).length;

    final filtered = widget.matches.where((m) {
      if (_selectedLeague != 'Összes' && m.league != _selectedLeague) return false;
      if (_smartFilter == 'favorites' && !widget.favoriteLeagues.contains(m.league)) return false;
      if (_smartFilter == 'live' && !m.isLive) return false;
      if (_smartFilter == 'pressure' && !m.isHighPressure) return false;
      if (_smartFilter == 'steam' && !m.isSteamMove) return false;
      if (_smartFilter == 'standings' && !m.hasStandingData) return false;
      if (m.edgePercent < _minEvThreshold) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchText = '${m.homeTeam} ${m.awayTeam} ${m.league} ${m.market}'.toLowerCase();
        if (!matchText.contains(q)) return false;
      }
      return true;
    }).toList();

    final topVault = widget.matches.where((m) => !m.isFinished && m.edgePercent > 0).toList()
      ..sort((a, b) {
        final aScore = a.edgePercent + (widget.favoriteLeagues.contains(a.league) ? 1.5 : 0.0);
        final bScore = b.edgePercent + (widget.favoriteLeagues.contains(b.league) ? 1.5 : 0.0);
        return bScore.compareTo(aScore);
      });

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      color: const Color(0xFF10B981),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 84),
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: -1, label: Text('Tegnap')),
              ButtonSegment(value: 0, label: Text('Ma')),
              ButtonSegment(value: 1, label: Text('Holnap')),
            ],
            selected: {widget.dayOffset},
            onSelectionChanged: (s) => widget.onDayChanged(s.first),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => widget.onGenerateAiSlip(conservative: true),
                  icon: const Icon(Icons.shield_outlined, size: 15, color: Color(0xFF10B981)),
                  label: const Text('AI Duplázó (~2.0x)', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF1F2937)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => widget.onGenerateAiSlip(conservative: false),
                  icon: const Icon(Icons.bolt, size: 15, color: Color(0xFF3B82F6)),
                  label: const Text('AI Value Tripla', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF1F2937)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Keresés csapatra, ligára vagy piacra...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFF131A29),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF1F2937)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _SmartChip(
                  label: 'Mind (${widget.matches.length})',
                  selected: _smartFilter == 'all',
                  onTap: () => setState(() => _smartFilter = 'all'),
                ),
                const SizedBox(width: 6),
                _SmartChip(
                  label: '★ Kedvenc ligák',
                  selected: _smartFilter == 'favorites',
                  color: const Color(0xFFF59E0B),
                  onTap: () => setState(() => _smartFilter = 'favorites'),
                ),
                const SizedBox(width: 6),
                _SmartChip(
                  label: '🔴 Élő ($liveCount)',
                  selected: _smartFilter == 'live',
                  color: const Color(0xFFEF4444),
                  onTap: () => setState(() => _smartFilter = 'live'),
                ),
                const SizedBox(width: 6),
                _SmartChip(
                  label: '🔥 Gólnyomás ($pressureCount)',
                  selected: _smartFilter == 'pressure',
                  color: const Color(0xFFF59E0B),
                  onTap: () => setState(() => _smartFilter = 'pressure'),
                ),
                const SizedBox(width: 6),
                _SmartChip(
                  label: '📉 Steam Move ($steamCount)',
                  selected: _smartFilter == 'steam',
                  color: const Color(0xFF3B82F6),
                  onTap: () => setState(() => _smartFilter = 'steam'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Állítható Min. EV% küszöb szűrő
          Row(
            children: [
              const Text('Min. EV:', style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
              const SizedBox(width: 8),
              ...[0.0, 2.0, 5.0, 8.0].map((thr) {
                final sel = _minEvThreshold == thr;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(thr == 0.0 ? 'Mind' : '+${thr.toInt()}%',
                        style: const TextStyle(fontSize: 10)),
                    selected: sel,
                    selectedColor: const Color(0xFF10B981),
                    onSelected: (_) => setState(() => _minEvThreshold = thr),
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 8),
          if (topVault.isNotEmpty && _searchQuery.isEmpty && _smartFilter == 'all' && _minEvThreshold == 0.0) ...[
            const Text('Napi Top 3 AI Széf (16-piacos Dixon-Coles)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
            const SizedBox(height: 8),
            SizedBox(
              height: 98,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: topVault.take(3).length,
                itemBuilder: (context, idx) {
                  final top = topVault[idx];
                  return GestureDetector(
                    onTap: () => widget.onSelectMatch(top),
                    child: Container(
                      width: 225,
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF132A24), Color(0xFF131A29)],
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
                              Expanded(
                                child: Text(
                                  '${top.homeTeam} – ${top.awayTeam}',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                              Text(
                                '+${top.edgePercent.toStringAsFixed(1)}%',
                                style: const TextStyle(
                                    color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                            ],
                          ),
                          Text(top.market,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: Color(0xFFD1D5DB))),
                          Text(
                            'Szorzó: ${top.marketOdds} • Tét: ${top.recommendedStake(widget.bankroll, widget.stakeProfile)} Ft',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
          ],
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: leagues.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final league = leagues[index];
                final isSelected = league == _selectedLeague;
                final isFav = widget.favoriteLeagues.contains(league);
                return GestureDetector(
                  onLongPress: () => widget.onToggleFavoriteLeague(league),
                  child: FilterChip(
                    label: Text(
                      league == 'Összes' ? league : '${isFav ? "★ " : ""}$league',
                      style: TextStyle(
                        fontSize: 12,
                        color: isSelected ? Colors.black : Colors.white,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: const Color(0xFF10B981),
                    backgroundColor: const Color(0xFF131A29),
                    onSelected: (_) => setState(() => _selectedLeague = league),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text('Nincs a szűrőnek megfelelő mérkőzés.',
                    style: TextStyle(color: Color(0xFF9CA3AF))),
              ),
            )
          else
            ...filtered.map(
              (match) {
                final inSlip = widget.slipItems.any((s) => s.matchId == match.id);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: MatchValueCard(
                    match: match,
                    baseUrl: widget.baseUrl,
                    apiKey: widget.apiKey,
                    bankroll: widget.bankroll,
                    stakeProfile: widget.stakeProfile,
                    isInSlip: inSlip,
                    isFavLeague: widget.favoriteLeagues.contains(match.league),
                    onToggleFavLeague: () => widget.onToggleFavoriteLeague(match.league),
                    onTap: () => widget.onSelectMatch(match),
                    onToggleWatch: () => widget.onToggleWatch(match.id),
                    onToggleSlip: () => widget.onToggleSlip(match),
                    onEditOdds: () => widget.onEditOdds(match),
                    onLogBet: () => widget.onLogBet(match),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _SmartChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _SmartChip({
    required this.label,
    required this.selected,
    this.color = const Color(0xFF10B981),
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color : const Color(0xFF131A29),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : const Color(0xFF1F2937)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: selected ? Colors.black : const Color(0xFFD1D5DB),
          ),
        ),
      ),
    );
  }
}

class MatchValueCard extends StatelessWidget {
  final MatchPick match;
  final String baseUrl;
  final String apiKey;
  final double bankroll;
  final String stakeProfile;
  final bool isInSlip;
  final bool isFavLeague;
  final VoidCallback onToggleFavLeague;
  final VoidCallback onTap;
  final VoidCallback onToggleWatch;
  final VoidCallback onToggleSlip;
  final VoidCallback onEditOdds;
  final VoidCallback onLogBet;

  const MatchValueCard({
    super.key,
    required this.match,
    required this.baseUrl,
    required this.apiKey,
    required this.bankroll,
    required this.stakeProfile,
    required this.isInSlip,
    required this.isFavLeague,
    required this.onToggleFavLeague,
    required this.onTap,
    required this.onToggleWatch,
    required this.onToggleSlip,
    required this.onEditOdds,
    required this.onLogBet,
  });

  @override
  Widget build(BuildContext context) {
    final edge = match.edgePercent;
    final recStake = match.recommendedStake(bankroll, stakeProfile);
    final dropPct = match.oddsDropPercent;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: onToggleFavLeague,
                          child: Icon(
                            isFavLeague ? Icons.star : Icons.star_border,
                            size: 16,
                            color: isFavLeague ? const Color(0xFFF59E0B) : const Color(0xFF6B7280),
                          ),
                        ),
                        const SizedBox(width: 4),
                        if (match.isLive) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'ÉLŐ ${match.minute ?? ""}\'',
                              style: const TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (match.isHighPressure) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color.fromRGBO(245, 158, 11, 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              '🔥 NYOMÁS',
                              style: TextStyle(
                                  fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFF59E0B)),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (match.isSteamMove) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color.fromRGBO(59, 130, 246, 0.22),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '📉 STEAM -${dropPct.toStringAsFixed(0)}%',
                              style: const TextStyle(
                                  fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF60A5FA)),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            '${match.league} • ${match.kickoff}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color.fromRGBO(16, 185, 129, 0.16),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '+${edge.toStringAsFixed(1)}% EV',
                          style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: onToggleWatch,
                        child: Icon(
                          match.isWatched ? Icons.bookmark : Icons.bookmark_border,
                          size: 20,
                          color: match.isWatched ? const Color(0xFFF59E0B) : const Color(0xFF9CA3AF),
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
                    baseUrl: baseUrl,
                    apiKey: apiKey,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          match.homePos != null ? '${match.homeTeam} (${match.homePos}.)' : match.homeTeam,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        WdlStrip(codes: match.homeFormCodes),
                      ],
                    ),
                  ),
                  if (match.homeScore != null && match.awayScore != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A0E17),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${match.homeScore} - ${match.awayScore}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: match.isLive ? const Color(0xFFEF4444) : Colors.white,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          match.awayPos != null ? '(${match.awayPos}.) ${match.awayTeam}' : match.awayTeam,
                          textAlign: TextAlign.end,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        WdlStrip(codes: match.awayFormCodes),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TeamLogoBadge(
                    teamId: match.awayId,
                    teamName: match.awayTeam,
                    baseUrl: baseUrl,
                    apiKey: apiKey,
                    size: 22,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                match.trendSummary,
                style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0E17),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1F2937)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(match.market,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 2),
                          Text(
                            'AI: ${(match.modelProb * 100).round()}% • Ajánlott tét: $recStake Ft',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: onEditOdds,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                            decoration: BoxDecoration(
                              color: match.isCustomOdds
                                  ? const Color(0xFFF59E0B)
                                  : const Color(0xFF10B981),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  '@ ${match.marketOdds.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                                const SizedBox(width: 3),
                                const Icon(Icons.edit, size: 11, color: Colors.black),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: Icon(
                            isInSlip ? Icons.check_circle : Icons.playlist_add,
                            color: isInSlip ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
                            size: 21,
                          ),
                          tooltip: 'Kombi szelvénybe',
                          onPressed: onToggleSlip,
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline, color: Color(0xFF10B981), size: 21),
                          tooltip: 'Naplózás',
                          onPressed: onLogBet,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TrendRadarTab extends StatefulWidget {
  final MatchList matches;
  final String baseUrl;
  final String apiKey;
  final void Function(MatchPick) onSelectMatch;

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
  String _selectedCategory = 'Összes';

  @override
  Widget build(BuildContext context) {
    final categories = ['Összes', 'Gólok / BTTS', 'Tabella & Forma', 'xG eltérés'];
    final list = _selectedCategory == 'Összes'
        ? widget.matches
        : widget.matches.where((m) => m.trendCategory == _selectedCategory).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Statisztikai Trend Radar',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: categories.map((cat) {
              final selected = cat == _selectedCategory;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(cat),
                  selected: selected,
                  selectedColor: const Color(0xFF3B82F6),
                  onSelected: (_) => setState(() => _selectedCategory = cat),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        ...list.map((m) {
          final hitCount = m.last6Trend.where((e) => e).length;
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              onTap: () => widget.onSelectMatch(m),
              contentPadding: const EdgeInsets.all(14),
              leading: TeamLogoBadge(
                teamId: m.homeId,
                teamName: m.homeTeam,
                baseUrl: widget.baseUrl,
                apiKey: widget.apiKey,
                size: 32,
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text('${m.homeTeam} – ${m.awayTeam}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                  Text('$hitCount / 6 találat',
                      style: const TextStyle(
                          color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 12)),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  Text(m.trendSummary, style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 10),
                  Row(
                    children: m.last6Trend.map((hit) {
                      return Container(
                        width: 24,
                        height: 24,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: hit
                              ? const Color.fromRGBO(16, 185, 129, 0.2)
                              : const Color.fromRGBO(239, 68, 68, 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: hit ? const Color(0xFF10B981) : const Color(0xFFEF4444)),
                        ),
                        child: Icon(
                          hit ? Icons.check : Icons.close,
                          size: 14,
                          color: hit ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

class CalculatorTab extends StatefulWidget {
  final MatchList matches;
  final double bankroll;
  final bool autoBankroll;
  final String stakeProfile;
  final void Function(double) onBankrollChanged;
  final void Function(bool) onAutoBankrollChanged;
  final void Function(String) onStakeProfileChanged;

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
  int _calcMode = 0; // 0: EV & Kelly, 1: Dixon-Coles, 2: Surebet, 3: Monte Carlo, 4: Odds Konverter
  double _odds = 1.95;
  double _probPercent = 56;
  double _simHomeXg = 1.85;
  double _simAwayXg = 1.15;

  // Surebet
  bool _isThreeWayArb = false;
  double _arbOdds1 = 2.15;
  double _arbOddsX = 3.60;
  double _arbOdds2 = 4.20;
  double _arbTotalStake = 20000;

  // Monte Carlo
  int _mcSimSeed = 1;
  double _mcAvgOdds = 1.92;
  double _mcEdgePct = 5.0;

  // Odds Konverter
  double _convDecimal = 2.10;

  String _toFractionalOdds(double dec) {
    final profitUnit = (dec - 1.0).clamp(0.01, 100.0);
    int bestNum = 1;
    int bestDen = 1;
    double minErr = 999.0;
    for (int d = 1; d <= 20; d++) {
      final n = (profitUnit * d).round().clamp(1, 500);
      final err = ((n / d) - profitUnit).abs();
      if (err < minErr) {
        minErr = err;
        bestNum = n;
        bestDen = d;
      }
    }
    return '$bestNum/$bestDen';
  }

  String _toAmericanOdds(double dec) {
    if (dec >= 2.0) {
      final us = ((dec - 1.0) * 100.0).round();
      return '+$us';
    } else {
      final us = (-100.0 / (dec - 1.0)).round();
      return '$us';
    }
  }

  @override
  Widget build(BuildContext context) {
    final prob = _probPercent / 100.0;
    final fairOdds = 1.0 / prob;
    final evPercent = ((prob * _odds) - 1.0) * 100.0;
    final kelly = ((prob * _odds) - 1.0) / (_odds - 1.0);
    final mult = widget.stakeProfile == 'quarter_kelly' ? 0.25 : 0.50;
    final recommendedStake = widget.stakeProfile == 'fix_2'
        ? (widget.bankroll * 0.02).round()
        : (kelly > 0 ? (widget.bankroll * (kelly * mult).clamp(0.005, 0.06)).round() : 0);

    final simPoisson = PoissonEngine.calculate(_simHomeXg, _simAwayXg);

    final invSum = _isThreeWayArb
        ? ((1.0 / _arbOdds1) + (1.0 / _arbOddsX) + (1.0 / _arbOdds2))
        : ((1.0 / _arbOdds1) + (1.0 / _arbOdds2));
    final isSurebet = invSum < 1.0;
    final arbProfitPct = ((1.0 / invSum) - 1.0) * 100.0;
    final stake1 = _arbTotalStake * ((1.0 / _arbOdds1) / invSum);
    final stakeX = _isThreeWayArb ? _arbTotalStake * ((1.0 / _arbOddsX) / invSum) : 0.0;
    final stake2 = _arbTotalStake * ((1.0 / _arbOdds2) / invSum);
    final guaranteedReturn = stake1 * _arbOdds1;

    final CurveList mcCurves = [];
    final mcWinProb = (((_mcEdgePct / 100.0) + 1.0) / _mcAvgOdds).clamp(0.15, 0.90);
    final mcStakeFrac = widget.stakeProfile == 'fix_2'
        ? 0.02
        : (((mcWinProb * _mcAvgOdds - 1.0) / (_mcAvgOdds - 1.0)) * mult).clamp(0.005, 0.05);
    final rng = math.Random(_mcSimSeed);
    int ruinCount = 0;
    final DoubleList endBankrolls = [];

    for (int sim = 0; sim < 30; sim++) {
      double b = widget.bankroll;
      final DoubleList path = [b];
      bool ruined = false;
      for (int bet = 0; bet < 100; bet++) {
        final st = b * mcStakeFrac;
        if (rng.nextDouble() < mcWinProb) {
          b += st * (_mcAvgOdds - 1.0);
        } else {
          b -= st;
        }
        if (b < widget.bankroll * 0.25) ruined = true;
        path.add(b);
      }
      if (ruined) ruinCount++;
      endBankrolls.add(b);
      mcCurves.add(path);
    }
    endBankrolls.sort();
    final medianEnd = endBankrolls[endBankrolls.length ~/ 2];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('EV / Kelly', style: TextStyle(fontSize: 11))),
              ButtonSegment(value: 1, label: Text('Dixon-Coles', style: TextStyle(fontSize: 11))),
              ButtonSegment(value: 2, label: Text('Surebet', style: TextStyle(fontSize: 11))),
              ButtonSegment(value: 3, label: Text('Monte Carlo', style: TextStyle(fontSize: 11))),
              ButtonSegment(value: 4, label: Text('Konverter', style: TextStyle(fontSize: 11))),
            ],
            selected: {_calcMode},
            onSelectionChanged: (s) => setState(() => _calcMode = s.first),
          ),
        ),
        const SizedBox(height: 16),
        if (_calcMode == 0) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Tőke (Bankroll): ${widget.bankroll.round()} Ft',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          const Text('Auto', style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                          Switch(
                            value: widget.autoBankroll,
                            activeColor: const Color(0xFF10B981),
                            onChanged: widget.onAutoBankrollChanged,
                          ),
                        ],
                      ),
                    ],
                  ),
                  Slider(
                    value: widget.bankroll.clamp(5000, 500000),
                    min: 5000,
                    max: 500000,
                    divisions: 99,
                    activeColor: const Color(0xFF10B981),
                    onChanged: widget.onBankrollChanged,
                  ),
                  const SizedBox(height: 6),
                  const Text('Tétkezelési stratégia:',
                      style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                  const SizedBox(height: 6),
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
                  const Divider(height: 24, color: Color(0xFF1F2937)),
                  Text('Bukmékeri szorzó: ${_odds.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Slider(
                    value: _odds,
                    min: 1.15,
                    max: 4.50,
                    divisions: 67,
                    activeColor: const Color(0xFF3B82F6),
                    onChanged: (v) => setState(() => _odds = double.parse(v.toStringAsFixed(2))),
                  ),
                  Text('Modell valószínűség: ${_probPercent.round()}% (Fair: ${fairOdds.toStringAsFixed(2)})',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Slider(
                    value: _probPercent,
                    min: 15,
                    max: 90,
                    divisions: 75,
                    activeColor: const Color(0xFF10B981),
                    onChanged: (v) => setState(() => _probPercent = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text('Várható Érték (EV)',
                          style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                      const SizedBox(height: 4),
                      Text(
                        '${evPercent >= 0 ? '+' : ''}${evPercent.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: evPercent > 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                        ),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      const Text('Ajánlott Tét', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                      const SizedBox(height: 4),
                      Text(
                        '$recommendedStake Ft',
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF3B82F6)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ] else if (_calcMode == 1) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Hazai várható gól (xG): ${_simHomeXg.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                  Slider(
                    value: _simHomeXg,
                    min: 0.30,
                    max: 3.80,
                    divisions: 70,
                    activeColor: const Color(0xFF10B981),
                    onChanged: (v) => setState(() => _simHomeXg = v),
                  ),
                  Text('Vendég várható gól (xG): ${_simAwayXg.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF3B82F6))),
                  Slider(
                    value: _simAwayXg,
                    min: 0.30,
                    max: 3.80,
                    divisions: 70,
                    activeColor: const Color(0xFF3B82F6),
                    onChanged: (v) => setState(() => _simAwayXg = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Dixon-Coles 16-piacos eredmények',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 12),
                  _StatCompareRow(
                    label: '1 / X / 2',
                    homeVal: '${(simPoisson.homeWin * 100).round()}% / ${(simPoisson.draw * 100).round()}%',
                    awayVal: '${(simPoisson.awayWin * 100).round()}%',
                  ),
                  _StatCompareRow(
                    label: '1X / X2 / DNB 1',
                    homeVal:
                        '${(simPoisson.doubleChance1X * 100).round()}% / ${(simPoisson.doubleChanceX2 * 100).round()}%',
                    awayVal: '${(simPoisson.dnbHome * 100).round()}%',
                  ),
                  _StatCompareRow(
                    label: '2.5 gól felett / BTTS',
                    homeVal: '${(simPoisson.over25 * 100).round()}%',
                    awayVal: '${(simPoisson.btts * 100).round()}%',
                  ),
                  _StatCompareRow(
                    label: '1. Félidő 0.5+ / 1.5+',
                    homeVal: '${(simPoisson.htOver05 * 100).round()}%',
                    awayVal: '${(simPoisson.htOver15 * 100).round()}%',
                  ),
                  const SizedBox(height: 12),
                  const Text('Top 3 legvalószínűbb pontos eredmény',
                      style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                  const SizedBox(height: 8),
                  Row(
                    children: simPoisson.topScores.map((s) {
                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0A0E17),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            children: [
                              Text(s.score,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              Text('${(s.probability * 100).toStringAsFixed(1)}%',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF10B981))),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ] else if (_calcMode == 2) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Surebet / Dutcher Kalkulátor',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('2-irányú', style: TextStyle(fontSize: 11))),
                          ButtonSegment(value: true, label: Text('1X2 (3)', style: TextStyle(fontSize: 11))),
                        ],
                        selected: {_isThreeWayArb},
                        onSelectionChanged: (s) => setState(() => _isThreeWayArb = s.first),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text('Összes megosztandó tét: ${_arbTotalStake.round()} Ft',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Slider(
                    value: _arbTotalStake,
                    min: 2000,
                    max: 200000,
                    divisions: 99,
                    activeColor: const Color(0xFF10B981),
                    onChanged: (v) => setState(() => _arbTotalStake = v),
                  ),
                  Text('1. kimenet szorzó: ${_arbOdds1.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 13)),
                  Slider(
                    value: _arbOdds1,
                    min: 1.20,
                    max: 6.00,
                    divisions: 96,
                    activeColor: const Color(0xFF3B82F6),
                    onChanged: (v) => setState(() => _arbOdds1 = double.parse(v.toStringAsFixed(2))),
                  ),
                  if (_isThreeWayArb) ...[
                    Text('Döntetlen (X) szorzó: ${_arbOddsX.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 13)),
                    Slider(
                      value: _arbOddsX,
                      min: 2.00,
                      max: 8.00,
                      divisions: 120,
                      activeColor: const Color(0xFFF59E0B),
                      onChanged: (v) => setState(() => _arbOddsX = double.parse(v.toStringAsFixed(2))),
                    ),
                  ],
                  Text('2. kimenet szorzó: ${_arbOdds2.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 13)),
                  Slider(
                    value: _arbOdds2,
                    min: 1.20,
                    max: 8.00,
                    divisions: 136,
                    activeColor: const Color(0xFF10B981),
                    onChanged: (v) => setState(() => _arbOdds2 = double.parse(v.toStringAsFixed(2))),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isSurebet ? 'BIZTOS PROFIT (SUREBET)' : 'Nincs arbitrázs (Dutcher)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isSurebet ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                        ),
                      ),
                      Text(
                        '${arbProfitPct >= 0 ? "+" : ""}${arbProfitPct.toStringAsFixed(2)}%',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isSurebet ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20, color: Color(0xFF1F2937)),
                  _StatCompareRow(
                    label: '1. kimenet tétje (@ $_arbOdds1)',
                    homeVal: '${stake1.round()} Ft',
                    awayVal: 'Vissza: ${guaranteedReturn.round()} Ft',
                  ),
                  if (_isThreeWayArb)
                    _StatCompareRow(
                      label: 'Döntetlen (X) tétje (@ $_arbOddsX)',
                      homeVal: '${stakeX.round()} Ft',
                      awayVal: 'Vissza: ${guaranteedReturn.round()} Ft',
                    ),
                  _StatCompareRow(
                    label: '2. kimenet tétje (@ $_arbOdds2)',
                    homeVal: '${stake2.round()} Ft',
                    awayVal: 'Vissza: ${guaranteedReturn.round()} Ft',
                  ),
                ],
              ),
            ),
          ),
        ] else if (_calcMode == 3) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Monte Carlo Tőke Szimulátor (100 tipp)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      IconButton(
                        icon: const Icon(Icons.casino, color: Color(0xFF10B981)),
                        tooltip: 'Új szimuláció futtatása',
                        onPressed: () => setState(() => _mcSimSeed++),
                      ),
                    ],
                  ),
                  Text('Átlagos szorzó: ${_mcAvgOdds.toStringAsFixed(2)} • Átlag EV: +${_mcEdgePct.toStringAsFixed(1)}%',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                  Slider(
                    value: _mcEdgePct,
                    min: 1.0,
                    max: 12.0,
                    divisions: 22,
                    activeColor: const Color(0xFF10B981),
                    onChanged: (v) => setState(() => _mcEdgePct = v),
                  ),
                  SizedBox(
                    height: 150,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: MonteCarloPainter(mcCurves, widget.bankroll),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _StatCompareRow(
                    label: 'Medián tőke 100 tipp után',
                    homeVal: '${widget.bankroll.round()} Ft →',
                    awayVal: '${medianEnd.round()} Ft',
                  ),
                  _StatCompareRow(
                    label: '75%+ tőkevesztés kockázata',
                    homeVal: '30 szimulált pálya',
                    awayVal: '${((ruinCount / 30.0) * 100).round()}%',
                  ),
                ],
              ),
            ),
          ),
        ] else ...[
          // 5. MÓD: ODDS KONVERTER (DECIMÁLIS <-> TÖRT UK <-> AMERIKAI US)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Odds Konverter & Implikált Valószínűség',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 12),
                  Text('Decimális (EU) szorzó: ${_convDecimal.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                  Slider(
                    value: _convDecimal,
                    min: 1.05,
                    max: 10.0,
                    divisions: 179,
                    activeColor: const Color(0xFF10B981),
                    onChanged: (v) => setState(() => _convDecimal = double.parse(v.toStringAsFixed(2))),
                  ),
                  const Divider(height: 20, color: Color(0xFF1F2937)),
                  _StatCompareRow(
                    label: 'Decimális (EU)',
                    homeVal: 'Európai formátum',
                    awayVal: _convDecimal.toStringAsFixed(2),
                  ),
                  _StatCompareRow(
                    label: 'Tört (UK / Brit)',
                    homeVal: 'Nettó nyeremény arány',
                    awayVal: _toFractionalOdds(_convDecimal),
                  ),
                  _StatCompareRow(
                    label: 'Amerikai (US / Moneyline)',
                    homeVal: _convDecimal >= 2.0 ? 'Underdog (+)' : 'Favorit (-)',
                    awayVal: _toAmericanOdds(_convDecimal),
                  ),
                  _StatCompareRow(
                    label: 'Implikált valószínűség',
                    homeVal: 'Break-even találati %',
                    awayVal: '${((1.0 / _convDecimal) * 100).toStringAsFixed(1)}%',
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

class TrackerAndWatchlistTab extends StatefulWidget {
  final MatchList matches;
  final BetList bets;
  final double bankroll;
  final void Function(String) onToggleWatch;
  final void Function(MatchPick) onSelectMatch;
  final void Function(String, String) onUpdateBetStatus;
  final void Function(BetRecord) onEditClosingOdds;
  final void Function(BetRecord) onAddManualBet;
  final void Function(double) onAdjustCapital;
  final void Function(String) onDeleteBet;

  const TrackerAndWatchlistTab({
    super.key,
    required this.matches,
    required this.bets,
    required this.bankroll,
    required this.onToggleWatch,
    required this.onSelectMatch,
    required this.onUpdateBetStatus,
    required this.onEditClosingOdds,
    required this.onAddManualBet,
    required this.onAdjustCapital,
    required this.onDeleteBet,
  });

  @override
  State<TrackerAndWatchlistTab> createState() => _TrackerAndWatchlistTabState();
}

class _TrackerAndWatchlistTabState extends State<TrackerAndWatchlistTab> {
  int _breakdownMode = 0; // 0: Liga, 1: Piac kategória

  String _generateCsvReport() {
    final buf = StringBuffer();
    buf.writeln('Datum;Liga;Merkozes;Piac;Kategoria;Odds;ZaroOdds;CLV_Pct;Tet_Ft;Statusz;Profit_Ft;Jegyzet');
    for (final b in widget.bets) {
      final clvStr = b.clvPercent != null ? b.clvPercent!.toStringAsFixed(2) : '';
      final closeStr = b.closingOdds != null ? b.closingOdds!.toStringAsFixed(2) : '';
      final cleanNote = b.note.replaceAll(';', ',').replaceAll('\n', ' ');
      buf.writeln(
          '${b.date};${b.league};${b.matchTitle};${b.market};${b.marketCategory};${b.odds.toStringAsFixed(2)};$closeStr;$clvStr;${b.stake.round()};${b.status};${b.profit.round()};$cleanNote');
    }
    return buf.toString();
  }

  void _showManualBetDialog() {
    final titleCtrl = TextEditingController();
    final leagueCtrl = TextEditingController(text: 'Premier League');
    final marketCtrl = TextEditingController(text: '2.5 gól felett');
    final oddsCtrl = TextEditingController(text: '1.90');
    final stakeCtrl = TextEditingController(text: '2000');
    final noteCtrl = TextEditingController();
    String status = 'pending';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDlg) {
            return AlertDialog(
              backgroundColor: const Color(0xFF131A29),
              title: const Text('Saját tipp kézi rögzítése', style: TextStyle(fontSize: 17)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Mérkőzés (pl. Real Madrid – Barcelona)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: leagueCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Bajnokság / Sport',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: marketCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Piac (pl. 9.5 szöglet felett)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: oddsCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Odds',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: stakeCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Tét (Ft)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'pending', label: Text('Nyitott', style: TextStyle(fontSize: 10))),
                        ButtonSegment(value: 'won', label: Text('Nyert', style: TextStyle(fontSize: 10))),
                        ButtonSegment(value: 'lost', label: Text('Vesztett', style: TextStyle(fontSize: 10))),
                      ],
                      selected: {status},
                      onSelectionChanged: (s) => setDlg(() => status = s.first),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Elemző jegyzet (opcionális)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Mégse'),
                ),
                FilledButton(
                  onPressed: () {
                    final title = titleCtrl.text.trim();
                    final odds = double.tryParse(oddsCtrl.text.replaceAll(',', '.')) ?? 1.85;
                    final stake = double.tryParse(stakeCtrl.text) ?? 1000.0;
                    if (title.isEmpty) return;
                    final now = DateTime.now();
                    final dateLabel =
                        '${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}.';
                    widget.onAddManualBet(
                      BetRecord(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        league: leagueCtrl.text.trim().isEmpty ? 'Egyéb' : leagueCtrl.text.trim(),
                        matchTitle: title,
                        market: marketCtrl.text.trim().isEmpty ? 'Saját piac' : marketCtrl.text.trim(),
                        marketCode: 'manual',
                        marketCategory: 'Saját tipp',
                        odds: odds.clamp(1.01, 100.0),
                        stake: stake.clamp(100, 1000000),
                        status: status,
                        date: dateLabel,
                        note: noteCtrl.text.trim(),
                      ),
                    );
                    Navigator.pop(context);
                  },
                  child: const Text('Hozzáadás'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showCapitalDialog() {
    final amountCtrl = TextEditingController(text: '10000');
    bool isDeposit = true;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDlg) {
            return AlertDialog(
              backgroundColor: const Color(0xFF131A29),
              title: const Text('Bankroll Befizetés / Kifizetés', style: TextStyle(fontSize: 17)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Jelenlegi tőke: ${widget.bankroll.round()} Ft',
                      style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('+ Befizetés')),
                      ButtonSegment(value: false, label: Text('- Kifizetés')),
                    ],
                    selected: {isDeposit},
                    onSelectionChanged: (s) => setDlg(() => isDeposit = s.first),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Összeg (Ft)',
                      border: OutlineInputBorder(),
                      isDense: true,
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
                    final amt = double.tryParse(amountCtrl.text) ?? 0.0;
                    if (amt > 0) {
                      widget.onAdjustCapital(isDeposit ? amt : -amt);
                    }
                    Navigator.pop(context);
                  },
                  child: const Text('Végrehajtás'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final watched = widget.matches.where((m) => m.isWatched).toList();
    final settledBets = widget.bets.where((b) => b.status == 'won' || b.status == 'lost').toList();

    final totalProfit = widget.bets.fold<double>(0.0, (sum, b) => sum + b.profit);
    final totalStaked = settledBets.fold<double>(0.0, (sum, b) => sum + b.stake);
    final roiPercent = totalStaked > 0 ? (totalProfit / totalStaked) * 100.0 : 0.0;
    final wonCount = settledBets.where((b) => b.status == 'won').length;
    final winRate = settledBets.isNotEmpty ? (wonCount / settledBets.length) * 100.0 : 0.0;

    final clvList = widget.bets.map((b) => b.clvPercent).whereType<double>().toList();
    final avgClv = clvList.isNotEmpty
        ? (clvList.reduce((a, b) => a + b) / clvList.length)
        : null;

    double brierSum = 0.0;
    int brierCount = 0;
    for (final b in settledBets) {
      if (b.modelProb != null) {
        final outcome = b.status == 'won' ? 1.0 : 0.0;
        final diff = b.modelProb! - outcome;
        brierSum += diff * diff;
        brierCount++;
      }
    }
    final brierScore = brierCount > 0 ? (brierSum / brierCount) : null;

    final DoubleList curvePoints = [0.0];
    double running = 0.0;
    for (final b in settledBets.reversed) {
      running += b.profit;
      curvePoints.add(running);
    }

    // Napi profit összesítés dátum szerint
    final Map<String, double> dailyMap = {};
    for (final b in settledBets.reversed) {
      dailyMap[b.date] = (dailyMap[b.date] ?? 0.0) + b.profit;
    }
    final dailyLabels = dailyMap.keys.toList();
    final DoubleList dailyValues = dailyMap.values.toList();

    final Map<String, BetList> grouped = {};
    for (final b in settledBets) {
      final key = _breakdownMode == 0 ? b.league : b.marketCategory;
      grouped.putIfAbsent(key, () => []).add(b);
    }
    final RoiBreakdownList breakdownRows = [];
    grouped.forEach((key, list) {
      final prof = list.fold<double>(0.0, (s, e) => s + e.profit);
      final stk = list.fold<double>(0.0, (s, e) => s + e.stake);
      final wins = list.where((e) => e.status == 'won').length;
      breakdownRows.add(
        RoiBreakdownItem(
          name: key,
          count: list.length,
          profit: prof,
          roiPercent: stk > 0 ? (prof / stk) * 100.0 : 0.0,
          winRatePercent: list.isNotEmpty ? (wins / list.length) * 100.0 : 0.0,
        ),
      );
    });
    breakdownRows.sort((a, b) => b.profit.compareTo(a.profit));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Portfólió & ROI',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _showCapitalDialog,
                  icon: const Icon(Icons.account_balance_wallet_outlined, size: 15),
                  label: const Text('Tőke +/-', style: TextStyle(fontSize: 11)),
                ),
                const SizedBox(width: 6),
                FilledButton.icon(
                  onPressed: _showManualBetDialog,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Saját tipp', style: TextStyle(fontSize: 11)),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.black,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        const Text('Aktuális Tőke',
                            style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.bankroll.round()} Ft',
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF3B82F6)),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        const Text('Nettó Profit',
                            style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                        const SizedBox(height: 4),
                        Text(
                          '${totalProfit >= 0 ? '+' : ''}${totalProfit.round()} Ft',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: totalProfit >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                          ),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        const Text('ROI / Találat',
                            style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                        const SizedBox(height: 4),
                        Text(
                          '${roiPercent.toStringAsFixed(1)}% / ${winRate.round()}%',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
                const Divider(height: 20, color: Color(0xFF1F2937)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Text(
                      'Átlag CLV: ${avgClv != null ? "${avgClv >= 0 ? "+" : ""}${avgClv.toStringAsFixed(1)}%" : "Nincs adat"}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: (avgClv ?? 0) >= 0 ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                      ),
                    ),
                    Text(
                      'Brier Kalibráció: ${brierScore != null ? brierScore.toStringAsFixed(3) : "Nincs adat"}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                    ),
                  ],
                ),
                if (curvePoints.length >= 2) ...[
                  const SizedBox(height: 14),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Kumulatív Tőkegörbe (Equity Curve)',
                        style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 68,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: RoiCurvePainter(curvePoints),
                    ),
                  ),
                ],
                if (dailyValues.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Napi Profit / Veszteség Barchart',
                          style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                      Text('${dailyLabels.first} – ${dailyLabels.last}',
                          style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 64,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: DailyProfitBarPainter(dailyValues),
                    ),
                  ),
                ],
                if (widget.bets.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        final csv = _generateCsvReport();
                        Clipboard.setData(ClipboardData(text: csv));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Teljes CSV riport (jegyzetekkel) vágólapra másolva!')),
                        );
                      },
                      icon: const Icon(Icons.table_chart_outlined, size: 16),
                      label: const Text('CSV / Excel Export másolása', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (breakdownRows.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Teljesítmény bontás',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Liga', style: TextStyle(fontSize: 11))),
                  ButtonSegment(value: 1, label: Text('Piac', style: TextStyle(fontSize: 11))),
                ],
                selected: {_breakdownMode},
                onSelectionChanged: (s) => setState(() => _breakdownMode = s.first),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...breakdownRows.map((row) {
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF131A29),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1F2937)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('${row.count} tipp • Találati arány: ${row.winRatePercent.round()}%',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${row.profit >= 0 ? "+" : ""}${row.profit.round()} Ft',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: row.profit >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                        ),
                      ),
                      Text(
                        'ROI: ${row.roiPercent >= 0 ? "+" : ""}${row.roiPercent.toStringAsFixed(1)}%',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
        const SizedBox(height: 18),
        Text('Figyelőlista (${watched.length} meccs)',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (watched.isEmpty)
          const Text('Még nem jelöltél meg meccset a könyvjelző ikonnal.',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13))
        else
          ...watched.map((m) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  onTap: () => widget.onSelectMatch(m),
                  title: Text('${m.homeTeam} – ${m.awayTeam}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text('${m.market} @ ${m.marketOdds} • ${m.kickoff}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF10B981))),
                  trailing: IconButton(
                    icon: const Icon(Icons.bookmark_remove, color: Color(0xFFF59E0B)),
                    onPressed: () => widget.onToggleWatch(m.id),
                  ),
                ),
              )),
        const SizedBox(height: 20),
        Text('Rögzített Tippjeim (${widget.bets.length})',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (widget.bets.isEmpty)
          const Text('Még nincs rögzített tipp. Használd a + vagy a Saját tipp gombot!',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13))
        else
          ...widget.bets.map((b) {
            final clv = b.clvPercent;
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
                          child: Text(b.matchTitle,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                          onPressed: () => widget.onDeleteBet(b.id),
                        ),
                      ],
                    ),
                    Text('${b.market} @ ${b.odds} • Tét: ${b.stake.round()} Ft (${b.date})',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                    if (b.note.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('📝 ${b.note}',
                          style: const TextStyle(
                              fontSize: 11, fontStyle: FontStyle.italic, color: Color(0xFFD1D5DB))),
                    ],
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () => widget.onEditClosingOdds(b),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A0E17),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF1F2937)),
                        ),
                        child: Text(
                          b.closingOdds != null
                              ? 'Záró odds: ${b.closingOdds!.toStringAsFixed(2)} • CLV: ${clv! >= 0 ? "+" : ""}${clv.toStringAsFixed(1)}%'
                              : '+ Záró odds megadása (CLV méréshez)',
                          style: TextStyle(
                            fontSize: 11,
                            color: clv != null
                                ? (clv >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444))
                                : const Color(0xFF60A5FA),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'pending', label: Text('Nyitott', style: TextStyle(fontSize: 11))),
                        ButtonSegment(value: 'won', label: Text('Nyert', style: TextStyle(fontSize: 11))),
                        ButtonSegment(value: 'lost', label: Text('Vesztett', style: TextStyle(fontSize: 11))),
                        ButtonSegment(value: 'void', label: Text('Void', style: TextStyle(fontSize: 11))),
                      ],
                      selected: {b.status},
                      onSelectionChanged: (s) => widget.onUpdateBetStatus(b.id, s.first),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}
