# PRD Wyrmwatch

1 November 2026 · Saidil Halim

## Ringkasan

App Claude Usage yang sudah ada dikembangkan menjadi **Wyrmwatch** ("Guarding your focus, your music, and your AI agents, right from the notch."): satu notch app produktivitas untuk MacBook. Isinya empat modul: Pomodoro, Claude Usage, Apple Music, dan info dasar. Semua animasinya halus, tapi pemakaian CPU saat idle tetap mendekati nol.

**Tujuan**

- Satu tempat di notch untuk fokus kerja: timer, status Claude, dan musik, tanpa membuka app lain.
- Tampilan dan perilaku yang sama di layar MacBook maupun monitor eksternal (lewat notch virtual).
- Animasi terasa premium tapi ringan: CPU di bawah 1% saat idle dan di bawah 5% saat animasi berjalan.
- Modul Pomodoro punya identitas visual sendiri yang menyatu dengan maskot naga merah.

**Bukan tujuan (versi ini)**

- File shelf (drag & drop file ke notch).
- Dukungan pemutar selain Apple Music (Spotify dan lainnya).
- Pengganti HUD volume dan brightness.
- Sinkronisasi antarperangkat dan akun.
- Distribusi di Mac App Store, karena app ini memakai AppleScript dan berjalan tanpa sandbox.

## Kondisi saat ini dan keputusan

Keputusannya: disatukan dan dikembangkan di repo yang sudah ada (sebelumnya `claude-usage-ui`, sekarang `notchwyrm`), bukan app baru. Fondasi notch di repo ini sudah matang, jadi tinggal ditambah modul.

**Yang sudah ada di repo (±3.600 baris Swift, Swift Package, macOS 14+)**

| Bagian | File | Status |
| --- | --- | --- |
| Window notch fixed-size (shape yang dianimasikan, bukan window) | `Notch/NotchWindow.swift` | Dipakai ulang |
| Bentuk notch dengan flare dan radius yang bisa dianimasikan | `Notch/NotchView.swift` (`NotchShape`) | Dipakai ulang |
| State closed / live / pop / expanded | `NotchModel` | Diperluas jadi berbasis modul |
| Hover 180 ms untuk buka, 300 ms untuk tutup, click-through saat tertutup | `NotchWindowController` | Dipakai ulang |
| Kurva open spring(0.46, 0.8), close spring(0.36, 1) | `NotchView` | Jadi standar semua modul |
| Mode Auto / Menu bar / Notch | `DisplayMode.swift` | Ditambah notch virtual |
| Usage, limit, sesi, forecast, notifikasi | `PlanLimitClient`, `SessionMonitor`, `UsageTracker`, dll. | Dipindah ke modul Claude |
| Slot maskot (hidden, peek, working, alert, done, sleep) | `Views/WyrmSlot.swift` (`WyrmSlot`, Rive) | Diisi `wyrm.riv` yang akan menyusul |
| Tema hitam frosted dan silver | `Views/Theme.swift` | Jadi design system semua modul |

**Kenapa disatukan**

1. Notch hanya satu. Dua app yang sama-sama memasang panel di level `.statusBar + 1` akan berebut hover, klik, dan animasi.
2. Logika layar (deteksi notch, ganti monitor, click-through) sudah ada dan teruji lewat `--selftest`. Membuat ulang di app baru berarti menduplikasi kode yang sudah jalan.
3. Satu proses, satu timer pointer, satu login item. Lebih hemat RAM dan energi dibanding dua app.
4. Naga merah dan tema hitam-silver jadi identitas yang konsisten untuk semua modul.

**Konsekuensi**

- Nama app diganti menjadi **Wyrmwatch** (repo `Wyrmwatch`) karena isinya tidak lagi hanya Claude.
- Kode Claude dirapikan ke folder `Modules/Claude/` supaya modul lain tidak bergantung padanya.

## Model tampilan dan prioritas

Notch punya empat state, sama seperti sekarang. Bedanya, isi state live dan pop kini ditentukan oleh modul dengan prioritas tertinggi.

