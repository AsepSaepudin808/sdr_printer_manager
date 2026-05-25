import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/print_server_service.dart';

final printServerServiceProvider = Provider<PrintServerService>((ref) {
  return PrintServerService();
});