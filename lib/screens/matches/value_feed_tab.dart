import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/models.dart';
import '../../services/poisson_engine.dart';
import '../../widgets/charts.dart';

class ValueFeedTab extends StatefulWidget {
  final MatchList matches;
  final String baseUrl;
  final String apiKey;
  final int dayOffset;
  final double bankroll;
  final String stakeProfile;
  final SlipItemList slipItems;
  final Set<String> favoriteLeagues;
  final void Function(String) onToggleFavoriteLeague;
  final void Function({required bool conservative}) onGenerateAiSlip;
  final void Function(int) onDayChanged;
  final Future<void> Function() onRefresh;
  final void Function(MatchPick) onSelectMatch;
  final void Function(String) onToggleWatch;
  final void Function(MatchPick) onToggleSlip;
  final void Function(MatchPick) onEditOdds;
  final void Function(MatchPick) onLogBet;

  const ValueFeedTab({
    super.key,
    required this.matches,
    required this.baseUrl,
    required this.apiKey,
    required this.dayOffset,
    required this.bankroll,
    required this.stakeProfile,
    required this.slipItems,
    required this.favoriteLeagues,
    required this.onToggleFavoriteLeague,
    required this.onGenerateAiSlip,
    required this.onDayChanged,
    required this.onRefresh,
    required this.onSelectMatch,
    required this.onToggleWatch,
    required this.onToggleSlip,
    required this.onEditOdds,
    required this.onLogBet,
  });

  @override
  State<ValueFeedTab> createState() => _ValueFeedTabState();
}

class _ValueFeedTabState extends State<ValueFeedTab> {
  String _selectedLeague = 'Összes';
  String _smartFilter = 'all';
  double _minEvThreshold = 0.0;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final leagueSet = <String>{'Összes', ...widget.favoriteLeagues};
    for (final m in widget.matches) {
      leagueSet.add(m.league);
    }
    final leagues = leagueSet.toList();
    if (!leagues.contains(_selectedLeague)) {
      _selectedLeague = 'Összes';
    }

    final liveCount = widget.matches.where((m) => m.isLive).length;
    final pressureCount = widget.matches.where((m) => m.isHighPressure).length;
    final steamCount = widget.matches.where((m) => m.isSteamMove).length;