| State | Kapan | Ukuran (lebar × tinggi) | Isi |
| --- | --- | --- | --- |
| Closed | Tidak ada modul aktif | Lebar notch × tinggi notch | Hitam polos, menyatu dengan notch fisik |
| Live | Ada modul aktif | Lebar notch + 100 pt × tinggi notch | Claude: naga kecil di kiri. Musik: cover + visualizer. Pomodoro: waktu silver. Kalau Pomodoro dan musik sama-sama aktif, keduanya bergantian tiap 6 detik |
| Pop | Event sesaat (sesi Claude selesai, Pomodoro selesai, lagu berganti) | 320 × tinggi notch + 58 pt | Satu baris: gambar 44 pt, dua baris teks, satu aksi utama |
| Expanded | Hover 180 ms atau klik | 600 × (tinggi notch + 10 + tinggi halaman + 16). Tinggi mengikuti isi tab (Home 96 pt, Musik 120 pt) | Header dibelah kamera + satu halaman (Home, Fokus, Musik, Claude) |

**Prioritas modul di state live** (yang teratas menang)

1. Pomodoro sedang berjalan (fokus atau istirahat)
2. Claude sedang bekerja (sesi `busy`)
3. Usage Claude di atas 90%
4. Musik sedang diputar
5. Usage Claude di atas batas peringatan (default 80%)
6. Tidak ada yang aktif: closed

**Aturan event pop**

- Pop menyela state live selama 5 detik, lalu kembali. Kalau kursor ada di atasnya, pop tetap terbuka (perilaku yang sudah ada).
- Kalau dua event datang bersamaan, keduanya diantrekan. Urutan: Pomodoro selesai, sesi Claude selesai, lalu lagu berganti.
- Lagu berganti hanya memunculkan pop singkat (2,5 detik) dan bisa dimatikan di Settings.
- Saat expanded, pop tidak muncul. Event cukup ditandai di dalam panel.

**Isi state expanded** (layout kartu, terinspirasi pola Perch: kartu sama tinggi, satu angka besar per kartu, tab ikon kecil. Hanya polanya yang dipelajari, tidak ada aset atau tampilan yang ditiru)

Lebar tetap ±640 pt (panel 620 + flare). Tinggi mengikuti isi tab aktif (`GeometryReader`, spring response 0,45, damping 0,8). Window tetap 680 × 420 dan tidak pernah di-resize.

1. **Header**: grid 3 kolom [kiri | lebar notch fisik | kanan].
    - Kiri: 4 tab ikon (Home, Focus, Music, Claude). Tombol 26 × 26, radius 8, ikon custom 14 pt. Tidak aktif: bg `#1C1C1E`, ikon `#8E8E93`. Aktif: bg `#3A3A3C`, ikon putih.
    - Tengah: kosong (kamera), berisi slot maskot `WyrmSlot`.
    - Kanan: pill (ikon + nama tab aktif, crossfade) + jam 11 pt.
    - Settings bukan tab lagi. Dibuka lewat klik kanan notch (menu Settings… / Quit, membuka jendela Settings) atau ikon menu bar.
2. **Home**: 3 kartu sejajar, tinggi sama 118 pt, gap 8, kolom [1 | 1,25 | 1], padding 12.
    - Claude: "Claude · session" + titik merah berdenyut dan "working" saat busy (atau titik putih dan "waiting" saat Claude menunggu kamu), persen sesi besar + bar 4 pt, lalu 1 baris status: alat yang sedang dipakai (dari ekor transkrip, misalnya "Editing HomePage.swift") atau "Waiting for you", plus waktu reset (ellipsis).
    - Music: cover 46 pt radius 11 + judul + artis, progress 4 pt, lalu 3 tombol [1 | 1,3 | 1]: previous, play/pause (aktif), next. Musik mati → "Play music".
    - Focus: "Focus n/N", "Break", atau "Timer" untuk countdown, waktu besar, lalu pause/resume dan Stop. Timer berhenti → label "Focus" + preset 25/5 dan 50/10.
3. **Focus**: kiri kartu 200 pt (waktu 46 pt + pause/Start dan +5). Kanan: segmented Pomodoro | Countdown + grid preset 3 × 2 (25/5, 50/10, 90/15, 05:00, 15:00, Custom) setinggi 34 pt. Custom membuka stepper sesuai mode.
4. **Music**: kartu cover 150 × 150 + kartu info (judul 16 semibold, artis · album, progress, shuffle/previous/play-pause/next/repeat). Playlist library di bawahnya kalau Music menyediakannya.
5. **Claude**: 3 kartu angka besar (Session %, Week %, Sessions running), lalu Now (sesi dengan Jump) / Recent / Usage.

