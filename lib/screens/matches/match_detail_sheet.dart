import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/models.dart';
import '../../services/poisson_engine.dart';
import '../../services/sport_api_service.dart';
import '../../widgets/monte_carlo_sheet.dart';
import '../../widgets/charts.dart';
import 'match_detail_widgets.dart';

/// Extracted Match Detail bottom sheet.
/// Previously lived inside AppController (~950 lines).
class MatchDetailSheet {
  static Future<void> show({
    required BuildContext context,
    required MatchPick match,
    required String baseUrl,
    required String apiKey,
    required double bankroll,
    required String stakeProfile,
    required void Function(MatchPick match, {MarketOption? chosenMarket}) onToggleSlip,
    required void Function(
      BuildContext context,
      MatchPick match, {
      MarketOption? chosenMarket,
      String customLabel,
      double? customOddsVal,
      double? customProbVal,
    }) onLogBet,
  }) {
    Future<FixtureFullBundle?>? bundleFuture;
    if (apiKey.isNotEmpty && match.fixtureId != null && match.fixtureId! > 0) {
      bundleFuture = SportApiService.fetchFullBundle(
        baseUrl: baseUrl,
        apiKey: apiKey,
        fixtureId: match.fixtureId!,
        leagueId: match.leagueId,
        homeId: match.homeId,
        awayId: match.awayId,
      );
    }

    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF131A29),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return _MatchDetailContent(
          match: match,
          baseUrl: baseUrl,
          apiKey: apiKey,
          bankroll: bankroll,
          stakeProfile: stakeProfile,
          bundleFuture: bundleFuture,
          onToggleSlip: onToggleSlip,
          onLogBet: onLogBet,
        );
      },
    );
  }
}

class _MatchDetailContent extends StatefulWidget {
  final MatchPick match;
  final String baseUrl;
  final String apiKey;
  final double bankroll;
  final String stakeProfile;
  final Future<FixtureFullBundle?>? bundleFuture;
  final void Function(MatchPick match, {MarketOption? chosenMarket}) onToggleSlip;
  final void Function(
    BuildContext context,
    MatchPick match, {
    MarketOption? chosenMarket,
    String customLabel,
    double? customOddsVal,
    double? customProbVal,
  }) onLogBet;

  const _MatchDetailContent({
    required this.match,
    required this.baseUrl,
    required this.apiKey,
    required this.bankroll,
    required this.stakeProfile,
    required this.bundleFuture,
    required this.onToggleSlip,
    required this.onLogBet,
  });

  @override
  State<_MatchDetailContent> createState() => _MatchDetailContentState();
}

class _MatchDetailContentState extends State<_MatchDetailContent> {
  late double homeModifier;
  late double awayModifier;
  late bool useInPlaySim;
  late double simMinute;
  late int simHomeGoals;
  late int simAwayGoals;

  // SGP state
  String sgpLeg1 = 'home';
  String sgpLeg2 = 'over25';
  double sgpBookieOdds = 3.10;

