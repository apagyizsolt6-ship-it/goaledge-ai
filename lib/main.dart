import 'package:flutter/material.dart';

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
  final List<double> probs1X2;
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
    required this.probs1X2,
    required this.last8Trend,
    this.isWatched = false,
  });

  double get impliedProb => 1.0 / marketOdds;
  double get edgePercent => (modelProb - impliedProb) * 100.0;
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;

  final List<MatchPick> _matches = [
    MatchPick(
      id: 'm1',
      league: 'Premier League',
      kickoff: 'Ma 18:30',
      homeTeam: 'Arsenal',
      awayTeam: 'Aston Villa',
      market: 'Mindkét csapat szerez gólt (BTTS)',
      trendSummary: 'Az utolsó 8 egymás elleni és bajnoki meccsből 7-szer mindkét fél betalált.',
      trendCategory: 'Gólok / BTTS',
      modelProb: 0.67,
      marketOdds: 1.72,
      oddsHistory: [1.88, 1.84, 1.80, 1.76, 1.72],
      homeXg: 2.15,
      awayXg: 1.48,
      probs1X2: [0.56, 0.24, 0.20],
      last8Trend: [true, true, true, false, true, true, true, true],
      isWatched: true,
    ),
    MatchPick(
      id: 'm2',
      league: 'NB I',
      kickoff: 'Ma 19:45',
      homeTeam: 'Ferencváros',
      awayTeam: 'Paksi FC',
      market: '2.5 gól felett',
      trendSummary: 'A Paks idegenbeli meccsein 3.4-es a gólátlag, az FTC hazai xG-je 2.35.',
      trendCategory: 'Gólok / BTTS',
      modelProb: 0.71,
      marketOdds: 1.65,
      oddsHistory: [1.78, 1.75, 1.70, 1.68, 1.65],
      homeXg: 2.35,
      awayXg: 1.32,
      probs1X2: [0.62, 0.22, 0.16],
      last8Trend: [true, true, true, true, false, true, true, true],
      isWatched: true,
    ),
    MatchPick(
      id: 'm3',
      league: 'La Liga',
      kickoff: 'Ma 21:00',
      homeTeam: 'Real Sociedad',
      awayTeam: 'Villarreal',
      market: 'Hazai győzelem (1)',
      trendSummary: 'xG-alulteljesítés: a Sociedad 2.1-es várható gólátlag mellett csak 1 gólt lőtt az elmúlt 2 meccsen.',
      trendCategory: 'xG eltérés',
      modelProb: 0.55,
      marketOdds: 2.15,
      oddsHistory: [2.35, 2.28, 2.22, 2.18, 2.15],
      homeXg: 1.95,
      awayXg: 1.12,
      probs1X2: [0.55, 0.26, 0.19],
      last8Trend: [true, false, true, true, true, false, true, true],
    ),
    MatchPick(
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
      probs1X2: [0.43, 0.28, 0.29],
      last8Trend: [true, true, true, true, true, false, true, true],
    ),
  ];

  void _toggleWatch(String matchId) {
    setState(() {
      final idx = _matches.indexWhere((m) => m.id == matchId);
      if (idx != -1) {
        _matches[idx].isWatched = !_matches[idx].isWatched;
      }
    });
  }

  void _openMatchDetail(MatchPick match) {
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
            return Padding(
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
                    '1X2 Modell Valószínűség',
                    style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      children: [
                        Expanded(
                          flex: (match.probs1X2[0] * 100).round(),
                          child: Container(
                            height: 28,
                            color: const Color(0xFF10B981),
                            alignment: Alignment.center,
                            child: Text(
                              '1: ${(match.probs1X2[0] * 100).round()}%',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: (match.probs1X2[1] * 100).round(),
                          child: Container(
                            height: 28,
                            color: const Color(0xFF374151),
                            alignment: Alignment.center,
                            child: Text(
                              'X: ${(match.probs1X2[1] * 100).round()}%',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: (match.probs1X2[2] * 100).round(),
                          child: Container(
                            height: 28,
                            color: const Color(0xFF3B82F6),
                            alignment: Alignment.center,
                            child: Text(
                              '2: ${(match.probs1X2[2] * 100).round()}%',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
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
                    height: 70,
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
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Várható gólok (xG): ${match.homeXg.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      Text('${match.awayXg.toStringAsFixed(2)}',
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
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        _toggleWatch(match.id);
                        setModalState(() {});
                      },
                      icon: Icon(match.isWatched ? Icons.notifications_active : Icons.notifications_none),
                      label: Text(match.isWatched ? 'Figyelőlistán (Kikapcsolás)' : 'Riasztás kérése erre a meccsre'),
                      style: FilledButton.styleFrom(
                        backgroundColor: match.isWatched ? const Color(0xFF1F2937) : const Color(0xFF10B981),
                        foregroundColor: match.isWatched ? Colors.white : Colors.black,
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

  @override
  Widget build(BuildContext context) {
    final pages = [
      ValueFeedTab(matches: _matches, onSelectMatch: _openMatchDetail, onToggleWatch: _toggleWatch),
      TrendRadarTab(matches: _matches, onSelectMatch: _openMatchDetail),
      CalculatorTab(matches: _matches),
      WatchlistTab(matches: _matches, onToggleWatch: _toggleWatch, onSelectMatch: _openMatchDetail),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E17),
        title: const Row(
          children: [
            Icon(Icons.insights, color: Color(0xFF10B981)),
            SizedBox(width: 8),
            Text('GoalEdge AI', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
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
          NavigationDestination(icon: Icon(Icons.notifications_outlined), label: 'Riasztások'),
        ],
      ),
    );
  }
}

class ValueFeedTab extends StatefulWidget {
  final List<MatchPick> matches;
  final Function(MatchPick) onSelectMatch;
  final Function(String) onToggleWatch;

  const ValueFeedTab({
    super.key,
    required this.matches,
    required this.onSelectMatch,
    required this.onToggleWatch,
  });

  @override
  State<ValueFeedTab> createState() => _ValueFeedTabState();
}

class _ValueFeedTabState extends State<ValueFeedTab> {
  String _selectedLeague = 'Összes';
  bool _sortByValue = true;

  @override
  Widget build(BuildContext context) {
    final leagues = ['Összes', 'Premier League', 'NB I', 'La Liga', 'Bajnokok Ligája'];
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
                            Text('${match.league} • ${match.kickoff}',
                                style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
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
                                const SizedBox(width: 6),
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

  const CalculatorTab({super.key, required this.matches});

  @override
  State<CalculatorTab> createState() => _CalculatorTabState();
}

class _CalculatorTabState extends State<CalculatorTab> {
  double _prob = 0.65;
  double _odds = 1.80;
  double _bankroll = 50000;

  @override
  Widget build(BuildContext context) {
    final ev = (_prob * _odds) - 1.0;
    final fairOdds = 1.0 / _prob;
    final fullKelly = ((_prob * _odds) - 1.0) / (_odds - 1.0);
    final halfKelly = fullKelly > 0 ? fullKelly * 0.5 : 0.0;
    final recommendedStake = (_bankroll * halfKelly).round();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Gyors betöltés a napi kínálatból:', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: widget.matches.map((m) {
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
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Saját / Modell valószínűség: ${(_prob * 100).round()}%',
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
                Text('Bankroll (Tőke): ${_bankroll.round()} Ft',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Slider(
                  value: _bankroll,
                  min: 10000,
                  max: 500000,
                  divisions: 49,
                  activeColor: const Color(0xFFF59E0B),
                  onChanged: (v) => setState(() => _bankroll = v),
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
              children: [
                _CalcRow(
                  label: 'Várható érték (EV)',
                  value: '${ev >= 0 ? '+' : ''}${(ev * 100).toStringAsFixed(1)}%',
                  valueColor: ev >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                ),
                const Divider(height: 24, color: Color(0xFF1F2937)),
                _CalcRow(
                  label: 'Valós (Fair) szorzó',
                  value: fairOdds.toStringAsFixed(2),
                  valueColor: Colors.white,
                ),
                const Divider(height: 24, color: Color(0xFF1F2937)),
                _CalcRow(
                  label: 'Ajánlott tét (Half-Kelly)',
                  value: ev > 0 ? '$recommendedStake Ft (${(halfKelly * 100).toStringAsFixed(1)}%)' : '0 Ft (Nincs előny)',
                  valueColor: ev > 0 ? const Color(0xFF10B981) : const Color(0xFF9CA3AF),
                ),
              ],
            ),
          ),
        ),
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
        Text(label, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)),
        Text(value, style: TextStyle(color: valueColor, fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }
}

class WatchlistTab extends StatelessWidget {
  final List<MatchPick> matches;
  final Function(String) onToggleWatch;
  final Function(MatchPick) onSelectMatch;

  const WatchlistTab({
    super.key,
    required this.matches,
    required this.onToggleWatch,
    required this.onSelectMatch,
  });

  @override
  Widget build(BuildContext context) {
    final watched = matches.where((m) => m.isWatched).toList();

    if (watched.isEmpty) {
      return const Center(
        child: Text(
          'Még nincs bekövetett meccsed.\nKoppints a csengő ikonra az Ajánlások fülön!',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF9CA3AF)),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: watched.length,
      itemBuilder: (context, index) {
        final match = watched[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            onTap: () => onSelectMatch(match),
            leading: const Icon(Icons.notifications_active, color: Color(0xFFF59E0B)),
            title: Text('${match.homeTeam} – ${match.awayTeam}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${match.market} • Odds: ${match.marketOdds}'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.grey),
              onPressed: () => onToggleWatch(match.id),
            ),
          ),
        );
      },
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
