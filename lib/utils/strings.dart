import 'package:shared_preferences/shared_preferences.dart';

class S {
  static String _lang = 'Indonesia';
  static String get lang => _lang;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _lang = p.getString('language') ?? 'Indonesia';
  }

  static Future<void> setLang(String l) async {
    _lang = l;
    final p = await SharedPreferences.getInstance();
    await p.setString('language', l);
  }

  static bool get isEn => _lang == 'English';

  // ── App ──
  static String get appName => 'dRetail Printer Manager';

  // ── Nav & Titles ──
  static String get home => isEn ? 'Home' : 'Beranda';
  static String get freeText => isEn ? 'Free Text' : 'Text Bebas';
  static String get printImage => isEn ? 'Print Image' : 'Cetak Gambar';
  static String get printPdf => isEn ? 'Print PDF' : 'Cetak PDF';
  static String get settings => isEn ? 'Settings' : 'Pengaturan';
  static String get activityHistory =>
      isEn ? 'Activity History' : 'Riwayat Aktivitas';
  static String get aboutApp => isEn ? 'About App' : 'Tentang Aplikasi';
  static String get exit => isEn ? 'Exit' : 'Keluar';

  // ── Home ──
  static String get printerActive => isEn ? 'Printer Active' : 'Printer Aktif';
  static String get printerInactive =>
      isEn ? 'Printer Inactive' : 'Printer Tidak Aktif';
  static String get tapToCopy =>
      isEn ? 'Tap URL to copy' : 'Ketuk URL untuk menyalin';
  static String get pressToActivate => isEn
      ? 'Press printer button to activate'
      : 'Tekan tombol printer untuk mengaktifkan';
  static String get urlCopied => isEn ? 'URL copied' : 'URL disalin';
  static String get noPrinter => isEn ? 'No printer' : 'Belum ada printer';
  static String get connected => isEn ? 'Connected' : 'Terhubung';
  static String get notConnected => isEn ? 'Not connected' : 'Belum terhubung';
  static String get selectPrinterFirst =>
      isEn ? 'Select printer first' : 'Pilih printer dulu';
  static String get change => isEn ? 'Change' : 'Ganti';
  static String get select => isEn ? 'Pilih' : 'Pilih';
  static String get receiptsPrinted =>
      isEn ? 'Receipts Printed' : 'Struk Dicetak';
  static String get paperSize => isEn ? 'Paper Size' : 'Ukuran Kertas';
  static String get portHttpServer =>
      isEn ? 'HTTP Server Port' : 'Port HTTP Server';
  static String get save => isEn ? 'Save' : 'Simpan';
  static String get cancel => isEn ? 'Cancel' : 'Batal';
  static String get testPrint => isEn ? 'Test Print' : 'Test Print';
  static String get shortReceipt =>
      isEn ? 'Print Short Receipt' : 'Cetak Struk Pendek';
  static String get fullReceipt =>
      isEn ? 'Print Full Receipt' : 'Cetak Struk Lengkap';
  static String get sending => isEn ? 'Sending...' : 'Mengirim...';
  static String get activity => isEn ? 'Activity' : 'Aktivitas';
  static String get viewAll => isEn ? 'View all' : 'Lihat semua';
  static String get noActivity =>
      isEn ? 'No activity yet' : 'Belum ada aktivitas';
  static String get autoStart => isEn ? 'Auto Start' : 'Aktifkan Otomatis';
  static String get autoStartDesc => isEn
      ? 'Printer activates when app opens'
      : 'Printer langsung aktif saat app dibuka';
  static String get portSaved => isEn ? 'Port saved' : 'Port disimpan';
  static String get portInvalid =>
      isEn ? 'Port must be 1024–65535' : 'Port harus 1024–65535';
  static String get selectPrinterToast =>
      isEn ? 'Select a printer first' : 'Pilih printer terlebih dahulu';
  static String get printerConnectFail =>
      isEn ? '❌ Printer connection failed' : '❌ Gagal menghubungkan printer';
  static String get printerConnected => isEn
      ? '✅ Printer connected via Bluetooth'
      : '✅ Printer terhubung via Bluetooth';
  static String get printerReady =>
      isEn ? 'Printer ready!' : 'Printer siap digunakan!';
  static String get serverReady =>
      isEn ? '🚀 Ready to receive from POS' : '🚀 Siap menerima print dari POS';
  static String get printerStopped =>
      isEn ? '⏹️ Printer deactivated' : '⏹️ Printer dinonaktifkan';
  static String get printerSelected =>
      isEn ? 'Printer selected' : 'Printer dipilih';
  static String printSuccess(String l) =>
      isEn ? '✅ $l printed!' : '✅ $l berhasil dicetak!';
  static String get printFail => isEn ? '❌ Print failed.' : '❌ Gagal mencetak.';
  static String get reconnecting =>
      isEn ? '🔄 Reconnecting...' : '🔄 Menghubungkan ulang...';
  static String get printerDisconnected =>
      isEn ? '❌ Printer disconnected!' : '❌ Printer terputus!';
  static String get printerNotConnected =>
      isEn ? '❌ Printer not connected!' : '❌ Printer belum terhubung!';

  // ── Settings ──
  static String get language => isEn ? 'Language' : 'Bahasa';
  static String get notifPermission =>
      isEn ? 'Notification Permission' : 'Ijin Notifikasi';
  static String get notifDesc => isEn
      ? 'Permission needed so the app can show notifications'
      : 'Ijin dibutuhkan supaya aplikasi bisa menampilkan notifikasi';
  static String get directPrint => isEn ? 'Direct Print' : 'Langsung Cetak';
  static String get directPrintDesc => isEn
      ? 'App will print immediately when receiving data from POS'
      : 'Aplikasi akan langsung cetak ketika menerima data dari POS';
  static String get printerConnection =>
      isEn ? 'Printer Connection' : 'Koneksi Printer';
  static String get printer => isEn ? 'Printer' : 'Printer';
  static String get printerSize => isEn ? 'Paper Size' : 'Ukuran Kertas';
  static String get charsPerLine =>
      isEn ? 'Characters per Line' : 'Karakter per Baris';
  static String get autoCut => isEn ? 'Auto Cut' : 'Auto Cut';
  static String get autoCutDesc => isEn
      ? 'Enable if printer has auto cutter'
      : 'Aktifkan jika printer memiliki pemotong otomatis';
  static String get extraFeed => isEn ? 'Extra Feed' : 'Extra Feed';
  static String get extraFeedDesc => isEn
      ? 'Extra blank lines after print for easy tear-off'
      : 'Baris kosong tambahan setelah cetak agar mudah disobek';
  static String get lines => isEn ? 'lines' : 'baris';
  static String get version => isEn ? 'Version' : 'Versi';
  static String get selectPrinter =>
      isEn ? 'Select Printer...' : 'Pilih Printer...';
  static String get settingsSaved =>
      isEn ? 'Settings saved!' : 'Pengaturan disimpan!';
  static String get settingsCancelled =>
      isEn ? 'Changes cancelled' : 'Perubahan dibatalkan';

  // ── Tabs ──
  static String get typeTextHere =>
      isEn ? 'Type text here...' : 'Ketik teks di sini...';
  static String get size => isEn ? 'Size:' : 'Ukuran:';
  static String get printText => isEn ? 'Print Text' : 'Cetak Teks';
  static String get printing => isEn ? 'Printing...' : 'Mencetak...';
  static String get tapToSelectImage =>
      isEn ? 'Tap to select image' : 'Ketuk untuk memilih gambar';
  static String get selectImage => isEn ? 'Select Image' : 'Pilih Gambar';
  static String get print_ => isEn ? 'Print' : 'Cetak';
  static String get tapToSelectPdf =>
      isEn ? 'Tap to select PDF' : 'Ketuk untuk memilih PDF';
  static String get selectPdf => isEn ? 'Select PDF' : 'Pilih PDF';
  static String get tapToChange =>
      isEn ? 'Tap to change file' : 'Ketuk untuk ganti file';
  static String get imageReadFail =>
      isEn ? '❌ Failed to read image' : '❌ Gagal membaca gambar';
}
