import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// LANGUAGE MODEL
class SLanguage {
  final String code;
  final String name;
  final String nativeName;

  const SLanguage({
    required this.code,
    required this.name,
    required this.nativeName,
  });

  String get displayLabel => '$nativeName ($code)';
}

// ─── REACTIVE LANGUAGE STATE ────────────────────────────────────────────────
/// ChangeNotifier for reactive language switching.
/// Use with ref.watch(langProvider) to trigger rebuild on language change.
class LangNotifier extends ChangeNotifier {
  @override
  void notifyListeners() {
    super.notifyListeners();
    S._onLanguageChanged();
  }
}

/// Provider for reactive language state
final langProvider = LangNotifier();

/// Hook to use langProvider in widgets without Provider scope
/// Usage: LangNotifier.instance.addListener(...) or use langProvider directly with ref.watch()

// ─── LOCALIZATION STRINGS ──────────────────────────────────────────────────
class S {
  static String _langCode = 'id';
  static String get langCode => _langCode;

  // Internal callback for language change notifications
  static void Function()? _languageChangeCallback;
  static void _onLanguageChanged() {
    _languageChangeCallback?.call();
  }

  static const List<SLanguage> languages = [
    SLanguage(code: 'id', name: 'Indonesian', nativeName: 'Indonesia'),
    SLanguage(code: 'en', name: 'English', nativeName: 'English'),
    SLanguage(code: 'ms', name: 'Malay', nativeName: 'Melayu'),
    SLanguage(code: 'th', name: 'Thai', nativeName: 'ไทย'),
    SLanguage(code: 'zh', name: 'Chinese (Simplified)', nativeName: '简体中文'),
    SLanguage(code: 'ar', name: 'Arabic', nativeName: 'العربية'),
  ];

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getString('language_code');
    if (saved != null && languages.any((e) => e.code == saved)) {
      _langCode = saved;
      return;
    }

    // backward compatibility: legacy saved language label
    final legacy = p.getString('language');
    if (legacy != null) {
      _langCode = _legacyToCode(legacy);
      await p.setString('language_code', _langCode);
      return;
    }

