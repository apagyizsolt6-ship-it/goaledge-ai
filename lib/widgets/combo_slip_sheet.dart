import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';
import '../screens/matches/match_detail_widgets.dart';
import 'monte_carlo_sheet.dart';

/// Extracted Combo Slip bottom sheet.
/// Previously lived inside AppController.
class ComboSlipSheet {
  static Future<void> show({
    required BuildContext context,
    required SlipItemList slipItems,
    required double bankroll,
    required void Function(SlipItemList updated) onSlipChanged,
    required void Function(BetRecord bet) onLogComboBet,
  }) {
    if (slipItems.isEmpty) return Future.value();

    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF131A29),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return _ComboSlipContent(
          initialItems: List<SlipItem>.from(slipItems),
          bankroll: bankroll,
          onSlipChanged: onSlipChanged,
          onLogComboBet: onLogComboBet,
        );
      },
    );
  }

  static String formatShareText(
    SlipItemList items,
    double totalOdds,
    double stake,
    bool isSystem,
  ) {
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
}

class _ComboSlipContent extends StatefulWidget {
  final SlipItemList initialItems;
  final double bankroll;
  final void Function(SlipItemList updated) onSlipChanged;
  final void Function(BetRecord bet) onLogComboBet;

  const _ComboSlipContent({
    required this.initialItems,
    required this.bankroll,
    required this.onSlipChanged,
    required this.onLogComboBet,
  });

  @override
  State<_ComboSlipContent> createState() => _ComboSlipContentState();
}

class _ComboSlipContentState extends State<_ComboSlipContent> {
  late SlipItemList items;
  late double comboStake;
  bool useSystem = false;

  @override
  void initState() {
    super.initState();
    items = List<SlipItem>.from(widget.initialItems);
    comboStake = (widget.bankroll * 0.02).clamp(500, 30000).roundToDouble();
  }

  void _notifyParent() {
    widget.onSlipChanged(List<SlipItem>.from(items));
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
      return const SizedBox.shrink();
    }

    final canSystem = items.length == 3 || items.length == 4;
    if (!canSystem) useSystem = false;

    double totalOdds = 1.0;
    double combinedProb = 1.0;
    for (final it in items) {
      totalOdds *= it.odds;
      combinedProb *= it.modelProb;
    }
    final comboEv = (combinedProb * totalOdds) - 1.0;

    double sysMinWin = 0.0;
    double sysMaxWin = 0.0;
    final int sysCombos = items.length;
    if (canSystem && useSystem) {
      final lineStake = comboStake / sysCombos;
      final DoubleList subOdds = [];
      for (int skip = 0; skip < items.length; skip++) {
        double prod = 1.0;
        for (int j = 0; j < items.length; j++) {
          if (j != skip) prod *= items[j].odds;
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
              Text(
                'Kombi Szelvény (${items.length} kötés)',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: () {
                  setState(() => items.clear());
                  _notifyParent();
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
                  const ButtonSegment(
                    value: false,
                    label: Text('Normál Kombi', style: TextStyle(fontSize: 11)),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text(
                      items.length == 3 ? 'System 2/3' : 'System 3/4',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
                selected: {useSystem},
                onSelectionChanged: (s) => setState(() => useSystem = s.first),
              ),
            ),
          ],
          const SizedBox(height: 8),
          ...items.map((it) {
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
                        Text(
                          it.matchTitle,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          '${it.marketLabel} (${(it.modelProb * 100).round()}%)',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '@ ${it.odds.toStringAsFixed(2)}',
                    style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                    onPressed: () {
                      setState(() => items.removeWhere((e) => e.key == it.key));
                      _notifyParent();
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
            onChanged: (v) => setState(() => comboStake = v),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    final text = ComboSlipSheet.formatShareText(
                      items,
                      totalOdds,
                      comboStake,
                      useSystem,
                    );
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Szelvény bemásolva a vágólapra')),
                    );
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
                        ? (items.length == 3 ? 'System 2/3' : 'System 3/4')
                        : 'Kombi (${items.length})';
                    final title =
                        '$prefix: ${items.map((e) => e.matchTitle.split(' – ').first).join(', ')}';
                    final effectiveOdds = useSystem ? (sysMaxWin / comboStake) : totalOdds;

                    widget.onLogComboBet(
                      BetRecord(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        league: useSystem ? 'System' : 'Kombi',
                        matchTitle: title,
                        market: items.map((e) => e.marketLabel).join(' + '),
                        marketCode: useSystem ? 'system' : 'combo',
                        marketCategory: useSystem ? 'System' : 'Kombi',
                        odds: double.parse(effectiveOdds.toStringAsFixed(2)),
                        modelProb: double.parse(combinedProb.toStringAsFixed(3)),
                        stake: comboStake,
                        status: 'pending',
                        date: dateLabel,
                      ),
                    );
                    setState(() => items.clear());
                    _notifyParent();
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
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                showSlipMonteCarloSheet(
                  context,
                  legs: List.from(items),
                );
              },
              icon: const Icon(Icons.casino, size: 16, color: Color(0xFF10B981)),
              label: const Text('Szelvény Monte Carlo (50k)', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }
}
