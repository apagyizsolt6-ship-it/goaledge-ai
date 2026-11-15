import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/models.dart';
import '../../services/poisson_engine.dart';
import '../../widgets/charts.dart';

class TrackerAndWatchlistTab extends StatefulWidget {
  final MatchList matches;
  final BetList bets;
  final double bankroll;
  final void Function(String) onToggleWatch;
  final void Function(MatchPick) onSelectMatch;
  final void Function(String, String) onUpdateBetStatus;
  final void Function(BetRecord) onEditClosingOdds;
  final void Function(BetRecord) onAddManualBet;
  final void Function(double) onAdjustCapital;
  final void Function(String) onDeleteBet;

  const TrackerAndWatchlistTab({
    super.key,
    required this.matches,
    required this.bets,
    required this.bankroll,
    required this.onToggleWatch,
    required this.onSelectMatch,
    required this.onUpdateBetStatus,
    required this.onEditClosingOdds,
    required this.onAddManualBet,
    required this.onAdjustCapital,
    required this.onDeleteBet,
  });

  @override
  State<TrackerAndWatchlistTab> createState() => _TrackerAndWatchlistTabState();
}

class _TrackerAndWatchlistTabState extends State<TrackerAndWatchlistTab> {
  int _breakdownMode = 0; // 0: Liga, 1: Piac kategória

  String _generateCsvReport() {
    final buf = StringBuffer();
    buf.writeln('Datum;Liga;Merkozes;Piac;Kategoria;Odds;ZaroOdds;CLV_Pct;Tet_Ft;Statusz;Profit_Ft;Jegyzet');
    for (final b in widget.bets) {
      final clvStr = b.clvPercent != null ? b.clvPercent!.toStringAsFixed(2) : '';
      final closeStr = b.closingOdds != null ? b.closingOdds!.toStringAsFixed(2) : '';
      final cleanNote = b.note.replaceAll(';', ',').replaceAll('\n', ' ');
      buf.writeln(
          '${b.date};${b.league};${b.matchTitle};${b.market};${b.marketCategory};${b.odds.toStringAsFixed(2)};$closeStr;$clvStr;${b.stake.round()};${b.status};${b.profit.round()};$cleanNote');
    }
    return buf.toString();
  }