    _langCode = 'id';
  }

  static Future<void> setLang(String input) async {
    final code = _normalizeLang(input);
    _langCode = code;
    final p = await SharedPreferences.getInstance();
    await p.setString('language_code', code);
    // keep legacy key for compatibility with old app state
    await p.setString('language', _codeToLegacy(code));
    // Trigger reactive rebuild
    langProvider.notifyListeners();
  }

  static String _normalizeLang(String input) {
    final lowered = input.trim().toLowerCase();
    if (languages.any((e) => e.code == lowered)) return lowered;
    return _legacyToCode(input);
  }

  static String _legacyToCode(String legacy) {
    switch (legacy.trim().toLowerCase()) {
      case 'english':
        return 'en';
      case 'melayu':
      case 'malay':
        return 'ms';
      case 'ไทย':
      case 'thai':
        return 'th';
      case '简体中文':
      case 'chinese':
      case 'chinese (simplified)':
        return 'zh';
      case 'العربية':
      case 'arabic':
        return 'ar';
      case 'indonesia':
      default:
        return 'id';
    }
  }

  static String _codeToLegacy(String code) {
    switch (code) {
      case 'en':
        return 'English';
      case 'ms':
        return 'Melayu';
      case 'th':
        return 'ไทย';
      case 'zh':
        return '简体中文';
      case 'ar':
        return 'العربية';
      case 'id':
      default:
        return 'Indonesia';
    }
  }

  static bool get isEn => _langCode == 'en';

  static String _t(Map<String, String> map) {
    return map[_langCode] ?? map['en'] ?? map['id'] ?? '';
  }

  static String withLang({
    required String id,
    required String en,
    String? ms,
    String? th,
    String? zh,
    String? ar,
  }) {
    return _t({
      'id': id,
      'en': en,
      'ms': ms ?? id,
      'th': th ?? en,
      'zh': zh ?? en,
      'ar': ar ?? en,
    });
  }

  // App
  static String get appName => 'dPrinter Mart';

  // Nav & Titles
  static String get home => withLang(
        id: 'Beranda',
        en: 'Home',
        ms: 'Laman Utama',
        th: 'หน้าแรก',
        zh: '首页',
        ar: 'الرئيسية',
      );
  static String get freeText => withLang(
        id: 'Print Text',
        en: 'Print Text',
        ms: 'Print Text',
        th: 'ข้อความอิสระ',
        zh: '自由文本',
        ar: 'نص حر',
      );
  static String get printImage => withLang(
        id: 'Cetak Gambar',
        en: 'Print Image',
        ms: 'Cetak Imej',
        th: 'พิมพ์รูปภาพ',
        zh: '打印图片',
        ar: 'طباعة صورة',
      );
  static String get printPdf => withLang(
        id: 'Cetak PDF',
        en: 'Print PDF',
        ms: 'Cetak PDF',
        th: 'พิมพ์ PDF',
        zh: '打印 PDF',
        ar: 'طباعة PDF',
      );
  static String get settings => withLang(
        id: 'Pengaturan',
        en: 'Settings',
        ms: 'Tetapan',
        th: 'การตั้งค่า',
        zh: '设置',
        ar: 'الإعدادات',
      );
  static String get activityHistory => withLang(
        id: 'Riwayat Aktivitas',
        en: 'Activity History',
        ms: 'Sejarah Aktiviti',
        th: 'ประวัติกิจกรรม',
        zh: '活动记录',
        ar: 'سجل النشاط',
      );
  static String get aboutApp => withLang(
        id: 'Tentang Aplikasi',
        en: 'About App',
        ms: 'Tentang Aplikasi',
        th: 'เกี่ยวกับแอป',
        zh: '关于应用',
        ar: 'حول التطبيق',
      );
  static String get exit => withLang(
        id: 'Keluar',
        en: 'Exit',
        ms: 'Keluar',
        th: 'ออก',
        zh: '退出',
        ar: 'خروج',
      );

  // Home
  static String get printerActive => withLang(
        id: 'Printer Aktif',
        en: 'Printer Active',
        ms: 'Pencetak Aktif',
        th: 'เครื่องพิมพ์พร้อมใช้งาน',
        zh: '打印机已激活',
        ar: 'الطابعة نشطة',
      );
  static String get printerInactive => withLang(
        id: 'Printer Tidak Aktif',
        en: 'Printer Inactive',
        ms: 'Pencetak Tidak Aktif',
        th: 'เครื่องพิมพ์ไม่พร้อมใช้งาน',
        zh: '打印机未激活',
        ar: 'الطابعة غير نشطة',
      );
  static String get tapToCopy => withLang(
        id: 'Ketuk URL untuk menyalin',
        en: 'Tap URL to copy',
        ms: 'Ketik URL untuk salin',
      );
  static String get pressToActivate => withLang(
        id: 'Tekan tombol printer untuk mengaktifkan',
        en: 'Press printer button to activate',
        ms: 'Tekan butang pencetak untuk aktifkan',
      );
  static String get urlCopied => withLang(
        id: 'URL disalin',
        en: 'URL copied',
        ms: 'URL disalin',
      );
  static String get noPrinter => withLang(
        id: 'Belum ada printer',
        en: 'No printer',
        ms: 'Tiada pencetak',
      );
  static String get connected => withLang(
        id: 'Terhubung',
        en: 'Connected',
        ms: 'Disambungkan',
      );
  static String get notConnected => withLang(
        id: 'Belum terhubung',
        en: 'Not connected',
        ms: 'Belum disambung',
      );
  static String get selectPrinterFirst => withLang(
        id: 'Pilih printer dulu',
        en: 'Select printer first',
        ms: 'Pilih pencetak dahulu',
      );
  static String get change => withLang(
        id: 'Ganti',
        en: 'Change',
        ms: 'Tukar',
      );
  static String get select => withLang(
        id: 'Pilih',
        en: 'Select',
        ms: 'Pilih',
      );
  static String get receiptsPrinted => withLang(
        id: 'Struk Dicetak',
        en: 'Receipts Printed',
        ms: 'Resit Dicetak',
      );
  static String get paperSize => withLang(
        id: 'Ukuran Kertas',
        en: 'Paper Size',
        ms: 'Saiz Kertas',
      );
  static String get portHttpServer => withLang(
        id: 'Port HTTP Server',
        en: 'HTTP Server Port',
        ms: 'Port Pelayan HTTP',
      );
  static String get save => withLang(
        id: 'Simpan',
        en: 'Save',
        ms: 'Simpan',
      );
  static String get cancel => withLang(
        id: 'Batal',
        en: 'Cancel',
        ms: 'Batal',
      );
  static String get testPrint => withLang(
        id: 'Test Print',
        en: 'Test Print',
        ms: 'Ujian Cetak',
      );
  static String get shortReceipt => withLang(
        id: 'Cetak Struk Pendek',
        en: 'Print Short Receipt',
        ms: 'Cetak Resit Pendek',
      );
  static String get fullReceipt => withLang(
        id: 'Cetak Struk Lengkap',
        en: 'Print Full Receipt',
        ms: 'Cetak Resit Penuh',
      );
  static String get sending => withLang(
        id: 'Mengirim...',
        en: 'Sending...',
        ms: 'Menghantar...',
      );
  static String get activity => withLang(
        id: 'Aktivitas',
        en: 'Activity',
        ms: 'Aktiviti',
      );
  static String get viewAll => withLang(
        id: 'Lihat semua',
        en: 'View all',
        ms: 'Lihat semua',
      );
  static String get noActivity => withLang(
        id: 'Belum ada aktivitas',
        en: 'No activity yet',
        ms: 'Belum ada aktiviti',
      );
  static String get autoStart => withLang(
        id: 'Aktifkan Otomatis',
        en: 'Auto Start',
        ms: 'Mula Automatik',
      );
  static String get autoStartDesc => withLang(
        id: 'Printer langsung aktif saat app dibuka',
        en: 'Printer activates when app opens',
        ms: 'Pencetak aktif automatik apabila aplikasi dibuka',
      );
  static String get portSaved => withLang(
        id: 'Port disimpan',
        en: 'Port saved',
        ms: 'Port disimpan',
      );
  static String get portInvalid => withLang(
        id: 'Port harus 1024–65535',
        en: 'Port must be 1024–65535',
        ms: 'Port mesti 1024–65535',
      );
  static String get selectPrinterToast => withLang(
        id: 'Pilih printer terlebih dahulu',
        en: 'Select a printer first',
        ms: 'Pilih pencetak terlebih dahulu',
      );
  static String get printerConnectFail => withLang(
        id: '❌ Gagal menghubungkan printer',
        en: '❌ Printer connection failed',
        ms: '❌ Sambungan pencetak gagal',
      );
  static String get printerConnected => withLang(
        id: '✅ Printer terhubung via Bluetooth',
        en: '✅ Printer connected via Bluetooth',
        ms: '✅ Pencetak disambung melalui Bluetooth',
      );
  static String get printerReady => withLang(
        id: 'Printer siap digunakan!',
        en: 'Printer ready!',
        ms: 'Pencetak sedia digunakan!',
      );
  static String get serverReady => withLang(
        id: '🚀 Siap menerima print dari POS',
        en: '🚀 Ready to receive from POS',
        ms: '🚀 Sedia menerima cetakan dari POS',
      );
  static String get printerStopped => withLang(
        id: '⏹️ Printer dinonaktifkan',
        en: '⏹️ Printer deactivated',
        ms: '⏹️ Pencetak dinyahaktifkan',
      );
  static String get printerSelected => withLang(
        id: 'Printer dipilih',
        en: 'Printer selected',
        ms: 'Pencetak dipilih',
      );
  static String printSuccess(String l) => withLang(
        id: '✅ $l berhasil dicetak!',
        en: '✅ $l printed!',
        ms: '✅ $l berjaya dicetak!',
      );
  static String get printFail => withLang(
        id: '❌ Gagal mencetak.',
        en: '❌ Print failed.',
        ms: '❌ Gagal mencetak.',
      );
  static String get reconnecting => withLang(
        id: '🔄 Menghubungkan ulang...',
        en: '🔄 Reconnecting...',
        ms: '🔄 Menyambung semula...',
      );
  static String get printerDisconnected => withLang(
        id: '❌ Printer terputus!',
        en: '❌ Printer disconnected!',
        ms: '❌ Pencetak terputus!',
      );
  static String get printerNotConnected => withLang(
        id: '❌ Printer belum terhubung!',
        en: '❌ Printer not connected!',
        ms: '❌ Pencetak belum disambung!',
      );

  // Settings
  static String get language => withLang(
        id: 'Bahasa',
        en: 'Language',
        ms: 'Bahasa',
        th: 'ภาษา',
        zh: '语言',
        ar: 'اللغة',
      );
  static String get notifPermission => withLang(
        id: 'Ijin Notifikasi',
        en: 'Notification Permission',
        ms: 'Kebenaran Notifikasi',
      );
  static String get notifDesc => withLang(
        id: 'Ijin dibutuhkan supaya aplikasi bisa menampilkan notifikasi',
        en: 'Permission needed so the app can show notifications',
        ms: 'Kebenaran diperlukan supaya aplikasi boleh memaparkan notifikasi',
      );
  static String get directPrint => withLang(
        id: 'Langsung Cetak',
        en: 'Direct Print',
        ms: 'Cetak Terus',
      );
  static String get directPrintDesc => withLang(
        id: 'Aplikasi akan langsung cetak ketika menerima data dari POS',
        en: 'App will print immediately when receiving data from POS',
        ms: 'Aplikasi akan terus mencetak apabila menerima data dari POS',
      );
  static String get printerConnection => withLang(
        id: 'Koneksi Printer',
        en: 'Printer Connection',
        ms: 'Sambungan Pencetak',
      );
  static String get printer =>
      withLang(id: 'Printer', en: 'Printer', ms: 'Pencetak');
  static String get printerSize => withLang(
        id: 'Ukuran Kertas',
        en: 'Paper Size',
        ms: 'Saiz Kertas',
      );
  static String get charsPerLine => withLang(
        id: 'Karakter per Baris',
        en: 'Characters per Line',
        ms: 'Aksara Setiap Baris',
      );
  static String get autoCut =>
      withLang(id: 'Auto Cut', en: 'Auto Cut', ms: 'Auto Cut');
  static String get autoCutDesc => withLang(
        id: 'Aktifkan jika printer memiliki pemotong otomatis',
        en: 'Enable if printer has auto cutter',
        ms: 'Aktifkan jika pencetak mempunyai pemotong automatik',
      );
  static String get extraFeed =>
      withLang(id: 'Extra Feed', en: 'Extra Feed', ms: 'Suapan Tambahan');
  static String get extraFeedDesc => withLang(
        id: 'Baris kosong tambahan setelah cetak agar mudah disobek',
        en: 'Extra blank lines after print for easy tear-off',
        ms: 'Baris kosong tambahan selepas cetak untuk mudah koyak',
      );
  static String get lines => withLang(id: 'baris', en: 'lines', ms: 'baris');
  static String get printQris => withLang(
        id: 'Cetak QRIS',
        en: 'Print QRIS',
        ms: 'Cetak QRIS',
      );
  static String get printQrisDesc => withLang(
        id: 'Cetak struk QRIS saat tombol Print QRIS ditekan',
        en: 'Print QRIS receipt when Print QRIS button is pressed',
        ms: 'Cetak resit QRIS apabila butang Cetak QRIS ditekan',
      );
  static String get cashDrawer => withLang(
        id: 'Cash Drawer',
        en: 'Cash Drawer',
        ms: 'Laci Tunai',
      );
  static String get cashDrawerDesc => withLang(
        id: 'Buka laci kasir secara otomatis',
        en: 'Automatically open the cash drawer',
        ms: 'Buka laci tunai secara automatik',
      );
  static String get cashDrawerOff => withLang(
        id: 'Nonaktif',
        en: 'Off',
        ms: 'Mati',
      );
  static String get cashDrawerOpenAfterPrint => withLang(
        id: 'Terbuka setelah cetak',
        en: 'Open after print',
        ms: 'Terbuka selepas cetak',
      );
  static String get cashDrawerOpenBeforePrint => withLang(
        id: 'Terbuka sebelum cetak',
        en: 'Open before print',
        ms: 'Terbuka sebelum cetak',
      );
  static String get cashDrawerOpened => withLang(
        id: 'Laci kasir terbuka!',
        en: 'Cash drawer opened!',
        ms: 'Laci tunai terbuka!',
      );
  static String get cashDrawerOnSessionSummary => withLang(
        id: 'Buka laci untuk Session Summary',
        en: 'Open drawer for Session Summary',
        ms: 'Buka laci untuk Session Summary',
      );
  static String get cashDrawerSessionSummaryOn => withLang(
        id: 'Ya, buka laci',
        en: 'Yes, open drawer',
        ms: 'Ya, buka laci',
      );
  static String get cashDrawerSessionSummaryOff => withLang(
        id: 'Tidak',
        en: 'No',
        ms: 'Tidak',
      );
  static String get version => withLang(
        id: 'Versi',
        en: 'Version',
        ms: 'Versi',
      );
  static String get selectPrinter => withLang(
        id: 'Pilih Printer...',
        en: 'Select Printer...',
        ms: 'Pilih Pencetak...',
      );
  static String get settingsSaved => withLang(
        id: 'Pengaturan disimpan!',
        en: 'Settings saved!',
        ms: 'Tetapan disimpan!',
      );
  static String get settingsCancelled => withLang(
        id: 'Perubahan dibatalkan',
        en: 'Changes cancelled',
        ms: 'Perubahan dibatalkan',
      );

  // Tabs
  static String get typeTextHere => withLang(
        id: 'Ketik teks di sini...',
        en: 'Type text here...',
        ms: 'Taip teks di sini...',
      );
  static String get size => withLang(
        id: 'Ukuran:',
        en: 'Size:',
        ms: 'Saiz:',
      );
  static String get printText => withLang(
        id: 'Cetak Teks',
        en: 'Print Text',
        ms: 'Cetak Teks',
      );
  static String get printing => withLang(
        id: 'Mencetak...',
        en: 'Printing...',
        ms: 'Mencetak...',
      );
  static String get tapToSelectImage => withLang(
        id: 'Ketuk untuk memilih gambar',
        en: 'Tap to select image',
        ms: 'Ketik untuk pilih imej',
      );
  static String get selectImage => withLang(
        id: 'Pilih Gambar',
        en: 'Select Image',
        ms: 'Pilih Imej',
      );
  static String get print_ => withLang(
        id: 'Cetak',
        en: 'Print',
        ms: 'Cetak',
      );
  static String get tapToSelectPdf => withLang(
        id: 'Ketuk untuk memilih PDF',
        en: 'Tap to select PDF',
        ms: 'Ketik untuk pilih PDF',
      );
  static String get selectPdf => withLang(
        id: 'Pilih PDF',
        en: 'Select PDF',
        ms: 'Pilih PDF',
      );
  static String get tapToChange => withLang(
        id: 'Ketuk untuk ganti file',
        en: 'Tap to change file',
        ms: 'Ketik untuk tukar fail',
      );
  static String get imageReadFail => withLang(
        id: '❌ Gagal membaca gambar',
        en: '❌ Failed to read image',
        ms: '❌ Gagal membaca imej',
      );

  // Statistics
  static String get statsTitle => withLang(
        id: 'Statistik Cetak',
        en: 'Print Statistics',
        ms: 'Statistik Cetak',
      );
  static String get totalPrinted => withLang(
        id: 'Total Dicetak',
        en: 'Total Printed',
        ms: 'Jumlah Dicetak',
      );
  static String get todayPrinted => withLang(
        id: 'Hari Ini',
        en: 'Today',
        ms: 'Hari Ini',
      );
  static String get successRate => withLang(
        id: 'Tingkat Sukses',
        en: 'Success Rate',
        ms: 'Kadar Kejayaan',
      );
  static String get dataSent => withLang(
        id: 'Data Terkirim',
        en: 'Data Sent',
        ms: 'Data Dihantar',
      );
  static String get printByType => withLang(
        id: 'Berdasarkan Jenis',
        en: 'By Type',
        ms: 'Mengikut Jenis',
      );
  static String get last7Days => withLang(
        id: '7 Hari Terakhir',
        en: 'Last 7 Days',
        ms: '7 Hari Lepas',
      );
  static String get printHistory => withLang(
        id: 'Riwayat Cetak',
        en: 'Print History',
        ms: 'Sejarah Cetak',
      );
  static String get allHistory => withLang(
        id: 'Semua Riwayat',
        en: 'All History',
        ms: 'Semua Sejarah',
      );
  static String get noHistoryYet => withLang(
        id: 'Belum ada riwayat cetak',
        en: 'No print history yet',
        ms: 'Belum ada sejarah cetak',
      );
  static String get successLabel => withLang(
        id: 'Berhasil',
        en: 'Success',
        ms: 'Berjaya',
      );
  static String get failedLabel => withLang(
        id: 'Gagal',
        en: 'Failed',
        ms: 'Gagal',
      );
  static String get receiptFull => withLang(
        id: 'Full Receipt',
        en: 'Full Receipt',
        ms: 'Full Receipt',
      );
  static String get receiptBasic => withLang(
        id: 'Basic Receipt',
        en: 'Basic Receipt',
        ms: 'Basic Receipt',
      );
  static String get sessionSummary => withLang(
        id: 'Session Summary',
        en: 'Session Summary',
        ms: 'Session Summary',
      );
  static String get textPrint => withLang(
        id: 'Text Print',
        en: 'Text Print',
        ms: 'Text Print',
      );
  static String get imagePrint => withLang(
        id: 'Image Print',
        en: 'Image Print',
        ms: 'Image Print',
      );
  static String get pdfPrint => withLang(
        id: 'PDF Print',
        en: 'PDF Print',
        ms: 'PDF Print',
      );
  static String get testPrintLabel => withLang(
        id: 'Test Print',
        en: 'Test Print',
        ms: 'Test Print',
      );

  // Settings - Reset Data
  static String get resetData => withLang(
        id: 'Reset Data',
        en: 'Reset Data',
        ms: 'Set Semula Data',
      );
  static String get resetDataDesc => withLang(
        id: 'Hapus semua riwayat cetak dan pengaturan untuk mengosongkan memori',
        en: 'Clear all print history and settings to free memory',
        ms: 'Padam semua sejarah cetak dan tetapan untuk mengosongkan memori',
      );
  static String get resetConfirmTitle => withLang(
        id: 'Reset Semua Data?',
        en: 'Reset All Data?',
        ms: 'Set Semula Semua Data?',
      );
  static String get resetConfirmMsg => withLang(
        id: 'Semua riwayat cetak, log aktivitas, dan pengaturan akan dihapus. Tindakan ini tidak bisa dibatalkan.',
        en: 'All print history, activity logs, and settings will be deleted. This action cannot be undone.',
        ms: 'Semua sejarah cetak, log aktiviti, dan tetapan akan dipadam. Tindakan ini tidak boleh dibatalkan.',
      );
  static String get resetButton => withLang(
        id: 'Hapus Semua',
        en: 'Delete All',
        ms: 'Padam Semua',
      );
  static String get resetSuccess => withLang(
        id: '✅ Semua data berhasil dihapus',
        en: '✅ All data cleared successfully',
        ms: '✅ Semua data berjaya dipadam',
      );
  static String get source => withLang(
        id: 'Sumber',
        en: 'Source',
        ms: 'Sumber',
      );
  static String get overview => withLang(
        id: 'Ringkasan',
        en: 'Overview',
        ms: 'Ringkasan',
      );

  // Hardcoded strings from screens
  static String get serverAlreadyRunning => withLang(
        id: 'Server sudah berjalan',
        en: 'Server already running',
        ms: 'Pelayan sudah berjalan',
      );
  static String get serverStartFailed => withLang(
        id: 'Gagal mengaktifkan layanan',
        en: 'Failed to activate service',
        ms: 'Gagal mengaktifkan perkhidmatan',
      );
  static String get refreshed => withLang(
        id: 'Disegarkan',
        en: 'Refreshed',
        ms: 'Disegarkan',
      );
  static String get noPrinterSelected => withLang(
        id: 'Belum ada printer',
        en: 'No printer',
        ms: 'Tiada pencetak',
      );
  static String get versionLabel => withLang(
        id: 'Versi',
        en: 'Version',
        ms: 'Versi',
      );
  static String get license => withLang(
        id: 'Lisensi',
        en: 'License',
        ms: 'Lesen',
      );
  static String get close => withLang(
        id: 'Tutup',
        en: 'Close',
        ms: 'Tutup',
      );
  static String get statistics => withLang(
        id: 'Statistik',
        en: 'Statistics',
        ms: 'Statistik',
        th: 'สถิติ',
        zh: '统计',
        ar: 'إحصائيات',
      );
  static String get totalPrintedLabel => withLang(
        id: 'Total Dicetak',
        en: 'Total Printed',
        ms: 'Jumlah Dicetak',
      );
  static String get paper => withLang(
        id: 'Kertas',
        en: 'Paper',
        ms: 'Kertas',
      );
  static String get chars => withLang(
        id: 'Karakter',
        en: 'Chars',
        ms: 'Aksara',
      );
  static String get printStatistics => withLang(
        id: 'Statistik Cetak',
        en: 'Print Statistics',
        ms: 'Statistik Cetak',
      );
  static String get recentPrintActivity => withLang(
        id: 'Aktivitas Cetak Terbaru',
        en: 'Recent Print Activity',
        ms: 'Aktiviti Cetak Terbaru',
      );
  static String get filterByDate => withLang(
        id: 'Filter tanggal',
        en: 'Filter by date',
        ms: 'Tapis tarikh',
      );

  // Scan screen
  static String get selectPrinterTitle => withLang(
        id: 'Pilih Printer',
        en: 'Select Printer',
        ms: 'Pilih Pencetak',
      );
  static String get loadingDevices => withLang(
        id: 'Memuat perangkat...',
        en: 'Loading devices...',
        ms: 'Memuatkan peranti...',
      );
  static String get bluetoothActive => withLang(
        id: 'Bluetooth Aktif',
        en: 'Bluetooth Active',
        ms: 'Bluetooth Aktif',
      );
  static String get bluetoothInactive => withLang(
        id: 'Bluetooth Nonaktif',
        en: 'Bluetooth Inactive',
        ms: 'Bluetooth Tidak Aktif',
      );
  static String get showingDevices => withLang(
        id: 'Menampilkan %d perangkat',
        en: 'Showing %d devices',
        ms: 'Menunjukkan %d peranti',
      );
  static String get noDevicesFound => withLang(
        id: 'Tidak ada perangkat ditemukan',
        en: 'No devices found',
        ms: 'Tiada peranti dijumpai',
      );
  static String get ensurePrinterPaired => withLang(
        id: 'Pastikan printer sudah di-pair dengan perangkat ini',
        en: 'Make sure the printer is paired with this device',
        ms: 'Pastikan pencetak sudah dipadankan dengan peranti ini',
      );
  static String get paired => withLang(
        id: 'Tersambung',
        en: 'Paired',
        ms: 'Dipadankan',
      );

  // Pair Printer screen
  static String get pairPrinterTitle => withLang(
        id: 'Printer',
        en: 'Printer',
        ms: 'Pencetak',
      );
  static String get printerMenu => withLang(
        id: 'Printer',
        en: 'Printer',
        ms: 'Pencetak',
      );
  static String get pairPrinterDescription => withLang(
        id: 'Daftarkan printer Bluetooth baru ke perangkat ini.',
        en: 'Register a new Bluetooth printer with this device.',
        ms: 'Daftarkan pencetak Bluetooth baru ke peranti ini.',
      );
  static String get openBluetoothSettings => withLang(
        id: 'Buka Pengaturan Bluetooth',
        en: 'Open Bluetooth Settings',
        ms: 'Buka Tetapan Bluetooth',
      );
  static String get bluetoothOffHint => withLang(
        id: 'Bluetooth nonaktif. Aktifkan Bluetooth untuk melihat perangkat.',
        en: 'Bluetooth is off. Turn on Bluetooth to see devices.',
        ms: 'Bluetooth tidak aktif. Hidupkan Bluetooth untuk melihat peranti.',
      );
  static String get pairInstructions => withLang(
        id: 'Buka Pengaturan Bluetooth untuk pairing printer, lalu kembali ke sini dan tekan Refresh.',
        en: 'Open Bluetooth Settings to pair your printer, then come back and tap Refresh.',
        ms: 'Buka Tetapan Bluetooth untuk memadankan pencetak, kemudian kembali dan tekan Refresh.',
      );
  static String get pairNewPrinter => withLang(
        id: 'Pair Printer Baru',
        en: 'Pair New Printer',
        ms: 'Pasangkan Pencetak Baru',
      );
  static String get pairedDevicesTitle => withLang(
        id: 'Perangkat Tersambung',
        en: 'Paired Devices',
        ms: 'Peranti Dipadankan',
      );
  static String get tabPaired => withLang(
        id: 'Tersambung',
        en: 'Paired',
        ms: 'Dipadankan',
      );
  static String get tabAvailable => withLang(
        id: 'Tersedia',
        en: 'Available',
        ms: 'Tersedia',
      );
  static String get deletePrinter => withLang(
        id: 'Hapus',
        en: 'Delete',
        ms: 'Padam',
      );
  static String get confirmDeleteTitle => withLang(
        id: 'Hapus Printer?',
        en: 'Delete Printer?',
        ms: 'Padam Pencetak?',
      );
  static String get confirmDeleteMessage => withLang(
        id: 'Printer akan dihapus dari daftar tersambung. Anda dapat pair ulang kapan saja dari tab Tersedia.',
        en: 'This printer will be removed from the paired list. You can re-pair anytime from the Available tab.',
        ms: 'Pencetak akan dipadamkan daripada senarai dipadankan. Anda boleh memadankan semula bila-bila dari tab Tersedia.',
      );
  static String get scanDevices => withLang(
        id: 'Pindai',
        en: 'Scan',
        ms: 'Imbas',
      );
  static String get stopScan => withLang(
        id: 'Berhenti',
        en: 'Stop',
        ms: 'Berhenti',
      );
  static String get scanningHint => withLang(
        id: 'Sedang memindai perangkat di sekitar...',
        en: 'Scanning for nearby devices...',
        ms: 'Mengimbas peranti berhampiran...',
      );
  static String get scanCompleteHint => withLang(
        id: 'Pemindaian selesai. Geser ke bawah untuk menyegarkan.',
        en: 'Scan complete. Pull to refresh.',
        ms: 'Imbasan selesai. Tarik untuk segarkan.',
      );
  static String get pair => withLang(
        id: 'Pasangkan',
        en: 'Pair',
        ms: 'Pasangkan',
      );
  static String get pairing => withLang(
        id: 'Mem-pair...',
        en: 'Pairing...',
        ms: 'Sedang memadankan...',
      );
  static String get noPairedPrinters => withLang(
        id: 'Belum ada printer tersambung',
        en: 'No paired printers yet',
        ms: 'Belum ada pencetak dipadankan',
      );
  static String get noAvailablePrinters => withLang(
        id: 'Belum ada perangkat tersedia',
        en: 'No available devices',
        ms: 'Tiada peranti tersedia',
      );
  static String get tapScanToStart => withLang(
        id: 'Tekan Pindai untuk mencari printer baru',
        en: 'Tap Scan to find new printers',
        ms: 'Tekan Imbas untuk mencari pencetak baru',
      );
  static String get unpairFailed => withLang(
        id: 'Gagal menghapus pairing. Coba lagi atau buka Pengaturan Bluetooth.',
        en: 'Failed to unpair. Try again or open Bluetooth Settings.',
        ms: 'Gagal memadamkan padanan. Cuba lagi atau buka Tetapan Bluetooth.',
      );
  static String get pairFailed => withLang(
        id: 'Gagal melakukan pairing. Coba lagi.',
        en: 'Failed to pair. Try again.',
        ms: 'Gagal memadankan. Cuba lagi.',
      );

  // Printer Screen
  static String get bluetoothRequired => withLang(
        id: 'Bluetooth belum aktif. Aktifkan Bluetooth untuk memindai printer.',
        en: 'Bluetooth is not active. Turn on Bluetooth to scan for printers.',
        ms: 'Bluetooth belum aktif. Aktifkan Bluetooth untuk mengimbas pencetak.',
      );
  static String get locationRequiredForScan => withLang(
        id: 'Aktifkan Lokasi di Pengaturan untuk memindai Bluetooth.',
        en: 'Turn on Location in Settings to scan for Bluetooth devices.',
        ms: 'Aktifkan Lokasi di Tetapan untuk mengimbas peranti Bluetooth.',
      );
  static String get bluetoothNeedsPermission => withLang(
        id: 'Bluetooth Perlu Izin',
        en: 'Bluetooth Needs Permission',
        ms: 'Bluetooth Perlu Kebenaran',
      );
  static String get bluetoothNeedsPermissionDesc => withLang(
        id: 'Aktifkan Bluetooth & Lokasi untuk memindai printer.',
        en: 'Turn on Bluetooth & Location to scan for printers.',
        ms: 'Aktifkan Bluetooth & Lokasi untuk mengimbas pencetak.',
      );
  static String get savedPrinters => withLang(
        id: 'Printer Tersimpan',
        en: 'Saved Printers',
        ms: 'Pencetak Tersimpan',
      );
  static String get noSavedPrinters => withLang(
        id: 'Belum ada printer tersimpan',
        en: 'No saved printers yet',
        ms: 'Belum ada pencetak tersimpan',
      );
  static String get noSavedPrintersDesc => withLang(
        id: 'Pindai untuk menemukan dan menyimpan printer baru.',
        en: 'Scan to discover and save new printers.',
        ms: 'Imbas untuk menjumpai dan menyimpan pencetak baharu.',
      );
  static String get printerDeleted => withLang(
        id: 'Printer dihapus:',
        en: 'Printer removed:',
        ms: 'Pencetak dipadamkan:',
      );
  static String get discoveredDevices => withLang(
        id: 'Perangkat Terdeteksi',
        en: 'Discovered Devices',
        ms: 'Peranti Dikesan',
      );
  static String get found => withLang(
        id: 'ditemukan',
        en: 'found',
        ms: 'dijumpai',
      );
  static String get readyToScan => withLang(
        id: 'Siap Memindai',
        en: 'Ready to Scan',
        ms: 'Sedia Mengimbas',
      );
  static String get readyToScanDesc => withLang(
        id: 'Tekan "Mulai Pindai" untuk mencari printer Bluetooth di sekitar.',
        en: 'Tap "Start Scan" to find Bluetooth printers nearby.',
        ms: 'Tekan "Mula Imbas" untuk mencari pencetak Bluetooth berhampiran.',
      );
  static String get startScan => withLang(
        id: 'Mulai Pindai',
        en: 'Start Scan',
        ms: 'Mula Imbas',
      );
  static String get openSettings => withLang(
        id: 'Buka Pengaturan',
        en: 'Open Settings',
        ms: 'Buka Tetapan',
      );
  static String get scan => withLang(
        id: 'Pindai',
        en: 'Scan',
        ms: 'Imbas',
      );
  static String get printerSuccessfullyPaired => withLang(
        id: 'Printer berhasil dipairkan:',
        en: 'Printer paired successfully:',
        ms: 'Pencetak berjaya dipadankan:',
      );
  static String get printerRegistered => withLang(
        id: 'Terdaftar',
        en: 'Registered',
        ms: 'Berdaftar',
      );

  // Log screen
  static String get fullLog => withLang(
        id: 'Log Lengkap',
        en: 'Full Log',
        ms: 'Log Penuh',
      );
  static String get copyAllLogs => withLang(
        id: 'Salin semua log',
        en: 'Copy all logs',
        ms: 'Salin semua log',
      );
  static String get logsCopied => withLang(
        id: 'Log disalin!',
        en: 'Logs copied!',
        ms: 'Log disalin!',
      );

  // Text tab
  static String get typeTextFirst => withLang(
        id: 'Ketik teks terlebih dahulu',
        en: 'Type text first',
        ms: 'Taip teks terlebih dahulu',
      );
  static String get alignLeft => withLang(
        id: 'Rata Kiri',
        en: 'Align Left',
        ms: 'Rata kiri',
      );
  static String get center => withLang(
        id: 'Rata Tengah',
        en: 'Center',
        ms: 'Tengah',
      );
  static String get right => withLang(
        id: 'Rata Kanan',
        en: 'Right',
        ms: 'Kanan',
      );
  static String get justify => withLang(
        id: 'Rata Kiri Kanan',
        en: 'Justify',
        ms: 'Kiri Kanan',
      );
  static String get bold => withLang(
        id: 'Tebal',
        en: 'Bold',
        ms: 'Tebal',
      );
  static String get italic => withLang(
        id: 'Miring',
        en: 'Italic',
        ms: 'Condong',
      );
  static String get deleteAll => withLang(
        id: 'Hapus Semua?',
        en: 'Delete All?',
        ms: 'Padam Semua?',
      );
  static String get deleteAllConfirm => withLang(
        id: 'Semua teks yang sudah diketik akan dihapus.',
        en: 'All typed text will be deleted.',
        ms: 'Semua teks yang diketik akan dipadam.',
      );
  static String get touchToEnterText => withLang(
        id: 'Sentuh masukan text',
        en: 'Tap to enter text',
        ms: 'Sentuh masuk teks',
      );

  // Test print card
  static String get shortReceiptPrint => withLang(
        id: 'Struk Pendek',
        en: 'Short Receipt',
        ms: 'Resit Pendek',
      );
  static String get fullReceiptPrint => withLang(
        id: 'Struk Lengkap',
        en: 'Full Receipt',
        ms: 'Resit Lengkap',
      );

  // Port card
  static String get portLabel => withLang(
        id: 'Port',
        en: 'Port',
        ms: 'Port',
      );

  // Onboarding Permissions
  static String get backgroundPermissionTitle => withLang(
        id: 'Izinkan Mulai Otomatis di Latar Belakang',
        en: 'Allow Auto-Start in Background',
        ms: 'Benarkan Mula Automatik di Latar Belakang',
      );
  static String get backgroundPermissionDesc => withLang(
        id: 'Agar printer tetap aktif saat aplikasi di-minimize, aktifkan "Mulai otomatis di latar belakang" di pengaturan aplikasi.',
        en: 'To keep the printer active when the app is minimized, enable "Auto-start in background" in app settings.',
        ms: 'Untuk memastikan pencetak kekal aktif apabila aplikasi di-minimize, aktifkan "Mula automatik di latar belakang" dalam tetapan aplikasi.',
      );
  static String get backgroundPermissionBtn => withLang(
        id: 'Buka Pengaturan Aplikasi',
        en: 'Open App Settings',
        ms: 'Buka Tetapan Aplikasi',
      );
  static String get backgroundActive => withLang(
        id: 'Mulai otomatis aktif',
        en: 'Auto-start active',
        ms: 'Mula automatik aktif',
      );
  static String get backgroundNotActive => withLang(
        id: 'Mulai otomatis belum aktif',
        en: 'Auto-start not active',
        ms: 'Mula automatik belum aktif',
      );
  static String get permissionOnboardingTitle => withLang(
        id: 'Izin yang Diperlukan',
        en: 'Required Permissions',
        ms: 'Kebenaran yang Diperlukan',
      );
  static String get permissionBluetooth => withLang(
        id: 'Bluetooth',
        en: 'Bluetooth',
        ms: 'Bluetooth',
      );
  static String get permissionBluetoothDesc => withLang(
        id: 'Untuk menghubungkan printer thermal via Bluetooth',
        en: 'To connect thermal printer via Bluetooth',
        ms: 'Untuk menyambung pencetak terma melalui Bluetooth',
      );
  static String get permissionLocation => withLang(
        id: 'Lokasi',
        en: 'Location',
        ms: 'Lokasi',
      );
  static String get permissionLocationDesc => withLang(
        id: 'Diperlukan untuk scan perangkat Bluetooth (Android 5+)',
        en: 'Required to scan Bluetooth devices (Android 5+)',
        ms: 'Diperlukan untuk mengimbas peranti Bluetooth (Android 5+)',
      );
  static String get permissionNotification => withLang(
        id: 'Notifikasi',
        en: 'Notifications',
        ms: 'Notifikasi',
      );
  static String get permissionNotificationDesc => withLang(
        id: 'Untuk menampilkan status printer dan print job',
        en: 'To show printer status and print job notifications',
        ms: 'Untuk memaparkan status pencetak dan notifikasi cetakan',
      );
  static String get permissionBackground => withLang(
        id: 'Latar Belakang',
        en: 'Background',
        ms: 'Latar Belakang',
      );
  static String get permissionBackgroundDesc => withLang(
        id: 'Agar printer tetap aktif saat app di-minimize',
        en: 'To keep printer active when app is minimized',
        ms: 'Untuk memastikan pencetak kekal aktif apabila aplikasi diminimize',
      );
  static String get permissionGrantAll => withLang(
        id: 'Izinkan Semua',
        en: 'Grant All',
        ms: 'Benarkan Semua',
      );
  static String get permissionSkip => withLang(
        id: 'Lewati',
        en: 'Skip',
        ms: 'Lewati',
      );
  static String get permissionGranted => withLang(
        id: 'Izin diberikan',
        en: 'Permission granted',
        ms: 'Kebenaran diberikan',
      );
  static String get permissionDone => withLang(
        id: 'Selesai',
        en: 'Done',
        ms: 'Selesai',
      );
  static String get permissionDenied => withLang(
        id: 'Izin belum diberikan',
        en: 'Permission not granted',
        ms: 'Kebenaran belum diberikan',
      );
}
