class_name Palette extends RefCounted

# Named-colour constants for the entire UI. Replace hex strings and
# raw Color(...) calls in screens with `Palette.GOLD` etc. so a single
# tweak ripples everywhere — re-skinning the game becomes a one-file edit.
#
# Naming: SCREAMING_SNAKE_CASE, grouped by intent (not hue) so we can
# re-skin without renaming references in callers.
#
# Tests preload the script directly; runtime code uses `Palette.X`
# via the editor-registered class_name.

# ── Brand ─────────────────────────────────────────────────────────────────────
const GOLD             := Color("#FFD700")
const GOLD_DIM         := Color("#CC9F00")
const HELL_RED         := Color("#CC3322")
const HELL_RED_DIM     := Color("#992211")

# ── Backgrounds ───────────────────────────────────────────────────────────────
const BG_BLACK         := Color(0.04, 0.03, 0.06)
const BG_DARK          := Color(0.08, 0.07, 0.10)
const BG_DARKER        := Color(0.05, 0.04, 0.08, 0.97)
const BG_PANEL         := Color(0.12, 0.11, 0.16)
const BG_PANEL_HOVER   := Color(0.20, 0.18, 0.24)
const BG_PANEL_PRESSED := Color(0.09, 0.08, 0.12)

# ── Text ──────────────────────────────────────────────────────────────────────
const TEXT_DISPLAY     := Color(0.96, 0.94, 0.99)   # bright headlines
const TEXT_PRIMARY     := Color(0.92, 0.90, 0.98)   # body
const TEXT_SECONDARY   := Color(0.82, 0.80, 0.86)   # labels
const TEXT_MUTED       := Color(0.55, 0.52, 0.62)   # placeholders, hints
const TEXT_DISABLED    := Color(0.35, 0.33, 0.40)

# ── Accents ───────────────────────────────────────────────────────────────────
const ACCENT_GREEN     := Color(0.50, 0.72, 0.42)
const ACCENT_BLUE      := Color(0.42, 0.62, 0.92)
const ACCENT_ORANGE    := Color("#FF8866")
const SIN_RED          := Color(0.78, 0.18, 0.18)

# ── Borders ───────────────────────────────────────────────────────────────────
const BORDER_DIM       := Color(0.32, 0.27, 0.18)
const BORDER_NEUTRAL   := Color(0.24, 0.22, 0.30)
const BORDER_HOVER     := Color(0.38, 0.35, 0.46)
const BORDER_PRIMARY   := Color(0.45, 0.15, 0.15)
const BORDER_PRIMARY_H := Color(0.65, 0.22, 0.22)

# ── Status ────────────────────────────────────────────────────────────────────
const SUCCESS          := Color(0.55, 0.85, 0.50)
const WARNING          := Color(0.95, 0.75, 0.30)
const DANGER           := Color(0.95, 0.35, 0.30)

# ── Button base flavors ───────────────────────────────────────────────────────
const BTN_PRIMARY_BG   := Color(0.30, 0.08, 0.08)
const BTN_PRIMARY_BG_H := Color(0.44, 0.12, 0.12)
const BTN_PRIMARY_BG_P := Color(0.22, 0.05, 0.05)
const BTN_DANGER_BG    := Color(0.20, 0.05, 0.05)
