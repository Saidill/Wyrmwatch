# Aturan kerja untuk Claude di repo ini

## Proyek

- App ini bernama **Wyrmwatch** (dulu "Claude Usage", sempat direncanakan "Notchwyrm"): notch app produktivitas dengan modul Pomodoro, Claude Usage, Apple Music, dan info dasar.
- Spesifikasi lengkap ada di `docs/PRD.md`. Baca dulu sebelum mulai, dan kerjakan milestone berurutan (1 sampai 6).
- Rename ke Wyrmwatch sudah selesai (target `Wyrmwatch`, bundle id `com.saidilhalim.wyrmwatch`). Rename berikutnya tetap dikerjakan di branch tersendiri, terpisah dari perubahan fitur.
- Kalau ada keputusan yang tidak dijawab PRD, pilih opsi paling sederhana, catat di bagian "Pertanyaan terbuka" PRD, lalu lanjut.

## Git

- Kerja di branch pendek per fitur dari `main` (misalnya `feat/wyrm`, `fix/pop-timing`), jangan commit langsung ke `main`.
- Setelah `swift build` dan `--selftest` lulus (`ALL PASSED`), merge branch fitur ke `main` (`git merge --no-ff`), lalu push `main` dan branch fiturnya ke `origin`.
- Kalau self-test gagal, jangan merge. Perbaiki dulu di branch fitur.
- Auto commit: setiap satu langkah selesai dan `swift build` lulus, langsung commit tanpa menunggu diminta.
- Format pesan commit: Conventional Commits (`feat:`, `refactor:`, `fix:`, `docs:`, `chore:`), bahasa Inggris, satu baris ringkas, plus body kalau perlu.
- Tanpa atribusi Claude: jangan tambahkan `Co-Authored-By: Claude`, link sesi Claude, atau "Generated with Claude Code" di commit maupun deskripsi PR.
- Author commit: `saidilhalim <saidilhalim@mail.ugm.ac.id>`.

## Build dan cek

- `swift build` harus lulus sebelum commit.
- Setelah perubahan di notch atau tampilan, jalankan self-test kalau bisa: `./scripts/build-app.sh && ./Wyrmwatch.app/Contents/MacOS/Wyrmwatch --selftest /tmp/wyrmwatch-test`.

## Desain

- Semua animasi memakai token di `Motion` (`Views/Theme.swift`), jangan membuat kurva baru.
- Window notch tidak boleh di-resize. Yang dianimasikan hanya shape di dalamnya.
- Animasi berulang wajib berhenti saat notch tertutup atau tidak terlihat.

## Cara kerja per fitur

1. Sebelum menulis kode untuk fitur baru, kirim dulu rencana singkat:
   - apakah bisa dengan API publik macOS, dan seberapa stabil
   - izin sistem apa yang dibutuhkan (Accessibility, Automation, dll)
   - risiko dan batasan, plus alternatif yang lebih sederhana
   Tunggu persetujuan sebelum mulai coding.
2. Hindari Accessibility/UI scripting ke app lain kecuali disetujui eksplisit.
   Utamakan AppleScript, notifikasi sistem, atau API resmi.
3. Aturan keamanan tetap untuk semua fitur yang menyentuh app lain:
   - hanya berinteraksi dengan app target (cek bundle ID)
   - tidak membaca isi text field / search field
   - berhenti seketika kalau konteks berubah (klik lain, window berubah)
   - tidak menyimpan data Accessibility ke file atau log
   - tidak ada fallback yang menekan tombol "kira-kira"
4. Satu fitur selesai (build + self-test lulus + dicek manual) baru lanjut fitur lain.
5. Jangan install build baru di tengah pengujian yang butuh izin sistem.