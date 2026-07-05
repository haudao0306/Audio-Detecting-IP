# dataset_loader.py
# Hardware-matched preprocessing for training the CNN backend.
#
# Flow matched to test_system.py:
#   WAV -> PCM16 -> 64 frames -> FFT1024 -> 512 bins
#       -> FFT scale/wrap/shift -> power -> mel ROM MAC
#       -> log LUT -> 40 x 64 -> float tensor for PyTorch

import os

import librosa
import numpy as np
import torch
from torch.utils.data import Dataset

import config


# ============================================================
# Hardware parameters, kept aligned with test_system.py
# ============================================================
SR = getattr(config, "SAMPLE_RATE", 16000)
N_FFT = 1024
HOP_LENGTH = 256
MAX_FRAMES = getattr(config, "MAX_FRAMES", 64)

NUM_BINS = 512
MEL_BINS = 40

IWIDTH = 16
OWIDTH = 22
E_WIDTH = 42
Q_SHIFT = 15
LUT_BITS = 12
FFT_SHIFT = 6

FFT_CORE_SCALE_SHIFT = int(np.log2(N_FFT)) - (OWIDTH - IWIDTH)
FFT_CORE_SCALE = float(1 << FFT_CORE_SCALE_SHIFT)

DEFAULT_MEL_ROM = "mel_rom_48bit_with_flags.mem"
DEFAULT_LOG_LUT = "log_lut.mem"

# Conv1 in the hardware model uses L1_PIXEL_FRAC = 10.
# Therefore raw log-mel integer should be divided by 2^10 for training.
DEFAULT_HW_SCALE_FACTOR = 1 << 10


# ============================================================
# Bit helpers
# ============================================================
def wrap_signed_np(values, width):
    """Vectorized signed two's-complement wrap, matching RTL truncation."""
    arr = np.asarray(values, dtype=np.int64)
    mask = (1 << width) - 1
    wrapped = arr & mask
    sign = 1 << (width - 1)
    return np.where(wrapped & sign, wrapped - (1 << width), wrapped).astype(np.int64)


def arith_shift_round_np(values, shift):
    """Match RTL style: (x + (1 << (shift - 1))) >>> shift."""
    arr = np.asarray(values, dtype=np.int64)
    if shift <= 0:
        return arr
    return (arr + (1 << (shift - 1))) >> shift


# ============================================================
# ROM / LUT loaders
# ============================================================
def load_mel_rom_matrix(filename):
    """
    Load mel filter ROM with the same format as test_system.py:
      48-bit word:
        [15:0]   = w0
        [31:16]  = w1
        [37:32]  = f0
        [43:38]  = f1
    Returns matrix shape: (40, 512).
    """
    if not os.path.exists(filename):
        raise FileNotFoundError(f"Cannot find mel ROM file: {filename}")

    matrix = np.zeros((MEL_BINS, NUM_BINS), dtype=np.int64)

    with open(filename, "r", encoding="ascii") as fp:
        lines = [
            line.strip()
            for line in fp
            if line.strip() and not line.strip().startswith(("//", "#"))
        ]

    for k, line in enumerate(lines[:NUM_BINS]):
        val_48bit = int(line, 16)

        w0 = (val_48bit >> 0) & 0xFFFF
        w1 = (val_48bit >> 16) & 0xFFFF
        f0 = (val_48bit >> 32) & 0x3F
        f1 = (val_48bit >> 38) & 0x3F

        if w0 > 0 and f0 < MEL_BINS:
            matrix[f0, k] = w0
        if w1 > 0 and f1 < MEL_BINS:
            matrix[f1, k] = w1

    return matrix


def load_log_lut(filename):
    """Load 12-bit log LUT and pad to 4096 entries if needed."""
    if not os.path.exists(filename):
        raise FileNotFoundError(f"Cannot find log LUT file: {filename}")

    lut = []
    with open(filename, "r", encoding="ascii") as fp:
        for line in fp:
            line = line.strip()
            if line and not line.startswith(("//", "#")):
                lut.append(int(line, 16))

    lut_size = 1 << LUT_BITS
    if len(lut) < lut_size:
        lut.extend([0] * (lut_size - len(lut)))

    return np.asarray(lut[:lut_size], dtype=np.int64)


# ============================================================
# Hardware-matched front-end
# ============================================================
def wav_to_pcm16_fixed(wav_path, sr=SR, max_frames=MAX_FRAMES):
    """
    Match test_system.py load_wav_full():
      - librosa.load(..., sr=target_sr)
      - round(y * 32768)
      - wrap to signed 16-bit
      - pad/crop to exactly N_FFT + (max_frames - 1) * HOP_LENGTH samples
    """
    y, _ = librosa.load(str(wav_path), sr=sr)
    pcm16 = wrap_signed_np(np.round(y * 32768.0).astype(np.int64), IWIDTH)

    required_samples = N_FFT + (max_frames - 1) * HOP_LENGTH
    if len(pcm16) < required_samples:
        pcm16 = np.pad(pcm16, (0, required_samples - len(pcm16)), mode="constant")
    else:
        pcm16 = pcm16[:required_samples]

    return pcm16.astype(np.int64)