Gerak: kartu muncul bergiliran (stagger 30 ms, fade + geser 5 pt), angka besar memakai `contentTransition(.numericText())`, cover memakai `matchedGeometryEffect` antara live dan expanded, tombol scale 0,96 saat ditekan, mengikuti Reduce Motion, dan semua animasi berulang berhenti saat notch tertutup.

Popover menu bar (mode Menu bar) tetap memakai tata letak vertikal 344 pt.

## Spesifikasi modul

### 1. Pomodoro "Ember" (prioritas tertinggi)

Konsepnya: setiap sesi fokus adalah bara yang dijaga naga. Sisa waktu digambarkan sebagai sumbu silver yang memendek di live, dan sebagai progres 4 pt di halaman Fokus. Semua visual memakai tema hitam-silver dengan naga merah.

**Perilaku**

- Preset 25/5, 50/10, 90/15, dan Custom. Jumlah sesi per siklus 1–8 (default 4). Istirahat panjang 15 menit setelah sesi terakhir siklus.
- Timer disimpan sebagai `endDate`, bukan hitungan mundur. Tetap akurat walau Mac sleep, dan dipulihkan dari `UserDefaults` setelah app restart.
- Kontrol: mulai, +5 menit, pause/lanjut, lewati, stop (kembali ke mode Atur). Shortcut global opsional (misalnya ⌥⌘P).
- **Mode Countdown**: timer biasa tanpa istirahat (preset 05:00 dan 15:00 atau custom 1–180 menit). Saat habis, alarm berbunyi dan muncul pop "Time's up", lalu timer kembali ke setup. Countdown tidak dihitung di statistik Pomodoro.
- Saat fokus habis, istirahat **langsung mulai menghitung mundur** sendiri, dihitung dari saat fokus habis (tetap tepat walau Mac sleep atau app ditutup). Kalau istirahat juga sudah lewat, timer kembali ke mode Atur. Fokus berikutnya tetap dimulai manual.
- Di akhir setiap fase berbunyi **alarm singkat** (dua kali tiga bip, ±1,2 detik), kalau suara Pomodoro aktif. Pop "Focus done" menampilkan hitung mundur istirahat dan tombol "Skip break".
- Statistik hari ini: jumlah sesi dan total menit fokus.
- Opsional: Apple Music otomatis di-pause saat istirahat dan diputar lagi saat fokus dimulai.

**Tampilan dan animasi khas**

| Momen | Live (compact) | Animasi |
| --- | --- | --- |
| Mulai fokus | Kiri: naga mode "jaga" (mata menyala, napas pelan). Kanan: sisa waktu `24:59` silver | Sumbu silver setebal 1,5 pt tergambar dari tengah ke kedua sisi dalam 0,5 detik. Bara kecil muncul di ujungnya |
| Berjalan | Sumbu memendek sesuai sisa waktu | Bara di ujung berkedip pelan (opasitas 0,75–1, siklus 2 detik). Digit berganti dengan `contentTransition(.numericText())` |
| Pause | Sumbu dan angka meredup 40% | Tidak ada animasi berjalan sama sekali |
| 10 detik terakhir | Angka putih terang | Angka sedikit membesar lalu kembali (scale 1 → 1,06 → 1) tiap detik |
| Fokus selesai | Pop "Fokus selesai": naga menyemburkan api (mood `happy`), satu titik sesi menyala. Tombol "Mulai istirahat" dan "Lewati" | Titik bara baru menyala dengan efek scale-in. Haptic `.levelChange` dan suara pendek |
| Istirahat | Naga tidur dengan asap (mood `sleeping`). Sumbu berubah cyan | Asap memakai animasi di `Wyrm.swift` |
| Istirahat selesai | Pop: "Siap fokus lagi?" dengan tombol "Fokus" dan "Nanti" | Naga bangun (transisi dari sleeping ke guarding) |

**Halaman Focus di state expanded**: lihat "Isi state expanded" butir 3.

### 2. Claude Usage

Fitur yang sudah ada dipertahankan semua: limit sesi dan mingguan, forecast, daftar sesi, Jump, Recent, Usage, suara dan notifikasi selesai.

