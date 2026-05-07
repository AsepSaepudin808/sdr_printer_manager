# TODO - Maksimalkan Pengaturan Aplikasi + Multi Bahasa

- [ ] Refactor `lib/utils/strings.dart`:
  - [ ] Ubah model bahasa dari 2-bahasa menjadi kode locale (`id`, `en`, `ms`, `th`, `zh`, `ar`)
  - [ ] Tambahkan daftar bahasa terstruktur (nama native + kode)
  - [ ] Buat helper translasi yang scalable untuk semua getter `S.*`
  - [ ] Pertahankan kompatibilitas pemanggilan existing
- [ ] Update `lib/screens/settings_screen.dart`:
  - [ ] Ganti dropdown bahasa menjadi multi-bahasa (6 bahasa)
  - [ ] Gunakan `S.*` (hapus ketergantungan helper `tr(...)` lokal 2-bahasa)
  - [ ] Pastikan perubahan bahasa tersimpan dan ter-apply realtime
- [ ] Jalankan validasi
  - [ ] `flutter analyze`
  - [ ] `flutter run` (sanity check)
