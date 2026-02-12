#!/usr/bin/env python3
"""
Generate a sci-fi "invisibility cloak activation" sound effect.

Produces a short (0.6s) ethereal power-up sound by layering:
  1. A rising frequency sweep with shimmer effect - the "cloaking" feel
  2. A high-pitched crystalline chime at the peak - the "activation confirmation"
  3. A subtle white noise hiss for the cloaking field effect
  4. A low frequency rumble for power activation
  5. Light reverb for spatial presence

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
    "assets", "audio", "invisibility_activation.wav",
)

t = np.linspace(0, DURATION, NUM_SAMPLES, endpoint=False)


# -- Layer 1: Ethereal rising frequency sweep ---------------------------------
# Sweep from 200 Hz to 1200 Hz with shimmer modulation for a mystical feel

f_start = 200.0
f_end = 1200.0
# Instantaneous frequency rises with a gentle curve
freq_t = f_start * (f_end/f_start) ** (t / DURATION)
phase_sweep = 2.0 * np.pi * np.cumsum(freq_t) / SAMPLE_RATE
sweep = np.sin(phase_sweep)

# Add shimmer (fast amplitude modulation)
shimmer_freq = 80.0  # Hz modulation rate
shimmer_depth = 0.3
shimmer = 1.0 + shimmer_depth * np.sin(2.0 * np.pi * shimmer_freq * t)
sweep *= shimmer

# Amplitude envelope: quick fade in, gentle sustain, smooth fade out
env_sweep = np.ones(NUM_SAMPLES)
fade_in_len = int(0.05 * SAMPLE_RATE)   # 50 ms fade-in
fade_out_len = int(0.15 * SAMPLE_RATE)  # 150 ms fade-out
env_sweep[:fade_in_len] = np.linspace(0, 1, fade_in_len)
env_sweep[-fade_out_len:] = np.linspace(1, 0, fade_out_len)

sweep *= env_sweep * 0.40


# -- Layer 2: Crystalline chime at the peak ----------------------------------
# A brief harmonic series that appears near the middle of the sound

chime_duration = 0.25  # seconds
chime_samples = int(chime_duration * SAMPLE_RATE)
chime_freqs = [3200.0, 4000.0, 4800.0]  # Harmonic series for crystalline effect

chime = np.zeros(NUM_SAMPLES)
chime_start = int(0.2 * SAMPLE_RATE)  # Start at 200ms
chime_t = np.linspace(0, chime_duration, chime_samples, endpoint=False)

# Build harmonic series
for i, freq in enumerate(chime_freqs):
    amplitude = 0.3 / (i + 1)  # Decreasing amplitude for higher harmonics
    chime_wave = np.sin(2.0 * np.pi * freq * chime_t) * amplitude
    chime[chime_start:chime_start + chime_samples] += chime_wave

# Apply envelope to chime (sharp attack, exponential decay)
chime_env = np.exp(-chime_t / 0.08)
chime_env[:int(0.01 * SAMPLE_RATE)] *= np.linspace(0, 1, int(0.01 * SAMPLE_RATE))
chime_wave *= chime_env

chime *= 0.25  # Keep it subtle but audible


# -- Layer 3: White noise hiss for cloaking field ---------------------------

# Generate filtered white noise for a "field effect"
np.random.seed(123)  # Reproducible
noise = np.random.randn(NUM_SAMPLES)

# Low-pass filter the noise (simple moving average)
kernel_size = 15
noise = np.convolve(noise, np.ones(kernel_size) / kernel_size, mode='same')

# Apply envelope (fade in and out with the main effect)
env_noise = np.ones(NUM_SAMPLES)
env_noise[:fade_in_len] = np.linspace(0, 1, fade_in_len)
env_noise[-fade_out_len:] = np.linspace(1, 0, fade_out_len)

noise *= env_noise * 0.08  # Very subtle


# -- Layer 4: Low frequency rumble -------------------------------------------

# A sub-bass rumble that rises from 40Hz to 80Hz
rumble_freq_start = 40.0
rumble_freq_end = 80.0
rumble_freq_t = rumble_freq_start + (rumble_freq_end - rumble_freq_start) * (t / DURATION)
rumble_phase = 2.0 * np.pi * np.cumsum(rumble_freq_t) / SAMPLE_RATE
rumble = np.sin(rumble_phase)

# Apply gentle envelope
rumble *= env_sweep * 0.15


# -- Mix layers ---------------------------------------------------------------

mixed = sweep + chime + noise + rumble


# -- Light reverb for spatial presence ----------------------------------------

reverb_duration = 0.12  # seconds
reverb_samples = int(reverb_duration * SAMPLE_RATE)
impulse = np.zeros(reverb_samples)
impulse[0] = 1.0

# Early reflections for space
for delay_ms, gain in [(12, 0.25), (28, 0.15), (45, 0.10), (70, 0.05)]:
    idx = int(delay_ms * SAMPLE_RATE / 1000)
    if idx < reverb_samples:
        impulse[idx] = gain

# Diffuse tail
reverb_t = np.linspace(0, reverb_duration, reverb_samples, endpoint=False)
np.random.seed(456)
impulse += 0.05 * np.exp(-reverb_t / 0.03) * (np.random.rand(reverb_samples) * 0.4 + 0.6)

# Normalize impulse
impulse /= np.sum(np.abs(impulse))
impulse *= 2.0  # Slight wet boost

wet = np.convolve(mixed, impulse)[:NUM_SAMPLES]

# Blend dry/wet (mostly dry for clarity)
output = 0.8 * mixed + 0.2 * wet


# -- Normalize & convert to 16-bit PCM ----------------------------------------

# Normalize to ~65% of full scale
peak = np.max(np.abs(output))
if peak > 0:
    output = output / peak * 0.65

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