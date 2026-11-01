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

## M6 · Polishing (`feat/m6-polish`), rename belum

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

**Self-test M6**: 3 kegagalan sebelumnya ("song pop goes away…", "charger pop goes away…", "no pop without a new plug-in") ternyata karena faktor lingkungan. Kursor sungguhan berada di atas notch, dan pop ditahan saat hover. Self-test kini mengabaikan hover asli untuk antrean pop, dan hasilnya `ALL PASSED`. M6 (tanpa rename) di-merge ke `feat/notch-hub`, lalu `feat/notch-hub` ke `main`.

## Revisi desain 1 Nov 2026 (`feat/wyrm`, `feat/expanded-redesign`)

**Alur Git baru**: branch pendek per fitur dari `main`, merge ke `main` + push setelah `swift build` dan `--selftest` lulus (lihat CLAUDE.md). `feat/notch-hub` (M1–M6) sudah di-merge ke `main`.

**Maskot**
- Versi ular ramping (wyrm bergelombang) sempat dibuat, lalu dibatalkan atas permintaan karena kepala naga lebih disukai.
- Kepala naga kini memakai palet navy `#0B1E3F` / biru `#4FA3FF` / cyan `#7FE3FF` dengan api biru (`Views/Wyrm.swift`, `WyrmView`). Mood: sleeping, idle, working, happy (api biru), guarding (fokus). Maks. 30 fps (15 untuk mood tenang), berhenti saat notch tertutup.
- Sumbu, bara, titik sesi, sorotan playlist, dan ikon kalender kini biru. Amber dan rose hanya untuk peringatan usage.

**Panel expanded baru (600 × ±200 pt, sama di semua halaman)**
- Header di pita sebelah kamera: kepala naga, tanggal, jam, acara berikutnya | tab bar Fokus / Musik / Claude / Settings (tab terakhir disimpan).
- Fokus: mode Atur (Klasik 25/5, Dalam 50/10, Custom; stepper Fokus 5–90 step 5, Istirahat 1–30, Sesi 1–8; field tugas; Mulai) dan mode Jalan (angka besar, "Fokus n/N · tugas", titik sesi, sumbu api biru selebar panel, +5 mnt, Pause, Lewati, Stop). Ring bulat dihapus.
- Musik: tiga kolom (cover 120 pt | judul, artis · album, progress, shuffle/prev/play/next/repeat | playlist scroll sendiri, lagu aktif biru). Shuffle dan repeat dibaca dan diatur lewat AppleScript.
- Claude: Plan limits | Sessions / Recent / Usage.
- Settings: tab Settings yang sudah ada.
- Baterai dan pop "Charging" dihapus. Info hanya untuk acara kalender berikutnya.
- Pop kini 320 × (tinggi notch + 58), pas satu baris. Sebelumnya 340 × +70 dengan ruang kosong.
- Popover menu bar: kartu Fokus dan Now Playing ditumpuk vertikal, dan halaman Fokus menyesuaikan lebar.
- Label halaman Fokus dan pop Pomodoro dalam bahasa Indonesia, sesuai permintaan. Halaman lain masih Inggris (dicatat di PRD).

**Self-test**: snapshot setiap halaman (`16-focus-setup`, `16-focus-running`, `19-music-page`, `20-claude-page`, `20-settings-page`), ukuran panel sama di semua tab, +5 mnt, Stop → Atur, pengaturan tersimpan, jumlah sesi menentukan istirahat panjang. Hasil: `ALL PASSED`.

**Cek manual**
- Ketik tugas di field halaman Fokus (panel notch harus menerima ketikan), lalu Enter untuk mulai.
- Shuffle dan repeat di halaman Musik sinkron dengan Music.app.
- Proporsi pop di notch asli dan virtual.

**Masih terbuka**: anggaran CPU live/expanded (lihat bagian M6), rename ke Notchwyrm, dan keputusan bahasa UI.

## Redesign ala Boring Notch / DynamicNotch (`feat/red-dragon-theme`, `feat/notch-home`)

