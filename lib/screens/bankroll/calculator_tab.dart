import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/models.dart';
import '../../services/poisson_engine.dart';
import '../../widgets/charts.dart';

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
                      Text('T艖ke (Bankroll): ${widget.bankroll.round()} Ft',
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
                  const Text('T茅tkezel茅si strat茅gia:',
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
                  Text('Bukm茅keri szorz贸: ${_odds.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Slider(
                    value: _odds,
                    min: 1.15,
                    max: 4.50,
                    divisions: 67,
                    activeColor: const Color(0xFF3B82F6),
                    onChanged: (v) => setState(() => _odds = double.parse(v.toStringAsFixed(2))),
                  ),
                  Text('Modell val贸sz铆n疟s茅g: ${_probPercent.round()}% (Fair: ${fairOdds.toStringAsFixed(2)})',
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
                      const Text('V谩rhat贸 脡rt茅k (EV)',
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
                      const Text('Aj谩nlott T茅t', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
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
                  Text('Hazai v谩rhat贸 g贸l (xG): ${_simHomeXg.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                  Slider(
                    value: _simHomeXg,
                    min: 0.30,
                    max: 3.80,
                    divisions: 70,
                    activeColor: const Color(0xFF10B981),
                    onChanged: (v) => setState(() => _simHomeXg = v),
                  ),
                  Text('Vend茅g v谩rhat贸 g贸l (xG): ${_simAwayXg.toStringAsFixed(2)}',
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
                  const Text('Dixon-Coles 16-piacos eredm茅nyek',
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
                    label: '2.5 g贸l felett / BTTS',
                    homeVal: '${(simPoisson.over25 * 100).round()}%',
                    awayVal: '${(simPoisson.btts * 100).round()}%',
                  ),
                  _StatCompareRow(
                    label: '1. F茅lid艖 0.5+ / 1.5+',
                    homeVal: '${(simPoisson.htOver05 * 100).round()}%',
                    awayVal: '${(simPoisson.htOver15 * 100).round()}%',
                  ),
                  const SizedBox(height: 12),
                  const Text('Top 3 legval贸sz铆n疟bb pontos eredm茅ny',
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
                      const Text('Surebet / Dutcher Kalkul谩tor',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('2-ir谩ny煤', style: TextStyle(fontSize: 11))),
                          ButtonSegment(value: true, label: Text('1X2 (3)', style: TextStyle(fontSize: 11))),
                        ],
                        selected: {_isThreeWayArb},
                        onSelectionChanged: (s) => setState(() => _isThreeWayArb = s.first),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text('脰sszes megosztand贸 t茅t: ${_arbTotalStake.round()} Ft',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Slider(
                    value: _arbTotalStake,
                    min: 2000,
                    max: 200000,
                    divisions: 99,
                    activeColor: const Color(0xFF10B981),
                    onChanged: (v) => setState(() => _arbTotalStake = v),
                  ),
                  Text('1. kimenet szorz贸: ${_arbOdds1.toStringAsFixed(2)}',
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
                    Text('D枚ntetlen (X) szorz贸: ${_arbOddsX.toStringAsFixed(2)}',
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
                  Text('2. kimenet szorz贸: ${_arbOdds2.toStringAsFixed(2)}',
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
                        isSurebet ? 'BIZTOS PROFIT (SUREBET)' : 'Nincs arbitr谩zs (Dutcher)',
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
                    label: '1. kimenet t茅tje (@ $_arbOdds1)',
                    homeVal: '${stake1.round()} Ft',
                    awayVal: 'Vissza: ${guaranteedReturn.round()} Ft',
                  ),
                  if (_isThreeWayArb)
                    _StatCompareRow(
                      label: 'D枚ntetlen (X) t茅tje (@ $_arbOddsX)',
                      homeVal: '${stakeX.round()} Ft',
                      awayVal: 'Vissza: ${guaranteedReturn.round()} Ft',
                    ),
                  _StatCompareRow(
                    label: '2. kimenet t茅tje (@ $_arbOdds2)',
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
                      const Text('Monte Carlo T艖ke Szimul谩tor (100 tipp)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      IconButton(
                        icon: const Icon(Icons.casino, color: Color(0xFF10B981)),
                        tooltip: '脷j szimul谩ci贸 futtat谩sa',
                        onPressed: () => setState(() => _mcSimSeed++),
                      ),
                    ],
                  ),
                  Text('脕tlagos szorz贸: ${_mcAvgOdds.toStringAsFixed(2)} 鈥� 脕tlag EV: +${_mcEdgePct.toStringAsFixed(1)}%',
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
                    label: 'Medi谩n t艖ke 100 tipp ut谩n',
                    homeVal: '${widget.bankroll.round()} Ft 鈫�',
                    awayVal: '${medianEnd.round()} Ft',
                  ),
                  _StatCompareRow(
                    label: '75%+ t艖keveszt茅s kock谩zata',
                    homeVal: '30 szimul谩lt p谩lya',
                    awayVal: '${((ruinCount / 30.0) * 100).round()}%',
                  ),
                ],
              ),
            ),
          ),
        ] else ...[
          // 5. M脫D: ODDS KONVERTER (DECIM脕LIS <-> T脰RT UK <-> AMERIKAI US)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Odds Konverter & Implik谩lt Val贸sz铆n疟s茅g',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 12),
                  Text('Decim谩lis (EU) szorz贸: ${_convDecimal.toStringAsFixed(2)}',
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
                    label: 'Decim谩lis (EU)',
                    homeVal: 'Eur贸pai form谩tum',
                    awayVal: _convDecimal.toStringAsFixed(2),
                  ),
                  _StatCompareRow(
                    label: 'T枚rt (UK / Brit)',
                    homeVal: 'Nett贸 nyerem茅ny ar谩ny',
                    awayVal: _toFractionalOdds(_convDecimal),
                  ),
                  _StatCompareRow(
                    label: 'Amerikai (US / Moneyline)',
                    homeVal: _convDecimal >= 2.0 ? 'Underdog (+)' : 'Favorit (-)',
                    awayVal: _toAmericanOdds(_convDecimal),
                  ),
                  _StatCompareRow(
                    label: 'Implik谩lt val贸sz铆n疟s茅g',
                    homeVal: 'Break-even tal谩lati %',
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
