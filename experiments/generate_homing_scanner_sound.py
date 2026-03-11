#!/usr/bin/env python3
"""
Generate a quiet looping sci-fi scanner sound for the Homing Bullets active item.

Produces a looping ~2s ambient "scanning" loop by layering:
  1. A slow sine sweep (200-600 Hz) cycling as a tracker/sweep pattern
  2. Subtle white noise (very quiet texture)
  3. Periodic soft "ping" pulses to simulate scanner sweeps
  4. Seamlessly loopable (start and end frames aligned)

Output: 44100 Hz, 16-bit PCM WAV, designed for AudioStreamWAV looping
"""

import numpy as np
import struct
import wave
import os


# -- Parameters --------------------------------------------------------------

SAMPLE_RATE = 44100
DURATION = 2.0           # seconds (seamlessly loopable)
NUM_SAMPLES = int(SAMPLE_RATE * DURATION)
OUTPUT_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "assets", "audio", "homing_scanner_loop.wav",
)

t = np.linspace(0, DURATION, NUM_SAMPLES, endpoint=False)


# -- Layer 1: Slow sine sweep background (scanner oscillation) ---------------
# A low-frequency sine that oscillates between 300 Hz and 700 Hz over 2 seconds
# Using a smooth cosine modulation so it loops seamlessly.

# Frequency modulates with cosine to loop cleanly (starts and ends at same freq)
freq_mod = 500.0 + 200.0 * np.cos(2.0 * np.pi * t / DURATION)  # 300-700 Hz
phase_sweep = 2.0 * np.pi * np.cumsum(freq_mod) / SAMPLE_RATE
sweep = np.sin(phase_sweep)

# Amplitude envelope: gently pulsing via cosine for looping
sweep_env = 0.6 + 0.4 * np.cos(2.0 * np.pi * t / DURATION + np.pi)
# Starts at 0.2 amplitude, peaks at 1.0 at midpoint, returns to 0.2
sweep_env = 0.4 + 0.6 * np.sin(np.pi * t / DURATION) ** 2

sweep *= sweep_env * 0.10  # keep it very quiet (scanner background)


# -- Layer 2: Very quiet white noise texture ---------------------------------
np.random.seed(12345)  # reproducible
noise = np.random.randn(NUM_SAMPLES)

# Low-pass filter the noise to make it "whooshy" rather than harsh
# Simple FIR rolling average as low-pass
kernel_size = 64
noise_lp = np.convolve(noise, np.ones(kernel_size) / kernel_size, mode='same')

noise_lp *= 0.04  # very subtle texture


# -- Layer 3: Periodic scanner pings -----------------------------------------
# Every 0.5 seconds, emit a subtle electronic ping
# This creates a "scanning" rhythm

ping_interval = 0.5   # seconds between pings
ping_duration = 0.08  # seconds per ping
ping_freq = 1200.0    # Hz

pings = np.zeros(NUM_SAMPLES)
num_pings = int(DURATION / ping_interval)

for i in range(num_pings):
    start_time = i * ping_interval + 0.05  # small offset from loop start
    start_sample = int(start_time * SAMPLE_RATE)
    ping_samples = int(ping_duration * SAMPLE_RATE)

    if start_sample + ping_samples > NUM_SAMPLES:
        break

    ping_t = np.linspace(0, ping_duration, ping_samples, endpoint=False)
    ping_wave = np.sin(2.0 * np.pi * ping_freq * ping_t)

    # Fast attack, exponential decay envelope
    env = np.exp(-ping_t / 0.015)
    env[:int(0.002 * SAMPLE_RATE)] *= np.linspace(0, 1, int(0.002 * SAMPLE_RATE))

    pings[start_sample:start_sample + ping_samples] += ping_wave * env * 0.12


# -- Layer 4: Sub-harmonic hum for depth ------------------------------------
# Very quiet 100 Hz hum for electronic ambience
hum_freq = 100.0
hum = np.sin(2.0 * np.pi * hum_freq * t)
hum_env = 0.5 + 0.5 * np.sin(np.pi * t / DURATION) ** 2  # peaks mid-loop
hum *= hum_env * 0.05


# -- Mix layers ---------------------------------------------------------------
mixed = sweep + noise_lp + pings + hum


# -- Normalize for seamless looping -------------------------------------------
# Ensure the first and last 20ms fade so the loop is seamless
fade_len = int(0.02 * SAMPLE_RATE)  # 20ms

# Create smooth fade in/out for loop stitching
fade_in = np.linspace(0, 1, fade_len)
fade_out = np.linspace(1, 0, fade_len)

mixed[:fade_len] *= fade_in
mixed[-fade_len:] *= fade_out


# -- Normalize & convert to 16-bit PCM ----------------------------------------
# Normalize to ~30% of full scale (quiet scanner ambient sound)
peak = np.max(np.abs(mixed))
if peak > 0:
    mixed = mixed / peak * 0.30

# Convert to int16
output_int16 = np.clip(mixed * 32767, -32768, 32767).astype(np.int16)


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
print(f"  This sound is designed to loop seamlessly.")
