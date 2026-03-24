#!/usr/bin/env python3
"""
Generate a sci-fi "homing lock-on" activation sound effect.

Produces a short (0.4s) electronic chirp/power-up sound by layering:
  1. A rising frequency sweep (sine) - the core "lock-on" feel
  2. A short high-pitched sine ping at the end - the "confirmation beep"
  3. A square-wave undertone for electronic texture
  4. Simple reverb via convolution with an exponential decay impulse

Output: 44100 Hz, 16-bit PCM WAV
"""

import numpy as np
import struct
import wave
import os


# -- Parameters --------------------------------------------------------------

SAMPLE_RATE = 44100
DURATION = 0.40          # seconds
NUM_SAMPLES = int(SAMPLE_RATE * DURATION)
OUTPUT_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "assets", "audio", "homing_activation.wav",
)

t = np.linspace(0, DURATION, NUM_SAMPLES, endpoint=False)


# -- Layer 1: Rising frequency sweep (sine) ----------------------------------
# Sweep from 400 Hz to 2400 Hz with an exponential curve for a sci-fi feel.

f_start = 400.0
f_end = 2400.0
# Instantaneous frequency rises exponentially
freq_t = f_start * np.exp(t / DURATION * np.log(f_end / f_start))
# Phase is the integral of frequency
phase_sweep = 2.0 * np.pi * np.cumsum(freq_t) / SAMPLE_RATE
sweep = np.sin(phase_sweep)

# Amplitude envelope: fade in quickly, sustain, then fade out at the end
env_sweep = np.ones(NUM_SAMPLES)
fade_in_len = int(0.01 * SAMPLE_RATE)   # 10 ms fade-in
fade_out_len = int(0.05 * SAMPLE_RATE)  # 50 ms fade-out
env_sweep[:fade_in_len] = np.linspace(0, 1, fade_in_len)
env_sweep[-fade_out_len:] = np.linspace(1, 0, fade_out_len)

sweep *= env_sweep * 0.45  # moderate volume


# -- Layer 2: Confirmation ping (short high sine burst at the tail) -----------
# A brief 1800 Hz sine tone that appears in the last 80 ms

ping_duration = 0.08  # seconds
ping_samples = int(ping_duration * SAMPLE_RATE)
ping_freq = 1800.0

ping = np.zeros(NUM_SAMPLES)
ping_t = np.linspace(0, ping_duration, ping_samples, endpoint=False)
ping_wave = np.sin(2.0 * np.pi * ping_freq * ping_t)

# Envelope: quick attack, exponential decay
ping_env = np.exp(-ping_t / 0.025)
ping_env[:int(0.003 * SAMPLE_RATE)] *= np.linspace(0, 1, int(0.003 * SAMPLE_RATE))
ping_wave *= ping_env

# Place the ping near the end of the sound
ping_start = NUM_SAMPLES - ping_samples - int(0.02 * SAMPLE_RATE)
ping[ping_start:ping_start + ping_samples] = ping_wave * 0.35


# -- Layer 3: Square-wave undertone for electronic texture --------------------
# A low square wave (200 Hz rising to 600 Hz) adds grit.

sq_f_start = 200.0
sq_f_end = 600.0
sq_freq_t = sq_f_start * np.exp(t / DURATION * np.log(sq_f_end / sq_f_start))
sq_phase = 2.0 * np.pi * np.cumsum(sq_freq_t) / SAMPLE_RATE
square = np.sign(np.sin(sq_phase))

# Soften the square wave slightly (low-pass via simple rolling average)
kernel_size = 5
square = np.convolve(square, np.ones(kernel_size) / kernel_size, mode='same')

square *= env_sweep * 0.12  # keep it subtle


# -- Mix layers ---------------------------------------------------------------

mixed = sweep + ping + square


# -- Simple reverb (convolution with exponential decay impulse) ---------------

reverb_duration = 0.08  # seconds
reverb_samples = int(reverb_duration * SAMPLE_RATE)
impulse = np.zeros(reverb_samples)
impulse[0] = 1.0
# A few discrete early reflections
for delay_ms, gain in [(8, 0.3), (18, 0.2), (30, 0.12), (50, 0.06)]:
    idx = int(delay_ms * SAMPLE_RATE / 1000)
    if idx < reverb_samples:
        impulse[idx] = gain

# Exponential tail
reverb_t = np.linspace(0, reverb_duration, reverb_samples, endpoint=False)
np.random.seed(42)  # reproducible
impulse += 0.08 * np.exp(-reverb_t / 0.02) * (np.random.rand(reverb_samples) * 0.3 + 0.7)

# Normalize impulse so dry signal level is preserved
impulse /= np.sum(np.abs(impulse))
impulse *= 2.5  # slight wet boost

wet = np.convolve(mixed, impulse)[:NUM_SAMPLES]

# Blend dry/wet
output = 0.6 * mixed + 0.4 * wet


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
