import 'package:flutter/material.dart';
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

  late String _language;
  late bool _notifEnabled;
  late bool _directPrint;
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
      _language = p.getString('language') ?? 'Indonesia';
      _notifEnabled = false;
      _directPrint = p.getBool('direct_print') ?? false;
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
    await S.setLang(_language);
    await p.setBool('direct_print', _directPrint);
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

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    String tr(String id, String en) => _language == 'English' ? en : id;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        title: Text(tr('Pengaturan', 'Settings'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(tr('Bahasa', 'Language'),
              child: DropdownButton<String>(
                value: _language,
                isExpanded: true,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(
                      value: 'Indonesia', child: Text('Indonesia')),
                  DropdownMenuItem(value: 'English', child: Text('English')),
                ],
                onChanged: (v) => setState(() => _language = v ?? 'Indonesia'),
              )),
          _section(tr('Ijin Notifikasi', 'Notification Permission'),
              child: _checkTile(
                tr('Ijin dibutuhkan supaya aplikasi bisa menampilkan notifikasi',
                    'Permission needed so the app can show notifications'),
                _notifEnabled,
                (v) => setState(() => _notifEnabled = v ?? false),
              )),
          _section(tr('Langsung Cetak', 'Direct Print'),
              child: _checkTile(
                tr('Aplikasi akan langsung cetak ketika menerima data dari POS',
                    'App will print immediately when receiving data from POS'),
                _directPrint,
                (v) => setState(() => _directPrint = v ?? false),
              )),
          _section(tr('Koneksi Printer', 'Printer Connection'),
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
          _section('Printer',
              child: GestureDetector(
                onTap: _pickPrinter,
                child: Text(
                  _printer != null
                      ? '${_printer!.name} (${_printer!.address})'
                      : tr('Pilih Printer...', 'Select Printer...'),
                  style: TextStyle(
                      fontSize: 14,
                      color: _printer != null ? _primary : Colors.grey,
                      fontWeight: FontWeight.w600),
                ),
              )),
          const SizedBox(height: 16),
          _section(tr('Versi', 'Version'),
              child: const Center(
                child: Text('1.0.0',
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
              child: Text(tr('Batal', 'Cancel'),
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
              child: Text(tr('Simpan', 'Save'),
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