  @override
  void initState() {
    super.initState();
    final match = widget.match;
    homeModifier = 1.0;
    awayModifier = 1.0;
    useInPlaySim = match.isLive;
    simMinute = (match.isLive ? match.parsedMinute : 0).toDouble();
    simHomeGoals = match.homeScore ?? 0;
    simAwayGoals = match.awayScore ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final match = widget.match;

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

    return DefaultTabController(
      length: 5,
      child: SizedBox(
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
                              baseUrl: widget.baseUrl,
                              apiKey: widget.apiKey,
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
                              baseUrl: widget.baseUrl,
                              apiKey: widget.apiKey,
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
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  showMatchMonteCarloSheet(
                    context,
                    match: match,
                    bankroll: widget.bankroll,
                    stakeProfile: widget.stakeProfile,
                  );
                },
                icon: const Icon(Icons.casino_outlined, size: 18),
                label: const Text('Monte Carlo szimuláció'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF10B981),
                  side: const BorderSide(color: Color(0xFF10B981)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const TabBar(
              isScrollable: true,
              labelColor: Color(0xFF10B981),
              unselectedLabelColor: Color(0xFF9CA3AF),
              indicatorColor: Color(0xFF10B981),
              tabs: [
                Tab(text: 'Piacok'),
                Tab(text: 'SGP'),
                Tab(text: 'Modell'),
                Tab(text: 'Statok'),
                Tab(text: 'Keret'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  // ========== TAB 1: Piacok ==========
                  _buildMarketsTab(match, poisson, fairMainOdds),
                  // ========== TAB 2: SGP ==========
                  _buildSgpTab(sgp, sgpEv, leg1Labels, leg2Labels),
                  // ========== TAB 3: Modell ==========
                  _buildModelTab(match, poisson, adjHomeXg, adjAwayXg),
                  // ========== TAB 4: Statok ==========
                  _buildStatsTab(match),
                  // ========== TAB 5: Keret ==========
                  _buildLineupTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarketsTab(MatchPick match, PoissonResult poisson, double fairMainOdds) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fő piac: ${match.market}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            'Modell: ${(match.modelProb * 100).toStringAsFixed(1)}%  •  Fair: ${fairMainOdds.toStringAsFixed(2)}  •  Könyves: ${match.marketOdds.toStringAsFixed(2)}',
            style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
          ),
          const SizedBox(height: 16),
          ...poisson.allMarkets.map((opt) {
            final isMain = opt.code == match.marketCode;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                dense: true,
                title: Text(
                  opt.label,
                  style: TextStyle(
                    fontWeight: isMain ? FontWeight.bold : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  '${opt.category}  •  ${(opt.probability * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          opt.fairOdds.toStringAsFixed(2),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          '${opt.edgePercent >= 0 ? "+" : ""}${opt.edgePercent.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 11,
                            color: opt.edgePercent >= 3
                                ? const Color(0xFF10B981)
                                : opt.edgePercent >= 0
                                    ? const Color(0xFF3B82F6)
                                    : const Color(0xFFEF4444),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 20),
                      tooltip: 'Szelvénybe',
                      onPressed: () => widget.onToggleSlip(match, chosenMarket: opt),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_note, size: 20),
                      tooltip: 'Fogadás rögzítése',
                      onPressed: () => widget.onLogBet(context, match, chosenMarket: opt),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSgpTab(
    SgpResult sgp,
    double sgpEv,
    Map<String, String> leg1Labels,
    Map<String, String> leg2Labels,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Same Game Parlay építő', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 12),
          const Text('1. láb (1X2 / DC)', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: leg1Labels.entries.map((e) {
              final selected = sgpLeg1 == e.key;
              return ChoiceChip(
                label: Text(e.value, style: const TextStyle(fontSize: 12)),
                selected: selected,
                onSelected: (_) => setState(() => sgpLeg1 = e.key),
                selectedColor: const Color(0xFF10B981).withOpacity(0.3),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          const Text('2. láb (Gólok)', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: leg2Labels.entries.map((e) {
              final selected = sgpLeg2 == e.key;
              return ChoiceChip(
                label: Text(e.value, style: const TextStyle(fontSize: 12)),
                selected: selected,
                onSelected: (_) => setState(() => sgpLeg2 = e.key),
                selectedColor: const Color(0xFF10B981).withOpacity(0.3),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${sgp.leg1Label} + ${sgp.leg2Label}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 10),
                  _kv('Független valószínűség', '${(sgp.independentProb * 100).toStringAsFixed(1)}%'),
                  _kv('Korrelált valószínűség', '${(sgp.correlatedProb * 100).toStringAsFixed(1)}%'),
                  _kv('Korrelációs faktor', sgp.correlationFactor.toStringAsFixed(3)),
                  _kv('Fair odds', sgp.fairOdds.toStringAsFixed(2)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Könyves odds: ', style: TextStyle(fontSize: 13)),
                      SizedBox(
                        width: 80,
                        child: TextFormField(
                          initialValue: sgpBookieOdds.toStringAsFixed(2),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) {
                            final parsed = double.tryParse(v.replaceAll(',', '.'));
                            if (parsed != null && parsed > 1.01) {
                              setState(() => sgpBookieOdds = parsed);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    decoration: BoxDecoration(
                      color: sgpEv >= 3
                          ? const Color.fromRGBO(16, 185, 129, 0.15)
 inter : const Color.fromRGBO(239, 68, 68, 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'EV: ${sgpEv >= 0 ? "+" : ""}${sgpEv.toStringAsFixed(1)}%',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: sgpEv >= 3 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelTab(
    MatchPick match,
    PoissonResult poisson,
    double adjHomeXg,
    double adjAwayXg,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('xG módosítók (What-if)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hazai xG × ${homeModifier.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12)),
                    Slider(
                      value: homeModifier,
                      min: 0.5,
                      max: 1.6,
                      divisions: 22,
                      label: homeModifier.toStringAsFixed(2),
                      activeColor: const Color(0xFF10B981),
                      onChanged: (v) => setState(() => homeModifier = v),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Vendég xG × ${awayModifier.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12)),
                    Slider(
                      value: awayModifier,
                      min: 0.5,
                      max: 1.6,
                      divisions: 22,
                      label: awayModifier.toStringAsFixed(2),
                      activeColor: const Color(0xFF3B82F6),
                      onChanged: (v) => setState(() => awayModifier = v),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (match.isLive) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              dense: true,
              title: const Text('In-play szimuláció', style: TextStyle(fontSize: 13)),
              value: useInPlaySim,
              activeColor: const Color(0xFF10B981),
              onChanged: (v) => setState(() => useInPlaySim = v),
            ),
            if (useInPlaySim) ...[
              Text('Perc: ${simMinute.toStringAsFixed(0)}\'', style: const TextStyle(fontSize: 12)),
              Slider(
                value: simMinute,
                min: 0,
                max: 90,
                divisions: 90,
                label: '${simMinute.toStringAsFixed(0)}\'',
                activeColor: const Color(0xFFEF4444),
                onChanged: (v) => setState(() => simMinute = v),
              ),
            ],
          ],
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  _kv('Adj. hazai xG', adjHomeXg.toStringAsFixed(2)),
                  _kv('Adj. vendég xG', adjAwayXg.toStringAsFixed(2)),
                  const Divider(height: 16),
                  _kv('Hazai győzelem', '${(poisson.homeWin * 100).toStringAsFixed(1)}%'),
                  _kv('Döntetlen', '${(poisson.draw * 100).toStringAsFixed(1)}%'),
                  _kv('Vendég győzelem', '${(poisson.awayWin * 100).toStringAsFixed(1)}%'),
                  const Divider(height: 16),
                  _kv('Over 2.5', '${(poisson.over25 * 100).toStringAsFixed(1)}%'),
                  _kv('BTTS', '${(poisson.btts * 100).toStringAsFixed(1)}%'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Legvalószínűbb eredmények', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          ...poisson.topScores.take(8).map((s) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 50,
                    child: Text(s.score, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: s.probability.clamp(0.0, 1.0),
                      backgroundColor: const Color(0xFF1F2937),
                      color: const Color(0xFF10B981),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(s.probability * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStatsTab(MatchPick match) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Trend összefoglaló', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          Text(
            match.trendSummary.isNotEmpty ? match.trendSummary : 'Nincs elérhető trend adat.',
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          if (widget.bundleFuture != null)
            FutureBuilder<FixtureFullBundle?>(
              future: widget.bundleFuture,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                final bundle = snap.data;
                if (bundle == null) {
                  return const Text(
                    'Nem sikerült betölteni a részletes statisztikákat.',
                    style: TextStyle(color: Color(0xFF9CA3AF)),
                  );
                }

                TeamStandingInfo? homeStanding;
                TeamStandingInfo? awayStanding;
                for (final row in bundle.standings) {
                  if (row.teamId == match.homeId) homeStanding = row;
                  if (row.teamId == match.awayId) awayStanding = row;
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Csapat statisztikák', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 10),
                    StatCompareRow(
                      label: 'Helyezés',
                      homeVal: '${homeStanding?.position ?? "-"}',
                      awayVal: '${awayStanding?.position ?? "-"}',
                    ),
                    StatCompareRow(
                      label: 'Pont',
                      homeVal: '${homeStanding?.points ?? "-"}',
                      awayVal: '${awayStanding?.points ?? "-"}',
                    ),
                    StatCompareRow(
                      label: 'Gól átlag',
                      homeVal: (homeStanding?.avgGoalsFor ?? 0).toStringAsFixed(2),
                      awayVal: (awayStanding?.avgGoalsFor ?? 0).toStringAsFixed(2),
                    ),
                    StatCompareRow(
                      label: 'Kapott gól',
                      homeVal: (homeStanding?.avgGoalsAgainst ?? 0).toStringAsFixed(2),
                      awayVal: (awayStanding?.avgGoalsAgainst ?? 0).toStringAsFixed(2),
                    ),
                    if (bundle.stadium != null || bundle.city != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        [bundle.stadium, bundle.city].where((e) => e != null && e.isNotEmpty).join(' • '),
                        style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                      ),
                    ],
                  ],
                );
              },
            )
          else
            const Text(
              'API kulcs nélkül a részletes statok nem érhetők el.',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
            ),
        ],
      ),
    );
  }

  Widget _buildLineupTab() {
    if (widget.bundleFuture == null) {
      return const Center(
        child: Text('API kulcs nélkül a keretek nem érhetők el.',
            style: TextStyle(color: Color(0xFF9CA3AF))),
      );
    }
    return FutureBuilder<FixtureFullBundle?>(
      future: widget.bundleFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final bundle = snap.data;
        if (bundle == null || (bundle.homeStarters.isEmpty && bundle.awayStarters.isEmpty)) {
          return const Center(
            child: Text('Nincs elérhető keret adat.', style: TextStyle(color: Color(0xFF9CA3AF))),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.match.homeTeam, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    ...bundle.homeStarters.map((p) => PlayerLineupTile(player: p)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.match.awayTeam, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    ...bundle.awayStarters.map((p) => PlayerLineupTile(player: p)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}