def frame_pcm16(pcm16, max_frames=MAX_FRAMES):
    """
    Build frames equivalent to test_system.py:
      frame_idx start = frame_idx * HOP_LENGTH
      frame = audio_samples[start : start + N_FFT]
    Returns shape: (max_frames, 1024).
    """
    frames = np.zeros((max_frames, N_FFT), dtype=np.int64)
    for frame_idx in range(max_frames):
        start = frame_idx * HOP_LENGTH
        frames[frame_idx] = pcm16[start : start + N_FFT]
    return frames


def fft_to_16bit_for_mel(frames):
    """
    Vectorized equivalent of test_system.py build_fft_golden(), but for
    many frames at once. Returns real/imag arrays with shape (frames, 512).
    """
    spectrum = np.fft.fft(frames.astype(np.float64), axis=1)[:, :NUM_BINS]

    re22 = wrap_signed_np(np.round(np.real(spectrum) / FFT_CORE_SCALE).astype(np.int64), OWIDTH)
    im22 = wrap_signed_np(np.round(np.imag(spectrum) / FFT_CORE_SCALE).astype(np.int64), OWIDTH)

    re16 = wrap_signed_np(arith_shift_round_np(re22, FFT_SHIFT), IWIDTH)
    im16 = wrap_signed_np(arith_shift_round_np(im22, FFT_SHIFT), IWIDTH)

    return re16, im16


def hardware_log2_lut(e_raw, log_lut):
    """
    Vectorized equivalent of test_system.py build_log_mel_golden() log stage:
      e_val = max(e_raw, 1)
      msb = bit_length(e_val) - 1
      shift_amt = (E_WIDTH - 1) - msb
      norm_val = e_val << shift_amt
      lut_addr = (norm_val >> (E_WIDTH - LUT_BITS - 1)) & ((1 << LUT_BITS) - 1)
      log_fixed = (msb << LUT_BITS) + log_lut[lut_addr]
    """
    e_val = np.maximum(e_raw, 1).astype(np.int64)

    # e_val is positive here, so floor(log2()) is equivalent to bit_length - 1.
    msb = np.floor(np.log2(e_val)).astype(np.int64)
    shift_amt = (E_WIDTH - 1) - msb

    norm_val = e_val << shift_amt
    lut_addr = (norm_val >> (E_WIDTH - LUT_BITS - 1)) & ((1 << LUT_BITS) - 1)
    lut_addr = np.clip(lut_addr, 0, len(log_lut) - 1)

    return (msb << LUT_BITS) + log_lut[lut_addr]


def pcm16_to_log_mel_40x64(pcm16, mel_matrix, log_lut, max_frames=MAX_FRAMES):
    """
    Hardware-matched fixed-point log-mel extraction.
    Returns raw integer log-mel with shape (40, max_frames).
    """
    frames = frame_pcm16(pcm16, max_frames=max_frames)
    re16, im16 = fft_to_16bit_for_mel(frames)

    power = (re16 * re16) + (im16 * im16)            # (frames, 512)
    accumulator = power @ mel_matrix.T              # (frames, 40)

    e_raw = accumulator >> Q_SHIFT
    log_fixed = hardware_log2_lut(e_raw, log_lut)

    log_q10 = log_fixed >> 2
    log_with_offset = log_q10 - 1625
    log_final = np.maximum(log_with_offset, 0) & 0xFFFF

    return log_final.T.astype(np.int64)             # (40, frames)


def wav_to_log_mel_40x64(wav_path, mel_matrix, log_lut, sr=SR, max_frames=MAX_FRAMES):
    pcm16 = wav_to_pcm16_fixed(wav_path, sr=sr, max_frames=max_frames)
    return pcm16_to_log_mel_40x64(pcm16, mel_matrix, log_lut, max_frames=max_frames)


# ============================================================
# Dataset
# ============================================================
class AudioDataset(Dataset):
    def __init__(
        self,
        folder_list,
        labels,
        mel_rom_file=DEFAULT_MEL_ROM,
        log_lut_file=DEFAULT_LOG_LUT,
        sr=SR,
        max_frames=MAX_FRAMES,
        hw_scale_factor=None,
    ):
        self.files = []
        self.labels = []
        self.sr = sr
        self.max_frames = max_frames
        self.hw_scale_factor = (
            hw_scale_factor
            if hw_scale_factor is not None
            else getattr(config, "HW_SCALE_FACTOR", DEFAULT_HW_SCALE_FACTOR)
        )

        for folder, label in zip(folder_list, labels):
            for root, _, names in os.walk(folder):
                for name in names:
                    if name.lower().endswith(".wav"):
                        self.files.append(os.path.join(root, name))
                        self.labels.append(label)

        print(f"-> Found {len(self.files)} wav files")
        print("-> Loading hardware mel ROM and log LUT")

        self.mel_matrix = load_mel_rom_matrix(mel_rom_file)
        self.log_lut = load_log_lut(log_lut_file)

    def __len__(self):
        return len(self.files)

    def __getitem__(self, idx):
        log_mel_spec = wav_to_log_mel_40x64(
            self.files[idx],
            self.mel_matrix,
            self.log_lut,
            sr=self.sr,
            max_frames=self.max_frames,
        )

        x = torch.tensor(
            log_mel_spec[np.newaxis, :, :] / float(self.hw_scale_factor),
            dtype=torch.float32,
        )

        y = torch.tensor(self.labels[idx], dtype=torch.long)
        return x, y
