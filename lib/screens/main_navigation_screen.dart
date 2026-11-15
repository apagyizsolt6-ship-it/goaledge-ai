import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../providers/app_controller.dart';
import 'matches/value_feed_tab.dart';
import 'radar/trend_radar_tab.dart';
import 'bankroll/calculator_tab.dart';
import 'bets/tracker_tab.dart';

class MainNavigationScreen extends ConsumerWidget {
  const MainNavigationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appControllerProvider);

    final pages = [
      ValueFeedTab(
        matches: app.matches,
        baseUrl: app.baseUrl,
        apiKey: app.apiKey,
        dayOffset: app.dayOffset,
        bankroll: app.bankroll,
        stakeProfile: app.stakeProfile,
        slipItems: app.slipItems,
        favoriteLeagues: app.favoriteLeagues,
        onToggleFavoriteLeague: app.toggleFavoriteLeague,
        onGenerateAiSlip: app.generateAiSlip,
        onDayChanged: app.changeDayOffset,
        onRefresh: () => app.syncSportApi(context: context),
        onSelectMatch: (m) => app.openMatchDetail(context, m),
        onToggleWatch: app.toggleWatch,
        onToggleSlip: (m) => app.toggleSlipOption(m),
        onEditOdds: (m) => app.openEditOddsDialog(context, m),
        onLogBet: (m) => app.openLogBetDialog(context, m),
      ),
      TrendRadarTab(
        matches: app.matches,
        baseUrl: app.baseUrl,
        apiKey: app.apiKey,
        onSelectMatch: (m) => app.openMatchDetail(context, m),
      ),
      CalculatorTab(
        matches: app.matches,
        bankroll: app.bankroll,
        autoBankroll: app.autoBankroll,
        stakeProfile: app.stakeProfile,
        onBankrollChanged: (val) {
          app.setBankroll(val);
        },
        onAutoBankrollChanged: (val) {
          app.setAutoBankroll(val);
        },
        onStakeProfileChanged: (val) {
          app.setStakeProfile(val);
        },
      ),
      TrackerAndWatchlistTab(
        matches: app.matches,
        bets: app.bets,
        bankroll: app.bankroll,
        onToggleWatch: app.toggleWatch,
        onSelectMatch: (m) => app.openMatchDetail(context, m),
        onUpdateBetStatus: app.updateBetStatus,
        onEditClosingOdds: (b) => app.openEditClosingOddsDialog(context, b),
        onAddManualBet: app.addManualBet,
        onAdjustCapital: app.adjustBankrollCapital,
        onDeleteBet: app.deleteBet,
      ),
    ];

    double slipOdds = 1.0;
    for (final it in app.slipItems) {
      slipOdds *= it.odds;
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E17),
        title: Row(
          children: [
            const Icon(Icons.insights, color: Color(0xFF10B981)),
            const SizedBox(width: 6),
            const Text('GoalEdge AI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: app.isLiveMode
                    ? const Color.fromRGBO(16, 185, 129, 0.2)
                    : const Color.fromRGBO(59, 130, 246, 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                app.isLiveMode ? 'v7.1 LAB' : 'v7.1 DEMÓ',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: app.isLiveMode ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              app.autoLiveRadar ? Icons.podcasts : Icons.sensors_off,
              color: app.autoLiveRadar ? const Color(0xFFEF4444) : Colors.grey,
            ),
            tooltip: 'Automata Élő Radar + Push (75 mp)',
            onPressed: () => app.toggleAutoLiveRadar(context),
          ),
          if (app.isLoadingApi)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'SportAPI.ai frissítés',
              onPressed: () => app.syncSportApi(context: context),
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Beállítások & Mentés',
            onPressed: () => app.openSettingsDialog(context),
          ),
        ],
      ),
      body: pages[app.selectedIndex],
      floatingActionButton: app.slipItems.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => app.openComboSlipSheet(context),
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.black,
              icon: const Icon(Icons.receipt_long),
              label: Text(
                'Szelvény (${app.slipItems.length}) • ${slipOdds.toStringAsFixed(2)}x',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF131A29),
        indicatorColor: const Color.fromRGBO(16, 185, 129, 0.2),
        selectedIndex: app.selectedIndex,
        onDestinationSelected: (index) => app.selectedIndex = index,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.auto_graph), label: 'Ajánlások'),
          NavigationDestination(icon: Icon(Icons.radar), label: 'Trendek'),
          NavigationDestination(icon: Icon(Icons.calculate_outlined), label: 'Kalkulátor'),
          NavigationDestination(icon: Icon(Icons.analytics_outlined), label: 'Napló & ROI'),
        ],
      ),
    );
  }
}
