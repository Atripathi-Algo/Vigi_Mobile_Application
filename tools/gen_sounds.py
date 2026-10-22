"""Synthesizes the VIGIL sound set. Every sound is original: built here from sine and
saw oscillators, filtered noise, echoes and a small reverb. Nothing is sampled, and
nothing imitates an existing film or game theme, so there are no licence issues.

Mood: cold, metallic, sonar pings over sub-bass.

Usage:  python tools/gen_sounds.py [--preview preview.png]
Writes: assets/audio/*.wav            in-app effects (played by lib/services/sfx.dart)
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
    """Adds darkened repeats, like a ping bouncing off concrete."""
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


def finish(x, peak=0.85, fade_in=0.002, fade_out=0.04):
    """Remove DC, fade the ends so nothing clicks, normalise to the peak."""
    x = x - np.mean(x)
    nin, nout = int(SR * fade_in), int(SR * fade_out)
    if nin:
        x[:nin] *= np.linspace(0, 1, nin)
    if nout:
        x[-nout:] *= np.linspace(1, 0, nout)
    return (x / (np.max(np.abs(x)) + 1e-9) * peak).astype(np.float32)


def metal(freqs, amps, taus, t):
    """Inharmonic partials: the sound of struck metal."""
    return sum(a * np.sin(2 * np.pi * f * t) * decay(t, tau, 0.0008) for f, a, tau in zip(freqs, amps, taus))


def ping(f, t, tau=0.3, bright=1.0):
    """A sonar ping: a fundamental with two inharmonic overtones."""
    return decay(t, tau, 0.002) * (np.sin(2 * np.pi * f * t) + 0.5 * bright * np.sin(2 * np.pi * f * 1.51 * t) * np.exp(-t / (tau * 0.6)) + 0.3 * bright * np.sin(2 * np.pi * f * 2.24 * t) * np.exp(-t / (tau * 0.35)))


def thump(f0, f1, t, tau=0.14):
    """A sub-bass hit with a falling pitch."""
    f = f1 + (f0 - f1) * np.exp(-t / 0.05)
    return decay(t, tau, 0.002) * sine(f, t)


def whoosh(dur, lo, hi, peak_at, seed=3):
    """Noise whose colour sweeps from lo to hi Hz, loudest at peak_at seconds."""
    t = tt(dur)
    n = noise(len(t), seed)
    centres = np.geomspace(lo, hi, 7)
    out = np.zeros_like(t)
    for i, c in enumerate(centres):
        band = bp(n, c * 0.6, c * 1.5)
        when = (i / (len(centres) - 1)) * peak_at
        out += band * np.exp(-((t - when) ** 2) / (2 * (peak_at / 5) ** 2))
    env = np.minimum(1, t / (peak_at * 0.9)) ** 1.5 * np.exp(-np.maximum(0, t - peak_at) / (dur * 0.15))
    return out * env


# ----------------------------------------------------------------- in-app effects
def sfx_tick():
    t = tt(0.07)
    click = hp(noise(len(t), 1), 3000) * decay(t, 0.004, 0.0003) * 0.6
    return finish(click + 0.5 * np.sin(2 * np.pi * 1900 * t) * decay(t, 0.012, 0.0005), 0.7, 0.0005, 0.02)


def sfx_clear():
    t = tt(0.6)
    plate = metal((196, 311, 463, 729), (1.0, 0.8, 0.6, 0.4), (0.11, 0.09, 0.07, 0.05), t)
    x = mix(0.6, (plate, 0.0), (ping(880, tt(0.5), 0.16, 0.6) * 0.5, 0.04))
    return finish(echo(x, (0.09, 0.18), (0.3, 0.14)), 0.88, 0.001, 0.08)


def sfx_engage():
    w = whoosh(1.0, 220, 5200, 0.42)
    t = tt(1.0)
    clink = metal((1180, 1870, 2650, 3320), (0.8, 0.6, 0.4, 0.3), (0.12, 0.09, 0.07, 0.05), tt(0.5))
    x = mix(1.0, (w * 0.7, 0.0), (thump(78, 46, t, 0.14) * 0.9, 0.0), (clink * 0.55, 0.45))
    return finish(echo(x, (0.12, 0.26), (0.22, 0.1)), 0.9, 0.001, 0.12)


def sfx_pulse():
    t = tt(0.7)

    def boom():
        return lp(saw(55, t), 170) * decay(t, 0.17, 0.004) * 0.7 + sine(55, t) * decay(t, 0.22, 0.004)

    p = ping(1100, tt(1.0), 0.38) * 0.45
    x = mix(1.6, (boom(), 0.0), (boom() * 0.85, 0.42), (p, 0.92))
    return finish(reverb(x, 0.3, 0.7), 0.9, 0.001, 0.25)


def sfx_deny():
    t = tt(0.2)
    buzz = lp(saw(98, t) + saw(104, t), 700) * (0.65 + 0.35 * np.sign(np.sin(2 * np.pi * 26 * t)))
    buzz *= np.minimum(1, t / 0.004) * np.exp(-np.maximum(0, t - 0.1) / 0.04)
    return finish(mix(0.45, (buzz, 0.0), (buzz * 0.8, 0.22)), 0.8, 0.001, 0.05)


def sfx_boot():
    t = tt(2.6)
    base = sine(44, t) + 0.5 * saw(44, t)
    swept = lp(base, 90) * np.clip(1.2 - t / 1.3, 0, 1) + lp(base, 420) * np.clip(t / 1.3, 0, 1)
    swell = np.where(t < 1.3, (t / 1.3) ** 2, np.exp(-(t - 1.3) / 0.8))
    pp = ping(1500, tt(1.2), 0.5) * 0.55
    x = mix(2.6, (swept * swell, 0.0), (pp, 1.25), (thump(60, 40, tt(0.6), 0.2) * 0.7, 1.25))
    return finish(reverb(x, 0.35, 0.8), 0.9, 0.004, 0.5)


def sfx_water():
    t = tt(0.25)
    f = 700 + 900 * (1 - np.exp(-t / 0.02))
    drop = sine(f, t) * decay(t, 0.07, 0.001)
    return finish(echo(drop, (0.12, 0.24), (0.35, 0.15)), 0.8, 0.001, 0.12)


# ----------------------------------------------------------------- notification sounds
def n_critical():
    t = tt(0.4)
    p1 = ping(1250, tt(0.9), 0.28)
    x = mix(1.9, (thump(64, 42, t, 0.16) * 0.9, 0.0), (p1, 0.0), (p1 * 0.9, 0.32), (ping(1000, tt(0.9), 0.5) * 0.9, 1.0))
    return finish(echo(x, (0.16, 0.32, 0.48), (0.3, 0.18, 0.1)), 0.92, 0.001, 0.2)


def n_ops():
    x = mix(1.0, (ping(1000, tt(0.9), 0.3), 0.0), (thump(70, 48, tt(0.3), 0.1) * 0.5, 0.0))
    return finish(echo(x, (0.2, 0.4), (0.25, 0.12)), 0.85, 0.001, 0.15)


def n_sleep():
    t = tt(2.2)
    pad = (sine(164.8, t) + sine(110.7, t) * 0.8) * decay(t, 0.9, 0.3)
    glide = sine(np.linspace(330, 247, len(t)), t) * decay(t, 0.7, 0.25) * 0.3
    x = mix(2.4, (pad * 0.7, 0.0), (glide, 0.0), (ping(880, tt(0.8), 0.25) * 0.3, 0.0))
    return finish(reverb(x, 0.4, 0.5), 0.8, 0.003, 0.5)


def n_brief():
    t = tt(1.4)
    drone = lp(sine(110, t) + 0.5 * saw(110, t), 500) * decay(t, 0.8, 0.25)
    x = mix(1.6, (drone * 0.6, 0.0), (ping(659, tt(0.9), 0.3) * 0.7, 0.45), (ping(988, tt(0.8), 0.28) * 0.6, 0.8))
    return finish(reverb(x, 0.3, 0.5), 0.85, 0.003, 0.3)


def n_soft():
    t = tt(0.4)
    x = ping(740, t, 0.12) * 0.7 + hp(noise(len(t), 5), 2500) * decay(t, 0.004, 0.0003) * 0.2
    return finish(echo(x, (0.12,), (0.2,)), 0.7, 0.001, 0.12)


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
    'bat_critical': n_critical,
    'bat_ops': n_ops,
    'bat_sleep': n_sleep,
    'bat_brief': n_brief,
    'bat_soft': n_soft,
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
    print('%-14s %7s %7s %8s %8s' % ('sound', 'secs', 'peak', 'rms dB', 'KB'))
    for name, x in made.items():
        rms = 20 * np.log10(np.sqrt(np.mean(x.astype(float) ** 2)) + 1e-9)
        print('%-14s %7.2f %7.2f %8.1f %8.0f' % (name, len(x) / SR, np.max(np.abs(x)), rms, len(x) * 2 / 1024))
    if args.preview:
        import matplotlib
        matplotlib.use('Agg')
        import matplotlib.pyplot as plt
        names = list(made)
        fig, axes = plt.subplots(len(names), 2, figsize=(11, 1.55 * len(names)))
        for i, n in enumerate(names):
            x = made[n]
            axes[i][0].plot(np.arange(len(x)) / SR, x, lw=0.4, color='#c8a200')
            axes[i][0].set_ylim(-1, 1)
            axes[i][0].set_ylabel(n, rotation=0, ha='right', va='center', fontsize=8)
            axes[i][0].set_xlim(0, len(x) / SR)
            f, tm, sxx = signal.spectrogram(x, SR, nperseg=512, noverlap=384)
            axes[i][1].pcolormesh(tm, f, 10 * np.log10(sxx + 1e-12), shading='auto', cmap='magma', vmin=-90, vmax=-20)
            axes[i][1].set_ylim(0, 6000)
            axes[i][1].set_xlim(0, len(x) / SR)
        plt.tight_layout()
        plt.savefig(args.preview, dpi=70)
        print('preview ->', args.preview)


if __name__ == '__main__':
    main()
