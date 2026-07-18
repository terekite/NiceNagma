"""fluidsynth wrapper: render a MIDI file to a WAV using a soundfont.

This is the ONLY place that shells out to the sampler. Keeping it isolated means
swapping fluidsynth for sfizz, or porting to an on-device library later, touches
exactly one file.
"""

from __future__ import annotations

import shutil
import subprocess


class SamplerNotAvailable(RuntimeError):
    """fluidsynth binary not found on PATH."""


def fluidsynth_available() -> bool:
    return shutil.which("fluidsynth") is not None


def render_midi_to_wav(
    midi_path: str,
    soundfont_path: str,
    wav_path: str,
    *,
    sample_rate: int = 44100,
    gain: float = 0.8,
) -> None:
    """Render `midi_path` to `wav_path` using `soundfont_path` via fluidsynth."""
    if not fluidsynth_available():
        raise SamplerNotAvailable(
            "fluidsynth not found on PATH. Install it (macOS: `brew install "
            "fluid-synth`) to render audio."
        )

    cmd = [
        "fluidsynth",
        "-ni",                     # no shell, no MIDI-in
        "-F", wav_path,            # render to file
        "-r", str(sample_rate),    # sample rate
        "-g", str(gain),           # master gain
        "-R", "0",                 # algorithmic reverb OFF (mastering adds a room IR)
        "-C", "0",                 # chorus OFF
        soundfont_path,
        midi_path,
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(
            f"fluidsynth failed (exit {proc.returncode}):\n{proc.stderr.strip()}"
        )