- Live: slot maskot (atau titik status kalau belum ada maskot): merah berdenyut saat Claude bekerja, putih saat Claude menunggu kamu, plus ring limit sesi.
- **Status `waiting`**: Claude Code menulis `status: "waiting"` di file sesi saat menunggu izin atau jawaban. Status ini tidak dianggap "selesai" (sebelumnya memicu pop "finished" yang salah). Yang dianggap selesai hanya perubahan busy → idle.
- **Aktivitas**: alat terakhir yang dipakai Claude dibaca dari ±200 KB terakhir transkrip `~/.claude/projects/<cwd>/<session>.jsonl`, tanpa membaca seluruh file. Pembacaan dilakukan di latar, maksimal tiap 2 detik per sesi, dan hanya untuk sesi yang busy atau waiting.
- Warna mengikuti level: silver sampai 90%, merah `#E5322B` di atas 90%. Di atas 90% ring berdenyut sekali setiap 4 detik, tidak terus-menerus.
- Pop "sesi selesai" dengan tombol Jump tetap ada.
- Batas peringatan 80% bisa diatur, seperti sekarang.

### 3. Apple Music

**Soal daftar lagu: bisa, dengan batasan.** Lewat AppleScript ke Music.app, app bisa membaca playlist atau album yang sedang diputar (`current playlist`): judul, artis, dan durasi setiap lagunya. App juga bisa memutar lagu tertentu dari daftar itu. Yang tidak bisa dibaca adalah antrean *Up Next* (lagu yang ditambahkan lewat "Play Next"). Selain itu, saat memutar stasiun radio atau lagu katalog Apple Music yang belum ditambahkan ke library, `current playlist` bisa kosong. Perilaku ini harus diuji di awal pengerjaan modul ini.

**Perilaku**

- Live: cover album kecil (18 pt, sudut 5 pt) di kiri, visualizer 4 batang di kanan.
- Pop saat lagu berganti: cover, judul, dan artis selama 2,5 detik (bisa dimatikan).
- Kontrol pemutar ada di Home (previous, play/pause, next, favorit, progress yang bisa digeser).
- **Halaman Musik**: cover 120 pt + playlist (judul | durasi) yang di-scroll vertikal di kolomnya sendiri.
    - Lagu yang sedang diputar berwarna putih (lainnya abu) dan otomatis di-scroll ke tengah.
    - Klik lagu untuk langsung memutarnya.
    - Ditampilkan 50 lagu di sekitar lagu aktif, sisanya dimuat saat di-scroll (`LazyVStack`).
    - Kalau daftar tidak tersedia (radio, lagu katalog di luar library), tampilkan teks "Daftar lagu tidak tersedia untuk sumber ini."
- Cover memakai `matchedGeometryEffect` antara live dan Home.
- **Lagu streaming** (di luar library): Music tidak memberi daftar lagu atau antrean, dan lagu katalog tidak bisa diputar langsung oleh app lain (lihat PROGRESS.md). Karena itu daftar Album / Top songs / Recent dari iTunes Search API **dihapus**. Tab Music hanya menampilkan playlist library saat tersedia. App tidak lagi mengirim data apa pun ke iTunes Search API.
- Di popover menu bar tetap ada kartu Now Playing (cover 56 pt) dengan panel daftar lagu yang bergeser saat hover 400 ms.

**Cara kerja yang hemat**

- Perubahan lagu dan play/pause dideteksi lewat notifikasi sistem `com.apple.Music.playerInfo` (DistributedNotificationCenter), bukan polling.
- Posisi lagu dibaca sekali saat panel dibuka, lalu dihitung sendiri di app. Tidak ada AppleScript setiap detik.
- Daftar lagu diambil dengan satu perintah AppleScript sekaligus (semua nama, artis, durasi), dan hanya diambil ulang saat playlist berganti.
- Cover diambil dari `artwork 1 of current track`, di-cache per lagu.
- Warna dominan cover dihitung sekali per lagu (gambar diperkecil ke 8×8 piksel), lalu dipakai untuk aksen tipis di kartu.

### 4. Info dasar

- InfoModule hanya untuk **acara kalender berikutnya** (dalam 24 jam, bukan acara seharian), lewat EventKit. Kalau izin ditolak, tidak ada yang tampil.
- Tanggal dan jam bagian dari header ("Min 1 Nov · 18.52"), diperbarui sekali per menit. Acara berikutnya tampil sebagai tooltip di tanggal.
- Baterai dan pop "Charging" dihapus.

### 5. Maskot dan tema

