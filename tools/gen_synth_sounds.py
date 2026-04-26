#!/usr/bin/env python3
"""Generate placeholder synthesized sounds for missing audio keys.

Writes mono 44.1 kHz WAVs into res://audio/sfx/<...> at the paths defined
in audio_config.json. SoundManager already accepts .wav alongside .ogg/.mp3,
so the moment a generated file lands at the right path play_sfx() finds it.

Idempotent: regenerating overwrites existing WAVs but won't touch other
formats (so a real .ogg/.mp3 placed later still wins via lookup order).

Usage:
    python3 tools/gen_synth_sounds.py
"""

from __future__ import annotations

import math
import os
import wave
from pathlib import Path

import numpy as np

SR = 44_100  # sample rate
ROOT = Path(__file__).resolve().parent.parent
AUDIO_ROOT = ROOT / "audio"


# ── Waveform primitives ──────────────────────────────────────────────────────

def t(dur: float) -> np.ndarray:
    return np.linspace(0.0, dur, int(SR * dur), endpoint=False)


def sine(freq: float, dur: float, phase: float = 0.0) -> np.ndarray:
    return np.sin(2 * math.pi * freq * t(dur) + phase)


def square(freq: float, dur: float) -> np.ndarray:
    return np.sign(sine(freq, dur))


def saw(freq: float, dur: float) -> np.ndarray:
    return 2 * (t(dur) * freq - np.floor(0.5 + t(dur) * freq))


def noise(dur: float) -> np.ndarray:
    return np.random.uniform(-1.0, 1.0, int(SR * dur))


def freq_sweep(f1: float, f2: float, dur: float, shape: str = "sine") -> np.ndarray:
    """Linear pitch sweep from f1 → f2 over dur seconds."""
    times = t(dur)
    freqs = np.linspace(f1, f2, len(times))
    phase = 2 * math.pi * np.cumsum(freqs) / SR
    if shape == "sine":
        return np.sin(phase)
    if shape == "saw":
        return 2 * (phase / (2 * math.pi) - np.floor(0.5 + phase / (2 * math.pi)))
    return np.sign(np.sin(phase))


def env_adsr(dur: float, attack: float, decay: float, sustain: float, release: float) -> np.ndarray:
    """Attack/decay/sustain/release envelope as a per-sample multiplier."""
    n = int(SR * dur)
    e = np.ones(n)
    a = int(SR * attack)
    d = int(SR * decay)
    r = int(SR * release)
    # attack: 0 → 1
    if a > 0:
        e[:a] = np.linspace(0.0, 1.0, a)
    # decay: 1 → sustain
    if d > 0:
        end = min(a + d, n)
        e[a:end] = np.linspace(1.0, sustain, end - a)
    # body sustains
    body_end = max(0, n - r)
    e[a + d:body_end] *= sustain if body_end > a + d else 1.0
    # release: sustain → 0
    if r > 0:
        e[body_end:] = np.linspace(e[body_end - 1] if body_end > 0 else sustain, 0.0, n - body_end)
    return e


def env_decay(dur: float, tau: float = 0.2) -> np.ndarray:
    """Exponential decay envelope — useful for plucks, drips, dings."""
    return np.exp(-t(dur) / tau)


def lowpass(sig: np.ndarray, cutoff: float, q: float = 0.7) -> np.ndarray:
    """Simple one-pole lowpass — cuts noise hash."""
    if cutoff >= SR / 2:
        return sig
    rc = 1.0 / (2 * math.pi * cutoff)
    dt = 1.0 / SR
    a = dt / (rc + dt)
    out = np.zeros_like(sig)
    prev = 0.0
    for i, x in enumerate(sig):
        prev = prev + a * (x - prev)
        out[i] = prev
    return out * q


# ── Persistence ──────────────────────────────────────────────────────────────

def save_wav(path: Path, sig: np.ndarray) -> None:
    # Normalize to ~0.85 peak so different sounds sit at similar perceived
    # loudness, then convert to int16.
    peak = np.max(np.abs(sig))
    if peak > 0:
        sig = sig * (0.85 / peak)
    int16 = np.clip(sig * 32767, -32768, 32767).astype(np.int16)
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(int16.tobytes())
    print(f"  wrote {path.relative_to(ROOT)}  ({len(sig) / SR:.2f}s)")


# ── Sound recipes ────────────────────────────────────────────────────────────

def player_death() -> np.ndarray:
    """Descending sad whoosh — pitch falls from 220 → 70 Hz over 0.7s."""
    body = freq_sweep(220.0, 70.0, 0.7, "sine") * env_adsr(0.7, 0.02, 0.1, 0.7, 0.5)
    return body


