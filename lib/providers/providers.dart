import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_controller.dart';

final appControllerProvider = ChangeNotifierProvider<AppController>((ref) {
  return AppController();
});
