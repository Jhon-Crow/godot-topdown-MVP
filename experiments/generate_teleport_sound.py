#!/usr/bin/env python3
"""
Generate a sci-fi "teleportation" sound effect.

Produces a short (0.6s) electronic teleport sound by layering:
  1. A descending frequency sweep with pitch bend effect
  2. A "whoosh" noise burst for the teleportation effect
  3. A high-pitched crystalline shimmer at the end
  4. A subtle low-frequency rumble for mass displacement

Output: 44100 Hz, 16-bit PCM WAV
"""

import numpy as np
import struct
import wave
import os


# -- Parameters --------------------------------------------------------------

SAMPLE_RATE = 44100
DURATION = 0.60          # seconds
NUM_SAMPLES = int(SAMPLE_RATE * DURATION)
OUTPUT_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "assets", "audio", "teleportation.wav",
)

t = np.linspace(0, DURATION, NUM_SAMPLES, endpoint=False)


# -- Layer 1: Main pitch bend sweep (descending) -----------------------------
# Creates the classic "teleport" pitch-down effect

f_start = 1200.0
f_end = 200.0
# Exponential frequency drop for sci-fi feel
freq_t = f_start * np.exp(t / DURATION * np.log(f_end / f_start))
# Phase is the integral of frequency
phase_sweep = 2.0 * np.pi * np.cumsum(freq_t) / SAMPLE_RATE
sweep = np.sin(phase_sweep)

# Amplitude envelope: quick attack, sustain, then quick release
env_sweep = np.ones(NUM_SAMPLES)
fade_in_len = int(0.02 * SAMPLE_RATE)   # 20 ms fade-in
fade_out_len = int(0.08 * SAMPLE_RATE)  # 80 ms fade-out
env_sweep[:fade_in_len] = np.linspace(0, 1, fade_in_len)
env_sweep[-fade_out_len:] = np.linspace(1, 0, fade_out_len)

sweep *= env_sweep * 0.4  # moderate volume


# -- Layer 2: Whoosh noise burst ---------------------------------------------
# White noise filtered to create "air displacement" effect

# Generate white noise
np.random.seed(123)  # reproducible
noise = np.random.randn(NUM_SAMPLES)

# Apply band-pass filter (simple convolution approach)
# Focus on mid frequencies for whoosh effect
low_cutoff = 800.0
high_cutoff = 4000.0

# Simple low-pass using moving average
kernel_size = int(SAMPLE_RATE / low_cutoff / 2)
if kernel_size > 1:
    noise_low = np.convolve(noise, np.ones(kernel_size) / kernel_size, mode='same')
else:
    noise_low = noise

# Simple high-pass by subtracting low-pass
kernel_size_high = int(SAMPLE_RATE / high_cutoff / 2)
if kernel_size_high > 1:
    noise_very_low = np.convolve(noise, np.ones(kernel_size_high) / kernel_size_high, mode='same')
    noise_band = noise_low - noise_very_low
else:
    noise_band = noise_low

# Envelope: quick burst in the middle
whoosh_env = np.zeros(NUM_SAMPLES)
whoosh_start = int(0.1 * SAMPLE_RATE)
whoosh_end = int(0.4 * SAMPLE_RATE)
whoosh_env[whoosh_start:whoosh_end] = np.exp(-np.linspace(0, 3, whoosh_end - whoosh_start))

whoosh = noise_band * whoosh_env * 0.15


# -- Layer 3: Crystalline shimmer (high frequency) ---------------------------
# Creates the "energy crystallization" effect at the end

shimmer_duration = 0.15  # seconds
shimmer_samples = int(shimmer_duration * SAMPLE_RATE)
shimmer_freq = 4800.0

shimmer = np.zeros(NUM_SAMPLES)
shimmer_t = np.linspace(0, shimmer_duration, shimmer_samples, endpoint=False)

# Create shimmer with multiple harmonics
shimmer_wave = (
    np.sin(2.0 * np.pi * shimmer_freq * shimmer_t) * 0.5 +
    np.sin(2.0 * np.pi * shimmer_freq * 1.5 * shimmer_t) * 0.3 +
    np.sin(2.0 * np.pi * shimmer_freq * 2.0 * shimmer_t) * 0.2
)

# Add some tremolo for sparkle effect
tremolo = 0.5 + 0.5 * np.sin(2.0 * np.pi * 20.0 * shimmer_t)  # 20 Hz tremolo
shimmer_wave *= tremolo

# Envelope: fade in and out
shimmer_env = np.sin(np.pi * shimmer_t / shimmer_duration)  # single sine wave envelope
shimmer_wave *= shimmer_env

# Place the shimmer near the end
shimmer_start = NUM_SAMPLES - shimmer_samples - int(0.05 * SAMPLE_RATE)
shimmer[shimmer_start:shimmer_start + shimmer_samples] = shimmer_wave * 0.25


# -- Layer 4: Low-frequency rumble -------------------------------------------
# Simulates the mass displacement effect

rumble_freq = 60.0  # low frequency rumble
rumble = np.sin(2.0 * np.pi * rumble_freq * t)

# Envelope: quick thump at the beginning
rumble_env = np.zeros(NUM_SAMPLES)
rumble_duration = int(0.15 * SAMPLE_RATE)
rumble_env[:rumble_duration] = np.exp(-np.linspace(0, 8, rumble_duration))

rumble *= rumble_env * 0.2


# -- Mix layers --------------------------------------------------------------

mixed = sweep + whoosh + shimmer + rumble


# -- Simple reverb (convolution with exponential decay impulse) ------------

reverb_duration = 0.10  # seconds
reverb_samples = int(reverb_duration * SAMPLE_RATE)
impulse = np.zeros(reverb_samples)
impulse[0] = 1.0
# A few discrete early reflections
for delay_ms, gain in [(12, 0.25), (25, 0.15), (40, 0.08), (65, 0.04)]:
    idx = int(delay_ms * SAMPLE_RATE / 1000)
    if idx < reverb_samples:
        impulse[idx] = gain

# Exponential tail with some diffusion
reverb_t = np.linspace(0, reverb_duration, reverb_samples, endpoint=False)
np.random.seed(456)  # reproducible
impulse += 0.06 * np.exp(-reverb_t / 0.025) * (np.random.rand(reverb_samples) * 0.4 + 0.6)

# Normalize impulse so dry signal level is preserved
impulse /= np.sum(np.abs(impulse))
impulse *= 2.0  # slight wet boost

wet = np.convolve(mixed, impulse)[:NUM_SAMPLES]

# Blend dry/wet
output = 0.7 * mixed + 0.3 * wet


# -- Normalize & convert to 16-bit PCM ----------------------------------------

# Normalize to ~65% of full scale (slightly quieter than homing sound)
peak = np.max(np.abs(output))
if peak > 0:
    output = output / peak * 0.65

# Convert to int16
output_int16 = np.clip(output * 32767, -32768, 32767).astype(np.int16)


# -- Write WAV file ----------------------------------------------------------

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