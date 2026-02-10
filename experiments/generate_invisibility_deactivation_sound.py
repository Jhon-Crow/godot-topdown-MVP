#!/usr/bin/env python3
"""
Generate a sci-fi "invisibility cloak deactivation" sound effect.

Produces a short (0.5s) ethereal power-down sound by layering:
  1. A descending frequency sweep with shimmer fade-out - the "decloaking" feel
  2. A low-frequency power-down resonance at the end
  3. A subtle white noise fade for the cloaking field collapse
  4. Light reverb for spatial presence

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
    "assets", "audio", "invisibility_deactivation.wav",
)

t = np.linspace(0, DURATION, NUM_SAMPLES, endpoint=False)


# -- Layer 1: Ethereal descending frequency sweep ---------------------------
# Sweep from 1200 Hz to 200 Hz with shimmer fade-out for mystical decloaking

f_start = 1200.0
f_end = 200.0
# Instantaneous frequency falls with a gentle curve
freq_t = f_start * (f_end/f_start) ** (t / DURATION)
phase_sweep = 2.0 * np.pi * np.cumsum(freq_t) / SAMPLE_RATE
sweep = np.sin(phase_sweep)

# Add shimmer (fast amplitude modulation) that fades with the sweep
shimmer_freq = 80.0  # Hz modulation rate
shimmer_depth = 0.3
shimmer_env = 1.0 - (t / DURATION)  # Fade shimmer out over time
shimmer = 1.0 + shimmer_depth * shimmer_env * np.sin(2.0 * np.pi * shimmer_freq * t)
sweep *= shimmer

# Amplitude envelope: gentle sustain, smooth fade out (no sharp attack)
env_sweep = np.ones(NUM_SAMPLES)
fade_start = int(0.1 * SAMPLE_RATE)   # Start fade after 100ms
fade_out_len = int(0.4 * SAMPLE_RATE)  # 400ms fade-out
env_sweep[fade_start:] = np.linspace(1, 0, fade_out_len)

sweep *= env_sweep * 0.35


# -- Layer 2: Low-frequency power-down resonance ----------------------------
# A sub-bass resonance that appears in the final third

resonance_start = int(0.3 * SAMPLE_RATE)  # Start at 300ms
resonance_duration = 0.2  # seconds
resonance_samples = int(resonance_duration * SAMPLE_RATE)
resonance_freq = 60.0  # Low frequency for power-down effect

resonance = np.zeros(NUM_SAMPLES)
resonance_t = np.linspace(0, resonance_duration, resonance_samples, endpoint=False)
resonance_wave = np.sin(2.0 * np.pi * resonance_freq * resonance_t)

# Apply envelope (fade in, then exponential decay)
resonance_env = np.exp(-resonance_t / 0.1)
resonance_env[:int(0.02 * SAMPLE_RATE)] *= np.linspace(0, 1, int(0.02 * SAMPLE_RATE))
resonance_wave *= resonance_env

resonance[resonance_start:resonance_start + resonance_samples] += resonance_wave
resonance *= 0.20  # Subtle but present


# -- Layer 3: White noise fade for field collapse ---------------------------

# Generate filtered white noise for the cloaking field collapse
np.random.seed(789)  # Different seed from activation
noise = np.random.randn(NUM_SAMPLES)

# Low-pass filter the noise (simple moving average)
kernel_size = 15
noise = np.convolve(noise, np.ones(kernel_size) / kernel_size, mode='same')

# Apply envelope (fade out throughout the sound)
env_noise = 1.0 - (t / DURATION)  # Linear fade out
env_noise **= 2.0  # Quadratic fade for smoother decay

noise *= env_noise * 0.06  # Very subtle


# -- Mix layers --------------------------------------------------------------

mixed = sweep + resonance + noise


# -- Light reverb for spatial presence ----------------------------------------

reverb_duration = 0.10  # seconds
reverb_samples = int(reverb_duration * SAMPLE_RATE)
impulse = np.zeros(reverb_samples)
impulse[0] = 1.0

# Early reflections for space
for delay_ms, gain in [(8, 0.20), (20, 0.12), (35, 0.08), (55, 0.04)]:
    idx = int(delay_ms * SAMPLE_RATE / 1000)
    if idx < reverb_samples:
        impulse[idx] = gain

# Diffuse tail
reverb_t = np.linspace(0, reverb_duration, reverb_samples, endpoint=False)
np.random.seed(101)
impulse += 0.04 * np.exp(-reverb_t / 0.025) * (np.random.rand(reverb_samples) * 0.4 + 0.6)

# Normalize impulse
impulse /= np.sum(np.abs(impulse))
impulse *= 1.8  # Slight wet boost

wet = np.convolve(mixed, impulse)[:NUM_SAMPLES]

# Blend dry/wet (mostly dry for clarity)
output = 0.85 * mixed + 0.15 * wet


# -- Normalize & convert to 16-bit PCM ----------------------------------------

# Normalize to ~60% of full scale (slightly quieter than activation)
peak = np.max(np.abs(output))
if peak > 0:
    output = output / peak * 0.60

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