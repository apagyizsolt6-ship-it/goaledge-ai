import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../services/poisson_engine.dart';
import '../services/sport_api_service.dart';
import '../services/notification_service.dart';
import '../services/app_update_service.dart';
import '../widgets/update_dialog.dart';
import '../widgets/charts.dart';
import '../screens/matches/match_detail_widgets.dart';

/// Central app state (refactored from monolithic MainNavigationScreen).
class AppController extends ChangeNotifier {
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

  AppController() {
    _matches = _buildDemoMatches();
    _loadSavedData();
  }

  int get selectedIndex => _selectedIndex;
  set selectedIndex(int v) { _selectedIndex = v; notifyListeners(); }
  int get dayOffset => _dayOffset;
  bool get isLoadingApi => _isLoadingApi;
  bool get isLiveMode => _isLiveMode;
  bool get autoLiveRadar => _autoLiveRadar;
  bool get autoBankroll => _autoBankroll;
  String get stakeProfile => _stakeProfile;
  String get apiKey => _apiKey;
  String get baseUrl => _baseUrl;
  String get lastApiStatus => _lastApiStatus;
  String? get rateLimitRemaining => _rateLimitRemaining;
  double get bankroll => _bankroll;
  MatchList get matches => _matches;
  BetList get bets => _bets;
  SlipItemList get slipItems => _slipItems;
  Set<String> get favoriteLeagues => _favoriteLeagues;

  void setBankroll(double val) { _bankroll = val; saveState(); notifyListeners(); }
  void setAutoBankroll(bool val) { _autoBankroll = val; saveState(); notifyListeners(); }
  void setStakeProfile(String val) { _stakeProfile = val; saveState(); notifyListeners(); }