- **Maskot**: naga lama (`Views/Dragon.swift` dan ikon game-icons.net) dihapus. Penggantinya adalah slot `WyrmSlot(state:look:)` di celah tengah header dan di kiri notch live.
    - State: `hidden`, `peek`, `working`, `alert`, `done`, `sleep`. Pemetaan: user idle lama (> 5 menit) → sleep, Claude busy → working, Claude menunggu input → alert, sesi selesai → done, selain itu peek.
    - Kalau `Resources/wyrm.riv` ada, file itu diputar dengan RiveRuntime (rive-ios 6.x, framework ±14 MB di `Contents/Frameworks`). Setiap state dipetakan ke input boolean bernama sama di state machine, ditambah input angka `lookX` / `lookY` dari posisi kursor (maks. 15 fps, hanya saat notch terbuka). Rive di-pause saat notch tertutup.
    - Kalau file belum ada, slot kosong (app tidak menggambar maskot sendiri). Notch live menampilkan titik status Claude.
- **Tema** (`Views/Theme.swift`): bg `#000`, kartu `#1C1C1E`, tombol `#2C2C2E`, tombol aktif/hover `#3A3A3C`, teks `#F5F5F7`, sekunder `#8E8E93`, progress silver `#D1D5DB`. Satu-satunya warna adalah merah `#E5322B`, hanya untuk titik status Claude "working" dan usage > 90%.
- Radius (semua `.continuous`): kartu 20, tombol 10, preset 11, tab 8.
- Tipografi: angka besar 38 pt semibold, tracking −1, `monospacedDigit`. Label 11 pt sekunder. Judul lagu 13 pt semibold.
- **Ikon app**: notch hitam dengan titik merah (digambar oleh binary lewat `--render-icon`).

## Notch virtual di monitor eksternal

Di layar tanpa notch, app menggambar notch virtual: bentuk hitam yang sama, ditempel di tengah atas layar, dengan semua state dan animasi yang sama. Mode menu bar tetap ada sebagai pilihan.

- Ukuran notch virtual: 185 × tinggi menu bar layar itu (`screen.frame.maxY - screen.visibleFrame.maxY`, biasanya 24–25 pt). Angka 185 pt sama dengan nilai default `NotchModel`.
- Di state closed, notch virtual tampil sebagai pil hitam kecil 120 × 6 pt supaya tidak menutupi menu bar. Saat di-hover, pil berubah ke ukuran penuh dengan kurva open yang sama.
- `show(on:)` saat ini berhenti kalau `notchSize` kosong. Ini diganti dengan `notchSize ?? virtualNotchSize(for: screen)`.
- `DisplayMode` mendapat pilihan baru:

| Pilihan | Layar MacBook | Monitor eksternal |
| --- | --- | --- |
| Auto (default baru) | Notch asli | Notch virtual di layar utama |
| Notch | Notch asli | Tidak tampil |
| Menu bar | Menu bar | Menu bar |
| Semua layar | Notch asli | Notch virtual di setiap layar |

- Untuk "Semua layar", cukup satu `NotchModel` yang dibagi, dengan satu panel per layar. Hanya panel di layar tempat kursor berada yang boleh expanded.
- Saat layar mati atau dicabut, panel layar itu ditutup dan dibuang, bukan sekadar disembunyikan.
- Saat ada app fullscreen di layar itu, notch virtual disembunyikan, kecuali Pomodoro sedang berjalan (sumbunya tetap tampil kecil).

## Animasi dan performa

Prinsipnya: membuka pelan dan sedikit memantul, menutup cepat dan tenang, dan tidak ada yang bergerak kalau tidak ada yang berubah. Semua modul wajib memakai token motion di bawah, tidak boleh membuat kurva sendiri.

**Token motion** (`Motion` di `Theme.swift`)

| Token | Nilai | Dipakai untuk |
| --- | --- | --- |
| `open` | spring(response 0.46, damping 0.8) | Notch membesar ke live, pop, expanded |
| `close` | spring(response 0.36, damping 1.0) | Notch mengecil |
| `contentIn` | easeOut 0.32 detik, delay 0.07 | Isi muncul setelah bentuk mulai membesar |
| `contentOut` | easeIn 0.14 detik | Isi hilang sebelum bentuk mengecil |
| `smooth` | smooth 0.28 detik | Perubahan nilai (ring, progress, warna) |
| `quick` | snappy 0.18 detik | Hover tombol, tekan |
| `slide` | spring(response 0.4, damping 0.86) | Panel daftar lagu di popover menu bar |
| `resize` | spring(response 0.45, damping 0.8) | Tinggi notch mengikuti isi tab, kapsul tab meluncur |
| `page` | easeOut 0.22 detik | Isi tab berganti (fade + geser 5 pt) |

