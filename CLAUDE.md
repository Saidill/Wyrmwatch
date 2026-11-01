# Aturan kerja untuk Claude di repo ini

## Proyek

- App ini sedang dikembangkan dari "Claude Usage" menjadi **Notchwyrm**: notch app produktivitas dengan modul Pomodoro, Claude Usage, Apple Music, dan info dasar.
- Spesifikasi lengkap ada di `docs/PRD.md`. Baca dulu sebelum mulai, dan kerjakan milestone berurutan (1 sampai 6).
- Rename teknis (target Swift, executable, `CFBundleName`, `CFBundleIdentifier` → `com.saidilhalim.notchwyrm`, ikon, README) dikerjakan di milestone 6, bukan di awal, supaya refactor dan rename tidak tercampur dalam satu diff.
- Kalau ada keputusan yang tidak dijawab PRD, pilih opsi paling sederhana, catat di bagian "Pertanyaan terbuka" PRD, lalu lanjut.

## Git

- Jangan pernah commit langsung ke `main`. Pengembangan berjalan di `feat/notch-hub`, dan setiap milestone di branch turunannya (`feat/m1-module-refactor`, `feat/m2-virtual-notch`, `feat/m3-pomodoro`, `feat/m4-apple-music`, `feat/m5-info`, `feat/m6-polish`).
- Auto commit: setiap satu langkah selesai dan `swift build` lulus, langsung commit tanpa menunggu diminta.
- Format pesan commit: Conventional Commits (`feat:`, `refactor:`, `fix:`, `docs:`, `chore:`), bahasa Inggris, satu baris ringkas, plus body kalau perlu.
- Tanpa atribusi Claude: jangan tambahkan `Co-Authored-By: Claude`, link sesi Claude, atau "Generated with Claude Code" di commit maupun deskripsi PR.
- Author commit: `saidilhalim <saidilhalim@mail.ugm.ac.id>`.

## Build dan cek

- `swift build` harus lulus sebelum commit.
- Setelah perubahan di notch atau tampilan, jalankan self-test kalau bisa: `./scripts/build-app.sh && ./ClaudeUsage.app/Contents/MacOS/ClaudeUsage --selftest /tmp/claude-usage-test`.

## Desain

- Semua animasi memakai token di `Motion` (`Views/Theme.swift`), jangan membuat kurva baru.
- Window notch tidak boleh di-resize. Yang dianimasikan hanya shape di dalamnya.
- Animasi berulang wajib berhenti saat notch tertutup atau tidak terlihat.