Hanya polanya yang dipelajari: notch hitam, Home berisi player + timer, tab yang meluncur. Tidak ada kode yang disalin, karena keduanya GPL v3.

**Naga dan tema** (`feat/red-dragon-theme`)
- Maskot lama (kepala naga biru) dan `Wyrm.swift` dihapus. Penggantinya `Views/Dragon.swift`: kepala naga merah bergaya ikon (sisik bergradasi, tanduk gading, sirip leher, tanduk hidung, mata amber). Responsif terhadap hover (kepala terangkat, mata menyala). Mood: tidur, siaga, kerja, selesai (api), fokus. Maks. 30 fps, berhenti saat tersembunyi.
- Ikon app kini naga merah yang sama, digambar oleh binary (`--render-icon`) saat `build-app.sh`. `make-icon.swift` lama dihapus.
- Tema baru sesuai spesifikasi: `#000`, teks `#F2F3F5`, sekunder `#8D9096`, track `#2A2B2F`, silver `#C9CDD3`, silver terang `#D5D8DD`, tombol `#3A3D44` / `#24262B`, garis `#1C1D20`. Aksen biru dihapus.
- Tafsiran: kalimat terpotong "jangan lupa iunutk …" dianggap "jangan lupa ikon app".

**Notch** (`feat/notch-home`)
- Header dibelah kamera: [naga + "Min 1 Nov · 18.52" | lebar notch | 4 tab ikon custom (Home, Fokus, Musik, Claude) 17 pt di tombol 38 × 26, kapsul aktif meluncur].
- Home 96 pt: [cover 96 dengan glow | judul/artis + visualizer, waktu | progress | durasi, 5 tombol | garis | Fokus + Claude]. "Putar musik" saat musik mati, dan chip 25/5 · 50/10 · Atur saat Pomodoro berhenti.
- Fokus: [tombol bulat 42 | keterangan + +5 mnt / Lewati / Stop | waktu 50 pt] + progres. Mode Atur tetap.
- Musik: cover 120 + playlist (judul | durasi, aktif putih).
- Claude: bar Sesi | Minggu + forecast, lalu Now / Recent / Usage. ⚙︎ membuka Settings (tab Settings tidak ada lagi).
- Tinggi notch mengikuti isi tab (`Motion.resize`, spring 0.45 / 0.78). Isi tab fade + geser 5 pt. Cover memakai `matchedGeometryEffect` antara live dan Home. Window tetap 640 × 330.
- Live: naga kecil (Claude), cover + visualizer (musik), waktu silver (Pomodoro). Pomodoro dan musik bergantian tiap 6 detik.
- Musik: favorit (hati) dan "Putar musik" lewat AppleScript (`favorited`, fallback `loved`).

**Self-test**: screenshot setiap tab di notch asli dan virtual (`tab-<tab>-real/virtual.png`), Home dengan Pomodoro berjalan dan tanpa musik, cek tidak ada view yang overlap atau keluar panel (frame dibandingkan lewat `LayoutProbe`), cek Home 96 pt dan Musik lebih tinggi (tinggi mengikuti tab), dan cek live bergantian. Hasil: `ALL PASSED`.

**Cek manual**
- Hover naga di header: kepala terangkat.
- Tombol hati di Home ikut berubah di Music.app.
- "Putar musik" saat Music tertutup: Music terbuka dan mulai memutar.
- Animasi cover live ↔ Home saat notch dibuka.
- Ketik tugas di halaman Fokus.

**Masih terbuka**: anggaran CPU live/expanded, rename ke Notchwyrm, tempat acara kalender berikutnya (sekarang tooltip), dan bahasa UI campuran.

