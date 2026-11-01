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

## M4 · Apple Music (`feat/m4-apple-music`)

**Hasil uji awal `current playlist` (via osascript dari terminal)**
- Playlist library ("cok", 62 lagu, `user playlist`): terbaca. Nama, artis, dan durasi semua lagu diambil dalam satu perintah. `index of current track` cocok dengan posisi di playlist.
- Notifikasi `com.apple.Music.playerInfo` membawa judul, artis, album, persistent ID, durasi, dan status, tapi **tidak** membawa posisi. Posisi dibaca sekali lewat AppleScript saat panel dibuka.
- Radio / lagu katalog di luar library: **belum diuji** (lihat cek manual).

**Dibuat**
- `MusicBridge`: perubahan lagu dan play/pause lewat `DistributedNotificationCenter` (tanpa polling). AppleScript (`NSAppleScript` di antrean background) hanya untuk cover, posisi saat panel dibuka, kontrol, seek, playlist sekali ambil, dan memutar lagu ke-N. Tidak pernah menjalankan AppleScript kalau Music tidak terbuka (supaya tidak meluncurkannya). Error -1743 memunculkan tombol "Give access" yang membuka System Settings → Automation.
- `ArtworkCache`: cache cover per lagu (40 item) + warna dominan dari gambar 8×8 untuk aksen tipis di kartu.
- `MusicModule` (prioritas 4 saat musik diputar): cover 18 pt di kiri, visualizer 4 batang (Canvas, maks. 30 fps, berhenti saat pause atau tidak terlihat) di kanan. Pop ganti lagu 2,5 detik.
- Kartu Now Playing: cover 56 pt, judul, artis, progress yang bisa digeser, previous/play-pause/next. Daftar lagu masuk dengan `Motion.slide` setelah hover 400 ms atau klik ikon daftar. Lagu aktif disorot (visualizer amber) dan di-scroll ke tengah, klik untuk memutar. Ada teks fallback kalau daftar kosong.
- Sinkron Pomodoro ↔ Music (default nonaktif): fokus mulai = play, istirahat mulai atau fokus selesai = pause.
- Settings → Music (pop ganti lagu, daftar saat hover) dan toggle sinkron di Pomodoro. Teks `NSAppleEventsUsageDescription` diperbarui.
- Baris kartu: Pomodoro dan Now Playing berdampingan, lebar dan tinggi sama.
- Self-test memakai data palsu (tanpa AppleScript, tanpa notifikasi asli): live, pop, kartu, daftar, daftar kosong, posisi lokal, sinkron Pomodoro. Pengaturan dipulihkan persis seperti sebelum tes.

**Penyimpangan dari PRD**
- Cover tidak memakai `matchedGeometryEffect` antara live dan expanded. Isi expanded selalu ada di hierarki (hanya disembunyikan), jadi dua view dengan id yang sama akan bentrok. Penggantinya: crossfade cover ±0,3 detik (`Motion.smooth`) saat lagu berganti.
- Daftar lagu memakai `LazyVStack` untuk seluruh playlist (baris hanya dibuat saat terlihat), bukan jendela manual 50 lagu. Data sudah diambil sekaligus dalam satu perintah, jadi hasilnya setara.

**Cek manual**
- App sendiri akan meminta izin Automation → Music saat pertama kali dijalankan (izin terminal tidak ikut). Klik Allow.
- Ganti lagu di Music.app: notch berubah < 0,5 detik dan pop muncul.
- Klik lagu di daftar: langsung diputar. Geser progress: posisi pindah.
- Putar radio atau lagu katalog di luar library: daftar menampilkan "Song list isn't available for this source." (atau isi kalau Music menyediakannya).
- Tolak izin di System Settings → Automation: kartu menampilkan tombol "Give access".

## M5 · Info dasar (`feat/m5-info`)

