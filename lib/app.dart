import 'package:flutter/material.dart';
import 'core/theme.dart';
import 'screens/main_navigation_screen.dart';

class GoalEdgeApp extends StatelessWidget {
  const GoalEdgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GoalEdge AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const MainNavigationScreen(),
    );
  }
}
