import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/app_update_service.dart';
import '../services/notification_service.dart';
import '../services/sport_api_service.dart';
import 'update_dialog.dart';

/// Extracted Settings dialog.
/// Previously lived inside AppController.
class SettingsDialog {
  static Future<void> show({
    required BuildContext context,
    required String apiKey,
    required String baseUrl,
    required String lastApiStatus,
    required String? rateLimitRemaining,
    required Future<SportApiResponse?> Function({bool silent}) onTestApi,
    required String Function() onExportBackup,
    required Future<bool> Function(String json) onImportBackup,
    required void Function(String apiKey, String baseUrl) onSave,
    required VoidCallback onDemoMode,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return _SettingsDialogContent(
          initialApiKey: apiKey,
          initialBaseUrl: baseUrl,
          lastApiStatus: lastApiStatus,
          rateLimitRemaining: rateLimitRemaining,
          onTestApi: onTestApi,
          onExportBackup: onExportBackup,
          onImportBackup: onImportBackup,
          onSave: onSave,
          onDemoMode: onDemoMode,
        );
      },
    );
  }
}

class _SettingsDialogContent extends StatefulWidget {
  final String initialApiKey;
  final String initialBaseUrl;
  final String lastApiStatus;
  final String? rateLimitRemaining;
  final Future<SportApiResponse?> Function({bool silent}) onTestApi;
  final String Function() onExportBackup;
  final Future<bool> Function(String json) onImportBackup;
  final void Function(String apiKey, String baseUrl) onSave;
  final VoidCallback onDemoMode;

  const _SettingsDialogContent({
    required this.initialApiKey,
    required this.initialBaseUrl,
    required this.lastApiStatus,
    required this.rateLimitRemaining,
    required this.onTestApi,
    required this.onExportBackup,
    required this.onImportBackup,
    required this.onSave,
    required this.onDemoMode,
  });

  @override
  State<_SettingsDialogContent> createState() => _SettingsDialogContentState();
}

class _SettingsDialogContentState extends State<_SettingsDialogContent> {
  late final TextEditingController keyController;
  late final TextEditingController baseController;
  late final TextEditingController backupController;
  late String testOutput;
  bool testing = false;

  @override
  void initState() {
    super.initState();
    keyController = TextEditingController(text: widget.initialApiKey);
    baseController = TextEditingController(text: widget.initialBaseUrl);
    backupController = TextEditingController();
    testOutput = widget.lastApiStatus;
  }

  @override
  void dispose() {
    keyController.dispose();
    baseController.dispose();
    backupController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF131A29),
      title: const Row(
        children: [
          Icon(Icons.api, color: Color(0xFF10B981)),
          SizedBox(width: 8),
          Text('Beállítások & Mentés', style: TextStyle(fontSize: 18)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snap) {
                final v = snap.data;
                final label = v == null
                    ? 'Verzió betöltése…'
                    : 'v${v.version} (${v.buildNumber})';
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0E17),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF1F2937)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ALKALMAZÁS',
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFF6B7280),
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final update = await AppUpdateService.checkForUpdate();
                            if (!context.mounted) return;
                            if (update == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Nincs újabb verzió.')),
                              );
                              return;
                            }
                            Navigator.pop(context);
                            await showAppUpdateDialog(context, update);
                          },
                          icon: const Icon(Icons.system_update, size: 16),
                          label: const Text('Frissítés keresése', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const Text(
              'SportAPI.ai (X-Api-Key + ETag gyorsítótár)',
              style: TextStyle(fontSize: 12, color: Color(0xFF10B981), fontWeight: FontWeight.bold),
            ),
            if (widget.rateLimitRemaining != null) ...[
              const SizedBox(height: 4),
              Text(
                'Maradék napi keret: ${widget.rateLimitRemaining} lekérés',
                style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: keyController,
              decoration: const InputDecoration(
                labelText: 'X-Api-Key (sk_live_...)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: baseController,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: testing
                        ? null
                        : () async {
                            setState(() => testing = true);
                            // Persist temp key for test via parent callback pattern:
                            // parent onTestApi should use current controller values if needed.
                            // We call onSave first so sync uses new key.
                            widget.onSave(keyController.text.trim(), baseController.text.trim());
                            final res = await widget.onTestApi(silent: true);
                            if (!mounted) return;
                            setState(() {
                              testing = false;
                              if (res != null) {
                                testOutput = '${res.message}\n\n${res.rawPreview}';
                              } else {
                                testOutput = 'Adj meg egy API kulcsot a teszthez!';
                              }
                            });
                          },
                    icon: testing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.bolt, size: 16),
                    label: const Text('API Teszt', style: TextStyle(fontSize: 11)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      NotificationService.showAlert(
                        99999,
                        '⚽ GoalEdge AI Teszt Értesítés',
                        'A valódi Android Push riasztások aktívak és működnek!',
                      );
                    },
                    icon: const Icon(Icons.notifications_active, size: 16),
                    label: const Text('Push Teszt', style: TextStyle(fontSize: 11)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0E17),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF1F2937)),
              ),
              child: Text(
                testOutput,
                style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
              ),
            ),
            const Divider(height: 22, color: Color(0xFF1F2937)),
            const Text(
              'JSON Biztonsági Mentés (Újratelepítéshez)',
              style: TextStyle(fontSize: 12, color: Color(0xFF3B82F6), fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  final jsonStr = widget.onExportBackup();
                  Clipboard.setData(ClipboardData(text: jsonStr));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Mentés a vágólapra másolva')),
                  );
                },
                icon: const Icon(Icons.copy, size: 15),
                label: const Text('Mentés másolása vágólapra', style: TextStyle(fontSize: 11)),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: backupController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'JSON visszaállítás beillesztése...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final ok = await widget.onImportBackup(backupController.text);
                  if (ok && context.mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.restore, size: 15),
                label: const Text('Adatok visszaállítása', style: TextStyle(fontSize: 11)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.onDemoMode();
            Navigator.pop(context);
          },
          child: const Text('Demó mód'),
        ),
        FilledButton(
          onPressed: () {
            widget.onSave(keyController.text.trim(), baseController.text.trim());
            Navigator.pop(context);
          },
          child: const Text('Mentés'),
        ),
      ],
    );
  }
}
