# PRD Notchwyrm

1 November 2026 · Saidil Halim

## Ringkasan

App Claude Usage yang sudah ada dikembangkan menjadi Notchwyrm: satu notch app produktivitas untuk MacBook. Isinya empat modul: Pomodoro, Claude Usage, Apple Music, dan info dasar. Semua animasinya halus, tapi pemakaian CPU saat idle tetap mendekati nol.

**Tujuan**

- Satu tempat di notch untuk fokus kerja: timer, status Claude, dan musik, tanpa membuka app lain.
- Tampilan dan perilaku yang sama di layar MacBook maupun monitor eksternal (lewat notch virtual).
- Animasi terasa premium tapi ringan: CPU di bawah 1% saat idle dan di bawah 5% saat animasi berjalan.
- Modul Pomodoro punya identitas visual sendiri yang menyatu dengan maskot naga.

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
| Maskot naga (sleep, working, happy) | `Views/Dragon.swift` | Dipakai juga oleh Pomodoro |
| Tema hitam frosted dan silver | `Views/Theme.swift` | Jadi design system semua modul |

**Kenapa disatukan**

1. Notch hanya satu. Dua app yang sama-sama memasang panel di level `.statusBar + 1` akan berebut hover, klik, dan animasi.
2. Logika layar (deteksi notch, ganti monitor, click-through) sudah ada dan teruji lewat `--selftest`. Membuat ulang di app baru berarti menduplikasi kode yang sudah jalan.
3. Satu proses, satu timer pointer, satu login item. Lebih hemat RAM dan baterai dibanding dua app.
4. Brand naga dan tema silver jadi identitas yang konsisten untuk semua modul.

**Konsekuensi**

- Nama app diganti menjadi Notchwyrm (repo `notchwyrm`) karena isinya tidak lagi hanya Claude.
- Kode Claude dirapikan ke folder `Modules/Claude/` supaya modul lain tidak bergantung padanya.

## Model tampilan dan prioritas

Notch punya empat state, sama seperti sekarang. Bedanya, isi state live dan pop kini ditentukan oleh modul dengan prioritas tertinggi.

| State | Kapan | Ukuran (lebar × tinggi) | Isi |
| --- | --- | --- | --- |
| Closed | Tidak ada modul aktif | Lebar notch × tinggi notch | Hitam polos, menyatu dengan notch fisik |
| Live | Ada modul aktif | Lebar notch + 100 pt × tinggi notch | Kiri: ikon/visual modul. Kanan: angka atau indikator |
| Pop | Event sesaat (sesi Claude selesai, Pomodoro selesai, lagu berganti) | 340 × tinggi notch + 70 pt | Kartu kecil dengan satu aksi utama |
| Expanded | Hover 180 ms atau klik | 400 × tinggi isi (maks. 640) | Panel lengkap semua modul |

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

**Isi state expanded** (atas ke bawah)

1. Header: naga, tanggal dan jam, baterai.
2. Baris kartu: Pomodoro (kiri) dan Now Playing (kanan).
3. Tab yang sudah ada: Now, Recent, Usage (Claude).
4. Daftar lagu playlist muncul sebagai panel geser di kartu Now Playing (lihat modul Apple Music).

## Spesifikasi modul

### 1. Pomodoro "Ember" (prioritas tertinggi)

Konsepnya: setiap sesi fokus adalah bara yang dijaga naga. Sisa waktu digambarkan sebagai sumbu menyala yang memendek di tepi bawah notch. Semua visual memakai elemen yang sudah ada (naga, amber `#E3B26A`, silver), jadi terasa satu keluarga dengan app.

**Perilaku**

- Preset 25/5, 50/10, dan custom. Istirahat panjang 15 menit setiap 4 sesi.
- Timer disimpan sebagai `endDate`, bukan hitungan mundur. Tetap akurat walau Mac sleep, dan dipulihkan dari `UserDefaults` setelah app restart.
- Kontrol: mulai, pause, reset, lewati. Shortcut global opsional (misalnya ⌥⌘P).
- Statistik hari ini: jumlah sesi dan total menit fokus.
- Opsional: Apple Music otomatis di-pause saat istirahat dan diputar lagi saat fokus dimulai.

**Tampilan dan animasi khas**

| Momen | Live (compact) | Animasi |
| --- | --- | --- |
| Mulai fokus | Kiri: naga mode "jaga" (mata amber menyala, napas pelan). Kanan: sisa waktu `24:59` | Sumbu amber setebal 1,5 pt tergambar dari tengah ke kedua sisi dalam 0,5 detik. Bara kecil muncul di ujungnya |
| Berjalan | Sumbu memendek sesuai sisa waktu | Bara di ujung berkedip pelan (opasitas 0,75–1, siklus 2 detik). Digit berganti dengan `contentTransition(.numericText())` |
| Pause | Sumbu dan angka meredup 40% | Tidak ada animasi berjalan sama sekali |
| 10 detik terakhir | Angka putih terang | Angka sedikit membesar lalu kembali (scale 1 → 1,06 → 1) tiap detik |
| Fokus selesai | Pop: naga mengaum dengan api (mood `happy` yang sudah ada), satu dari 4 titik bara menyala. Tombol "Mulai istirahat" dan "Lewati" | Titik bara baru menyala dengan efek scale-in. Haptic `.levelChange` dan suara pendek |
| Istirahat | Naga tidur dengan asap (mood `sleep`). Sumbu berubah silver-biru dingin | Asap memakai animasi yang sudah ada di `Dragon.swift` |
| Istirahat selesai | Pop: "Siap fokus lagi?" | Naga bangun (transisi dari sleep ke jaga) |

