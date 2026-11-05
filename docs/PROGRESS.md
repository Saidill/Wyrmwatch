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

## Performa dengan transkrip Claude Code yang besar (`perf/usage-scan`)

Pengukuran ulang menemukan dua masalah baru:
- **Saat launch, CPU ±24% selama ±2 menit dan memori 145 MB.** `UsageTracker` membaca 126 MB transkrip 8 hari terakhir sekaligus per file (`readToEnd`), dan mem-parse JSON setiap baris yang memuat kata "usage" (banyak sekali di repo ini). Diperbaiki: baca per 4 MB dengan autorelease pool per chunk, dan hanya parse baris yang memuat `"type":"assistant"` dan `"usage":{` (683 dari 683 baris assistant tetap terbaca). Scan token di latar kini tiap 60 detik (sebelumnya 15). Saat notch atau popover dibuka tetap langsung refresh.
- **Tab Claude ±20% CPU.** Ikon "working" di daftar sesi memakai `.symbolEffect(.pulse)`, animasi SwiftUI berulang yang mengabaikan status tersembunyi dan Reduce Motion. Diganti tiga titik Core Animation.
- `--perf` kini juga mengukur setiap tab.

Hasil (sesi Claude ini aktif selama pengukuran): closed ±0,1–1%, live 0,9–1,8%, expanded 1,2–3,2%, memori 23–40 MB. Live dan expanded di dalam anggaran. Closed sedikit di atas 0,5% saat ada aktivitas latar (file sesi Claude yang terus ditulis, monitor mouse saat mouse digerakkan), dan 0,06–0,2% saat tenang.

## Musik dari luar library (`fix/music-streaming`)

- **Respons tertunda**: lagu streaming Apple Music atau radio (kelas `URL track`) dikirim Music lewat notifikasi `playerInfo` **tanpa `PersistentID`**, hanya Name, Artist, Album, Total Time, dan Player State (sudah dicek dengan listener). Bridge mengabaikan notifikasi itu sampai tab Music membaca pemutar lewat AppleScript. Kini ID cadangan memakai Store URL atau judul + artis + album. Setiap ganti lagu memicu satu pembacaan AppleScript (bukan polling) untuk melengkapi ID asli, posisi, favorit, shuffle/repeat, dan cover. Pause pada lagu stream tidak dianggap lagu baru.
- **Daftar lagu kosong**: untuk lagu streaming, Music tidak menyediakan `current playlist` lewat AppleScript ("Can't get current playlist"), dan antrean Up Next memang tidak bisa dibaca app lain. Teks di tab Music kini menjelaskan hal ini.
- Self-test: notifikasi stream tanpa ID langsung tampil, pause stream tetap lagu yang sama. Hasil: `ALL PASSED`.

## Daftar album untuk lagu streaming (`feat/album-lookup`)

- Lagu streaming tidak punya daftar lagu dari Music, jadi tab Musik kini mencari albumnya di iTunes Search API Apple (`search?entity=album`, lalu `lookup?entity=song`, negara mengikuti region Mac). Prosesnya di latar, dengan timeout 5 detik dan cache per album. Hanya artis dan nama album yang dikirim. Saat mencari tampil tiga titik Core Animation ("Finding the album…"), tanpa biaya CPU.
- Lagu aktif dicocokkan dengan mengabaikan huruf besar/kecil dan tambahan dalam kurung seperti "(Remastered)", lalu di-scroll ke tengah. Klik lagu membuka lagu itu di Music.
- Bisa dimatikan di Settings → Music ("Look up the album of streamed songs").
- Diuji nyata lewat `--diagnose --album-test`: 14 lagu dari "Strange Foreign Beauty". Self-test memakai album palsu (tanpa jaringan): `ALL PASSED`.
- Cek manual: putar lagu Apple Music di luar library, buka tab Music, lalu klik salah satu lagu album (Music membukanya, tapi mungkin tidak langsung memutar).

## Daftar sesuai konteks untuk lagu streaming (`feat/stream-context`)

