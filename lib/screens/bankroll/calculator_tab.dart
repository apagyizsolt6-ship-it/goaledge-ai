import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/models.dart';
import '../../services/poisson_engine.dart';
import '../../services/monte_carlo_service.dart';
import '../../widgets/charts.dart';
import '../matches/match_detail_widgets.dart';

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
  int _mcSimSeed = 42;
  double _mcAvgOdds = 1.92;
  double _mcEdgePct = 5.0;
  int _mcRuns = 50000;
  int _mcBets = 100;
  int _mcMode = 0; // 0 tőke, 1 piac, 2 szelvény
  String _mcMarketCode = 'home';

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

    final mcWinProb = (((_mcEdgePct / 100.0) + 1.0) / _mcAvgOdds).clamp(0.12, 0.92);
    final mcStakeFrac = widget.stakeProfile == 'flat_2'
        ? 0.02
        : (((mcWinProb * _mcAvgOdds - 1.0) / (_mcAvgOdds - 1.0)) * mult).clamp(0.005, 0.05);

    final mcBankroll = MonteCarloService.simulateBankrollPaths(
      startBankroll: widget.bankroll,
      winProb: mcWinProb,
      odds: _mcAvgOdds,
      stakeFraction: mcStakeFrac,
      runs: _mcRuns,
      betsPerRun: _mcBets,
      seed: _mcSimSeed,
    );
    final mcCurves = mcBankroll.samplePaths;

    final mcPoisson = PoissonEngine.calculate(_simHomeXg, _simAwayXg);
    String mcMarketLabel = _mcMarketCode;
    double mcMarketOdds = _mcAvgOdds;
    for (final m in mcPoisson.allMarkets) {
      if (m.code == _mcMarketCode) {
        mcMarketLabel = m.label;
        mcMarketOdds = m.refOdds;
        break;
      }
    }
    final mcMarket = MonteCarloService.simulateMarket(
      poisson: mcPoisson,
      marketCode: _mcMarketCode,
      marketLabel: mcMarketLabel,
      odds: mcMarketOdds,
      runs: _mcRuns,
      seed: _mcSimSeed + 7,
    );

    double homeOdds = 1.9;
    double overOdds = 1.9;
    for (final m in mcPoisson.allMarkets) {
      if (m.code == 'home') homeOdds = m.refOdds;
      if (m.code == 'over25') overOdds = m.refOdds;
    }
    final mcSlip = MonteCarloService.simulateSlip(
      legs: [
        McSlipLeg(
          matrix: mcPoisson.matrix,
          baseHome: mcPoisson.baseHomeScore,
          baseAway: mcPoisson.baseAwayScore,
          marketCode: 'home',
          odds: homeOdds,
        ),
        McSlipLeg(
          matrix: mcPoisson.matrix,
          baseHome: mcPoisson.baseHomeScore,
          baseAway: mcPoisson.baseAwayScore,
          marketCode: 'over25',
          odds: overOdds,
        ),
      ],
      runs: _mcRuns,
      seed: _mcSimSeed + 99,
    );


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
                  StatCompareRow(
                    label: '1 / X / 2',
                    homeVal: '${(simPoisson.homeWin * 100).round()}% / ${(simPoisson.draw * 100).round()}%',
                    awayVal: '${(simPoisson.awayWin * 100).round()}%',
                  ),
                  StatCompareRow(
                    label: '1X / X2 / DNB 1',
                    homeVal:
                        '${(simPoisson.doubleChance1X * 100).round()}% / ${(simPoisson.doubleChanceX2 * 100).round()}%',
                    awayVal: '${(simPoisson.dnbHome * 100).round()}%',
                  ),
                  StatCompareRow(
                    label: '2.5 gól felett / BTTS',
                    homeVal: '${(simPoisson.over25 * 100).round()}%',
                    awayVal: '${(simPoisson.btts * 100).round()}%',
                  ),
                  StatCompareRow(
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
                  StatCompareRow(
                    label: '1. kimenet tétje (@ $_arbOdds1)',
                    homeVal: '${stake1.round()} Ft',
                    awayVal: 'Vissza: ${guaranteedReturn.round()} Ft',
                  ),
                  if (_isThreeWayArb)
                    StatCompareRow(
                      label: 'Döntetlen (X) tétje (@ $_arbOddsX)',
                      homeVal: '${stakeX.round()} Ft',
                      awayVal: 'Vissza: ${guaranteedReturn.round()} Ft',
                    ),
                  StatCompareRow(
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
                    children: [
                      const Expanded(
                        child: Text(
                          'Monte Carlo Labor',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.casino, color: Color(0xFF10B981)),
                        tooltip: 'Új seed',
                        onPressed: () => setState(() => _mcSimSeed++),
                      ),
                    ],
                  ),
                  const Text(
                    'Akár 50 000 futás · bankroll / piac / szelvény',
                    style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Tőke', style: TextStyle(fontSize: 11))),
                      ButtonSegment(value: 1, label: Text('Piac', style: TextStyle(fontSize: 11))),
                      ButtonSegment(value: 2, label: Text('Szelvény', style: TextStyle(fontSize: 11))),
                    ],
                    selected: {_mcMode},
                    onSelectionChanged: (s) => setState(() => _mcMode = s.first),
                  ),
                  const SizedBox(height: 12),
                  Text('Futások: $_mcRuns', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  Slider(
                    value: _mcRuns.toDouble(),
                    min: 5000,
                    max: 50000,
                    divisions: 9,
                    activeColor: const Color(0xFF10B981),
                    onChanged: (v) => setState(() => _mcRuns = (v / 5000).round() * 5000),
                  ),
                  if (_mcMode == 0) ...[
                    Text(
                      'Szorzó: ${_mcAvgOdds.toStringAsFixed(2)} · modell EV: +${_mcEdgePct.toStringAsFixed(1)}%',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                    ),
                    Slider(
                      value: _mcAvgOdds,
                      min: 1.3,
                      max: 4.0,
                      divisions: 54,
                      activeColor: const Color(0xFF3B82F6),
                      onChanged: (v) => setState(() => _mcAvgOdds = double.parse(v.toStringAsFixed(2))),
                    ),
                    Slider(
                      value: _mcEdgePct,
                      min: 0.0,
                      max: 12.0,
                      divisions: 24,
                      activeColor: const Color(0xFF10B981),
                      onChanged: (v) => setState(() => _mcEdgePct = v),
                    ),
                    Text('Tipp / pálya: $_mcBets', style: const TextStyle(fontSize: 12)),
                    Slider(
                      value: _mcBets.toDouble(),
                      min: 20,
                      max: 200,
                      divisions: 18,
                      activeColor: const Color(0xFF10B981),
                      onChanged: (v) => setState(() => _mcBets = v.round()),
                    ),
                    SizedBox(
                      height: 150,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: MonteCarloPainter(mcCurves, widget.bankroll),
                      ),
                    ),
                    const SizedBox(height: 10),
                    StatCompareRow(
                      label: 'Medián tőke',
                      homeVal: '${widget.bankroll.round()} →',
                      awayVal: '${mcBankroll.medianEnd.round()} Ft',
                    ),
                    StatCompareRow(
                      label: '5–95% sáv',
                      homeVal: '${mcBankroll.p5End.round()} Ft',
                      awayVal: '${mcBankroll.p95End.round()} Ft',
                    ),
                    StatCompareRow(
                      label: 'Átlag tőke',
                      homeVal: '${mcBankroll.runs} pálya',
                      awayVal: '${mcBankroll.meanEnd.round()} Ft',
                    ),
                    StatCompareRow(
                      label: 'P(profit)',
                      homeVal: 'vég > start',
                      awayVal: '${(mcBankroll.profitRate * 100).toStringAsFixed(1)}%',
                    ),
                    StatCompareRow(
                      label: 'Ruin kockázat',
                      homeVal: '< 25% tőke',
                      awayVal: '${(mcBankroll.ruinRate * 100).toStringAsFixed(1)}%',
                    ),
                    StatCompareRow(
                      label: 'Tét arány',
                      homeVal: widget.stakeProfile,
                      awayVal: '${(mcStakeFrac * 100).toStringAsFixed(2)}%',
                    ),
                  ] else if (_mcMode == 1) ...[
                    Text(
                      'xG: ${_simHomeXg.toStringAsFixed(2)} – ${_simAwayXg.toStringAsFixed(2)} (állítsd a Dixon–Coles fülön is)',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final code in ['home', 'draw', 'away', 'over25', 'under25', 'btts', '1x', 'x2'])
                          ChoiceChip(
                            label: Text(code, style: const TextStyle(fontSize: 11)),
                            selected: _mcMarketCode == code,
                            selectedColor: const Color(0xFF10B981),
                            onSelected: (_) => setState(() => _mcMarketCode = code),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    StatCompareRow(
                      label: 'MC találati arány',
                      homeVal: '${mcMarket.runs} futás',
                      awayVal: '${(mcMarket.hitRate * 100).toStringAsFixed(2)}%',
                    ),
                    StatCompareRow(
                      label: 'Modell p',
                      homeVal: mcMarket.marketLabel,
                      awayVal: '${(mcMarket.modelProb * 100).toStringAsFixed(1)}%',
                    ),
                    StatCompareRow(
                      label: 'Fair odds (MC)',
                      homeVal: '1 / hitRate',
                      awayVal: mcMarket.fairOdds.toStringAsFixed(2),
                    ),
                    StatCompareRow(
                      label: 'Ref odds',
                      homeVal: 'piac / modell',
                      awayVal: mcMarket.odds.toStringAsFixed(2),
                    ),
                    StatCompareRow(
                      label: 'Edge',
                      homeVal: 'MC vs odds',
                      awayVal: '${mcMarket.edgePercent >= 0 ? '+' : ''}${mcMarket.edgePercent.toStringAsFixed(2)}%',
                    ),
                    StatCompareRow(
                      label: 'EV / 1 Ft tét',
                      homeVal: 'várható nettó',
                      awayVal: mcMarket.evPerUnitStake.toStringAsFixed(3),
                    ),
                  ] else ...[
                    const Text(
                      '2 lábas minta: Hazai + Over 2.5 (azonos meccs, korrelált)',
                      style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                    ),
                    const SizedBox(height: 12),
                    StatCompareRow(
                      label: 'Kombinált odds',
                      homeVal: '${mcSlip.legCount} láb',
                      awayVal: mcSlip.combinedOdds.toStringAsFixed(2),
                    ),
                    StatCompareRow(
                      label: 'MC hit rate',
                      homeVal: '${mcSlip.runs} futás',
                      awayVal: '${(mcSlip.hitRate * 100).toStringAsFixed(2)}%',
                    ),
                    StatCompareRow(
                      label: 'Fair odds',
                      homeVal: '1 / p',
                      awayVal: mcSlip.fairOdds.toStringAsFixed(2),
                    ),
                    StatCompareRow(
                      label: 'Edge',
                      homeVal: 'MC vs kombi',
                      awayVal: '${mcSlip.edgePercent >= 0 ? '+' : ''}${mcSlip.edgePercent.toStringAsFixed(2)}%',
                    ),
                    StatCompareRow(
                      label: 'EV / 1 Ft',
                      homeVal: 'szelvény',
                      awayVal: mcSlip.evPerUnitStake.toStringAsFixed(3),
                    ),
                  ],
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
                  StatCompareRow(
                    label: 'Decimális (EU)',
                    homeVal: 'Európai formátum',
                    awayVal: _convDecimal.toStringAsFixed(2),
                  ),
                  StatCompareRow(
                    label: 'Tört (UK / Brit)',
                    homeVal: 'Nettó nyeremény arány',
                    awayVal: _toFractionalOdds(_convDecimal),
                  ),
                  StatCompareRow(
                    label: 'Amerikai (US / Moneyline)',
                    homeVal: _convDecimal >= 2.0 ? 'Underdog (+)' : 'Favorit (-)',
                    awayVal: _toAmericanOdds(_convDecimal),
                  ),
                  StatCompareRow(
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

