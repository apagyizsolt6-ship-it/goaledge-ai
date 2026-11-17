import 'package:flutter/material.dart';
import '../services/app_update_service.dart';
import '../widgets/update_dialog.dart';
import 'main_navigation_screen.dart';

/// Checks for update once after first frame, then shows the main app.
class SplashUpdateGate extends StatefulWidget {
  const SplashUpdateGate({super.key});

  @override
  State<SplashUpdateGate> createState() => _SplashUpdateGateState();
}

class _SplashUpdateGateState extends State<SplashUpdateGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    final update = await AppUpdateService.checkForUpdate();
    if (!mounted || update == null) return;
    await showAppUpdateDialog(context, update);
  }

  @override
  Widget build(BuildContext context) => const MainNavigationScreen();
}