- Music.app tidak memberi tahu dari mana lagu streaming diputar, dan antreannya tidak bisa dibaca. Konteks kini ditebak dari lagu sebelumnya: album yang sama → Album, artis yang sama dengan album lain → Top songs artis itu, artis lain → Recent (riwayat sesi). Ada switch Album · Top songs · Recent untuk mengganti manual.
- Top songs: iTunes Search (`entity=song&attribute=artistTerm`, sudah diurutkan menurut popularitas), versi duplikat seperti "(Remastered)" dibuang, maks. 15 lagu. Diuji nyata: "Paint My Love", "That's Why (You Go Away)", "The Actor", "Sleeping Child", "Take Me To Your Heart".
- Ringan: riwayat diperbarui hanya saat ganti lagu, dan hanya daftar yang tampil yang diambil, di latar, dengan cache per album atau artis. Loading memakai titik Core Animation. Tepi daftar diberi fade statis.
- Self-test: aturan tebakan (4 kasus), Top songs tampil setelah lagu artis yang sama dari album lain, dan daftar tidak menimpa cover.
- Cek manual: putar Top Songs seorang artis di Apple Music, lalu buka tab Music setelah lagu kedua (tebakan butuh satu lagu sebelumnya).

## Memutar lagu dari daftar katalog (`fix/play-from-list`)

- Investigasi: lagu playlist adalah objek track milik Music.app (`play track N of current playlist`). Album, Top songs, dan Recent berasal dari iTunes Search API dan hanya berupa ID katalog plus link. Kamus AppleScript Music tidak punya properti ID katalog, dan `play` hanya menerima track atau file. Lima variasi link `music://` / `itmss://` hanya membuka halaman. `SystemMusicPlayer` (MusicKit) ditandai `@available(macOS, unavailable)`, `MPMusicPlayerController` ditandai `API_UNAVAILABLE(macos)`, dan menelusuri antrean dengan `next track`/`previous track` tidak andal untuk stream.
- Keputusan akhir pengguna: **lagu di library** diputar langsung lewat AppleScript (diuji: "Multo"), dan **lagu katalog** hanya dibuka halamannya di Music tanpa menekan apa pun. Lagu dari Recent dicari dulu link katalognya. Baris status di bawah daftar: "Playing …" atau "Opened … in Music".
- Fitur Accessibility (menekan tombol Play di Music) sempat dibuat dan diperketat, lalu **dihapus seluruhnya**: `MusicUI`, penekanan tombol, `--inspect-music`, `--play-test`, dan teks permintaan izin. Tidak ada sertifikat signing yang dibuat.
- Cek manual: hapus ClaudeUsage dari System Settings → Privacy & Security → Accessibility (izin itu tidak dipakai lagi).
- Masih terbuka: daftar Top songs dibatasi 15 lagu (data tersedia ±30 dari 40 hasil), dan isinya peringkat pencarian Apple, bukan daftar Top Songs Apple Music yang persis.

## Layout kartu, slot maskot Rive, rename ke Wyrmwatch (`feat/card-redesign`, `feat/rename-wyrmwatch`)

**Cek kelayakan (langkah 0)**
- Status Claude live **bisa**. Alat terakhir dan file yang disentuh dibaca dari ±200 KB terakhir transkrip (file 32 MB tidak dibaca utuh). Saat Claude menunggu izin atau jawaban, file sesi menulis `status: "waiting"` (dikonfirmasi di binary Claude Code). Temuan sampingan: app sebelumnya menganggap `waiting` sebagai "selesai" dan memunculkan pop palsu. Sekarang sudah diperbaiki.
- RiveRuntime (rive-ios 6.x) **bisa** di-build lewat SPM untuk macOS 14. Bentuknya framework dinamis 14 MB (arm64 + x86_64) yang di-embed di `Contents/Frameworks`. Tanpa `wyrm.riv` tidak ada biaya CPU, karena view Rive tidak dibuat. Biaya saat memutar baru bisa diukur setelah file maskot ada. API `RiveViewModel` yang dipakai ditandai deprecated di 6.x.

