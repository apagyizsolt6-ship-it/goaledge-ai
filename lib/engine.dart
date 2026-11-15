import 'dart:math' as math;
import 'models.dart';

class PoissonEngine {
  static double _pmf(double lambda, int k) {
    if (lambda <= 0) return k == 0 ? 1.0 : 0.0;
    double factorial = 1.0;
    for (int i = 2; i <= k; i++) {
      factorial *= i;
    }
    return (math.pow(lambda, k) * math.exp(-lambda)) / factorial;
  }

  static double _dixonColesTau(int h, int a, double lambdaH, double lambdaA, double rho) {
    if (h == 0 && a == 0) return (1.0 - (lambdaH * lambdaA * rho)).clamp(0.15, 2.2);
    if (h == 0 && a == 1) return (1.0 + (lambdaH * rho)).clamp(0.15, 2.2);
    if (h == 1 && a == 0) return (1.0 + (lambdaA * rho)).clamp(0.15, 2.2);
    if (h == 1 && a == 1) return (1.0 - rho).clamp(0.15, 2.2);
    return 1.0;
  }

  static PoissonResult calculate(
    double remHomeXg,
    double remAwayXg, {
    double rho = -0.085,
    int baseHomeScore = 0,
    int baseAwayScore = 0,
    double fullPreMatchTotalXg = 2.65,
  }) {
    final CurveList grid = List.generate(8, (_) => List.filled(8, 0.0));
    double totalMass = 0.0;

    for (int dh = 0; dh <= 7; dh++) {
      final ph = _pmf(remHomeXg, dh);
      for (int da = 0; da <= 7; da++) {
        final pa = _pmf(remAwayXg, da);
        final tau = _dixonColesTau(dh, da, remHomeXg, remAwayXg, rho);
        final p = ph * pa * tau;
        grid[dh][da] = p;
        totalMass += p;
      }
    }

    final norm = totalMass > 0 ? totalMass : 1.0;
    final CurveList normGrid = List.generate(8, (dh) => List.generate(8, (da) => grid[dh][da] / norm));

    double pHome = 0.0;
    double pDraw = 0.0;
    double pAway = 0.0;
    double pOver15 = 0.0;
    double pOver25 = 0.0;
    double pBtts = 0.0;
    double pHomeOver15 = 0.0;
    double pAhM10Win = 0.0;
    double pAhM10Push = 0.0;
    final ScoreProbList scores = [];

    for (int dh = 0; dh <= 7; dh++) {
      for (int da = 0; da <= 7; da++) {
        final prob = normGrid[dh][da];
        final fh = baseHomeScore + dh;
        final fa = baseAwayScore + da;

        if (fh > fa) {
          pHome += prob;
        } else if (fh == fa) {
          pDraw += prob;
        } else {
          pAway += prob;
        }

        if ((fh - fa) >= 2) {
          pAhM10Win += prob;
        } else if ((fh - fa) == 1) {
          pAhM10Push += prob;
        }

        if (fh + fa > 1) pOver15 += prob;
        if (fh + fa > 2) pOver25 += prob;
        if (fh > 0 && fa > 0) pBtts += prob;
        if (fh > 1) pHomeOver15 += prob;
        if (fh <= 6 && fa <= 6) {
          scores.add(ScoreProbability('$fh-$fa', prob));
        }
      }
    }

    scores.sort((a, b) => b.probability.compareTo(a.probability));

    final p1 = pHome.clamp(0.02, 0.97);
    final pX = pDraw.clamp(0.02, 0.92);
    final p2 = pAway.clamp(0.02, 0.97);
    final p1X = (p1 + pX).clamp(0.05, 0.98);
    final pX2 = (pX + p2).clamp(0.05, 0.98);
    final pDnbHome = (p1 / (p1 + p2)).clamp(0.05, 0.97);
    final pO15 = pOver15.clamp(0.04, 0.98);
    final pO25 = pOver25.clamp(0.03, 0.97);
    final pU25 = (1.0 - pO25).clamp(0.03, 0.97);
    final pGg = pBtts.clamp(0.03, 0.97);
    final pHo15 = pHomeOver15.clamp(0.03, 0.97);

    final pAhM05 = p1;
    final nonPushMass = (1.0 - pAhM10Push).clamp(0.15, 1.0);
    final pAhM10 = (pAhM10Win / nonPushMass).clamp(0.04, 0.95);
    final pAhP05 = pX2;

    final htLambda = (fullPreMatchTotalXg * 0.44).clamp(0.35, 2.4);
    final pHt0 = _pmf(htLambda, 0);
    final pHt1 = _pmf(htLambda, 1);
    final pHtO05 = (1.0 - pHt0).clamp(0.15, 0.95);
    final pHtO15 = (1.0 - pHt0 - pHt1).clamp(0.05, 0.85);

    MarketOption buildOpt(String code, String label, String cat, double prob, double edgeBoost) {
      final fair = 1.0 / prob;
      final ref = double.parse((fair * edgeBoost).clamp(1.16, 5.80).toStringAsFixed(2));
      final edge = (prob - (1.0 / ref)) * 100.0;
      return MarketOption(
        code: code,
        label: label,
        category: cat,
        probability: prob,
        fairOdds: double.parse(fair.toStringAsFixed(2)),
        refOdds: ref,
        edgePercent: edge,
      );
    }

    final MarketOptionList options = [
      buildOpt('home', 'Hazai győzelem (1)', '1X2 & Dupla', p1, 1.07),
      buildOpt('draw', 'Döntetlen (X)', '1X2 & Dupla', pX, 1.06),
      buildOpt('away', 'Vendég győzelem (2)', '1X2 & Dupla', p2, 1.07),
      buildOpt('1x', 'Dupla esély (1X)', '1X2 & Dupla', p1X, 1.05),
      buildOpt('x2', 'Dupla esély (X2)', '1X2 & Dupla', pX2, 1.05),
      buildOpt('dnb_home', 'Hazai DNB (Tét visszajár)', '1X2 & Dupla', pDnbHome, 1.06),
      buildOpt('ah_home_m05', 'Ázsiai Hendikep Hazai -0.5', 'Ázsiai Hendikep', pAhM05, 1.08),
      buildOpt('ah_home_m10', 'Ázsiai Hendikep Hazai -1.0', 'Ázsiai Hendikep', pAhM10, 1.09),
      buildOpt('ah_away_p05', 'Ázsiai Hendikep Vendég +0.5', 'Ázsiai Hendikep', pAhP05, 1.06),
      buildOpt('over15', '1.5 gól felett', 'Gólok / BTTS', pO15, 1.05),
      buildOpt('over25', '2.5 gól felett', 'Gólok / BTTS', pO25, 1.09),
      buildOpt('under25', '2.5 gól alatt', 'Gólok / BTTS', pU25, 1.08),
      buildOpt('btts', 'Mindkét csapat szerez gólt (BTTS)', 'Gólok / BTTS', pGg, 1.09),
      buildOpt('home_over15', 'Hazai csapat 1.5 gól felett', 'Gólok / BTTS', pHo15, 1.08),
      buildOpt('ht_over05', '1. Félidő 0.5 gól felett', '1. Félidő', pHtO05, 1.06),
      buildOpt('ht_over15', '1. Félidő 1.5 gól felett', '1. Félidő', pHtO15, 1.09),
    ];

    return PoissonResult(
      homeWin: p1,
      draw: pX,
      awayWin: p2,
      doubleChance1X: p1X,
      doubleChanceX2: pX2,
      dnbHome: pDnbHome,
      over15: pO15,
      over25: pO25,
      under25: pU25,
      btts: pGg,
      homeOver15: pHo15,
      ahHomeMinus05: pAhM05,
      ahHomeMinus10: pAhM10,
      ahAwayPlus05: pAhP05,
      htOver05: pHtO05,
      htOver15: pHtO15,
      topScores: scores.take(3).toList(),
      allMarkets: options,
      matrix: normGrid,
      baseHomeScore: baseHomeScore,
      baseAwayScore: baseAwayScore,
    );
  }

