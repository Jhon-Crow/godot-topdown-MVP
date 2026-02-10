#!/usr/bin/env python3
"""
Generate a sci-fi "teleportation" sound effect.

Produces a short (0.5s) electronic whoosh/zap sound by layering:
  1. A descending frequency sweep (sine) - the core "zap" feel
  2. A quick rising chirp at start - the "wind-up"
  3. White noise burst with envelope - the "whoosh"
  4. Simple reverb via convolution with an exponential decay impulse

Output: 44100 Hz, 16-bit PCM WAV
"""

import numpy as np
import struct
import wave
import os


# -- Parameters --------------------------------------------------------------

SAMPLE_RATE = 44100
DURATION = 0.50          # seconds
NUM_SAMPLES = int(SAMPLE_RATE * DURATION)
OUTPUT_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "assets", "audio", "teleport_activation.wav",
)

t = np.linspace(0, DURATION, NUM_SAMPLES, endpoint=False)


# -- Layer 1: Quick rising chirp at start (wind-up) --------------------------
# Very short sweep from 1000 Hz to 3000 Hz

chirp_duration = 0.08  # seconds
chirp_samples = int(chirp_duration * SAMPLE_RATE)

chirp = np.zeros(NUM_SAMPLES)
chirp_t = np.linspace(0, chirp_duration, chirp_samples, endpoint=False)

f_chirp_start = 1000.0
f_chirp_end = 3000.0
freq_chirp = f_chirp_start * np.exp(chirp_t / chirp_duration * np.log(f_chirp_end / f_chirp_start))
phase_chirp = 2.0 * np.pi * np.cumsum(freq_chirp) / SAMPLE_RATE
chirp_wave = np.sin(phase_chirp)

# Envelope: quick attack, exponential decay
chirp_env = np.exp(-chirp_t / 0.02)
chirp_env[:int(0.002 * SAMPLE_RATE)] *= np.linspace(0, 1, int(0.002 * SAMPLE_RATE))
chirp_wave *= chirp_env

chirp[:chirp_samples] = chirp_wave * 0.3


# -- Layer 2: Descending frequency sweep (main zap) --------------------------
# Sweep from 2500 Hz down to 200 Hz

f_start = 2500.0
f_end = 200.0
# Instantaneous frequency drops exponentially
freq_t = f_start * np.exp(t / DURATION * np.log(f_end / f_start))
# Phase is the integral of frequency
phase_sweep = 2.0 * np.pi * np.cumsum(freq_t) / SAMPLE_RATE
sweep = np.sin(phase_sweep)

# Amplitude envelope: quick fade in, sustain, then fade out
env_sweep = np.ones(NUM_SAMPLES)
fade_in_len = int(0.02 * SAMPLE_RATE)   # 20 ms fade-in
fade_out_len = int(0.15 * SAMPLE_RATE)  # 150 ms fade-out
env_sweep[:fade_in_len] = np.linspace(0, 1, fade_in_len)
env_sweep[-fade_out_len:] = np.linspace(1, 0, fade_out_len)

sweep *= env_sweep * 0.4  # moderate volume


# -- Layer 3: White noise burst (whoosh) --------------------------------------
# Short burst of filtered white noise

np.random.seed(123)  # reproducible
noise = np.random.randn(NUM_SAMPLES) * 0.15

# Envelope: peaks in the middle, fades at both ends
noise_env = np.ones(NUM_SAMPLES)
noise_env[:fade_in_len] = np.linspace(0, 1, fade_in_len)
noise_env[-fade_out_len:] = np.linspace(1, 0, fade_out_len)

# Add a mid-peak emphasis
mid_peak = np.exp(-((np.arange(NUM_SAMPLES) - NUM_SAMPLES * 0.3) ** 2) / (NUM_SAMPLES * 0.1) ** 2)
noise_env *= (0.5 + 0.5 * mid_peak)

noise *= noise_env

# Simple low-pass filter on noise (rolling average)
kernel_size = 20
noise = np.convolve(noise, np.ones(kernel_size) / kernel_size, mode='same')


# -- Layer 4: Sub-bass rumble for depth ---------------------------------------
# A very low frequency (40-80 Hz) sine wave for extra impact

bass_f_start = 40.0
bass_f_end = 80.0
bass_freq_t = bass_f_start + (bass_f_end - bass_f_start) * (t / DURATION)
bass_phase = 2.0 * np.pi * np.cumsum(bass_freq_t) / SAMPLE_RATE
bass = np.sin(bass_phase)

# Quick attack and decay
bass_env = np.exp(-t / 0.15)
bass_env[:int(0.01 * SAMPLE_RATE)] *= np.linspace(0, 1, int(0.01 * SAMPLE_RATE))

bass *= bass_env * 0.25


# -- Mix layers ---------------------------------------------------------------

mixed = chirp + sweep + noise + bass


# -- Simple reverb (convolution with exponential decay impulse) ---------------

reverb_duration = 0.12  # seconds
reverb_samples = int(reverb_duration * SAMPLE_RATE)
impulse = np.zeros(reverb_samples)
impulse[0] = 1.0

# A few discrete early reflections
for delay_ms, gain in [(5, 0.25), (12, 0.18), (22, 0.10), (40, 0.05)]:
    idx = int(delay_ms * SAMPLE_RATE / 1000)
    if idx < reverb_samples:
        impulse[idx] = gain

# Exponential tail
reverb_t = np.linspace(0, reverb_duration, reverb_samples, endpoint=False)
np.random.seed(456)  # reproducible
impulse += 0.06 * np.exp(-reverb_t / 0.025) * (np.random.rand(reverb_samples) * 0.4 + 0.6)

# Normalize impulse so dry signal level is preserved
impulse /= np.sum(np.abs(impulse))
impulse *= 2.0  # slight wet boost

wet = np.convolve(mixed, impulse)[:NUM_SAMPLES]

# Blend dry/wet
output = 0.65 * mixed + 0.35 * wet


# -- Normalize & convert to 16-bit PCM ----------------------------------------

# Normalize to ~70% of full scale (not too loud)
peak = np.max(np.abs(output))
if peak > 0:
    output = output / peak * 0.70

# Convert to int16
output_int16 = np.clip(output * 32767, -32768, 32767).astype(np.int16)


# -- Write WAV file ------------------------------------------------------------

os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)

with wave.open(OUTPUT_PATH, 'w') as wf:
    wf.setnchannels(1)           # mono
    wf.setsampwidth(2)           # 16-bit = 2 bytes
    wf.setframerate(SAMPLE_RATE) # 44100 Hz
    wf.writeframes(output_int16.tobytes())

print(f"Generated: {OUTPUT_PATH}")
print(f"  Duration : {DURATION:.2f} s ({NUM_SAMPLES} samples)")
print(f"  Format   : 44100 Hz, 16-bit PCM, mono")
print(f"  File size: {os.path.getsize(OUTPUT_PATH)} bytes")
