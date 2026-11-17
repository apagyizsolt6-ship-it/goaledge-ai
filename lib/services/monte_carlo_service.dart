import 'dart:math' as math;
import '../models/models.dart';
import 'poisson_engine.dart';

class McBankrollResult {
  final int runs;
  final int betsPerRun;
  final double startBankroll;
  final double medianEnd;
  final double p5End;
  final double p95End;
  final double meanEnd;
  final double ruinRate;
  final double profitRate;
  final double expectedValuePerBet;
  final List<List<double>> samplePaths; // few paths for chart
  final List<double> endHistogram; // sorted ends

  const McBankrollResult({
    required this.runs,
    required this.betsPerRun,
    required this.startBankroll,
    required this.medianEnd,
    required this.p5End,
    required this.p95End,
    required this.meanEnd,
    required this.ruinRate,
    required this.profitRate,
    required this.expectedValuePerBet,
    required this.samplePaths,
    required this.endHistogram,
  });
}

class McMarketResult {
  final int runs;
  final String marketCode;
  final String marketLabel;
  final double modelProb;
  final double odds;
  final double hitRate;
  final double edgePercent;
  final double evPerUnitStake;
  final double fairOdds;

  const McMarketResult({
    required this.runs,
    required this.marketCode,
    required this.marketLabel,
    required this.modelProb,
    required this.odds,
    required this.hitRate,
    required this.edgePercent,
    required this.evPerUnitStake,
    required this.fairOdds,
  });
}

class McSlipLeg {
  final CurveList matrix;
  final int baseHome;
  final int baseAway;
  final String marketCode;
  final double odds;

  const McSlipLeg({
    required this.matrix,
    required this.baseHome,
    required this.baseAway,
    required this.marketCode,
    required this.odds,
  });
}

class McSlipResult {
  final int runs;
  final double combinedOdds;
  final double hitRate;
  final double fairOdds;
  final double edgePercent;
  final double evPerUnitStake;
  final int legCount;

  const McSlipResult({
    required this.runs,
    required this.combinedOdds,
    required this.hitRate,
    required this.fairOdds,
    required this.edgePercent,
    required this.evPerUnitStake,
    required this.legCount,
  });
}

class MonteCarloService {
  /// Sample final score from Dixon–Coles grid (already normalized).
  static (int, int) sampleScore(
    CurveList matrix,
    int baseHome,
    int baseAway,
    math.Random rng,
  ) {
    final rows = matrix.length;
    final cols = matrix.isNotEmpty ? matrix[0].length : 0;
    var r = rng.nextDouble();
    for (var dh = 0; dh < rows; dh++) {
      for (var da = 0; da < cols; da++) {
        r -= matrix[dh][da];
        if (r <= 0) {
          return (baseHome + dh, baseAway + da);
        }
      }
    }
    return (baseHome, baseAway);
  }

  static bool marketHits(String code, int fh, int fa) {
    switch (code) {
      case 'home':
        return fh > fa;
      case 'draw':
        return fh == fa;
      case 'away':
        return fa > fh;
      case '1x':
        return fh >= fa;
      case 'x2':
        return fa >= fh;
      case 'dnb_home':
        return fh > fa; // push ignored → treat as non-win for conservative sim
      case 'ah_home_m05':
        return fh > fa;
      case 'ah_home_m10':
        return (fh - fa) >= 2;
      case 'ah_away_p05':
        return fa >= fh;
      case 'over15':
        return (fh + fa) > 1;
      case 'over25':
        return (fh + fa) > 2;
      case 'under25':
        return (fh + fa) <= 2;
      case 'btts':
        return fh > 0 && fa > 0;
      case 'home_over15':
        return fh > 1;
      case 'ht_over05':
      case 'ht_over15':
        // HT markets: approximate with full-time total scaled (no HT grid)
        return code == 'ht_over05' ? (fh + fa) > 0 : (fh + fa) > 1;
      default:
        return false;
    }
  }

  /// Market hit-rate via sampling the Poisson matrix (default 50_000).
  static McMarketResult simulateMarket({
    required PoissonResult poisson,
    required String marketCode,
    required String marketLabel,
    required double odds,
    int runs = 50000,
    int? seed,
  }) {
    final rng = math.Random(seed);
    var hits = 0;
    for (var i = 0; i < runs; i++) {
      final (fh, fa) = sampleScore(
        poisson.matrix,
        poisson.baseHomeScore,
        poisson.baseAwayScore,
        rng,
      );
      if (marketHits(marketCode, fh, fa)) hits++;
    }
    final hitRate = hits / runs;
    final fair = hitRate > 1e-9 ? 1.0 / hitRate : 99.0;
    final edge = (hitRate - (1.0 / odds)) * 100.0;
    final ev = hitRate * (odds - 1.0) - (1.0 - hitRate);
    // analytical model prob if available
    double modelProb = hitRate;
    for (final m in poisson.allMarkets) {
      if (m.code == marketCode) {
        modelProb = m.probability;
        break;
      }
    }
    return McMarketResult(
      runs: runs,
      marketCode: marketCode,
      marketLabel: marketLabel,
      modelProb: modelProb,
      odds: odds,
      hitRate: hitRate,
      edgePercent: edge,
      evPerUnitStake: ev,
      fairOdds: fair,
    );
  }

