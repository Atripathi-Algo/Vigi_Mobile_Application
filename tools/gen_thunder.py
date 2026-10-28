"""Synthesizes K's thunder sound set. Every sound is original: built here from filtered noise, oscillators,
echoes and a small reverb. Nothing is sampled, so there are no licence issues.

Mood: storm. Short electric cracks and sparks for taps, low rolling thunder for states and alerts.

Usage:  python tools/gen_thunder.py [--preview preview.png]
Writes: assets/audio/sfx_*.wav        in-app effects (played by lib/services/sfx.dart)
        assets/audio/k_*.wav          alert previews in Loadout
        android/app/src/main/res/raw  notification sounds (one per channel)
Needs:  numpy, scipy (and matplotlib for --preview)
"""
import argparse
import os
import wave

import numpy as np
from scipy import signal

SR = 32000
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_FX = os.path.join(ROOT, 'assets', 'audio')
OUT_NOTIF = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res', 'raw')


# ----------------------------------------------------------------- building blocks
def tt(dur):
    return np.arange(int(SR * dur)) / SR


def lp(x, fc, order=4):
    return signal.sosfilt(signal.butter(order, min(fc, SR / 2 - 100) / (SR / 2), 'low', output='sos'), x)


def hp(x, fc, order=4):
    return signal.sosfilt(signal.butter(order, fc / (SR / 2), 'high', output='sos'), x)


def bp(x, lo, hi, order=2):
    return signal.sosfilt(signal.butter(order, [lo / (SR / 2), min(hi, SR / 2 - 100) / (SR / 2)], 'band', output='sos'), x)


def sine(f, t):
    """f may be a number or an array of instantaneous frequencies."""
    f = np.broadcast_to(np.asarray(f, dtype=float), t.shape)
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def saw(f, t):
    f = np.broadcast_to(np.asarray(f, dtype=float), t.shape)
    return 2 * ((np.cumsum(f) / SR) % 1.0) - 1


def noise(n, seed):
    return np.random.default_rng(seed).standard_normal(n)


def decay(t, tau, attack=0.002):
    return np.exp(-t / tau) * np.minimum(1.0, t / attack)


def mix(total, *parts):
    """parts: (signal, start_seconds). Sums them into one buffer."""
    out = np.zeros(int(SR * total))
    for x, at in parts:
        i = int(SR * at)
        n = min(len(x), len(out) - i)
        if n > 0:
            out[i:i + n] += x[:n]
    return out


def echo(x, delays, gains, darken=3000):
    out = np.concatenate([x, np.zeros(int(SR * (max(delays) + 0.05)))])
    for d, g in zip(delays, gains):
        rep = lp(np.concatenate([np.zeros(int(SR * d)), x]), darken, 2) * g
        out[:len(rep)] += rep
    return out


def reverb(x, wet=0.25, tail=0.6):
    """A small Schroeder reverb: four combs and two all-passes."""
    x = np.concatenate([x, np.zeros(int(SR * tail))])
    combs = np.zeros_like(x)
    for ms, g in ((29.7, 0.77), (37.1, 0.75), (41.1, 0.73), (43.7, 0.71)):
        d = int(SR * ms / 1000)
        a = np.zeros(d + 1)
        a[0], a[d] = 1.0, -g
        combs += signal.lfilter([1.0], a, x)
    y = combs / 4
    for ms, g in ((5.0, 0.7), (1.7, 0.7)):
        d = int(SR * ms / 1000)
        b = np.zeros(d + 1)
        a = np.zeros(d + 1)
        b[0], b[d] = -g, 1.0
        a[0], a[d] = 1.0, -g
        y = signal.lfilter(b, a, y)
    return x * (1 - wet) + lp(y, 5000, 2) * wet * 2.2


def finish(x, peak=0.85, fade_in=0.002, fade_out=0.04, maxlen=None):
    """Remove DC, cut to [maxlen] seconds, fade the ends so nothing clicks, normalise to the peak."""
    if maxlen:
        x = x[:int(SR * maxlen)]
    x = x - np.mean(x)
    nin, nout = int(SR * fade_in), int(SR * fade_out)
    if nin:
        x[:nin] *= np.linspace(0, 1, nin)
    if nout:
        x[-nout:] *= np.linspace(1, 0, nout)
    return (x / (np.max(np.abs(x)) + 1e-9) * peak).astype(np.float32)


# ----------------------------------------------------------------- thunder elements
def crack(dur=0.25, seed=1, bright=1.0):
    """The snap of a lightning strike: a hard broadband burst that dies in a few milliseconds, with a short body."""
    t = tt(dur)
    snap = hp(noise(len(t), seed), 1200) * decay(t, 0.010 / bright, 0.0002)
    body = bp(noise(len(t), seed + 7), 300, 2500) * decay(t, 0.045, 0.0004) * 0.55
    return snap + body


