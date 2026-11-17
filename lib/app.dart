import 'package:flutter/material.dart';
import 'core/theme.dart';
import 'screens/splash_update_gate.dart';

class GoalEdgeApp extends StatelessWidget {
  const GoalEdgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GoalEdge AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const SplashUpdateGate(),
    );
  }
}
