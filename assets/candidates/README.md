# Wyrmwatch mascot candidates

Searched 5 Nov 2026 via the Iconify API (which covers Tabler, Game Icons, Font Awesome, Line Awesome and many other open sets), plus the Rive and LottieFiles communities. Criteria: a slender, serpentine dragon (wyrm) or an expressive dragon head; not chibi or round cartoon; readable at 24–48 px; ideally animatable per part. Licences allowed: CC0, CC BY, MIT, or otherwise free for commercial use. NC, SA and unclear licences are left out.

`preview.png` shows each candidate large, at 24 px and at 40 px.

| # | Name | Link | Format | Licence + attribution | Animatable per part? | Login? | Notes |
|---|------|------|--------|------------------------|----------------------|--------|-------|
| 1 | Tabler "dragon" | https://tabler.io/icons/icon/dragon | SVG, 4 stroked paths | MIT. Keep the MIT notice: "Tabler Icons, © Paweł Kuna" | **Yes**: wing, S-shaped body, head and crest are separate paths; the jaw and eye are split out of the head | No | **Chosen as the temporary mascot.** Slender serpent with a wing; its line style matches the tab icons; reads well at 24 px. |
| 2 | Game Icons "sea-dragon" (Lorc) | https://game-icons.net/1x1/lorc/sea-dragon.html | SVG, 1 filled path | CC BY 3.0: "Sea dragon by Lorc, game-icons.net" | Only by cutting the single path into regions | No | The strongest wyrm silhouette (horned S curve). Good fallback if a filled look is preferred. |
| 3 | Game Icons "dragon-spiral" (Lorc) | https://game-icons.net/1x1/lorc/dragon-spiral.html | SVG, 1 filled path | CC BY 3.0: "Dragon spiral by Lorc, game-icons.net" | Only by cutting the path | No | A coiled wyrm: a natural pose for "sleep". |
| 4 | Game Icons "dragon-head" (Lorc) | https://game-icons.net/1x1/lorc/dragon-head.html | SVG, 1 filled path | CC BY 3.0: "Dragon head by Lorc, game-icons.net" | Only by cutting the path | No | Expressive head with an open, toothed jaw; busy at 24 px. |
| 5 | Font Awesome "dragon" | https://fontawesome.com/icons/dragon?s=solid | SVG, 1 filled path | CC BY 4.0: "Font Awesome by Fonticons, Inc." | Only by cutting the path | No | Well-known and generic; reads well but has little character. |
| 6 | Line Awesome "dragon" (Icons8) | https://icons8.com/line-awesome/icon/dragon | SVG, 1 path | Apache 2.0 (keep the licence notice) | Only by cutting the path | No | Eastern-style head, thin outline; gets muddy below 32 px. |
| 7 | IconOven "dragon-sharp" | https://iconoven.com/icons | SVG, 3 paths | Listed as MIT on Iconify, but the source site publishes no licence file: **unclear, not recommended** | Partly (3 paths) | No | Angular head; shown for comparison only. |
| 8 | Rive Community, search "dragon" | https://rive.app/community/files?search=dragon | .riv with state machines | Per file (many are free to remix; check each) | Yes, built for it | **Yes, to download or remix** | The best fit for the final mascot (state machine with inputs). Needs your account; not downloaded. LottieFiles (https://lottiefiles.com/search?q=dragon) is similar but also needs a login to download, and Lottie has no state machine inputs. |

Not included: emoji sets (Noto, Twemoji, Fluent, Emoji One) for being colourful and cartoon-like; OpenMoji and Arcticons for being CC BY-SA; "with icons" dragon heads for being round and chibi-like.

## The temporary mascot

`Views/WyrmArt.swift` redraws candidate 1 (Tabler "dragon", MIT) as separate Core Animation layers: wing, body, crest, skull, jaw and eye, so each can move on its own: the eye blinks, the head turns towards the pointer on a spring, and the jaw opens with a short burst of flame on "done". It is used until a `Resources/wyrm.riv` exists.
