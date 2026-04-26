# Audio Credits

## SFX

All current sound effects are sourced from **Kenney.nl** asset packs,
licensed CC0 (public domain — no attribution required).

- [Impact Sounds](https://kenney.nl/assets/impact-sounds) — footsteps, landing thuds
- [UI Audio](https://kenney.nl/assets/ui-audio) — clicks, hovers, switches
- [Casino Audio](https://kenney.nl/assets/casino-audio) — chip sounds repurposed for soul/bonus pickup chimes
- [Sci-Fi Sounds](https://kenney.nl/assets/sci-fi-sounds) — force-field whoosh repurposed for jump

## Mapping

| In-game key | Source file | Re-purposed as |
|---|---|---|
| player.jump | impact/footstep_concrete_001.ogg | takeoff stomp (forceField_004 was too techno) |
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