**Koreografi per transisi**

- Closed → live: bentuk melebar dengan `open`. Isi kiri dan kanan fade-in 0,25 detik setelah 0,1 detik.
- Live → expanded: bentuk membesar dengan `open`. Isi turun dari offset −10 pt dan scale 0,94 ke 1 dengan `contentIn`.
- Expanded → closed: isi hilang dengan `contentOut`, baru bentuk mengecil dengan `close`.
- Ganti modul di live (misalnya musik ke Pomodoro): isi lama fade-out dan geser 6 pt ke atas, isi baru masuk dari bawah. Lebar notch tidak berubah, jadi tidak ada lompatan.
- Ganti lagu: cover lama crossfade ke cover baru dalam ±0,3 detik (`smooth`).
- Ganti tab di expanded: isi lama fade, isi baru masuk dengan fade + geser 5 pt (`page`). Tinggi notch mengikuti isi baru dengan `resize`, dan kapsul tab meluncur dengan `resize`.
- Cover: `matchedGeometryEffect` antara cover kecil di live dan cover 96 pt di Home.
- Mode Atur ↔ Jalan di halaman Fokus: fade + geser 5 pt.
- Live dengan Pomodoro dan musik aktif: bergantian tiap 6 detik (fade + geser 6 pt).

**Aturan supaya tetap ringan**

1. Window tidak pernah di-resize. Yang dianimasikan hanya `NotchShape` di dalam window berukuran tetap (sudah begitu sekarang, pertahankan).
2. Animasi berulang (visualizer, bara berkedip, naga) hanya berjalan saat terlihat. Saat notch closed atau layar sleep, semuanya berhenti total lewat `environment(\.animationsPaused)`. Panel expanded hanya dibangun saat notch terbuka.
3. Animasi berulang memakai `TimelineView(.animation(minimumInterval: 1/30))` dan `Canvas`, bukan `repeatForever` di banyak view. Maksimal 30 fps untuk dekorasi.
4. Timer Pomodoro memperbarui angka dengan `TimelineView(.periodic(by: 1))`, sekali per detik.
5. Tidak ada blur, shadow, atau gradient yang ikut dianimasikan. Gradient silver hanya untuk elemen statis.
6. Visualizer musik adalah animasi dekoratif, bukan analisis audio asli. Itu sengaja, karena membaca audio sistem butuh izin rekam layar dan berat.
7. Pointer tracking 30 Hz hanya saat expanded (sudah begitu sekarang). Saat closed cukup event monitor.
8. Ikuti Reduce Motion: spring diganti fade 0,2 detik, dan animasi berulang dimatikan.

**Anggaran performa (diukur di M2, Activity Monitor dan Instruments)**

| Kondisi | CPU | Memori |
| --- | --- | --- |
| Closed, tidak ada modul aktif | < 0,5% | < 80 MB |
| Live (Pomodoro atau musik) | < 2% | < 90 MB |
| Expanded, animasi berjalan | < 5% | < 120 MB |
| Transisi buka/tutup | Tidak ada frame drop di 120 Hz ProMotion | - |

## Settings, arsitektur, dan izin

**Settings** (menambah tab di `SettingsView` yang sudah ada)

| Tab | Pengaturan |
| --- | --- |
| Display | Mode tampil (Auto, Notch, Menu bar, Semua layar), buka saat hover atau klik saja |
| Modul | Aktif/nonaktif per modul, urutan prioritas (bisa di-drag) |
| Pomodoro | Durasi fokus, istirahat pendek dan panjang, suara, haptic, sinkron dengan Apple Music |
| Music | Pop saat ganti lagu, tampilkan daftar lagu saat hover |
| Claude | Batas peringatan, suara selesai, notifikasi (sudah ada) |
| System | Open at login, Reduce Motion paksa, Quit (sudah ada) |

**Struktur folder baru**

```
Sources/Wyrmwatch/
  App/            entry point, AppModels, DisplayMode, StatusItem
  Notch/          NotchWindow, NotchView, NotchShape, VirtualNotch, ExpandedPanel (header + halaman)
  Core/           NotchModule (protokol), ModuleRegistry, PriorityResolver, PopQueue
  Modules/
    Claude/       semua file Claude yang sekarang + ClaudeModule
    Pomodoro/     PomodoroTimer, PomodoroModule, FocusPage, EmberViews (EmberFuse, EmberDots)
    Music/        MusicBridge (AppleScript), MusicModule, MusicPage, PlaylistPanel, ArtworkCache
    Info/         CalendarSource, InfoModule
  Views/          Theme (Palette, Motion), Dragon, komponen bersama
```