def player_respawn() -> np.ndarray:
    """Ascending hopeful breath — sweep 180 → 380 Hz, soft sine."""
    body = freq_sweep(180.0, 380.0, 0.5, "sine") * env_adsr(0.5, 0.15, 0.05, 0.9, 0.25)
    return body * 0.6


def enemy_alert() -> np.ndarray:
    """Quick up-pitch ping — 600 → 950 Hz, sharp attack."""
    body = freq_sweep(600.0, 950.0, 0.18, "sine") * env_decay(0.18, 0.06)
    return body


def enemy_chase() -> np.ndarray:
    """Ominous descending growl — saw wave 200 → 90 Hz with vibrato."""
    base = freq_sweep(200.0, 90.0, 0.5, "saw")
    vib = 1.0 + 0.05 * np.sin(2 * math.pi * 6.0 * t(0.5))
    body = base * vib * env_adsr(0.5, 0.05, 0.1, 0.8, 0.3)
    return lowpass(body, 800.0, 1.0) * 0.7


def water_drip() -> np.ndarray:
    """Damped sine pluck around 800 Hz — short bell."""
    body = sine(820.0, 0.18) * env_decay(0.18, 0.05)
    return body * 0.5


def chain_clank() -> np.ndarray:
    """Metallic hit: short noise burst + 380 Hz body, decaying fast."""
    metal = sine(380.0, 0.25) * env_decay(0.25, 0.08)
    hit = noise(0.05) * env_decay(0.05, 0.015)
    out = np.zeros(int(SR * 0.25))
    out[:len(hit)] += hit * 0.6
    out += metal * 0.7
    return lowpass(out, 4000.0, 1.0)


def ui_pause_open() -> np.ndarray:
    """Two-note ascending chime — C5 + E5 stacked."""
    c5 = sine(523.25, 0.35) * env_adsr(0.35, 0.005, 0.05, 0.7, 0.25)
    e5 = sine(659.25, 0.35) * env_adsr(0.35, 0.005, 0.05, 0.7, 0.25)
    return (c5 + e5 * 0.7) * 0.5


def ui_level_complete() -> np.ndarray:
    """Triumphant arpeggio C → E → G → C across 0.6s."""
    notes = [(261.63, 0.0), (329.63, 0.12), (392.00, 0.24), (523.25, 0.36)]
    total = 0.65
    out = np.zeros(int(SR * total))
    for f, start in notes:
        seg = sine(f, 0.25) * env_adsr(0.25, 0.005, 0.04, 0.8, 0.2)
        i = int(start * SR)
        end = min(i + len(seg), len(out))
        out[i:end] += seg[: end - i] * 0.55
    return out


def ui_star_soft() -> np.ndarray:
    """Soft single-note chime — A5, gentle."""
    body = sine(880.0, 0.4) * env_adsr(0.4, 0.01, 0.08, 0.6, 0.3)
    return body * 0.5


def ui_star_gold() -> np.ndarray:
    """Brighter chime + harmonic — A5 + E6, slightly longer."""
    a5 = sine(880.0, 0.55) * env_adsr(0.55, 0.005, 0.08, 0.7, 0.4)
    e6 = sine(1318.5, 0.55) * env_adsr(0.55, 0.005, 0.08, 0.5, 0.4)
    return (a5 + e6 * 0.6) * 0.5


def bonus_expiring_tick() -> np.ndarray:
    """Short high blip — square 1000 Hz, 0.05s."""
    body = square(1000.0, 0.05) * env_decay(0.05, 0.012)
    return body * 0.4


# ── Job table ────────────────────────────────────────────────────────────────

JOBS: list[tuple[str, callable]] = [
    ("audio/sfx/player/death_gasp.wav",        player_death),
    ("audio/sfx/player/respawn_breath.wav",    player_respawn),
    ("audio/sfx/enemy/alert_grunt.wav",        enemy_alert),
    ("audio/sfx/enemy/chase_growl.wav",        enemy_chase),
    ("audio/sfx/env/water_drip.wav",           water_drip),
    ("audio/sfx/env/chain_clank.wav",          chain_clank),
    ("audio/sfx/ui/pause_chime.wav",           ui_pause_open),
    ("audio/sfx/ui/level_complete_chime.wav",  ui_level_complete),
    ("audio/sfx/ui/star_soft.wav",             ui_star_soft),
    ("audio/sfx/ui/star_gold.wav",             ui_star_gold),
    ("audio/sfx/bonus/expiring_tick.wav",      bonus_expiring_tick),
]


def main() -> int:
    print(f"Generating {len(JOBS)} synth sounds → {AUDIO_ROOT.relative_to(ROOT)}/")
    for rel, fn in JOBS:
        sig = fn()
        save_wav(ROOT / rel, sig)
    print("Done. Run Godot --headless --import to register the new files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
