import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/monte_carlo_service.dart';

Future<void> showMatchMonteCarloSheet(
  BuildContext context, {
  required MatchPick match,
  required double bankroll,
  required String stakeProfile,
  String? marketCode,
  double? odds,
  String? marketLabel,
  int runs = 50000,
}) async {
  final code = marketCode ?? match.marketCode;
  final label = marketLabel ?? match.market;
  final o = odds ?? match.marketOdds;
  final poisson = match.poisson;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF131A29),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return _McLoadingThenResult(
        title: 'Monte Carlo · ${match.homeTeam} – ${match.awayTeam}',
        subtitle: label,
        compute: () async {
          // yield so the sheet can paint the spinner
          await Future<void>.delayed(const Duration(milliseconds: 30));
          final market = MonteCarloService.simulateMarket(
            poisson: poisson,
            marketCode: code,
            marketLabel: label,
            odds: o,
            runs: runs,
          );
          final bank = MonteCarloService.simulateMatchPickBankroll(
            match: match,
            bankroll: bankroll,
            stakeProfile: stakeProfile,
            runs: runs > 20000 ? 20000 : runs,
            betsPerRun: 100,
          );
          return (market, bank);
        },
      );
    },
  );
}

Future<void> showSlipMonteCarloSheet(
  BuildContext context, {
  required SlipItemList legs,
  int runs = 50000,
}) async {
  if (legs.isEmpty) return;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF131A29),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return _McSlipLoading(
        legCount: legs.length,
        compute: () async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          final mcLegs = <McSlipLeg>[];
          for (final leg in legs) {
            // Rebuild matrix from stored xG if available via modelProb-only fallback:
            // SlipItem may not store xG — use probability Bernoulli-style independent legs.
            // Prefer match-linked matrix when possible is done by caller; here we sample by modelProb.
            mcLegs.add(
              McSlipLeg(
                matrix: _probToDegenerateMatrix(leg.modelProb),
                baseHome: 0,
                baseAway: 0,
                marketCode: 'home', // matrix encodes win as home>away via synthetic
                odds: leg.odds,
              ),
            );
          }
          // Better: independent Bernoulli hit using simulateSlip with synthetic matrix
          // where P(home win) = modelProb approximately via skewed grid is heavy —
          // use dedicated independent path:
          return _simulateIndependentSlip(legs, runs);
        },
      );
    },
  );
}

McSlipResult _simulateIndependentSlip(SlipItemList legs, int runs) {
  // Independent legs by modelProb (different matches → OK)
  final rng = DateTime.now().millisecondsSinceEpoch;
  var hits = 0;
  var combined = 1.0;
  for (final l in legs) {
    combined *= l.odds;
  }
  final r = _SeedRandom(rng);
  for (var i = 0; i < runs; i++) {
    var ok = true;
    for (final l in legs) {
      if (r.nextDouble() >= l.modelProb) {
        ok = false;
        break;
      }
    }
    if (ok) hits++;
  }
  final hitRate = hits / runs;
  final fair = hitRate > 1e-9 ? 1.0 / hitRate : 99.0;
  final edge = (hitRate - (1.0 / combined)) * 100.0;
  final ev = hitRate * (combined - 1.0) - (1.0 - hitRate);
  return McSlipResult(
    runs: runs,
    combinedOdds: combined,
    hitRate: hitRate,
    fairOdds: fair,
    edgePercent: edge,
    evPerUnitStake: ev,
    legCount: legs.length,
  );
}

/// Minimal 2x2 matrix where P(home goals extra making "home" hit) ≈ p — actually
/// marketHits('home') needs fh>fa. Put mass on (1,0) with p and (0,1) with 1-p.
CurveList _probToDegenerateMatrix(double p) {
  final grid = List.generate(8, (_) => List.filled(8, 0.0));
  final pp = p.clamp(0.01, 0.99);
  grid[1][0] = pp; // 1-0 home win
  grid[0][1] = 1.0 - pp; // 0-1 away
  return grid;
}

