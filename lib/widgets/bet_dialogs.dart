import 'package:flutter/material.dart';
import '../models/models.dart';

/// Small bet-related dialogs extracted from AppController.

class BetDialogs {
  /// Edit bookmaker odds for a match (custom odds).
  static Future<void> showEditOdds({
    required BuildContext context,
    required MatchPick match,
    required void Function(double? odds) onApply,
    required VoidCallback onReset,
  }) {
    final controller = TextEditingController(text: match.marketOdds.toStringAsFixed(2));
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF131A29),
          title: const Text('Saját bukmékeri szorzó', style: TextStyle(fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${match.homeTeam} – ${match.awayTeam}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              Text(
                'Piac: ${match.market} (Modell: ${(match.modelProb * 100).round()}%)',
                style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
              ),
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
                onReset();
                Navigator.pop(context);
              },
              child: const Text('Alaphelyzet'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = double.tryParse(controller.text.replaceAll(',', '.'));
                if (parsed != null && parsed >= 1.05 && parsed <= 50.0) {
                  onApply(parsed);
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

  /// Edit closing odds for CLV measurement.
  static Future<void> showEditClosingOdds({
    required BuildContext context,
    required BetRecord bet,
    required void Function(double? closingOdds) onSave,
  }) {
    final controller = TextEditingController(
      text: bet.closingOdds != null ? bet.closingOdds!.toStringAsFixed(2) : '',
    );
    return showDialog<void>(
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
              Text(
                'Megtett szorzó: ${bet.odds.toStringAsFixed(2)}',
                style: const TextStyle(color: Color(0xFF10B981), fontSize: 12),
              ),
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
                onSave(parsed);
                Navigator.pop(context);
              },
              child: const Text('Mentés'),
            ),
          ],
        );
      },
    );
  }

  /// Log a bet into the tracker.
  static Future<void> showLogBet({
    required BuildContext context,
    required MatchPick match,
    required double bankroll,
    required String stakeProfile,
    MarketOption? chosenMarket,
    String customLabel = '',
    double? customOddsVal,
    double? customProbVal,
    required void Function({
      required MatchPick match,
      required double stake,
      MarketOption? chosenMarket,
      String customLabel,
      double? customOddsVal,
      double? customProbVal,
      String note,
    }) onConfirm,
  }) {
    final rec = match.recommendedStake(bankroll, stakeProfile);
    double stake = (rec > 0 ? rec.toDouble() : bankroll * 0.02).clamp(500, 50000).roundToDouble();
    final label = customLabel.isNotEmpty ? customLabel : (chosenMarket?.label ?? match.market);
    final odds = customOddsVal ?? chosenMarket?.refOdds ?? match.marketOdds;
    final noteController = TextEditingController();

    return showDialog<void>(
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
                    Text(
                      '${match.homeTeam} – ${match.awayTeam}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
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
                    onConfirm(
                      match: match,
                      stake: stake,
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
}