  void _showManualBetDialog() {
    final titleCtrl = TextEditingController();
    final leagueCtrl = TextEditingController(text: 'Premier League');
    final marketCtrl = TextEditingController(text: '2.5 gól felett');
    final oddsCtrl = TextEditingController(text: '1.90');
    final stakeCtrl = TextEditingController(text: '2000');
    final noteCtrl = TextEditingController();
    String status = 'pending';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDlg) {
            return AlertDialog(
              backgroundColor: const Color(0xFF131A29),
              title: const Text('Saját tipp kézi rögzítése', style: TextStyle(fontSize: 17)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Mérkőzés (pl. Real Madrid – Barcelona)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: leagueCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Bajnokság / Sport',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: marketCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Piac (pl. 9.5 szöglet felett)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: oddsCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Odds',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: stakeCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Tét (Ft)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'pending', label: Text('Nyitott', style: TextStyle(fontSize: 10))),
                        ButtonSegment(value: 'won', label: Text('Nyert', style: TextStyle(fontSize: 10))),
                        ButtonSegment(value: 'lost', label: Text('Vesztett', style: TextStyle(fontSize: 10))),
                      ],
                      selected: {status},
                      onSelectionChanged: (s) => setDlg(() => status = s.first),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: noteCtrl,
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
                    final title = titleCtrl.text.trim();
                    final odds = double.tryParse(oddsCtrl.text.replaceAll(',', '.')) ?? 1.85;
                    final stake = double.tryParse(stakeCtrl.text) ?? 1000.0;
                    if (title.isEmpty) return;
                    final now = DateTime.now();
                    final dateLabel =
                        '${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}.';
                    widget.onAddManualBet(
                      BetRecord(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        league: leagueCtrl.text.trim().isEmpty ? 'Egyéb' : leagueCtrl.text.trim(),
                        matchTitle: title,
                        market: marketCtrl.text.trim().isEmpty ? 'Saját piac' : marketCtrl.text.trim(),
                        marketCode: 'manual',
                        marketCategory: 'Saját tipp',
                        odds: odds.clamp(1.01, 100.0),
                        stake: stake.clamp(100, 1000000),
                        status: status,
                        date: dateLabel,
                        note: noteCtrl.text.trim(),
                      ),
                    );
                    Navigator.pop(context);
                  },
                  child: const Text('Hozzáadás'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showCapitalDialog() {
    final amountCtrl = TextEditingController(text: '10000');
    bool isDeposit = true;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDlg) {
            return AlertDialog(
              backgroundColor: const Color(0xFF131A29),
              title: const Text('Bankroll Befizetés / Kifizetés', style: TextStyle(fontSize: 17)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Jelenlegi tőke: ${widget.bankroll.round()} Ft',
                      style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('+ Befizetés')),
                      ButtonSegment(value: false, label: Text('- Kifizetés')),
                    ],
                    selected: {isDeposit},
                    onSelectionChanged: (s) => setDlg(() => isDeposit = s.first),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Összeg (Ft)',
                      border: OutlineInputBorder(),
                      isDense: true,
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
                    final amt = double.tryParse(amountCtrl.text) ?? 0.0;
                    if (amt > 0) {
                      widget.onAdjustCapital(isDeposit ? amt : -amt);
                    }
                    Navigator.pop(context);
                  },
                  child: const Text('Végrehajtás'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final watched = widget.matches.where((m) => m.isWatched).toList();
    final settledBets = widget.bets.where((b) => b.status == 'won' || b.status == 'lost').toList();

    final totalProfit = widget.bets.fold<double>(0.0, (sum, b) => sum + b.profit);
    final totalStaked = settledBets.fold<double>(0.0, (sum, b) => sum + b.stake);
    final roiPercent = totalStaked > 0 ? (totalProfit / totalStaked) * 100.0 : 0.0;
    final wonCount = settledBets.where((b) => b.status == 'won').length;
    final winRate = settledBets.isNotEmpty ? (wonCount / settledBets.length) * 100.0 : 0.0;

    final clvList = widget.bets.map((b) => b.clvPercent).whereType<double>().toList();
    final avgClv = clvList.isNotEmpty
        ? (clvList.reduce((a, b) => a + b) / clvList.length)
        : null;

    double brierSum = 0.0;
    int brierCount = 0;
    for (final b in settledBets) {
      if (b.modelProb != null) {
        final outcome = b.status == 'won' ? 1.0 : 0.0;
        final diff = b.modelProb! - outcome;
        brierSum += diff * diff;
        brierCount++;
      }
    }
    final brierScore = brierCount > 0 ? (brierSum / brierCount) : null;

    final DoubleList curvePoints = [0.0];
    double running = 0.0;
    for (final b in settledBets.reversed) {
      running += b.profit;
      curvePoints.add(running);
    }

    // Napi profit összesítés dátum szerint
    final Map<String, double> dailyMap = {};
    for (final b in settledBets.reversed) {
      dailyMap[b.date] = (dailyMap[b.date] ?? 0.0) + b.profit;
    }
    final dailyLabels = dailyMap.keys.toList();
    final DoubleList dailyValues = dailyMap.values.toList();

    final Map<String, BetList> grouped = {};
    for (final b in settledBets) {
      final key = _breakdownMode == 0 ? b.league : b.marketCategory;
      grouped.putIfAbsent(key, () => []).add(b);
    }
    final RoiBreakdownList breakdownRows = [];
    grouped.forEach((key, list) {
      final prof = list.fold<double>(0.0, (s, e) => s + e.profit);
      final stk = list.fold<double>(0.0, (s, e) => s + e.stake);
      final wins = list.where((e) => e.status == 'won').length;
      breakdownRows.add(
        RoiBreakdownItem(
          name: key,
          count: list.length,
          profit: prof,
          roiPercent: stk > 0 ? (prof / stk) * 100.0 : 0.0,
          winRatePercent: list.isNotEmpty ? (wins / list.length) * 100.0 : 0.0,
        ),
      );
    });
    breakdownRows.sort((a, b) => b.profit.compareTo(a.profit));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Portfólió & ROI',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _showCapitalDialog,
                  icon: const Icon(Icons.account_balance_wallet_outlined, size: 15),
                  label: const Text('Tőke +/-', style: TextStyle(fontSize: 11)),
                ),
                const SizedBox(width: 6),
                FilledButton.icon(
                  onPressed: _showManualBetDialog,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Saját tipp', style: TextStyle(fontSize: 11)),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.black,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        const Text('Aktuális Tőke',
                            style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.bankroll.round()} Ft',
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF3B82F6)),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        const Text('Nettó Profit',
                            style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                        const SizedBox(height: 4),
                        Text(
                          '${totalProfit >= 0 ? '+' : ''}${totalProfit.round()} Ft',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: totalProfit >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                          ),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        const Text('ROI / Találat',
                            style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                        const SizedBox(height: 4),
                        Text(
                          '${roiPercent.toStringAsFixed(1)}% / ${winRate.round()}%',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
                const Divider(height: 20, color: Color(0xFF1F2937)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Text(
                      'Átlag CLV: ${avgClv != null ? "${avgClv >= 0 ? "+" : ""}${avgClv.toStringAsFixed(1)}%" : "Nincs adat"}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: (avgClv ?? 0) >= 0 ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                      ),
                    ),
                    Text(
                      'Brier Kalibráció: ${brierScore != null ? brierScore.toStringAsFixed(3) : "Nincs adat"}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                    ),
                  ],
                ),
                if (curvePoints.length >= 2) ...[
                  const SizedBox(height: 14),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Kumulatív Tőkegörbe (Equity Curve)',
                        style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 68,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: RoiCurvePainter(curvePoints),
                    ),
                  ),
                ],
                if (dailyValues.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Napi Profit / Veszteség Barchart',
                          style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                      Text('${dailyLabels.first} – ${dailyLabels.last}',
                          style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 64,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: DailyProfitBarPainter(dailyValues),
                    ),
                  ),
                ],
                if (widget.bets.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        final csv = _generateCsvReport();
                        Clipboard.setData(ClipboardData(text: csv));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Teljes CSV riport (jegyzetekkel) vágólapra másolva!')),
                        );
                      },
                      icon: const Icon(Icons.table_chart_outlined, size: 16),
                      label: const Text('CSV / Excel Export másolása', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (breakdownRows.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Teljesítmény bontás',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Liga', style: TextStyle(fontSize: 11))),
                  ButtonSegment(value: 1, label: Text('Piac', style: TextStyle(fontSize: 11))),
                ],
                selected: {_breakdownMode},
                onSelectionChanged: (s) => setState(() => _breakdownMode = s.first),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...breakdownRows.map((row) {
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF131A29),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1F2937)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('${row.count} tipp • Találati arány: ${row.winRatePercent.round()}%',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${row.profit >= 0 ? "+" : ""}${row.profit.round()} Ft',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: row.profit >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                        ),
                      ),
                      Text(
                        'ROI: ${row.roiPercent >= 0 ? "+" : ""}${row.roiPercent.toStringAsFixed(1)}%',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
        const SizedBox(height: 18),
        Text('Figyelőlista (${watched.length} meccs)',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (watched.isEmpty)
          const Text('Még nem jelöltél meg meccset a könyvjelző ikonnal.',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13))
        else
          ...watched.map((m) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  onTap: () => widget.onSelectMatch(m),
                  title: Text('${m.homeTeam} – ${m.awayTeam}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text('${m.market} @ ${m.marketOdds} • ${m.kickoff}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF10B981))),
                  trailing: IconButton(
                    icon: const Icon(Icons.bookmark_remove, color: Color(0xFFF59E0B)),
                    onPressed: () => widget.onToggleWatch(m.id),
                  ),
                ),
              )),
        const SizedBox(height: 20),
        Text('Rögzített Tippjeim (${widget.bets.length})',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (widget.bets.isEmpty)
          const Text('Még nincs rögzített tipp. Használd a + vagy a Saját tipp gombot!',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13))
        else
          ...widget.bets.map((b) {
            final clv = b.clvPercent;
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
                          child: Text(b.matchTitle,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                          onPressed: () => widget.onDeleteBet(b.id),
                        ),
                      ],
                    ),
                    Text('${b.market} @ ${b.odds} • Tét: ${b.stake.round()} Ft (${b.date})',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                    if (b.note.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('📝 ${b.note}',
                          style: const TextStyle(
                              fontSize: 11, fontStyle: FontStyle.italic, color: Color(0xFFD1D5DB))),
                    ],
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () => widget.onEditClosingOdds(b),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A0E17),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF1F2937)),
                        ),
                        child: Text(
                          b.closingOdds != null
                              ? 'Záró odds: ${b.closingOdds!.toStringAsFixed(2)} • CLV: ${clv! >= 0 ? "+" : ""}${clv.toStringAsFixed(1)}%'
                              : '+ Záró odds megadása (CLV méréshez)',
                          style: TextStyle(
                            fontSize: 11,
                            color: clv != null
                                ? (clv >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444))
                                : const Color(0xFF60A5FA),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'pending', label: Text('Nyitott', style: TextStyle(fontSize: 11))),
                        ButtonSegment(value: 'won', label: Text('Nyert', style: TextStyle(fontSize: 11))),
                        ButtonSegment(value: 'lost', label: Text('Vesztett', style: TextStyle(fontSize: 11))),
                        ButtonSegment(value: 'void', label: Text('Void', style: TextStyle(fontSize: 11))),
                      ],
                      selected: {b.status},
                      onSelectionChanged: (s) => widget.onUpdateBetStatus(b.id, s.first),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}