**Kontrak modul**

```swift
@MainActor
protocol NotchModule: ObservableObject {
    var id: String { get }
    /// nil = tidak aktif; makin kecil makin diprioritaskan
    var livePriority: Int? { get }
    func liveLeading() -> AnyView
    func liveTrailing() -> AnyView
    func expandedCard() -> AnyView?
    /// event sesaat yang minta pop
    var pops: AsyncStream<NotchPop> { get }
    func setVisible(_ visible: Bool) // untuk menghentikan animasi
}
```

`PriorityResolver` memilih modul aktif dengan `livePriority` terkecil. `NotchModel.state` tidak lagi menerima `busy: Bool`, tapi membaca hasil resolver.

**Izin dan privasi**

| Izin | Untuk | Kalau ditolak |
| --- | --- | --- |
| Automation → Music | Membaca lagu dan daftar putar, kontrol pemutar | Modul Music menampilkan tombol "Beri izin" yang membuka System Settings |
| Automation → Terminal/iTerm2 | Jump ke sesi (sudah ada) | Seperti sekarang |
| Kalender | Acara berikutnya | Baris kalender disembunyikan |
| Notifikasi | Pomodoro dan Claude selesai | Hanya pop dan suara |
| Keychain | Token Claude Code (sudah ada) | Seperti sekarang |

Tambahkan `NSAppleEventsUsageDescription` dan `NSCalendarsFullAccessUsageDescription` di `Info.plist` lewat `build-app.sh`. Bundle ID `com.saidilhalim.wyrmwatch`. Setelah rename, macOS meminta izin Music, Kalender, dan akses Keychain sekali lagi. Pengaturan lama dari `com.saidilhalim.claudeusage` disalin otomatis saat pertama kali jalan. Data yang dikirim ke luar hanya request limit Claude, dan (untuk lagu streaming) artis + nama album ke iTunes Search API Apple.

## Alur kerja Git

Semua pengembangan dilakukan di branch terpisah, di-commit otomatis per langkah, dan tanpa atribusi Claude.

- **Branch:** kerja di branch pendek per fitur dari `main`. Setelah `swift build` dan `--selftest` lulus, branch di-merge ke `main` dan di-push. (Milestone 1–6 sebelumnya berjalan di `feat/notch-hub`, yang sudah di-merge ke `main`.)
- **Auto commit:** setiap satu langkah selesai dan `swift build` lulus, perubahan langsung di-commit dengan format Conventional Commits (`feat:`, `refactor:`, `fix:`, `docs:`).
- **Tanpa atribusi Claude:** commit dan PR tidak memuat `Co-Authored-By: Claude`, link sesi, maupun "Generated with Claude Code". Author commit adalah akun GitHub pemilik repo.
- **Ganti nama repo:** dilakukan lewat GitHub → Settings → General → Repository name. GitHub otomatis mengalihkan URL lama. Setelah itu jalankan `git remote set-url origin <url-baru>` di clone lokal, lalu perbarui URL clone di `README.md`.

## Milestone, kriteria penerimaan, dan risiko

**Milestone** (berurutan, masing-masing bisa dirilis sendiri)

1. **Refactor ke modul.** Protokol `NotchModule`, `PriorityResolver`, dan `PopQueue`. Claude dipindah menjadi modul pertama. Hasil akhir: app terlihat dan berperilaku persis seperti sekarang, dan `--selftest` tetap lulus.
2. **Notch virtual.** Monitor eksternal mendapat notch virtual, plus pilihan baru di `DisplayMode`.
3. **Pomodoro Ember.** Timer, sumbu, bara, mood naga, pop selesai, dan statistik harian.
4. **Apple Music.** Now playing, kontrol, pop ganti lagu, lalu panel daftar lagu.
5. **Info dasar.** Jam dan acara kalender berikutnya (baterai dan pop charger dihapus setelah revisi desain).
6. **Polishing dan rename.** Reduce Motion, Settings lengkap, pengukuran performa, ganti nama app (akhirnya menjadi Wyrmwatch) (target, executable, bundle identifier, ikon, README).

**Kriteria penerimaan**