**Koreksi**: `feat/notch-home` sempat ter-merge ke `main` (13dc967) padahal self-test gagal 1 ("dragon moves in the menu bar header"). Penyebabnya, skrip runner self-test lokal mengembalikan exit code 0 walau ada FAIL, jadi rantai `&&` tidak berhenti. Skrip sudah diperbaiki (gagal kalau report tidak `ALL PASSED`). Kegagalan itu menunjukkan bug nyata: popover menu bar lebih tinggi dari layar, karena kartu Fokus penuh ditambah Now Playing, sehingga header terdorong keluar. Diperbaiki di `fix/popover-height`: popover kini memakai kartu Fokus ringkas (sama dengan kolom kanan Home), dan setup penuh hanya muncul lewat "Atur". Self-test `ALL PASSED`.

## Naga baru, performa stabil, bahasa Inggris (`perf/stable-cpu`)

**Performa** (diukur dengan `scripts/measure-perf.sh`, sekarang juga menghitung perubahan publisher dan redraw)
- Temuan: SwiftUI hanya me-redraw 1–3 kali per 15 detik, jadi biaya CPU datang dari animasi berulang SwiftUI (TimelineView/Canvas). Setiap frame membuat panel ikut dirender ulang. Live Pomodoro 14% walau semua animasi dimatikan, karena sumbu dan animasi angka per detik.
- Perbaikan: naga diam di notch live, sumbu dihapus, angka live tanpa animasi per detik, dan visualizer serta naga animasi dipindah ke **Core Animation** (`CALayer`, `CABasicAnimation`, `CAEmitterLayer` untuk api), yang berjalan di render server.
- Hasil: closed 0,19%, live Pomodoro 0,55%, live Claude 0,19%, live musik 0,17%, expanded (musik) 1,57%, expanded idle 0,70%. Memori 27–40 MB. **Semua dalam anggaran PRD.**

**Naga**: memakai ikon "Spiked dragon head" (Delapouite, game-icons.net, CC BY 3.0, atribusi di README) yang diwarnai merah, dengan animasi halus (napas, glow, mata, api partikel, "z"). Naga gambar tangan dihapus.

**Pomodoro**: garis sumbu di notch live (yang menimpa naga) diganti cincin progres kecil di samping waktu. Halaman Focus memakai skala tick seperti piringan jam (tick ke-5 lebih tinggi, tick aktif lebih terang), bukan garis polos.

**Lainnya**: tab Settings kembali (tab ke-5, ikon gear custom, tombol 36 × 26 supaya 5 tab muat), ⚙︎ di halaman Claude dihapus, dan semua teks UI berbahasa Inggris.

**Self-test**: `ALL PASSED`. Cek "dragon moves" kini memeriksa animasi Core Animation yang aktif. Reduce Motion memastikan tidak ada animasi.

**Cek manual**: hover naga di header, api saat sesi Claude selesai (pop), dan CPU di Activity Monitor saat musik diputar.

## Istirahat otomatis, alarm, api dari mulut (`feat/pomodoro-autobreak`)

- Fokus habis: istirahat langsung berjalan, dihitung dari saat fokus habis. Setelah sleep atau restart, sisa waktunya tetap tepat. Kalau istirahat juga sudah lewat, timer kembali ke setup.
- Alarm singkat (dua kali tiga bip C6, ±1,2 detik, dibuat di memori seperti chime) di akhir fokus dan akhir istirahat. Haptic tetap ada.
- Pop "Focus done" kini menampilkan "Break 5:00" yang menghitung mundur dan tombol "Skip break". Tombol "Start break" dihapus karena istirahat sudah berjalan.
- Api naga keluar dari celah rahang (0,85; 0,665), bukan dari bawah moncong. Api animasi kini dua lapis partikel (inti putih-panas + tubuh oranye ke merah) yang sedikit mengarah ke bawah. Api diam (Reduce Motion) berupa satu semburan utuh, bukan bulatan terpisah.
- Self-test: istirahat berjalan sendiri (298 detik tersisa), istirahat tampil di live, fokus yang habis saat app tertutup masuk istirahat dengan waktu yang benar, fokus dan istirahat yang sama-sama lewat kembali ke setup. Hasil: `ALL PASSED`.
- Cek manual: dengarkan alarm di akhir fokus, dan lihat api saat sesi Claude selesai.
