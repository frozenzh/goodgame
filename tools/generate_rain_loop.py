"""Regenerate the seamless rain ambience from filtered periodic noise.

Uses the bundled workspace Python with NumPy. No downloaded recording or AI
audio source is involved. The inverse FFT makes the first and last samples
adjacent in a periodic waveform.
"""

from pathlib import Path
import wave

import numpy as np


RATE = 22_050
SECONDS = 6
SAMPLES = RATE * SECONDS
OUTPUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "rain_ambient_loop.wav"

rng = np.random.default_rng(20261027)
frequencies = np.fft.rfftfreq(SAMPLES, 1 / RATE)
spectrum = rng.normal(size=len(frequencies)) + 1j * rng.normal(size=len(frequencies))
band = np.clip((frequencies - 110) / 280, 0, 1) * np.clip((6000 - frequencies) / 3200, 0, 1)
spectrum *= band / np.sqrt(np.maximum(frequencies, 1))
spectrum[0] = 0
samples = np.fft.irfft(spectrum, n=SAMPLES)
samples /= max(float(np.max(np.abs(samples))), 1e-9)
samples *= 0.20

OUTPUT.parent.mkdir(parents=True, exist_ok=True)
with wave.open(str(OUTPUT), "wb") as audio:
    audio.setnchannels(1)
    audio.setsampwidth(2)
    audio.setframerate(RATE)
    audio.writeframes((samples * 32767).astype("<i2").tobytes())

print(OUTPUT)