def spark(dur=0.05, seed=2, hits=4):
    """A few tiny static ticks."""
    t = tt(dur)
    out = np.zeros_like(t)
    rng = np.random.default_rng(seed)
    for _ in range(hits):
        i = int(rng.uniform(0, 0.6) * len(t))
        n = int(SR * 0.0025)
        click = hp(noise(n, int(rng.integers(0, 1 << 30))), 3500) * np.linspace(1, 0, n) ** 2
        out[i:i + n] += click[:len(out) - i] * rng.uniform(0.5, 1.0)
    return out


def rumble(dur, seed=3, fc=150, tau=None, roll=2.5):
    """Low thunder: low-passed noise with a rolling, uneven loudness and a faint sub-bass underneath."""
    t = tt(dur)
    base = lp(noise(len(t), seed), fc, 4)
    wobble = lp(np.abs(noise(len(t), seed + 11)), roll, 2)
    wobble = wobble / (wobble.max() + 1e-9)
    env = (0.35 + 0.65 * wobble)
    tau = tau or dur / 2.2
    env = env * np.exp(-t / tau) * np.minimum(1.0, t / 0.03)
    sub = sine(46 + 10 * np.exp(-t / 0.4), t) * np.exp(-t / (tau * 0.8)) * 0.5
    return base * env * 6 + sub


def thump(f0, f1, t, tau=0.14):
    f = f1 + (f0 - f1) * np.exp(-t / 0.05)
    return decay(t, tau, 0.002) * sine(f, t)


def ping(f, t, tau=0.3, bright=1.0):
    return decay(t, tau, 0.002) * (np.sin(2 * np.pi * f * t) + 0.5 * bright * np.sin(2 * np.pi * f * 2.0 * t) * np.exp(-t / (tau * 0.5)))


# ----------------------------------------------------------------- in-app effects
def sfx_tick():
    return finish(spark(0.05, 2, 4), 0.7, 0.0004, 0.01)


def sfx_clear():
    x = mix(0.25, (crack(0.25, 11), 0.0), (0.5 * thump(90, 55, tt(0.2), 0.05), 0.0))
    return finish(echo(x, (0.05,), (0.12,), 4000), 0.88, 0.0004, 0.06, maxlen=0.22)


def sfx_engage():
    t = tt(0.62)
    sweep = np.linspace(110, 520, len(t)) ** 1.0
    hum = lp(saw(sweep, t), 1800) * (0.6 + 0.4 * np.sin(2 * np.pi * 70 * t))
    hum *= np.minimum(1, t / 0.4) ** 1.8 * np.where(t > 0.5, np.exp(-(t - 0.5) / 0.015), 1.0)
    snap = crack(0.2, 21) * 1.4
    x = mix(0.8, (hum * 0.7, 0.0), (snap, 0.5), (thump(80, 50, tt(0.2), 0.06) * 0.6, 0.5))
    return finish(x, 0.9, 0.003, 0.1, maxlen=0.7)


def sfx_pulse():
    x = rumble(0.9, 31, fc=130, tau=0.3, roll=3.0)
    return finish(x, 0.85, 0.01, 0.35)


def sfx_deny():
    t = tt(0.25)
    f = 380 * np.exp(-t / 0.07) + 90
    fizz = lp(saw(f, t), 900) * 0.7 + lp(noise(len(t), 41), 1400) * 0.5
    fizz *= decay(t, 0.07, 0.002) * (0.7 + 0.3 * np.sin(2 * np.pi * 38 * t))
    return finish(fizz, 0.8, 0.001, 0.06, maxlen=0.3)


def sfx_boot():
    c = crack(0.4, 51) * 1.3
    r = rumble(1.7, 52, fc=170, tau=0.65, roll=3.4)
    x = mix(2.0, (c, 0.0), (r, 0.02), (thump(70, 40, tt(0.5), 0.2) * 0.8, 0.02))
    return finish(reverb(x, 0.32, 0.5), 0.9, 0.0005, 0.4, maxlen=1.7)


def sfx_water():
    t = tt(0.22)
    f = 700 + 900 * (1 - np.exp(-t / 0.02))
    drop = sine(f, t) * decay(t, 0.06, 0.001)
    x = drop + spark(0.22, 61, 5) * 0.35
    return finish(echo(x, (0.09,), (0.25,)), 0.8, 0.001, 0.08, maxlen=0.25)


