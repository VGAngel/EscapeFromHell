# Audio Credits

## SFX

Most current sound effects come from **Kenney.nl** asset packs (CC0, no
attribution required); the jump sound is from a **freesound.org community
sample** (also CC0).

- [Impact Sounds](https://kenney.nl/assets/impact-sounds) — footsteps, landing thuds
- [UI Audio](https://kenney.nl/assets/ui-audio) — clicks, hovers, switches
- [Casino Audio](https://kenney.nl/assets/casino-audio) — chip sounds repurposed for soul/bonus pickup chimes
- [Sci-Fi Sounds](https://kenney.nl/assets/sci-fi-sounds) — kept around for future weapons / environment cues
- [Freesound community sample 30946](https://freesound.org/) — dedicated jump-landing whoosh

## Mapping

| In-game key | Source file | Re-purposed as |
|---|---|---|
| player.jump | freesound community sample 30946 (mp3) | dedicated jump-and-landing whoosh |
| player.footstep_stone | impact/footstep_concrete_002.ogg | step on stone |
| player.land_soft | impact/footstep_concrete_004.ogg | low landing |
| player.land_hard | impact/impactBell_heavy_000.ogg | high-fall thud |
| player.hurt | impact/impactGeneric_light_002.ogg | hit reaction (placeholder) |
| souls.pickup_resonance | casino/chips-stack-1.ogg | soul collected |
| souls.delivered | casino/chips-handle-1.ogg | altar delivery chime |
| bonuses.pickup_generic | casino/chip-lay-1.ogg | bonus collected |
| ui.button_click | ui/click1.ogg | auto-wired on every BaseButton |
| ui.button_hover | ui/rollover1.ogg | (not yet wired) |
| ui.toggle_on | ui/switch1.ogg | (not yet wired) |
| ui.toggle_off | ui/switch2.ogg | (not yet wired) |
| ui.tab_soft | ui/click3.ogg | (not yet wired) |

`audio_config.json` keys for `souls.innocent_idle`, `enemies.*`, `environment.*`,
`music.*` etc. are still empty — no asset shipped, `play_sfx`/`play_music` is a
no-op until files arrive.
