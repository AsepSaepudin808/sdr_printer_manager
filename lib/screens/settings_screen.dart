import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/crash_log_service.dart';
import '../utils/strings.dart';
import '../providers/history_provider.dart';
import '../providers/app_state_provider.dart';
import 'scan_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _channel =
      MethodChannel('id.dretail.sdr_printer_manager/settings');

  late String _languageCode;
  late bool _directPrint;
  late bool _androidPrintService;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _languageCode = p.getString('language_code') ?? 'id';
      _directPrint = p.getBool('direct_print_on') ?? true;
      _androidPrintService = p.getBool('android_print_service') ?? false;
      _loaded = true;
    });
  }

  Future<void> _pickPrinter() async {
    final result = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (result != null && mounted) {
      ref.read(printerConfigProvider.notifier).setPrinter(result);
      final p = await SharedPreferences.getInstance();
      await p.setString('printer_address', result.address);
      await p.setString('printer_name', result.name);
    }
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await S.setLang(_languageCode);
    await p.setBool('direct_print_on', _directPrint);
    await p.setBool('android_print_service', _androidPrintService);
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Text(S.settingsSaved),
        ]),
        backgroundColor: const Color(0xFF06C270),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
      Navigator.pop(context);
    }
  }

  Future<void> _openPrintSettings() async {
    try {
      await _channel.invokeMethod('openPrintSettings');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Gagal membuka pengaturan cetak Android'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ));
      }
    }
  }

  Future<void> _resetData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFFF3B30), size: 24),
          const SizedBox(width: 10),
          Expanded(
              child: Text(S.resetConfirmTitle,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800))),
        ]),
        content: Text(S.resetConfirmMsg,
            style: const TextStyle(fontSize: 13, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                Text(S.cancel, style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF3B30),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Text(S.resetButton,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final p = await SharedPreferences.getInstance();
    final historyRaw = p.getString('print_history_v1') ?? '';
    int freedBytes = historyRaw.length;

    await ref.read(historyNotifierProvider.notifier).clear();
    await p.setInt('print_count', 0);
    await p.remove('print_history_v1');
    ref.read(printCountProvider.notifier).reset();
    ref.read(logsProvider.notifier).clear();

    String freedLabel;
    if (freedBytes < 1024) {
      freedLabel = '${freedBytes}B';
    } else if (freedBytes < 1024 * 1024) {
      freedLabel = '${(freedBytes / 1024).toStringAsFixed(1)}KB';
    } else {
      freedLabel = '${(freedBytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }

    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(S.resetSuccess,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${S.isEn ? 'Freed' : 'Memori dibebaskan'}: $freedLabel',
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ]),
        backgroundColor: const Color(0xFF06C270),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height - 150,
          left: 16,
          right: 16,
        ),
        duration: const Duration(seconds: 3),
      ));
    }
  }

  Future<void> _sendLog() async {
    final file = crashLogService.logFile;
    if (file == null || !await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(S.isEn
            ? 'No log file yet. Try again after a crash.'
            : 'Belum ada log. Coba lagi setelah crash terjadi.'),
        backgroundColor: Colors.grey.shade700,
      ));
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'dPrinter Mart Crash Log V1.0.3',
        text: S.isEn
            ? 'Crash log from dPrinter Mart V1.0.3'
            : 'Log crash dari dPrinter Mart V1.0.3',
      ),
    );
  }

  Future<void> _clearLog() async {
    await crashLogService.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(S.isEn ? 'Log cleared' : 'Log dihapus'),
      backgroundColor: Colors.grey.shade700,
    ));
  }

  Widget _buildSection(String label,
      {required Widget child, IconData? icon, Color? iconColor}) {
    final themeColor = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            if (icon != null) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: (iconColor ?? themeColor).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 18, color: iconColor ?? themeColor),
              ),
              const SizedBox(width: 10),
            ],
            Text(label,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2C3E50))),
          ]),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final printer = ref.watch(printerConfigProvider.select((s) => s.printer));
    final themeColor = Theme.of(context).colorScheme.primary;

    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      appBar: AppBar(
        backgroundColor: themeColor,
        foregroundColor: Colors.white,
        title: Text(S.settings,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection(
            S.language,
            icon: Icons.language_rounded,
            iconColor: const Color(0xFF7B2FBE),
            child: DropdownButton<String>(
              value: _languageCode,
              isExpanded: true,
              underline: const SizedBox(),
              items: S.languages
                  .map((e) => DropdownMenuItem(
                      value: e.code,
                      child: Text('${e.nativeName} (${e.code.toUpperCase()})')))
                  .toList(),
              onChanged: (v) async {
                if (v == null) return;
                setState(() => _languageCode = v);
                await S.setLang(v);
                if (mounted) setState(() {});
              },
            ),
          ),
          _buildSection(
            S.printer,
            icon: Icons.print_rounded,
            iconColor: themeColor,
            child: GestureDetector(
              onTap: _pickPrinter,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: printer != null
                      ? themeColor.withValues(alpha: 0.06)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: printer != null
                          ? themeColor.withValues(alpha: 0.3)
                          : Colors.grey.shade200),
                ),
                child: Row(children: [
                  Icon(
                      printer != null
                          ? Icons.print_rounded
                          : Icons.add_rounded,
                      color: printer != null ? themeColor : Colors.grey,
                      size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(
                          printer != null ? printer.name : S.selectPrinter,
                          style: TextStyle(
                              fontSize: 14,
                              color: printer != null ? themeColor : Colors.grey,
                              fontWeight: FontWeight.w600))),
                  Icon(
                      printer != null
                          ? Icons.chevron_right_rounded
                          : Icons.add_rounded,
                      color: printer != null ? themeColor : Colors.grey,
                      size: 20),
                ]),
              ),
            ),
          ),
          _buildSection(
            S.printerConnection,
            icon: Icons.bluetooth_rounded,
            iconColor: themeColor,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'bluetooth',
                    label: Text('Bluetooth', style: TextStyle(fontSize: 12)),
                    icon: Icon(Icons.bluetooth_rounded, size: 16)),
                ButtonSegment(
                    value: 'wifi',
                    label: Text('Wifi', style: TextStyle(fontSize: 12)),
                    icon: Icon(Icons.wifi_rounded, size: 16),
                    enabled: false),
                ButtonSegment(
                    value: 'usb',
                    label: Text('USB', style: TextStyle(fontSize: 12)),
                    icon: Icon(Icons.usb_rounded, size: 16),
                    enabled: false),
              ],
              selected: const {'bluetooth'},
              onSelectionChanged: (v) {},
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith(
                    (s) => s.contains(WidgetState.selected) ? themeColor : null),
                foregroundColor: WidgetStateProperty.resolveWith((s) =>
                    s.contains(WidgetState.selected) ? Colors.white : null),
              ),
            ),
          ),
          _buildSection(
            S.directPrint,
            icon: Icons.flash_on_rounded,
            iconColor: Colors.amber.shade700,
            child: Row(children: [
              Expanded(
                  child: Text(S.directPrintDesc,
                      style: const TextStyle(fontSize: 13))),
              Switch.adaptive(
                  value: _directPrint,
                  activeTrackColor: themeColor,
                  onChanged: (v) => setState(() => _directPrint = v)),
            ]),
          ),
          _buildSection(
            S.withLang(
                id: 'Layanan Cetak Android',
                en: 'Android Print Service',
                ms: 'Perkhidmatan Cetak Android',
                th: 'บริการพิมพ์ Android',
                zh: 'Android 打印服务',
                ar: 'خدمة طباعة أندرويد'),
            icon: Icons.android_rounded,
            iconColor: Colors.green.shade700,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  S.withLang(
                      id: 'Aktifkan agar muncul sebagai pilihan printer di dialog cetak Android',
                      en: 'Enable to appear as a printer option in Android print dialog',
                      ms: 'Aktifkan agar muncul sebagai pilihan pencetak di dialog cetak Android',
                      th: 'เปิดใช้านเพื่อให้แสดงเป็นตัวเลือกเครื่องพิมพ์ในกล่องพิมพ์ Android',
                      zh: '启用后会在 Android 打印对话框中显示为打印机选项',
                      ar: 'فعّل هذا الخيار ليظهر كخيار طابعة في نافذة طباعة أندرويد'),
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              Row(children: [
                Switch.adaptive(
                  value: _androidPrintService,
                  activeTrackColor: themeColor,
                  onChanged: (v) async {
                    setState(() => _androidPrintService = v);
                    if (v) {
                      await _openPrintSettings();
                    }
                  },
                ),
                if (_androidPrintService)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      Icon(Icons.check_circle_rounded,
                          size: 14, color: Colors.green.shade600),
                      const SizedBox(width: 4),
                      Text('Aktif',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.green.shade600,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ),
              ]),
            ]),
          ),
          _buildSection(
            S.resetData,
            icon: Icons.delete_forever_rounded,
            iconColor: const Color(0xFFFF3B30),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(S.resetDataDesc, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _resetData,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text(S.resetButton,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF3B30),
                    side: const BorderSide(color: Color(0xFFFF3B30)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ]),
          ),
          _buildSection(
            S.isEn ? 'Send Crash Log' : 'Kirim Log Crash',
            icon: Icons.bug_report_outlined,
            iconColor: Colors.orange.shade700,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.isEn
                      ? 'If the app crashes, the error is saved here. Send this file when contacting support.'
                      : 'Jika aplikasi crash, error tersimpan di sini. Kirim file ini saat menghubungi support.',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  '${crashLogService.lineCount} ${S.isEn ? "entries" : "entri"}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _sendLog,
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: Text(
                        S.isEn ? 'Send Log' : 'Kirim Log',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _clearLog,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: Text(
                      S.isEn ? 'Clear' : 'Hapus',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                      side: BorderSide(color: Colors.grey.shade400),
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
          _buildSection(
            S.version,
            icon: Icons.info_outline_rounded,
            iconColor: Colors.grey.shade600,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                    color: themeColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20)),
                child: const Text('V1.0.3',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2BBCC4))),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
                child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey.shade600,
                  side: BorderSide(color: Colors.grey.shade400),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
              child: Text(S.cancel,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            )),
            const SizedBox(width: 12),
            Expanded(
                child: ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                  backgroundColor: themeColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0),
              child: Text(S.save,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            )),
          ]),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}