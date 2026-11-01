# Progress Notchwyrm

Ringkasan per milestone: apa yang dibuat dan apa yang perlu dicek manual.

## M1 · Refactor ke modul (`feat/m1-module-refactor`)

**Dibuat**
- Folder baru: `App/`, `Core/`, `Modules/Claude/`, `Notch/`, `Views/` (masih di `Sources/ClaudeUsage`, rename di M6).
- `Core/NotchModule.swift` (protokol + `NotchPop`), `PriorityResolver`, `PopQueue` (antrean Pomodoro → Claude → musik, tahan saat hover, tidak pop saat expanded), `ModuleRegistry`.
- `ClaudeModule`: prioritas 2 (sesi busy), 3 (limit ≥ 90%), 5 (limit ≥ batas peringatan). Live row dan pop "finished" dipindah ke modul ini.
- `NotchModel.state` kini dihitung dari registry dan antrean pop (bukan `busy: Bool`).
- Token `Motion` lengkap (`open`, `close`, `contentIn`, `contentOut`, `liveIn`, `smooth`, `quick`, `popIn`, `slide`, `reduced`). `dragonPaused` → `animationsPaused`.
- Self-test: cek resolver, urutan antrean pop, pop tampil dan bisa diklik.

**Perubahan perilaku kecil (sesuai PRD)**
- Notch kini juga live saat limit sesi ≥ 90% atau ≥ batas peringatan walau tidak ada sesi busy (naga mode idle).
- Ring mini: silver < 80%, amber 80–90%, rose ≥ 90%, berdenyut sekali tiap 4 detik di atas 90%.

**Cek manual**
- Jalankan sesi Claude: notch live (naga working + ring), lalu pop "finished" dengan Jump.
- Hover di pop: pop tetap terbuka; lepas: tertutup setelah ±1 detik.

## M2 · Notch virtual (`feat/m2-virtual-notch`)

**Dibuat**
- `Notch/VirtualNotch.swift`: `notchSize`, `virtualNotchSize` (185 × tinggi menu bar), `displayID`.
- `NotchWindowController` kini mengelola satu panel per layar (`NotchScreen` per panel) dengan satu `NotchModel` bersama. `expandedOn` menyimpan layar yang sedang terbuka, jadi hanya satu layar yang bisa expanded.
- Notch virtual saat closed berupa pil 120 × 6 pt (tanpa flare). Zona hover selebar notch virtual, hanya di strip paling atas.
- `DisplayMode`: Auto, Notch, Menu bar, Semua layar. Auto = satu notch di layar menu bar (asli atau virtual).
- Panel untuk layar yang dicabut ditutup dan dilepas (`orderOut` + `close`), bukan disembunyikan.
- Notch virtual disembunyikan saat ada jendela fullscreen app lain di layar itu (deteksi via `CGWindowListCopyWindowInfo`), kecuali modul aktif adalah Pomodoro.
- Tombol header "notch / menu bar" kini selalu tampil (notch virtual selalu tersedia).
- Self-test: satu panel per layar, ukuran window tetap, pil closed, live, open di satu layar saja, pop, kembali ke satu panel.

**Cek manual**
- Colok/cabut monitor eksternal di mode Auto dan Semua layar: notch tidak hilang dan tidak dobel.
- Hover di pil notch virtual: terbuka dengan kurva open. Klik menu bar di sekitarnya tetap tembus.
- Buka app fullscreen (misalnya Safari ⌃⌘F) di monitor eksternal: notch virtual hilang, kembali saat keluar fullscreen.
- Catatan: satu kali self-test gagal di "popover opens from the menu bar icon" (lulus di dua run berikutnya). Kemungkinan karena klik mouse sungguhan saat tes berjalan (popover menutup saat ada klik global).

## M3 · Pomodoro Ember (`feat/m3-pomodoro`)

**Dibuat**
- `PomodoroTimer`: fase fokus / istirahat pendek / istirahat panjang (tiap 4 sesi), disimpan sebagai `endDate` di UserDefaults dan dipulihkan saat restart. Satu `Timer` di `endDate` (bukan per detik), dicek ulang saat Mac bangun (`didWakeNotification`). Fase yang habis saat app mati diselesaikan saat launch.
- Kontrol: mulai, pause, reset, lewati. Preset 25/5, 50/10, dan Custom (dari Settings). Statistik harian: jumlah sesi dan menit fokus.
- `PomodoroModule` (prioritas 1 saat berjalan atau di-pause):
    - Live: naga mood baru `.guarding` (fokus) atau `.sleeping` (istirahat) di kiri, sisa waktu `TimelineView(.periodic)` + `.numericText()` di kanan.
    - `EmberFuse`: sumbu 1,5 pt di tepi bawah notch, tergambar dari tengah dalam 0,5 detik (`Motion.fuse`), memendek ke tengah, bara berkedip di kedua ujung. Amber saat fokus, silver-biru (`Palette.frost`) saat istirahat.
    - Pause: semua meredup 40% dan tidak ada animasi.
    - 10 detik terakhir: angka putih, scale 1 → 1,06 → 1 tiap detik.
    - Pop "Focus done" (naga mengaum, titik bara baru scale-in, Start break / Skip) dan "Ready to focus again?" (naga bangun, Focus / Later). Haptic `.levelChange` + suara. Di mode menu bar dikirim sebagai notifikasi.
    - Kartu expanded (`EmberRing` dengan bara di ujung busur, 4 titik bara, kontrol, statistik, chip preset). Kartu tampil di baris kartu di atas tab, di notch maupun popover menu bar.
- Settings → Pomodoro: durasi fokus, istirahat pendek dan panjang, suara, haptic.
- Hook baru di protokol: `liveAccent()` untuk elemen selebar notch live (sumbu).
- Self-test: prioritas di atas Claude, pause tidak bergerak, akhir fase (statistik, bara, pop), istirahat selesai, pemulihan setelah restart, fase yang habis saat app mati. State Pomodoro asli dikembalikan setelah tes.

**Cek manual**
- Mulai fokus, tidurkan Mac 10 menit, bangunkan: sisa waktu meleset < 1 detik dan pop muncul kalau fase sudah habis.
- Quit app saat timer berjalan, buka lagi: timer lanjut.
- Rasakan haptic di trackpad saat fase selesai (Force Touch).
- Sinkron Apple Music belum ada (dikerjakan di M4).