**Dibuat**
- Token desain baru, header 3 kolom (tab ikon | slot maskot | pill + jam), Home 3 kartu 118 pt, Focus (Pomodoro/Countdown + grid preset 3 × 2), Music (cover card + info card + playlist library), Claude (3 angka besar + Now/Recent/Usage).
- Settings pindah ke klik kanan notch (menu Settings… / Quit, jendela Settings sendiri).
- Mode Countdown (05:00, 15:00, custom) dengan pop "Time's up". Preset baru 90/15.
- `WyrmSlot` memutar `Resources/wyrm.riv` kalau ada. Tanpa file itu slot kosong dan notch live menampilkan titik status (merah berdenyut = working, putih = waiting).
- Naga lama dan ikon game-icons.net dihapus. Ikon app baru: notch hitam dengan titik merah.
- **Dihapus**: daftar Album/Top songs/Recent katalog (`AlbumLookup`, stream context, `CatalogPlayer`), karena lagu katalog tidak bisa diputar langsung. App tidak lagi menghubungi iTunes Search API.
- Rename ke **Wyrmwatch**: target, executable, folder `Sources/Wyrmwatch`, bundle ID `com.saidilhalim.wyrmwatch`, README dengan tagline baru. Pengaturan lama disalin sekali dari `com.saidilhalim.claudeusage`. `--install` menutup ClaudeUsage lama dan memindahkan app lamanya ke Trash.
- Self-test: cek overlap kini mengabaikan view yang bersarang (kartu yang memuat isinya). Hasil: `ALL PASSED`.

**Cek manual**
- Izin Music (Automation), Kalender, dan akses Keychain untuk token Claude Code akan diminta lagi sekali karena bundle ID baru.
- Klik kanan notch → Settings…
- Status Claude saat menunggu izin: titik putih dan "waiting", tanpa pop "finished".
- Remote git lokal masih menunjuk `claude-usage-ui`. GitHub sudah mengalihkan ke `Saidill/Wyrmwatch`, tapi perintah `git remote set-url` tidak dijalankan karena diblokir pengecekan izin.

## Identitas Wyrmwatch: adapter now playing, maskot, elemen khas, Focus, desain (`feat/wyrmwatch-identity`)

**A. mediaremote-adapter (riset dan keputusan)**
- Lisensi **BSD 3-Clause** (aman untuk dipakai dan didistribusikan; teks lisensi wajib ikut, jadi disalin ke `Contents/Resources/mediaremote-adapter-LICENSE`).
- Diuji di Mac ini (macOS 27.0.1): `test` lulus, `get` dan `stream` membaca Apple Music. Adapter didesain untuk macOS 15.4 ke atas, tempat MediaRemote hanya bisa dibaca proses bertanda tangan Apple. Karena itu adapter berjalan di `/usr/bin/perl`.
- Tanpa izin sistem. `stream` memakai 0,03 detik CPU saat mulai, lalu 0,00 selama 20 detik diam, dengan RSS 19 MB.
- Bisa: judul, artis, album, durasi, posisi, status putar, cover, dan bundle ID app sumber; play/pause, next, previous, seek. Tidak bisa: playlist, favorit.
- **Keputusan:** dipakai sebagai sumber untuk semua pemutar **selain** Apple Music. Apple Music tetap lewat notifikasi + AppleScript (`MusicBridge`), karena hanya jalur itu yang memberi playlist, favorit, shuffle, dan repeat, dan notifikasinya sudah instan. Kalau adapter tidak ada (build tanpa CMake) atau prosesnya mati lebih dari 5 kali, app tetap jalan dengan Apple Music saja.
- Di-vendor di `Vendor/mediaremote-adapter` (tag v0.7.7, tanpa perubahan) dan dibangun `build-app.sh` dengan CMake (hanya saat sumbernya berubah).

