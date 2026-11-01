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