**Kartu di state expanded**

- Ring progres besar berwarna amber dengan bara kecil di ujung busurnya.
- Empat titik bara untuk menunjukkan sesi ke berapa dalam satu siklus.
- Chip preset, tombol kontrol, dan baris statistik hari ini.

### 2. Claude Usage

Fitur yang sudah ada dipertahankan semua: limit sesi dan mingguan, forecast, daftar sesi, Jump, Recent, Usage, suara dan notifikasi selesai.

- Live: naga mode working dan ring limit sesi, seperti sekarang.
- Warna ring mengikuti level: silver di bawah 80%, amber 80–90%, rose di atas 90%. Di atas 90% ring berdenyut sekali setiap 4 detik, tidak terus-menerus.
- Pop "sesi selesai" dengan tombol Jump tetap ada.
- Batas peringatan 80% bisa diatur, seperti sekarang.

### 3. Apple Music

**Soal daftar lagu: bisa, dengan batasan.** Lewat AppleScript ke Music.app, app bisa membaca playlist atau album yang sedang diputar (`current playlist`): judul, artis, dan durasi setiap lagunya. App juga bisa memutar lagu tertentu dari daftar itu. Yang tidak bisa dibaca adalah antrean *Up Next* (lagu yang ditambahkan lewat "Play Next"). Selain itu, saat memutar stasiun radio atau lagu katalog Apple Music yang belum ditambahkan ke library, `current playlist` bisa kosong. Perilaku ini harus diuji di awal pengerjaan modul ini.

**Perilaku**

- Live: cover album kecil (18 pt, sudut 5 pt) di kiri, visualizer 4 batang di kanan.
- Pop saat lagu berganti: cover, judul, dan artis selama 2,5 detik (bisa dimatikan).
- Kartu di state expanded: cover 56 pt, judul, artis, progress bar yang bisa digeser, tombol previous/play-pause/next.
- **Daftar lagu:** saat kursor diam di kartu Now Playing selama 400 ms, atau ikon daftar diklik, kartu bergeser dan menampilkan lagu-lagu di playlist yang sedang diputar.
    - Lagu yang sedang diputar disorot dan otomatis di-scroll ke tengah.
    - Klik lagu untuk langsung memutarnya.
    - Ditampilkan 50 lagu di sekitar lagu aktif, sisanya dimuat saat di-scroll (`LazyVStack`).
    - Kalau daftar tidak tersedia, tampilkan teks "Daftar lagu tidak tersedia untuk sumber ini".

**Cara kerja yang hemat**

- Perubahan lagu dan play/pause dideteksi lewat notifikasi sistem `com.apple.Music.playerInfo` (DistributedNotificationCenter), bukan polling.
- Posisi lagu dibaca sekali saat panel dibuka, lalu dihitung sendiri di app. Tidak ada AppleScript setiap detik.
- Daftar lagu diambil dengan satu perintah AppleScript sekaligus (semua nama, artis, durasi), dan hanya diambil ulang saat playlist berganti.
- Cover diambil dari `artwork 1 of current track`, di-cache per lagu.
- Warna dominan cover dihitung sekali per lagu (gambar diperkecil ke 8×8 piksel), lalu dipakai untuk aksen tipis di kartu.

### 4. Info dasar

- Ditampilkan di header state expanded: tanggal, jam, baterai, dan acara kalender berikutnya.
- Baterai dibaca lewat notifikasi IOKit (`IOPSNotificationCreateRunLoopSource`), bukan polling.
- Kalender lewat EventKit. Kalau izin ditolak, baris kalender disembunyikan tanpa pesan error.
- Pop singkat saat charger dicolok: ikon baterai terisi dan persentase, selama 2 detik (bisa dimatikan).

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
| `slide` | spring(response 0.4, damping 0.86) | Panel daftar lagu masuk dan keluar |

**Koreografi per transisi**