    final filtered = widget.matches.where((m) {
      if (_selectedLeague != 'Összes' && m.league != _selectedLeague) return false;
      if (_smartFilter == 'favorites' && !widget.favoriteLeagues.contains(m.league)) return false;
      if (_smartFilter == 'live' && !m.isLive) return false;
      if (_smartFilter == 'pressure' && !m.isHighPressure) return false;
      if (_smartFilter == 'steam' && !m.isSteamMove) return false;
      if (_smartFilter == 'standings' && !m.hasStandingData) return false;
      if (m.edgePercent < _minEvThreshold) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchText = '${m.homeTeam} ${m.awayTeam} ${m.league} ${m.market}'.toLowerCase();
        if (!matchText.contains(q)) return false;
      }
      return true;
    }).toList();

    final topVault = widget.matches.where((m) => !m.isFinished && m.edgePercent > 0).toList()
      ..sort((a, b) {
        final aScore = a.edgePercent + (widget.favoriteLeagues.contains(a.league) ? 1.5 : 0.0);
        final bScore = b.edgePercent + (widget.favoriteLeagues.contains(b.league) ? 1.5 : 0.0);
        return bScore.compareTo(aScore);
      });

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      color: const Color(0xFF10B981),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 84),
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: -1, label: Text('Tegnap')),
              ButtonSegment(value: 0, label: Text('Ma')),
              ButtonSegment(value: 1, label: Text('Holnap')),
            ],
            selected: {widget.dayOffset},
            onSelectionChanged: (s) => widget.onDayChanged(s.first),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => widget.onGenerateAiSlip(conservative: true),
                  icon: const Icon(Icons.shield_outlined, size: 15, color: Color(0xFF10B981)),
                  label: const Text('AI Duplázó (~2.0x)', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF1F2937)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => widget.onGenerateAiSlip(conservative: false),
                  icon: const Icon(Icons.bolt, size: 15, color: Color(0xFF3B82F6)),
                  label: const Text('AI Value Tripla', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF1F2937)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Keresés csapatra, ligára vagy piacra...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFF131A29),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF1F2937)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _SmartChip(
                  label: 'Mind (${widget.matches.length})',
                  selected: _smartFilter == 'all',
                  onTap: () => setState(() => _smartFilter = 'all'),
                ),
                const SizedBox(width: 6),
                _SmartChip(
                  label: '★ Kedvenc ligák',
                  selected: _smartFilter == 'favorites',
                  color: const Color(0xFFF59E0B),
                  onTap: () => setState(() => _smartFilter = 'favorites'),
                ),
                const SizedBox(width: 6),
                _SmartChip(
                  label: '🔴 Élő ($liveCount)',
                  selected: _smartFilter == 'live',
                  color: const Color(0xFFEF4444),
                  onTap: () => setState(() => _smartFilter = 'live'),
                ),
                const SizedBox(width: 6),
                _SmartChip(
                  label: '🔥 Gólnyomás ($pressureCount)',
                  selected: _smartFilter == 'pressure',
                  color: const Color(0xFFF59E0B),
                  onTap: () => setState(() => _smartFilter = 'pressure'),
                ),
                const SizedBox(width: 6),
                _SmartChip(
                  label: '📉 Steam Move ($steamCount)',
                  selected: _smartFilter == 'steam',
                  color: const Color(0xFF3B82F6),
                  onTap: () => setState(() => _smartFilter = 'steam'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Állítható Min. EV% küszöb szűrő
          Row(
            children: [
              const Text('Min. EV:', style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
              const SizedBox(width: 8),
              ...[0.0, 2.0, 5.0, 8.0].map((thr) {
                final sel = _minEvThreshold == thr;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(thr == 0.0 ? 'Mind' : '+${thr.toInt()}%',
                        style: const TextStyle(fontSize: 10)),
                    selected: sel,
                    selectedColor: const Color(0xFF10B981),
                    onSelected: (_) => setState(() => _minEvThreshold = thr),
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 8),
          if (topVault.isNotEmpty && _searchQuery.isEmpty && _smartFilter == 'all' && _minEvThreshold == 0.0) ...[
            const Text('Napi Top 3 AI Széf (16-piacos Dixon-Coles)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
            const SizedBox(height: 8),
            SizedBox(
              height: 98,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: topVault.take(3).length,
                itemBuilder: (context, idx) {
                  final top = topVault[idx];
                  return GestureDetector(
                    onTap: () => widget.onSelectMatch(top),
                    child: Container(
                      width: 225,
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF132A24), Color(0xFF131A29)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color.fromRGBO(16, 185, 129, 0.45)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  '${top.homeTeam} – ${top.awayTeam}',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                              Text(
                                '+${top.edgePercent.toStringAsFixed(1)}%',
                                style: const TextStyle(
                                    color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                            ],
                          ),
                          Text(top.market,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: Color(0xFFD1D5DB))),
                          Text(
                            'Szorzó: ${top.marketOdds} • Tét: ${top.recommendedStake(widget.bankroll, widget.stakeProfile)} Ft',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
          ],
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: leagues.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final league = leagues[index];
                final isSelected = league == _selectedLeague;
                final isFav = widget.favoriteLeagues.contains(league);
                return GestureDetector(
                  onLongPress: () => widget.onToggleFavoriteLeague(league),
                  child: FilterChip(
                    label: Text(
                      league == 'Összes' ? league : '${isFav ? "★ " : ""}$league',
                      style: TextStyle(
                        fontSize: 12,
                        color: isSelected ? Colors.black : Colors.white,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: const Color(0xFF10B981),
                    backgroundColor: const Color(0xFF131A29),
                    onSelected: (_) => setState(() => _selectedLeague = league),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text('Nincs a szűrőnek megfelelő mérkőzés.',
                    style: TextStyle(color: Color(0xFF9CA3AF))),
              ),
            )
          else
            ...filtered.map(
              (match) {
                final inSlip = widget.slipItems.any((s) => s.matchId == match.id);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: MatchValueCard(
                    match: match,
                    baseUrl: widget.baseUrl,
                    apiKey: widget.apiKey,
                    bankroll: widget.bankroll,
                    stakeProfile: widget.stakeProfile,
                    isInSlip: inSlip,
                    isFavLeague: widget.favoriteLeagues.contains(match.league),
                    onToggleFavLeague: () => widget.onToggleFavoriteLeague(match.league),
                    onTap: () => widget.onSelectMatch(match),
                    onToggleWatch: () => widget.onToggleWatch(match.id),
                    onToggleSlip: () => widget.onToggleSlip(match),
                    onEditOdds: () => widget.onEditOdds(match),
                    onLogBet: () => widget.onLogBet(match),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _SmartChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _SmartChip({
    required this.label,
    required this.selected,
    this.color = const Color(0xFF10B981),
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color : const Color(0xFF131A29),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : const Color(0xFF1F2937)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: selected ? Colors.black : const Color(0xFFD1D5DB),
          ),
        ),
      ),
    );
  }
}

class MatchValueCard extends StatelessWidget {
  final MatchPick match;
  final String baseUrl;
  final String apiKey;
  final double bankroll;
  final String stakeProfile;
  final bool isInSlip;
  final bool isFavLeague;
  final VoidCallback onToggleFavLeague;
  final VoidCallback onTap;
  final VoidCallback onToggleWatch;
  final VoidCallback onToggleSlip;
  final VoidCallback onEditOdds;
  final VoidCallback onLogBet;

  const MatchValueCard({
    super.key,
    required this.match,
    required this.baseUrl,
    required this.apiKey,
    required this.bankroll,
    required this.stakeProfile,
    required this.isInSlip,
    required this.isFavLeague,
    required this.onToggleFavLeague,
    required this.onTap,
    required this.onToggleWatch,
    required this.onToggleSlip,
    required this.onEditOdds,
    required this.onLogBet,
  });

  @override
  Widget build(BuildContext context) {
    final edge = match.edgePercent;
    final recStake = match.recommendedStake(bankroll, stakeProfile);
    final dropPct = match.oddsDropPercent;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: onToggleFavLeague,
                          child: Icon(
                            isFavLeague ? Icons.star : Icons.star_border,
                            size: 16,
                            color: isFavLeague ? const Color(0xFFF59E0B) : const Color(0xFF6B7280),
                          ),
                        ),
                        const SizedBox(width: 4),
                        if (match.isLive) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'ÉLŐ ${match.minute ?? ""}\'',
                              style: const TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (match.isHighPressure) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color.fromRGBO(245, 158, 11, 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              '🔥 NYOMÁS',
                              style: TextStyle(
                                  fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFF59E0B)),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (match.isSteamMove) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color.fromRGBO(59, 130, 246, 0.22),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '📉 STEAM -${dropPct.toStringAsFixed(0)}%',
                              style: const TextStyle(
                                  fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF60A5FA)),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            '${match.league} • ${match.kickoff}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color.fromRGBO(16, 185, 129, 0.16),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '+${edge.toStringAsFixed(1)}% EV',
                          style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: onToggleWatch,
                        child: Icon(
                          match.isWatched ? Icons.bookmark : Icons.bookmark_border,
                          size: 20,
                          color: match.isWatched ? const Color(0xFFF59E0B) : const Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  TeamLogoBadge(
                    teamId: match.homeId,
                    teamName: match.homeTeam,
                    baseUrl: baseUrl,
                    apiKey: apiKey,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          match.homePos != null ? '${match.homeTeam} (${match.homePos}.)' : match.homeTeam,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        WdlStrip(codes: match.homeFormCodes),
                      ],
                    ),
                  ),
                  if (match.homeScore != null && match.awayScore != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A0E17),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${match.homeScore} - ${match.awayScore}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: match.isLive ? const Color(0xFFEF4444) : Colors.white,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          match.awayPos != null ? '(${match.awayPos}.) ${match.awayTeam}' : match.awayTeam,
                          textAlign: TextAlign.end,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        WdlStrip(codes: match.awayFormCodes),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TeamLogoBadge(
                    teamId: match.awayId,
                    teamName: match.awayTeam,
                    baseUrl: baseUrl,
                    apiKey: apiKey,
                    size: 22,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                match.trendSummary,
                style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0E17),
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
                          Text(match.market,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 2),
                          Text(
                            'AI: ${(match.modelProb * 100).round()}% • Ajánlott tét: $recStake Ft',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: onEditOdds,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                            decoration: BoxDecoration(
                              color: match.isCustomOdds
                                  ? const Color(0xFFF59E0B)
                                  : const Color(0xFF10B981),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  '@ ${match.marketOdds.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                                const SizedBox(width: 3),
                                const Icon(Icons.edit, size: 11, color: Colors.black),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: Icon(
                            isInSlip ? Icons.check_circle : Icons.playlist_add,
                            color: isInSlip ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
                            size: 21,
                          ),
                          tooltip: 'Kombi szelvénybe',
                          onPressed: onToggleSlip,
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline, color: Color(0xFF10B981), size: 21),
                          tooltip: 'Naplózás',
                          onPressed: onLogBet,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