class _SeedRandom {
  int _s;
  _SeedRandom(this._s);
  double nextDouble() {
    _s = (_s * 1103515245 + 12345) & 0x7fffffff;
    return _s / 0x7fffffff;
  }
}

class _McLoadingThenResult extends StatefulWidget {
  final String title;
  final String subtitle;
  final Future<(McMarketResult, McBankrollResult)> Function() compute;

  const _McLoadingThenResult({
    required this.title,
    required this.subtitle,
    required this.compute,
  });

  @override
  State<_McLoadingThenResult> createState() => _McLoadingThenResultState();
}

class _McLoadingThenResultState extends State<_McLoadingThenResult> {
  (McMarketResult, McBankrollResult)? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    widget.compute().then((v) {
      if (mounted) setState(() => _data = v);
    }).catchError((e) {
      if (mounted) setState(() => _error = e);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + pad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF374151),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 4),
          Text(widget.subtitle, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
          const SizedBox(height: 16),
          if (_error != null)
            Text('Hiba: $_error', style: const TextStyle(color: Color(0xFFEF4444)))
          else if (_data == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator(color: Color(0xFF10B981))),
            )
          else ...[
            _kv('MC találati arány', '${(_data!.$1.hitRate * 100).toStringAsFixed(2)}% (${_data!.$1.runs} futás)'),
            _kv('Fair odds', _data!.$1.fairOdds.toStringAsFixed(2)),
            _kv('Piaci odds', _data!.$1.odds.toStringAsFixed(2)),
            _kv('Edge', '${_data!.$1.edgePercent >= 0 ? '+' : ''}${_data!.$1.edgePercent.toStringAsFixed(2)}%'),
            _kv('EV / 1 Ft tét', _data!.$1.evPerUnitStake.toStringAsFixed(3)),
            const Divider(height: 24, color: Color(0xFF1F2937)),
            const Text('Ha 100x ismételnéd (bankroll pálya)', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
            const SizedBox(height: 8),
            _kv('Medián tőke', '${_data!.$2.medianEnd.round()} Ft'),
            _kv('5–95% sáv', '${_data!.$2.p5End.round()} – ${_data!.$2.p95End.round()} Ft'),
            _kv('P(profit)', '${(_data!.$2.profitRate * 100).toStringAsFixed(1)}%'),
            _kv('Ruin (<25%)', '${(_data!.$2.ruinRate * 100).toStringAsFixed(1)}%'),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.black),
                child: const Text('Rendben'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(k, style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)))),
          Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _McSlipLoading extends StatefulWidget {
  final int legCount;
  final Future<McSlipResult> Function() compute;
  const _McSlipLoading({required this.legCount, required this.compute});

  @override
  State<_McSlipLoading> createState() => _McSlipLoadingState();
}

class _McSlipLoadingState extends State<_McSlipLoading> {
  McSlipResult? _r;
  Object? _error;

  @override
  void initState() {
    super.initState();
    widget.compute().then((v) {
      if (mounted) setState(() => _r = v);
    }).catchError((e) {
      if (mounted) setState(() => _error = e);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + pad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Szelvény Monte Carlo (${widget.legCount} láb)',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 12),
          if (_error != null)
            Text('Hiba: $_error', style: const TextStyle(color: Color(0xFFEF4444)))
          else if (_r == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator(color: Color(0xFF10B981))),
            )
          else ...[
            _row('Kombinált odds', _r!.combinedOdds.toStringAsFixed(2)),
            _row('MC hit rate', '${(_r!.hitRate * 100).toStringAsFixed(2)}%'),
            _row('Fair odds', _r!.fairOdds.toStringAsFixed(2)),
            _row('Edge', '${_r!.edgePercent >= 0 ? '+' : ''}${_r!.edgePercent.toStringAsFixed(2)}%'),
            _row('EV / 1 Ft', _r!.evPerUnitStake.toStringAsFixed(3)),
            _row('Futások', '${_r!.runs}'),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.black),
                child: const Text('Rendben'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Expanded(child: Text(k, style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)))),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      );
}