- Closed → live: bentuk melebar dengan `open`. Isi kiri dan kanan fade-in 0,25 detik setelah 0,1 detik.
- Live → expanded: bentuk membesar dengan `open`. Isi turun dari offset −10 pt dan scale 0,94 ke 1 dengan `contentIn`.
- Expanded → closed: isi hilang dengan `contentOut`, baru bentuk mengecil dengan `close`.
- Ganti modul di live (misalnya musik ke Pomodoro): isi lama fade-out dan geser 6 pt ke atas, isi baru masuk dari bawah. Lebar notch tidak berubah, jadi tidak ada lompatan.
- Ganti lagu: cover memakai `matchedGeometryEffect` antara live dan expanded. Cover lama crossfade ke cover baru dalam 0,3 detik.
- Daftar lagu: kartu Now Playing bergeser ke kiri, daftar masuk dari kanan dengan `slide`. Tinggi panel ikut berubah dengan `smooth`.

**Aturan supaya tetap ringan**

1. Window tidak pernah di-resize. Yang dianimasikan hanya `NotchShape` di dalam window berukuran tetap (sudah begitu sekarang, pertahankan).
2. Animasi berulang (visualizer, bara berkedip, naga) hanya berjalan saat terlihat. Saat notch closed atau layar sleep, semuanya berhenti total lewat `environment(\.dragonPaused)` yang diperluas jadi `animationsPaused`.
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
Sources/Notchwyrm/
  App/            entry point, AppModels, DisplayMode, StatusItem
  Notch/          NotchWindow, NotchView, NotchShape, VirtualNotch
  Core/           NotchModule (protokol), ModuleRegistry, PriorityResolver, PopQueue
  Modules/
    Claude/       semua file Claude yang sekarang + ClaudeModule
    Pomodoro/     PomodoroTimer, PomodoroModule, EmberFuse, EmberRing
    Music/        MusicBridge (AppleScript), MusicModule, PlaylistPanel, ArtworkCache
    Info/         BatteryMonitor, CalendarSource, InfoModule
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

Tambahkan `NSAppleEventsUsageDescription` dan `NSCalendarsFullAccessUsageDescription` di `Info.plist` lewat `build-app.sh`. Tidak ada data yang dikirim ke luar selain request limit Claude yang sudah ada.

## Alur kerja Git

Semua pengembangan dilakukan di branch terpisah, di-commit otomatis per langkah, dan tanpa atribusi Claude.

- **Branch:** `main` tetap stabil. Pengembangan berjalan di `feat/notch-hub`. Setiap milestone punya branch turunan (`feat/m1-module-refactor`, `feat/m2-virtual-notch`, dst.) yang di-merge lewat pull request.
- **Auto commit:** setiap satu langkah selesai dan `swift build` lulus, perubahan langsung di-commit dengan format Conventional Commits (`feat:`, `refactor:`, `fix:`, `docs:`).
- **Tanpa atribusi Claude:** commit dan PR tidak memuat `Co-Authored-By: Claude`, link sesi, maupun "Generated with Claude Code". Author commit adalah akun GitHub pemilik repo.
- **Ganti nama repo:** dilakukan lewat GitHub → Settings → General → Repository name. GitHub otomatis mengalihkan URL lama. Setelah itu jalankan `git remote set-url origin <url-baru>` di clone lokal, lalu perbarui URL clone di `README.md`.

## Milestone, kriteria penerimaan, dan risiko

**Milestone** (berurutan, masing-masing bisa dirilis sendiri)

1. **Refactor ke modul.** Protokol `NotchModule`, `PriorityResolver`, dan `PopQueue`. Claude dipindah menjadi modul pertama. Hasil akhir: app terlihat dan berperilaku persis seperti sekarang, dan `--selftest` tetap lulus.
2. **Notch virtual.** Monitor eksternal mendapat notch virtual, plus pilihan baru di `DisplayMode`.
3. **Pomodoro Ember.** Timer, sumbu, bara, mood naga, pop selesai, dan statistik harian.
4. **Apple Music.** Now playing, kontrol, pop ganti lagu, lalu panel daftar lagu.
5. **Info dasar.** Jam, baterai, kalender, dan pop charger.
6. **Polishing dan rename.** Reduce Motion, Settings lengkap, pengukuran performa, ganti nama app menjadi Notchwyrm (target, executable, bundle identifier, ikon, README).

**Kriteria penerimaan**

- [ ] Semua fitur Claude yang sekarang tetap berfungsi setelah refactor
- [ ] `--selftest` diperluas: setiap state setiap modul, di notch asli dan notch virtual
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
- Bahasa teks UI: PRD memakai contoh teks berbahasa Indonesia ("Mulai istirahat", "Siap fokus lagi?"), sedangkan UI yang ada berbahasa Inggris.
    - Keputusan sementara: **UI tetap berbahasa Inggris** supaya konsisten ("Start break", "Skip", "Ready to focus again?", "Focus", "Later").
- Preset "Custom" Pomodoro: di mana durasinya diatur?
    - Keputusan sementara: di Settings → Pomodoro (stepper menit). Chip "Custom" menyala otomatis kalau durasi tidak cocok dengan 25/5 atau 50/10.
- Setelah satu fase selesai, apakah fase berikutnya mulai otomatis?
    - Keputusan sementara: **tidak**. Fase berikutnya disiapkan, dan pop memberi tombol untuk memulainya.