  void toggleAutoLiveRadar([BuildContext? context]) {
    
      _autoLiveRadar = !_autoLiveRadar;
    
    notifyListeners();
    _liveTimer?.cancel();
    if (_autoLiveRadar) {
      _liveTimer = Timer.periodic(const Duration(seconds: 75), (_) {
        if (_apiKey.isNotEmpty && !_isLoadingApi) {
          syncSportApi(silent: true);
        }
      });
    } else {
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
    
    notifyListeners();

    if (_apiKey.isNotEmpty) {
      syncSportApi(silent: true);
    }
  }

  Future<void> saveState() async {
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

  void toggleFavoriteLeague(String league) {
    if (league == 'Összes') return;
    
      if (_favoriteLeagues.contains(league)) {
        _favoriteLeagues.remove(league);
      } else {
        _favoriteLeagues.add(league);
      }
    
    notifyListeners();
    saveState();
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
      
    notifyListeners();

      if (decoded['watchedIds'] is List) {
        final StringList wList = (decoded['watchedIds'] as List).map((e) => e.toString()).toList();
        await prefs.setStringList('watched_ids', wList);
      }

      await saveState();
      if (_apiKey.isNotEmpty) {
        syncSportApi(silent: true);
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

  Future<SportApiResponse?> syncSportApi({bool silent = false, BuildContext? context}) async {
    if (_apiKey.trim().isEmpty) {
      if (!silent ) {
      }
      return null;
    }

    _isLoadingApi = true;
    notifyListeners();
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

    {
      
        _isLoadingApi = false;
        _rateLimitRemaining = result.rateLimitRemaining ?? _rateLimitRemaining;
        _lastApiStatus = '${result.message}\nNyers válasz: ${result.rawPreview}';
        if (result.success && result.matches.isNotEmpty) {
          _matches = result.matches;
          _isLiveMode = true;
        }
      
    notifyListeners();

      if (result.success && result.matches.isNotEmpty) {
        _checkAndFirePushNotifications(result.matches);
        if (result.matches.any((m) => m.isHighPressure)) {
          HapticFeedback.heavyImpact();
        }
        saveState();
        _autoSettlePendingBets(result.matches);
        _enrichMatchesWithStandings();
      }

      if (!silent) {
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
      if (table.isEmpty) continue;

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
      if (anyUpdated ) {
        
    notifyListeners();
        saveState();
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

      updateBetStatus(bet.id, newStatus);
      changed = true;
    }

    if (changed) {
      saveState();
    }
  }

  void changeDayOffset(int newOffset) {
    _dayOffset = newOffset;
    notifyListeners();
    if (_apiKey.isNotEmpty) {
      syncSportApi();
    }
  }

  void toggleWatch(String matchId) {
    
      final idx = _matches.indexWhere((m) => m.id == matchId);
      if (idx != -1) {
        _matches[idx].isWatched = !_matches[idx].isWatched;
      }
    
    notifyListeners();
    saveState();
  }

  bool _isMarketInSlip(String matchId, String marketCode) {
    return _slipItems.any((s) => s.matchId == matchId && s.marketCode == marketCode);
  }

  void toggleSlipOption(MatchPick match, {MarketOption? chosenMarket}) {
    final code = chosenMarket?.code ?? match.marketCode;
    final label = chosenMarket?.label ?? match.market;
    final odds = chosenMarket?.refOdds ?? match.marketOdds;
    final prob = chosenMarket?.probability ?? match.modelProb;
    final key = '${match.id}_$code';

    
      final existingIdx = _slipItems.indexWhere((s) => s.key == key);
      if (existingIdx != -1) {
        _slipItems.removeAt(existingIdx);
      } else {
        if (_slipItems.length >= 6) {
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
    
    notifyListeners();
  }

  void generateAiSlip({required bool conservative}) {
    final candidates = _matches.where((m) => !m.isFinished && m.edgePercent > 0).toList();
    if (candidates.length < 2) {
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
    
      _slipItems
        ..clear()
        ..addAll(generated);
    
    notifyListeners();
    HapticFeedback.mediumImpact();
  }

  void openEditOddsDialog(BuildContext context, MatchPick match) {
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
                
                  _customOddsMap.remove(match.id);
                  final fair = 1.0 / match.modelProb;
                  match.marketOdds = double.parse((fair * 1.08).clamp(1.20, 5.20).toStringAsFixed(2));
                  match.isCustomOdds = false;
                
    notifyListeners();
                saveState();
                Navigator.pop(context);
              },
              child: const Text('Alaphelyzet'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = double.tryParse(controller.text.replaceAll(',', '.'));
                if (parsed != null && parsed >= 1.05 && parsed <= 50.0) {
                  
                    _customOddsMap[match.id] = parsed;
                    match.marketOdds = parsed;
                    match.isCustomOdds = true;
                    match.oddsHistory.add(parsed);
                  
    notifyListeners();
                  saveState();
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

  void openEditClosingOddsDialog(BuildContext context, BetRecord bet) {
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
                
    notifyListeners();
                saveState();
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

  void openComboSlipSheet(BuildContext context) {
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
                          _slipItems.clear();
    notifyListeners();
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
                              _slipItems.removeWhere((e) => e.key == it.key);
    notifyListeners();
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
                              StatCompareRow(
                                label: 'Alaptét / oszlop ($sysCombos db)',
                                homeVal: '${(comboStake / sysCombos).round()} Ft',
                                awayVal: 'Összesen: ${comboStake.round()} Ft',
                              ),
                              StatCompareRow(
                                label: 'Min / Max nyeremény',
                                homeVal: 'Min: ${sysMinWin.round()} Ft',
                                awayVal: 'Max: ${sysMaxWin.round()} Ft',
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              StatCompareRow(
                                label: 'Eredő szorzó',
                                homeVal: '${(combinedProb * 100).toStringAsFixed(1)}% esély',
                                awayVal: '${totalOdds.toStringAsFixed(2)}x',
                              ),
                              StatCompareRow(
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
                            
    notifyListeners();
                            saveState();
                            Navigator.pop(context);
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

  void addBet(MatchPick match, double stake, {MarketOption? chosenMarket, String customLabel = '', double? customOddsVal, double? customProbVal, String note = ''}) {
    final now = DateTime.now();
    final dateLabel = '${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}.';
    final mLabel = customLabel.isNotEmpty ? customLabel : (chosenMarket?.label ?? match.market);
    final mCode = customLabel.isNotEmpty ? 'sgp' : (chosenMarket?.code ?? match.marketCode);
    final mCat = customLabel.isNotEmpty ? 'SGP Builder' : (chosenMarket?.category ?? match.marketCategory);
    final mOdds = customOddsVal ?? chosenMarket?.refOdds ?? match.marketOdds;
    final mProb = customProbVal ?? chosenMarket?.probability ?? match.modelProb;

    
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
    
    notifyListeners();
    saveState();
  }

  void addManualBet(BetRecord record) {
    
      _bets.insert(0, record);
      if (_autoBankroll) {
        _bankroll = (_bankroll + record.profit).clamp(1000, 10000000);
      }
    
    notifyListeners();
    saveState();
  }

  void adjustBankrollCapital(double delta) {
    
      _bankroll = (_bankroll + delta).clamp(1000, 10000000);
    
    notifyListeners();
    saveState();
  }

  void updateBetStatus(String betId, String newStatus) {
    
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
    
    notifyListeners();
    saveState();
  }

  void deleteBet(String betId) {
    
      final idx = _bets.indexWhere((b) => b.id == betId);
      if (idx != -1) {
        final old = _bets[idx];
        if (_autoBankroll) {
          _bankroll = (_bankroll - old.profit).clamp(1000, 10000000);
        }
        _bets.removeAt(idx);
      }
    
    notifyListeners();
    saveState();
  }

  void openSettingsDialog(BuildContext context) {
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
                    FutureBuilder<PackageInfo>(
                      future: PackageInfo.fromPlatform(),
                      builder: (context, snap) {
                        final v = snap.data;
                        final label = v == null
                            ? 'Verzió betöltése…'
                            : 'v${v.version} (${v.buildNumber})';
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0A0E17),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF1F2937)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('ALKALMAZÁS', style: TextStyle(fontSize: 10, color: Color(0xFF6B7280), letterSpacing: 0.8)),
                              const SizedBox(height: 4),
                              Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final update = await AppUpdateService.checkForUpdate();
                                    if (!context.mounted) return;
                                    if (update == null) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Nincs újabb verzió.')),
                                      );
                                      return;
                                    }
                                    Navigator.pop(context);
                                    await showAppUpdateDialog(context, update);
                                  },
                                  icon: const Icon(Icons.system_update, size: 16),
                                  label: const Text('Frissítés keresése', style: TextStyle(fontSize: 12)),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
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
                                    await saveState();
                                    final res = await syncSportApi(silent: true);
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
                          {
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
                    
                      _apiKey = '';
                      _isLiveMode = false;
                      _matches = _buildDemoMatches();
                    
    notifyListeners();
                    saveState();
                    Navigator.pop(context);
                  },
                  child: const Text('Demó mód'),
                ),
                FilledButton(
                  onPressed: () {
                    
                      _apiKey = keyController.text.trim();
                      _baseUrl = baseController.text.trim();
                    
    notifyListeners();
                    saveState();
                    Navigator.pop(context);
                    if (_apiKey.isNotEmpty) {
                      syncSportApi();
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

  void openLogBetDialog(BuildContext context, MatchPick match, {MarketOption? chosenMarket, String customLabel = '', double? customOddsVal, double? customProbVal}) {
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
                    addBet(
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

  void openMatchDetail(BuildContext context, MatchPick match) {
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
                                        StatCompareRow(
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
                                              openLogBetDialog(
                                                context,
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
                                              toggleSlipOption(match, chosenMarket: opt);
                                              setModalState(() {});
                                            },
                                          ),
                                          GestureDetector(
                                            onTap: () {
                                              Navigator.pop(context);
                                              openLogBetDialog(context, match, chosenMarket: opt);
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
                                          StatCompareRow(
                                            label: 'Összes lövés',
                                            homeVal: '${bundle!.homeStats!['shots'] ?? 0}',
                                            awayVal: '${bundle.awayStats!['shots'] ?? 0}',
                                          ),
                                          StatCompareRow(
                                            label: 'Kaput eltaláló lövés',
                                            homeVal: '${bundle.homeStats!['shots_on_target'] ?? 0}',
                                            awayVal: '${bundle.awayStats!['shots_on_target'] ?? 0}',
                                          ),
                                          StatCompareRow(
                                            label: 'Passzpontosság',
                                            homeVal: '${bundle.homeStats!['pass_accuracy'] ?? 0}%',
                                            awayVal: '${bundle.awayStats!['pass_accuracy'] ?? 0}%',
                                          ),
                                          StatCompareRow(
                                            label: 'Szabálytalanságok',
                                            homeVal: '${bundle.homeStats!['fouls'] ?? 0}',
                                            awayVal: '${bundle.awayStats!['fouls'] ?? 0}',
                                          ),
                                          StatCompareRow(
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
                                          ...bundle.homeStarters.map((p) => PlayerLineupTile(player: p)),
                                          const SizedBox(height: 16),
                                          Text('${match.awayTeam} – Kezdő XI',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold, color: Color(0xFF3B82F6))),
                                          const SizedBox(height: 6),
                                          ...bundle.awayStarters.map((p) => PlayerLineupTile(player: p)),
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
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }
}
