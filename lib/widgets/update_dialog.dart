import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import '../services/app_update_service.dart';

Future<void> showAppUpdateDialog(BuildContext context, AppUpdateInfo update) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _UpdateDialog(update: update),
  );
}

class _UpdateDialog extends StatefulWidget {
  final AppUpdateInfo update;
  const _UpdateDialog({required this.update});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  double _progress = 0;
  String? _error;

  Future<void> _startDownload() async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });
    final file = await AppUpdateService.downloadApk(
      widget.update,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    if (!mounted) return;
    if (file == null) {
      setState(() {
        _downloading = false;
        _error = 'Letöltés sikertelen. Próbáld később.';
      });
      return;
    }
    final result = await OpenFilex.open(file.path);
    if (!mounted) return;
    if (result.type != ResultType.done) {
      setState(() {
        _downloading = false;
        _error = 'Telepítő megnyitása sikertelen: ${result.message}';
      });
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.update;
    return AlertDialog(
      backgroundColor: const Color(0xFF131A29),
      title: const Text('Új verzió elérhető'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            u.releaseName,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
          ),
          const SizedBox(height: 8),
          Text('Build: ${u.remoteBuild}', style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
          if (u.releaseNotes != null && u.releaseNotes!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              u.releaseNotes!.length > 280 ? '${u.releaseNotes!.substring(0, 280)}…' : u.releaseNotes!,
              style: const TextStyle(fontSize: 13, color: Color(0xFFD1D5DB)),
            ),
          ],
          if (_downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: _progress > 0 && _progress < 1 ? _progress : null,
              color: const Color(0xFF10B981),
              backgroundColor: const Color(0xFF1F2937),
            ),
            const SizedBox(height: 6),
            Text(
              _progress > 0 ? '${(_progress * 100).toStringAsFixed(0)}%' : 'Letöltés…',
              style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
          ],
        ],
      ),
      actions: [
        if (!_downloading)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Később'),
          ),
        FilledButton(
          onPressed: _downloading ? null : _startDownload,
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
          child: Text(_downloading ? 'Letöltés…' : 'Frissítés'),
        ),
      ],
    );
  }
}
