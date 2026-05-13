import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/strings.dart';
import '../models/printer_device.dart';
import 'scan_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const Color _primary = Color(0xFF2BBCC4);
  static const _channel =
      MethodChannel('id.dretail.sdr_printer_manager/settings');

  late String _languageCode;
  late bool _notifEnabled;
  late bool _directPrint;
  late bool _androidPrintService;
  late String _connectionType;
  PrinterDevice? _printer;
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
      _notifEnabled = false;
      _directPrint = p.getBool('direct_print') ?? false;
      _androidPrintService = p.getBool('android_print_service') ?? false;
      _connectionType = 'bluetooth';
      final addr = p.getString('printer_address');
      final name = p.getString('printer_name');
      if (addr != null && name != null) {
        _printer = PrinterDevice(address: addr, name: name);
      }
      _loaded = true;
    });
  }

  Future<void> _pickPrinter() async {
    final result = await Navigator.push<PrinterDevice>(
      context,
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (result != null) {
      final p = await SharedPreferences.getInstance();
      await p.setString('printer_address', result.address);
      await p.setString('printer_name', result.name);
      setState(() => _printer = result);
    }
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await S.setLang(_languageCode);
    await p.setBool('direct_print', _directPrint);
    await p.setBool('android_print_service', _androidPrintService);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(S.settingsSaved),
        backgroundColor: const Color(0xFF06C270),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      Navigator.pop(context);
    }
  }

  Future<void> _openPrintSettings() async {
    try {
      await _channel.invokeMethod('openPrintSettings');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Gagal membuka pengaturan cetak Android')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        title: Text(S.settings,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Bahasa
          _section(S.language,
              child: DropdownButton<String>(
                value: _languageCode,
                isExpanded: true,
                underline: const SizedBox(),
                items: S.languages
                    .map((e) => DropdownMenuItem(
                          value: e.code,
                          child:
                              Text('${e.nativeName} (${e.code.toUpperCase()})'),
                        ))
                    .toList(),
                onChanged: (v) async {
                  if (v == null) return;
                  setState(() => _languageCode = v);
                  await S.setLang(v);
                  if (mounted) setState(() {});
                },
              )),
          // 2. Printer
          _section(S.printer,
              child: GestureDetector(
                onTap: _pickPrinter,
                child: Text(
                  _printer != null
                      ? '${_printer!.name} (${_printer!.address})'
                      : S.selectPrinter,
                  style: TextStyle(
                      fontSize: 14,
                      color: _printer != null ? _primary : Colors.grey,
                      fontWeight: FontWeight.w600),
                ),
              )),
          // 3. Koneksi Printer
          _section(S.printerConnection,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'bluetooth',
                      label: Text('Bluetooth', style: TextStyle(fontSize: 12))),
                  ButtonSegment(
                      value: 'wifi',
                      label: Text('Wifi', style: TextStyle(fontSize: 12)),
                      enabled: false),
                  ButtonSegment(
                      value: 'usb',
                      label: Text('USB', style: TextStyle(fontSize: 12)),
                      enabled: false),
                ],
                selected: {_connectionType},
                onSelectionChanged: (v) =>
                    setState(() => _connectionType = v.first),
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((s) =>
                      s.contains(WidgetState.selected) ? _primary : null),
                  foregroundColor: WidgetStateProperty.resolveWith((s) =>
                      s.contains(WidgetState.selected) ? Colors.white : null),
                ),
              )),
          // 4. Ijin Notifikasi
          _section(S.notifPermission,
              child: _checkTile(
                S.notifDesc,
                _notifEnabled,
                (v) => setState(() => _notifEnabled = v ?? false),
              )),
          // 5. Langsung Cetak
          _section(S.directPrint,
              child: _checkTile(
                S.directPrintDesc,
                _directPrint,
                (v) => setState(() => _directPrint = v ?? false),
              )),
          // 6. Layanan Cetak Android
          _section(
              S.withLang(
                  id: 'Layanan Cetak Android',
                  en: 'Android Print Service',
                  ms: 'Perkhidmatan Cetak Android',
                  th: 'บริการพิมพ์ Android',
                  zh: 'Android 打印服务',
                  ar: 'خدمة طباعة أندرويد'),
              child: _checkTile(
                S.withLang(
                    id: 'Aktifkan agar muncul sebagai pilihan printer di dialog cetak Android',
                    en: 'Enable to appear as a printer option in Android print dialog',
                    ms: 'Aktifkan agar muncul sebagai pilihan pencetak di dialog cetak Android',
                    th: 'เปิดใช้งานเพื่อให้แสดงเป็นตัวเลือกเครื่องพิมพ์ในกล่องพิมพ์ Android',
                    zh: '启用后会在 Android 打印对话框中显示为打印机选项',
                    ar: 'فعّل هذا الخيار ليظهر كخيار طابعة في نافذة طباعة أندرويد'),
                _androidPrintService,
                (v) async {
                  setState(() => _androidPrintService = v ?? false);
                  if (v == true) {
                    await _openPrintSettings();
                  }
                },
              )),
          // 7. Versi
          _section(S.version,
              child: const Center(
                child: Text('V1.0.0.1',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _primary)),
              )),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
                child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.grey[600],
                side: BorderSide(color: Colors.grey.shade400),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(S.cancel,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            )),
            const SizedBox(width: 12),
            Expanded(
                child: ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(S.save,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            )),
          ]),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _section(String label, {required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
        ),
        child: child,
      ),
    );
  }

  Widget _checkTile(String desc, bool value, ValueChanged<bool?> onChanged) {
    return Row(children: [
      Expanded(child: Text(desc, style: const TextStyle(fontSize: 13))),
      Checkbox(value: value, onChanged: onChanged, activeColor: _primary),
    ]);
  }
}