# ----------------------------------------------------------------- alert sounds (notification channels)
def n_critical():
    c1 = crack(0.3, 71) * 1.3
    c2 = crack(0.3, 72) * 1.1
    boom = thump(60, 38, tt(0.7), 0.25) * 0.9
    r = rumble(1.0, 73, fc=140, tau=0.4)
    x = mix(1.25, (c1, 0.0), (c2, 0.24), (boom, 0.1), (r * 0.7, 0.1))
    return finish(reverb(x, 0.2, 0.3), 0.93, 0.0005, 0.2, maxlen=1.3)


def n_ops():
    x = mix(0.3, (crack(0.3, 81), 0.0), (0.4 * thump(80, 50, tt(0.25), 0.08), 0.0))
    return finish(echo(x, (0.08,), (0.15,), 3500), 0.85, 0.0005, 0.1, maxlen=0.35)


def n_sleep():
    r = rumble(2.0, 91, fc=95, tau=0.9, roll=1.6)
    return finish(reverb(r, 0.4, 0.4), 0.75, 0.15, 0.7, maxlen=2.2)


def n_brief():
    r = rumble(2.0, 101, fc=120, tau=0.9, roll=2.0) * 0.8
    chimes = mix(2.4, (ping(523.25, tt(0.8), 0.3) * 0.5, 0.9), (ping(659.25, tt(0.8), 0.3) * 0.55, 1.2), (ping(783.99, tt(1.0), 0.4) * 0.6, 1.5))
    x = mix(2.4, (r, 0.0), (chimes, 0.0))
    return finish(reverb(x, 0.3, 0.4), 0.85, 0.05, 0.5, maxlen=2.5)


def n_soft():
    t = tt(0.6)
    shimmer = bp(noise(len(t), 111), 3000, 9000) * (0.5 + 0.5 * np.sin(2 * np.pi * 14 * t)) * np.sin(np.pi * t / 0.6) ** 2
    return finish(shimmer + spark(0.6, 112, 6) * 0.3, 0.6, 0.02, 0.2)


FX = {
    'sfx_tick': sfx_tick,
    'sfx_clear': sfx_clear,
    'sfx_engage': sfx_engage,
    'sfx_pulse': sfx_pulse,
    'sfx_deny': sfx_deny,
    'sfx_boot': sfx_boot,
    'sfx_water': sfx_water,
}
NOTIF = {
    'k_critical': n_critical,
    'k_ops': n_ops,
    'k_sleep': n_sleep,
    'k_brief': n_brief,
    'k_soft': n_soft,
}


def write_wav(path, x):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype('<i2').tobytes())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--preview', help='write a waveform and spectrogram sheet to this PNG')
    args = ap.parse_args()
    made = {}
    for name, fn in FX.items():
        made[name] = fn()
        write_wav(os.path.join(OUT_FX, name + '.wav'), made[name])
    for name, fn in NOTIF.items():
        made[name] = fn()
        write_wav(os.path.join(OUT_NOTIF, name + '.wav'), made[name])
        write_wav(os.path.join(OUT_FX, name + '.wav'), made[name])
    print('%-14s %7s %7s %8s %8s' % ('sound', 'secs', 'peak', 'rms dB', 'KB'))
    for name, x in made.items():
        rms = 20 * np.log10(np.sqrt(np.mean(x.astype(float) ** 2)) + 1e-9)
        print('%-14s %7.2f %7.2f %8.1f %8.0f' % (name, len(x) / SR, np.max(np.abs(x)), rms, len(x) * 2 / 1024))
    if args.preview:
        import matplotlib
        matplotlib.use('Agg')
        import matplotlib.pyplot as plt
        names = list(made)
        fig, axes = plt.subplots(len(names), 2, figsize=(11, 1.4 * len(names)))
        for i, n in enumerate(names):
            x = made[n]
            axes[i][0].plot(np.arange(len(x)) / SR, x, lw=0.4, color='#3FB6FF')
            axes[i][0].set_ylim(-1, 1)
            axes[i][0].set_ylabel(n, rotation=0, ha='right', va='center', fontsize=8)
            axes[i][0].set_xlim(0, len(x) / SR)
            f, tm, sxx = signal.spectrogram(x, SR, nperseg=512, noverlap=384)
            axes[i][1].pcolormesh(tm, f, 10 * np.log10(sxx + 1e-12), shading='auto', cmap='magma', vmin=-90, vmax=-20)
            axes[i][1].set_ylim(0, 8000)
            axes[i][1].set_xlim(0, len(x) / SR)
        plt.tight_layout()
        plt.savefig(args.preview, dpi=70)
        print('preview ->', args.preview)


if __name__ == '__main__':
    main()