  static bool _matchesOutcome(String code, int fh, int fa) {
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
      default:
        return false;
    }
  }

  static SgpResult calculateSgp(
    PoissonResult res,
    String leg1Code,
    String leg1Label,
    String leg2Code,
    String leg2Label,
  ) {
    double p1 = 0.0;
    double p2 = 0.0;
    double pJoint = 0.0;

    for (int dh = 0; dh < res.matrix.length; dh++) {
      for (int da = 0; da < res.matrix[dh].length; da++) {
        final prob = res.matrix[dh][da];
        final fh = res.baseHomeScore + dh;
        final fa = res.baseAwayScore + da;
        final ok1 = _matchesOutcome(leg1Code, fh, fa);
        final ok2 = _matchesOutcome(leg2Code, fh, fa);
        if (ok1) p1 += prob;
        if (ok2) p2 += prob;
        if (ok1 && ok2) pJoint += prob;
      }
    }

    final indep = (p1 * p2).clamp(0.01, 0.98);
    final corr = pJoint.clamp(0.01, 0.98);
    final factor = corr / indep;
    final fair = double.parse((1.0 / corr).clamp(1.05, 50.0).toStringAsFixed(2));

    return SgpResult(
      leg1Code: leg1Code,
      leg1Label: leg1Label,
      leg2Code: leg2Code,
      leg2Label: leg2Label,
      independentProb: indep,
      correlatedProb: corr,
      correlationFactor: factor,
      fairOdds: fair,
    );
  }
}
