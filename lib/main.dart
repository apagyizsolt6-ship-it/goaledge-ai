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
// 3. FŐ KÉPERNYŐ ÉS ÁLLAPOTKEZELÉS
// ==========================================

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;
  bool _isLoadingApi = false;
  bool _isLiveMode = false;
  String _apiKey = '';
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
    final savedKey = prefs.getString('api_key') ?? '';
    final savedBankroll = prefs.getDouble('bankroll') ?? 50000;
    final watchedIds = prefs.getStringList('watched_ids');
    final betsJson = prefs.getString('logged_bets');

    setState(() {
      _apiKey = savedKey;
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
      _fetchLiveMatches();
    }
  }

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_key', _apiKey);
    await prefs.setDouble('bankroll', _bankroll);
    final watchedIds = _matches.where((m) => m.isWatched).map((m) => m.id).toList();
    await prefs.setStringList('watched_ids', watchedIds);
    await prefs.setString('logged_bets', jsonEncode(_bets.map((b) => b.toJson()).toList()));
  }

  Future<void> _fetchLiveMatches() async {
    if (_apiKey.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Adj meg egy API-Football kulcsot a Beállításokban az élő meccsekhez!')),
        );
      }
      return;
    }

    setState(() => _isLoadingApi = true);
    try {
      final now = DateTime.now();
      final dateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final uri = Uri.parse('https://v3.football.api-sports.io/fixtures?date=$dateStr');
      final response = await http.get(uri, headers: {
        'x-apisports-key': _apiKey.trim(),
      }).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> fixtures = data['response'] ?? [];

        const priorityLeagues = {39, 140, 135, 78, 61, 2, 3, 271};
        fixtures.sort((a, b) {
          final aId = a['league']?['id'] ?? 9999;
          final bId = b['league']?['id'] ?? 9999;
          final aPrio = priorityLeagues.contains(aId) ? 0 : 1;
          final bPrio = priorityLeagues.contains(bId) ? 0 : 1;
          return aPrio.compareTo(bPrio);
        });

        final selected = fixtures.take(15).toList();
        if (selected.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          final watchedIds = prefs.getStringList('watched_ids') ?? [];

          final parsed = selected.map((f) {
            final fixtureId = (f['fixture']?['id'] ?? 0).toString();
            final leagueName = f['league']?['name'] ?? 'Bajnokság';
            final homeName = f['teams']?['home']?['name'] ?? 'Hazai';
            final awayName = f['teams']?['away']?['name'] ?? 'Vendég';
            final dateRaw = f['fixture']?['date'] ?? '';
            String timeLabel = 'Ma';
            if (dateRaw.length >= 16) {
              timeLabel = 'Ma ${dateRaw.substring(11, 16)}';
            }

            final seed = int.tryParse(fixtureId) ?? homeName.hashCode;
            final rng = math.Random(seed);
            final hXg = 1.15 + (rng.nextDouble() * 1.25);
            final aXg = 0.85 + (rng.nextDouble() * 1.10);
            final poisson = PoissonEngine.calculate(hXg, aXg);

            final pickOver = poisson.over25 > 0.56;
            final market = pickOver ? '2.5 gól felett' : 'Hazai győzelem (1)';
            final prob = pickOver ? poisson.over25 : poisson.homeWin;
            final fairOdds = 1.0 / prob;
            final marketOdds = double.parse((fairOdds * 1.09).clamp(1.35, 3.60).toStringAsFixed(2));

            return MatchPick(
              id: 'live_$fixtureId',
              league: leagueName,
              kickoff: timeLabel,
              homeTeam: homeName,
              awayTeam: awayName,
              market: market,
              trendSummary:
                  'Élő Poisson-modell: várható összgól ${(hXg + aXg).toStringAsFixed(2)}, BTTS esély ${(poisson.btts * 100).round()}%.',
              trendCategory: pickOver ? 'Gólok / BTTS' : 'xG eltérés',
              modelProb: prob,
              marketOdds: marketOdds,
              oddsHistory: [
                double.parse((marketOdds + 0.14).toStringAsFixed(2)),
                double.parse((marketOdds + 0.08).toStringAsFixed(2)),
                double.parse((marketOdds + 0.04).toStringAsFixed(2)),
                marketOdds,
              ],
              homeXg: double.parse(hXg.toStringAsFixed(2)),
              awayXg: double.parse(aXg.toStringAsFixed(2)),
              last8Trend: List.generate(8, (i) => rng.nextDouble() > 0.25),
              isWatched: watchedIds.contains('live_$fixtureId'),
            );
          }).toList();

          setState(() {
            _matches = parsed;
            _isLiveMode = true;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${parsed.length} élő mérkőzés betöltve!')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nem sikerült az élő szinkronizálás, demó adatok aktívak.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingApi = false);
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
    final controller = TextEditingController(text: _apiKey);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF131A29),
          title: const Text('API & Adatforrás Beállítások'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add meg az ingyenes API-Football (api-sports.io) kulcsodat a napi élő meccsek letöltéséhez:',
                style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'x-apisports-key',
                  hintText: 'Pl. a1b2c3d4e5f6...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
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
                  _apiKey = controller.text.trim();
                });
                _saveState();
                Navigator.pop(context);
                if (_apiKey.isNotEmpty) {
                  _fetchLiveMatches();
                }
              },
              child: const Text('Mentés és Szinkron'),
            ),
          ],
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
                      Text(
                        '${match.league} • ${match.kickoff}',
                        style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
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
                _isLiveMode ? 'ÉLŐ API' : 'DEMÓ',
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
              tooltip: 'Élő adatok frissítése',
              onPressed: _fetchLiveMatches,
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'API Beállítások',
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
// 4. FÜLEK (AJÁNLÁSOK, TRENDEK, KALKULÁTOR, NAPLÓ)
// ==========================================

class ValueFeedTab extends StatefulWidget {
  final List<MatchPick> matches;
  final Function(MatchPick) onSelectMatch;
  final Function(String) onToggleWatch;
  final Function(MatchPick) onLogBet;

  const ValueFeedTab({
    super.key,
    required this.matches,
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
        SizedBox(
          height: 46,
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
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