**B. Maskot**
- 8 kandidat (CC0/CC BY/MIT/Apache; yang lisensinya tidak jelas ditandai) ada di `assets/candidates/` dengan `README.md` dan `preview.png`. Rive Community dan LottieFiles butuh login, jadi hanya link-nya yang dicatat.
- Dipasang sebagai maskot **sementara**: Tabler "dragon" (MIT), digambar ulang per bagian di `Views/WyrmArt.swift`: mata berkedip, kepala menoleh ke kursor dengan spring, rahang membuka + api saat "done". Kini kepala juga mengikuti kursor tanpa file Rive. Spring tidak jalan saat Reduce Motion atau saat tidak ada kursor yang diikuti.

**C. Tiga elemen khas**: Ember Edge (Core Animation, maks. 30 fps, berhenti saat notch tertutup), wyrm di sarangnya, scale bar (sisik 8 pt, stagger 20 ms). Kartu aktif mendapat tepi 1 pt `#3A3A3C`.

**D. Focus**
- Pomodoro: preset 25/5, 50/10, 90/15 + Custom (fokus 1–180, istirahat 1–60, istirahat panjang 1–60, sesi 1–12).
- Timer: durasi jam:menit:detik (ketik atau scroll), preset 5/10/15/30 menit, +1/+5 saat berjalan, selesai dengan suara + notifikasi/pop berlabel.
- Nama tugas: kolom "What are you working on?" + 5 chip terakhir, nama di kartu waktu (bisa diedit di tempat), di notch live (bergantian dengan waktu), dan di pop selesai. Riwayat hari ini per tugas, disimpan lokal 30 hari (`TaskLog`).
- Sayap notch live dilebarkan dari 50 ke 64 pt supaya nama tugas muat.

**E–F. Desain**
- 5 ukuran teks dan 2 ketebalan di notch dan popover, grid 4 pt, tanpa emoji, sapaan dekoratif, shimmer, atau pill yang mengulang tab. Settings tidak diubah (`CardTitle` dan ukuran teksnya tetap).
- Tiga ronde kritik dari screenshot self-test, ditulis di `docs/DESIGN-REVIEW.md`. Temuan yang berupa bug: sesi yang menunggu tampil sebagai "Done", dan Timer menampilkan durasi Pomodoro sebelum dimulai.

**Self-test**
- Baru: riwayat tugas, Timer (detik tepat, +1/+5, pop berlabel), sumber pemutar lain (data adapter tiruan), status Claude idle/working/waiting (sesi tiruan), Ember Edge bergerak saat terbuka, dan Ember Edge + wyrm berhenti saat notch tertutup.
- Self-test tidak lagi mengotori riwayat tugas asli (`focus.*` dan `timer.*` disimpan dan dikembalikan).
- Cek overlap menunggu halaman lama selesai memudar, bukan jeda tetap (sebelumnya kadang gagal palsu).

**Performa (`--perf`, 15 detik per kondisi, 6 Nov 2026)**

| Kondisi | CPU | Memori | Target |
| --- | --- | --- | --- |
| Closed | 0,22% (0,36% setelah dibuka-tutup) | 23–37 MB | < 0,5% |
| Live Pomodoro / Claude / Musik | 0,55% / 0,16% / 0,25% | 24 MB | < 2% |
| Expanded (per tab) | 0,76–1,46% | 36–38 MB | < 5% |

- Ember Edge diukur terpisah (build dengan Ember Edge dimatikan): tidak ada beda yang terukur, karena animasinya berjalan di Core Animation.
- Temuan: nama tugas yang bergantian dengan waktu di live notch sempat memakan +1,1% CPU karena crossfade animasi tiap 4 detik. Sekarang berganti tanpa animasi dan digerakkan oleh timeline 1 detik yang sama dengan angka (live Pomodoro kembali 0,55%).
- Angka pertama "closed" kadang tinggi (sekali 5,9%) saat pemindaian token 60 detik jatuh di jendela ukur; pengukuran ulang memberi 0,13–0,26%.

**Cek manual yang tersisa**
- Mengetik di kolom tugas dan durasi Timer di notch (panel harus menerima keyboard).
- Scroll di angka durasi Timer dengan trackpad dan mouse.
- Spotify atau YouTube di browser: lagu, cover, play/pause, next, seek muncul dan berfungsi.
- Klik preset saat timer berjalan (memulai ulang dengan preset itu).