  /// Bankroll path: repeated bets with given win prob & odds (e.g. long-run strategy).
  static McBankrollResult simulateBankrollPaths({
    required double startBankroll,
    required double winProb,
    required double odds,
    required double stakeFraction,
    int runs = 50000,
    int betsPerRun = 100,
    double ruinThresholdFrac = 0.25,
    int pathSamples = 24,
    int? seed,
  }) {
    final rng = math.Random(seed);
    final ends = <double>[];
    final paths = <List<double>>[];
    var ruin = 0;
    var profit = 0;
    var totalEv = 0.0;

    for (var s = 0; s < runs; s++) {
      var b = startBankroll;
      final path = <double>[];
      final recordPath = s < pathSamples;
      if (recordPath) path.add(b);
      var ruined = false;
      for (var bet = 0; bet < betsPerRun; bet++) {
        final st = (b * stakeFraction).clamp(0.0, b);
        if (st <= 0) {
          ruined = true;
          break;
        }
        if (rng.nextDouble() < winProb) {
          b += st * (odds - 1.0);
        } else {
          b -= st;
        }
        if (b < startBankroll * ruinThresholdFrac) ruined = true;
        if (recordPath) path.add(b);
      }
      if (ruined) ruin++;
      if (b > startBankroll) profit++;
      ends.add(b);
      if (recordPath) paths.add(path);
      totalEv += (b - startBankroll) / betsPerRun;
    }

    ends.sort();
    double pct(double p) {
      final i = ((ends.length - 1) * p).round().clamp(0, ends.length - 1);
      return ends[i];
    }

    final mean = ends.reduce((a, b) => a + b) / ends.length;
    return McBankrollResult(
      runs: runs,
      betsPerRun: betsPerRun,
      startBankroll: startBankroll,
      medianEnd: pct(0.5),
      p5End: pct(0.05),
      p95End: pct(0.95),
      meanEnd: mean,
      ruinRate: ruin / runs,
      profitRate: profit / runs,
      expectedValuePerBet: totalEv / runs,
      samplePaths: paths,
      endHistogram: ends,
    );
  }

  /// Multi-leg slip: each leg has own matrix; all must hit (independent matches).
  static McSlipResult simulateSlip({
    required List<McSlipLeg> legs,
    int runs = 50000,
    int? seed,
  }) {
    if (legs.isEmpty) {
      return const McSlipResult(
        runs: 0,
        combinedOdds: 1,
        hitRate: 0,
        fairOdds: 99,
        edgePercent: 0,
        evPerUnitStake: -1,
        legCount: 0,
      );
    }
    final rng = math.Random(seed);
    var hits = 0;
    var combinedOdds = 1.0;
    for (final leg in legs) {
      combinedOdds *= leg.odds;
    }
    for (var i = 0; i < runs; i++) {
      var allHit = true;
      for (final leg in legs) {
        final (fh, fa) = sampleScore(leg.matrix, leg.baseHome, leg.baseAway, rng);
        if (!marketHits(leg.marketCode, fh, fa)) {
          allHit = false;
          break;
        }
      }
      if (allHit) hits++;
    }
    final hitRate = hits / runs;
    final fair = hitRate > 1e-9 ? 1.0 / hitRate : 99.0;
    final edge = (hitRate - (1.0 / combinedOdds)) * 100.0;
    final ev = hitRate * (combinedOdds - 1.0) - (1.0 - hitRate);
    return McSlipResult(
      runs: runs,
      combinedOdds: combinedOdds,
      hitRate: hitRate,
      fairOdds: fair,
      edgePercent: edge,
      evPerUnitStake: ev,
      legCount: legs.length,
    );
  }

  /// Convenience: bankroll sim from a MatchPick tip.
  static McBankrollResult simulateMatchPickBankroll({
    required MatchPick match,
    required double bankroll,
    required String stakeProfile,
    int runs = 50000,
    int betsPerRun = 100,
    int? seed,
  }) {
    final mult = stakeProfile == 'flat_2'
        ? 0.0
        : (stakeProfile == 'kelly_half' ? 0.5 : (stakeProfile == 'kelly_full' ? 1.0 : 0.25));
    final p = match.modelProb.clamp(0.05, 0.95);
    final odds = match.marketOdds;
    final kelly = ((p * odds) - 1.0) / (odds - 1.0);
    final frac = stakeProfile == 'flat_2'
        ? 0.02
        : (kelly * (mult == 0 ? 0.25 : mult)).clamp(0.005, 0.06);
    return simulateBankrollPaths(
      startBankroll: bankroll,
      winProb: p,
      odds: odds,
      stakeFraction: frac,
      runs: runs,
      betsPerRun: betsPerRun,
      seed: seed,
    );
  }
}
