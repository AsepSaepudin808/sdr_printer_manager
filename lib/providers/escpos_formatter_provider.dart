import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/escpos/escpos_config.dart';
import '../utils/escpos/escpos_receipts.dart';
import 'app_state_provider.dart';

final escposFormatterProvider = Provider<EscPosFormatter>((ref) {
  final print = ref.watch(printConfigProvider);
  final printer = ref.watch(printerConfigProvider);
  return EscPosFormatter(EscPosConfig(
    customCharsPerLine: print.customCharsPerLine,
    extraFeed: print.extraFeed,
    autoCut: print.autoCut,
    useFontB: print.useFontB,
    cashDrawerMode: printer.cashDrawerMode,
    sessionSummaryCashDrawer: printer.sessionSummaryCashDrawer,
  ));
});