- [ ] Semua fitur Claude yang sekarang tetap berfungsi setelah refactor
- [ ] `--selftest` diperluas: setiap state setiap modul, di notch asli dan notch virtual
- [ ] Panel expanded selebar 600 pt di semua tab, tingginya mengikuti isi tab, window tidak pernah di-resize (dicek di self-test)
- [ ] Tidak ada view yang overlap di setiap tab, di notch asli dan virtual (self-test membandingkan frame)
- [ ] Mode Atur dan Jalan di halaman Fokus: +5 mnt menambah 5 menit, Stop kembali ke Atur, jumlah sesi menentukan kapan istirahat panjang
- [ ] Timer Pomodoro meleset kurang dari 1 detik setelah Mac sleep 10 menit
- [ ] Ganti lagu di Music.app terlihat di notch dalam waktu kurang dari 0,5 detik
- [ ] Klik lagu di daftar langsung memutar lagu itu
- [ ] Colok/cabut monitor tidak membuat notch hilang atau dobel
- [ ] Anggaran CPU dan memori di bagian Animasi dan performa terpenuhi
- [ ] Dengan Reduce Motion aktif, tidak ada animasi berulang

**Risiko**

| Risiko | Dampak | Mitigasi |
| --- | --- | --- |
| `current playlist` kosong untuk radio atau lagu katalog di luar library | Daftar lagu tidak muncul | Tampilkan pesan yang jelas. Uji di awal milestone 4 sebelum membangun UI daftar |
| AppleScript ke Music lambat untuk playlist besar (ribuan lagu) | Panel terasa lag | Ambil semua kolom dalam satu perintah, di background thread, dan batasi jendela 50 lagu |
| Endpoint limit Claude tidak resmi | Data limit hilang | Sudah ditangani: app memberi tahu dan fitur lain tetap jalan |
| Notch virtual menutupi menu app di monitor sempit | Mengganggu kerja | Pil 120 × 6 pt saat closed, dan opsi mematikan notch virtual per layar |
| Animasi berulang lupa dihentikan | Baterai boros | Satu flag `animationsPaused` terpusat, dicek di self-test |

**Pertanyaan terbuka**

- Apakah sinkron Pomodoro dengan Apple Music aktif secara default?
    - Keputusan sementara: **nonaktif** secara default, bisa diaktifkan di Settings → Pomodoro.
- Shortcut global untuk Pomodoro: perlu di versi pertama atau nanti?
    - Keputusan sementara: **ditunda**, tidak masuk versi pertama.
- Mode Auto saat MacBook tersambung ke monitor eksternal: notch di layar MacBook, di layar utama, atau keduanya?
    - Keputusan sementara: **satu notch di layar yang memegang menu bar** (`NSScreen.screens.first`). Notch asli kalau layar itu punya notch, notch virtual kalau tidak. "Semua layar" untuk notch di setiap layar.
- Pop saat mode "Semua layar": di layar mana?
    - Keputusan sementara: pop tampil di semua panel; expanded hanya di layar tempat kursor berada.
- Bahasa teks UI: PRD memakai contoh teks berbahasa Indonesia, sedangkan UI awal berbahasa Inggris.
    - Keputusan akhir: **seluruh UI berbahasa Inggris** ("Classic 25/5", "Deep 50/10", "Start", "Focus n/N", "+5 min", "Skip", "Focus done", "Play music").
- Preset "Custom" Pomodoro: di mana durasinya diatur?
    - Keputusan sementara: di Settings → Pomodoro (stepper menit). Chip "Custom" menyala otomatis kalau durasi tidak cocok dengan 25/5 atau 50/10.
- Setelah satu fase selesai, apakah fase berikutnya mulai otomatis?
    - Keputusan sementara: **tidak**. Fase berikutnya disiapkan, dan pop memberi tombol untuk memulainya.
- Di mana Settings dibuka di notch?
    - Keputusan: tab Settings ke-5 (dikembalikan). Tombol ⚙︎ di halaman Claude dihapus.
- Acara kalender berikutnya tidak punya tempat di header baru ("naga + tanggal · jam").
    - Keputusan sementara: tampil sebagai tooltip di tanggal. Perlu diputuskan apakah butuh baris sendiri.
- Kalimat terpotong di permintaan ("jangan lupa iunutk …"): ditafsirkan sebagai "jangan lupa untuk ikon app", jadi ikon app kini naga merah.
- Nama app: **Wyrmwatch** (keputusan 5 Nov 2026), menggantikan rencana "Notchwyrm". Nama app tidak memakai kata "Claude".