**Dibuat**
- `BatteryMonitor`: persen, charging, dan status colokan lewat `IOPSNotificationCreateRunLoopSource` (tanpa polling).
- `CalendarSource`: EventKit `requestFullAccessToEvents`. Acara berikutnya (bukan seharian, belum selesai, dalam 24 jam) diperbarui lewat `EKEventStoreChanged` dan saat notch dibuka. Kalau izin ditolak, baris kalender disembunyikan tanpa pesan.
- `InfoModule` (tidak pernah mengambil notch live): baris info di bawah header (tanggal, jam via `TimelineView(.everyMinute)`, ikon baterai, acara berikutnya "in 25m" / jam mulai). Pop "Charging" 2 detik saat charger dicolok (bisa dimatikan di Settings → Info).
- `NSCalendarsFullAccessUsageDescription` di Info.plist.
- Mode `--diagnose <file>`: membaca Music, kalender, dan baterai dengan izin app sendiri, lalu menulis laporan.
- Self-test: baris header, pop charger muncul dan hilang setelah 2 detik, tidak ada pop tanpa colokan baru.

**Hasil `--diagnose` dengan izin asli (1 Nov 2026)**
- Music (radio / lagu katalog): judul, artis, cover, dan posisi terbaca. Daftar lagu: **unavailable**, jadi teks fallback yang tampil (sesuai risiko di PRD).
- Kalender: full access diberikan, tidak ada acara dalam 24 jam ke depan.
- Baterai: 41%, tidak dicolok.
- Catatan: kalau app dijalankan langsung sebagai child process terminal, prompt Kalender tidak muncul. Lewat `open` / Finder, prompt muncul normal.

**Cek manual**
- Colok charger: pop "Charging" + persen selama 2 detik.
- Buat acara 30 menit lagi di Calendar: muncul di baris info dalam beberapa detik.
- Tolak akses Kalender di System Settings: baris kalender hilang tanpa pesan error.

## M6 · Polishing dan rename (`feat/m6-polish`), BELUM SELESAI

**Sudah dibuat**
- Reduce Motion (sistem + "Always reduce motion" di Settings): spring jadi fade 0,2 detik, semua animasi berulang berhenti. Diverifikasi self-test (0 piksel berubah).
- Settings dalam 6 tab (Display, Modules, Pomodoro, Music, Claude, System). Modul bisa dimatikan dan diurutkan dengan drag. Opsi buka notch hanya dengan klik.
- `--perf` + `scripts/measure-perf.sh`: CPU dan memori per state.
- **Perbaikan CPU besar:** panel penuh kini hanya dibangun saat notch terbuka. Dulu panel tersembunyi ikut menggambar ulang naga setiap kali file sesi Claude berubah. CPU closed turun dari ±22% ke **0,1%**. Build lama di `main` juga memakan ±50% CPU saat ada sesi Claude aktif.

**Hasil ukur terakhir (M-series, sesi Claude aktif)**: closed 0,1–0,3% ✅ · live Pomodoro 11% ❌ (tetap 10% tanpa animasi, jadi penyebabnya bukan animasi) · live Claude 7,6% ❌ · live music 5,4% ❌ · expanded 21–26% ❌ (budget < 2% live, < 5% expanded).

**Sisa pekerjaan**
1. Cari penyebab CPU di state live/expanded. Petunjuk dari `sample`: hampir tidak ada kode app di stack. Ada blur vImage dan rasterisasi CoreGraphics, jadi kemungkinan ada invalidasi berulang dari luar animasi (cek publish `SessionMonitor`/`UsageTracker`). Perlu Instruments.
2. Rename ke Notchwyrm (folder target, executable, bundle id `com.saidilhalim.notchwyrm`, ikon, README, .gitignore, CLAUDE.md) + migrasi UserDefaults dari `com.saidilhalim.claudeusage`.
3. Merge M6 ke `feat/notch-hub` dan ringkasan akhir.

**Catatan**: kalau `--perf` dihentikan paksa, ia bisa meninggalkan `motion.forceReduce` dan state Pomodoro di UserDefaults. Hapus dengan `defaults delete com.saidilhalim.claudeusage motion.forceReduce`.

**Self-test terakhir di `feat/m6-polish`: 3 FAILED** ("song pop goes away after 2.5 s", "charger pop goes away after 2 s", "no pop without a new plug-in"). Pop tidak hilang tepat waktu. Belum diselidiki: bisa karena kursor sungguhan berada di atas notch (pop ditahan saat hover), atau regresi dari perubahan M6. Karena itu M6 **belum di-merge** ke `feat/notch-hub`.
