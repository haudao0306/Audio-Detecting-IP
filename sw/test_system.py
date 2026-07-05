# ============================================================
# test_system.py
# System-Level Testbench với tính năng chẩn đoán biên độ & tần số
# CNN Backend: Bit-true golden model (đồng bộ RTL)
# ============================================================

import argparse
import cmath
import math
import os
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from pathlib import Path
import config
import librosa

# ============================================================
# 1. CẤU HÌNH HỆ THỐNG
# ============================================================
NFFT      = 1024
HOP_SIZE  = 256
NUM_FRAMES = 64
IWIDTH    = 16
OWIDTH    = 22
E_WIDTH   = 42
NUM_BINS  = 512
MEL_BINS  = 40
Q_SHIFT   = 15
LUT_BITS  = 12
FFT_SHIFT = 6

FFT_CORE_SCALE_SHIFT = int(math.log2(NFFT)) - (OWIDTH - IWIDTH)

DEFAULT_MEL_ROM = "mel_rom_48bit_with_flags.mem"
DEFAULT_LOG_LUT = "log_lut.mem"
OUTPUT_FFT_INPUT_MEM  = "hw_input.mem"
OUTPUT_CNN_OUTPUT_MEM = "hw_output.mem"

# CNN weight / bias files
L1_WEIGHT_FILE   = "features.0_fused_weight.hex"
L1_BIAS_FILE     = "features.0_fused_bias.hex"
L2_WEIGHT_FILE   = "features.4_fused_weight.hex"
L2_BIAS_FILE     = "features.4_fused_bias.hex"
L3_WEIGHT_FILE   = "features.8_fused_weight.hex"
L3_BIAS_FILE     = "features.8_fused_bias.hex"
CLS_L1_WEIGHT_FILE = "classifier.0_weight.hex"
CLS_L1_BIAS_FILE   = "classifier.0_bias.hex"
CLS_L2_WEIGHT_FILE = "classifier.3_weight.hex"
CLS_L2_BIAS_FILE   = "classifier.3_bias.hex"

# CNN Quantization Parameters
DATA_WIDTH = 16

L1_ACCUM_WIDTH = 32
L1_PIXEL_FRAC  = 10
L1_WEIGHT_FRAC = 8
L1_OUT_FRAC    = 8

L23_ACCUM_WIDTH = 40
L23_PIXEL_FRAC  = 8
L23_WEIGHT_FRAC = 8
L23_OUT_FRAC    = 8

CLS_PIXEL_FRAC  = 8
CLS_WEIGHT_FRAC = 8
CLS_OUT_FRAC    = 8
CLS_SHIFT_RIGHT = CLS_PIXEL_FRAC + CLS_WEIGHT_FRAC - CLS_OUT_FRAC
CLS_ROUND_CONST = 1 << (CLS_SHIFT_RIGHT - 1)
CLS_L1_ACCUM_WIDTH = 48

# CNN Network dimensions
L1_IN, L1_OUT = 1, 16
L2_IN, L2_OUT = 16, 32
L3_IN, L3_OUT = 32, 64

# ============================================================
# 2. CÔNG CỤ XỬ LÝ SỐ (DSP & HARDWARE SIMULATION)
# ============================================================
def wrap_signed(value, width):
    mask = (1 << width) - 1
    value &= mask
    if value & (1 << (width - 1)):
        value -= 1 << width
    return value

def arith_shift_round_like_verilog(x, shift):
    if shift <= 0:
        return x
    bias = 1 << (shift - 1)
    return (x + bias) >> shift

def hex_to_signed_16(h_str):
    val = int(h_str.strip(), 16)
    if val >= 0x8000:
        val -= 0x10000
    return val

def hex_to_signed_32(h_str):
    val = int(h_str.strip(), 16)
    if val >= 0x80000000:
        val -= 0x100000000
    return val

def mask_bits(bits):
    return (1 << bits) - 1

# ============================================================
# 3. TIỀN XỬ LÝ (FRONT-END LOG-MEL)
# ============================================================
def fft(values):
    data = list(values)
    n = len(data)
    j = 0
    for i in range(1, n):
        bit = n >> 1
        while j & bit:
            j ^= bit
            bit >>= 1
        j ^= bit
        if i < j:
            data[i], data[j] = data[j], data[i]
    size = 2
    while size <= n:
        half = size >> 1
        w_step = cmath.exp(-2j * math.pi / size)
        for start in range(0, n, size):
            w = 1.0 + 0.0j
            for k in range(half):
                even = data[start + k]
                odd  = w * data[start + k + half]
                data[start + k]        = even + odd
                data[start + k + half] = even - odd
                w *= w_step
        size <<= 1
    return data

def build_fft_golden(audio_samples):
    complex_in = [complex(x, 0) for x in audio_samples]
    spectrum   = fft(complex_in)
    scale      = 1 << FFT_CORE_SCALE_SHIFT

    fft_16_for_mel = []
    for k in range(NUM_BINS):
        v    = spectrum[k]
        re22 = wrap_signed(int(round(v.real / scale)), OWIDTH)
        im22 = wrap_signed(int(round(v.imag / scale)), OWIDTH)
        re16 = wrap_signed(arith_shift_round_like_verilog(re22, FFT_SHIFT), 16)
        im16 = wrap_signed(arith_shift_round_like_verilog(im22, FFT_SHIFT), 16)
        fft_16_for_mel.append((re16, im16))
    return fft_16_for_mel

def build_log_mel_golden(fft_16_for_mel, mel_matrix, log_lut):
    frame_mel_data = []
    for m in range(MEL_BINS):
        accumulator = 0
        for b in range(NUM_BINS):
            re, im = fft_16_for_mel[b]
            pwr    = (re * re) + (im * im)
            weight = mel_matrix[m][b]
            if weight == 0:
                continue
            accumulator += (pwr * weight)

        e_raw    = accumulator >> Q_SHIFT
        e_val    = 1 if e_raw == 0 else e_raw
        msb_s1   = e_val.bit_length() - 1
        shift_amt = (E_WIDTH - 1) - msb_s1
        norm_val  = e_val << shift_amt
        lut_addr  = (norm_val >> (E_WIDTH - LUT_BITS - 1)) & ((1 << LUT_BITS) - 1)
        lut_fraction = log_lut[lut_addr] if lut_addr < len(log_lut) else 0

        log_fixed       = (msb_s1 << LUT_BITS) + lut_fraction
        log_q10         = log_fixed >> 2
        log_with_offset = log_q10 - 1625
        log_final       = 0 if log_with_offset < 0 else log_with_offset
        log_final      &= 0xFFFF

        frame_mel_data.append(log_final)
    return frame_mel_data

# ============================================================
# [SỬA] load_wav_full: thêm tham số verbose=True
#        Khi chạy batch 30 file, truyền verbose=False để
#        tắt diagnostic in ra màn hình cho gọn output.
#        Logic xử lý audio hoàn toàn không thay đổi.
# ============================================================
def load_wav_full(wav_path, verbose=True):
    target_sr = getattr(config, 'SAMPLE_RATE', 16000)
    y, sr_orig = librosa.load(str(wav_path), sr=target_sr)
    mono_mẫu = np.round(y * 32768.0).astype(np.int64)
    mono = [wrap_signed(int(x), 16) for x in mono_mẫu]

    required_samples = NFFT + (NUM_FRAMES - 1) * HOP_SIZE

    if verbose:
        print(f"   [CHẨN ĐOÁN AUDIO]")
        print(f"   + Định dạng: 16-bit PCM (Qua Librosa chuẩn hóa)")
        print(f"   + Tần số lấy mẫu gốc: {sr_orig} Hz -> Hạ âm thông minh về: {target_sr} Hz")
        print(f"   + Tổng số mẫu sau khi chuyển đổi: {len(mono)} mẫu (~{len(mono)/target_sr:.2f} giây)")

    if len(mono) < required_samples:
        if verbose:
            print(f"   + Cảnh báo: File ngắn hơn tiêu chuẩn, hệ thống tự động chèn thêm Zero-padding.")
        mono.extend([0] * (required_samples - len(mono)))
    else:
        if verbose:
            print(f"   + Hệ thống trích xuất {required_samples} mẫu đầu tiên (~{required_samples/target_sr:.3f} giây) để phân tích.")

    audio_segment = mono[:required_samples]
    if verbose:
        print(f"   + Biên độ sóng âm: Cực tiểu = {min(audio_segment)}, Cực đại = {max(audio_segment)}")
    return audio_segment, target_sr

def load_mel_rom(filename):
    matrix = [[0] * NUM_BINS for _ in range(MEL_BINS)]
    if not os.path.exists(filename):
        print(f"   + Cảnh báo: Không tìm thấy file ROM '{filename}'! Ma trận Mel sẽ bằng 0.")
        return matrix
    with open(filename, "r", encoding="ascii") as f:
        lines = [l.strip() for l in f if l.strip() and not l.strip().startswith(("//", "#"))]
        for k, line in enumerate(lines):
            if k >= NUM_BINS:
                break
            val_48bit = int(line, 16)
            w0, w1 = (val_48bit >> 0) & 0xFFFF, (val_48bit >> 16) & 0xFFFF
            f0, f1 = (val_48bit >> 32) & 0x3F,  (val_48bit >> 38) & 0x3F
            if w0 > 0 and f0 < MEL_BINS:
                matrix[f0][k] = w0
            if w1 > 0 and f1 < MEL_BINS:
                matrix[f1][k] = w1
    return matrix

def load_log_lut(filename):
    if not os.path.exists(filename):
        print(f"   + Cảnh báo: Không tìm thấy file LUT '{filename}'! Bảng log_lut sẽ bằng 0.")
        return [0] * (1 << LUT_BITS)
    lut = []
    with open(filename, "r", encoding="ascii") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("//") and not line.startswith("#"):
                lut.append(int(line, 16))
    if len(lut) < (1 << LUT_BITS):
        lut.extend([0] * ((1 << LUT_BITS) - len(lut)))
    return lut

# ============================================================
# 4. XUẤT FILE .MEM CHO TESTBENCH PHẦN CỨNG
# ============================================================
def export_fft_input_mem(audio_samples, filename):
    with open(filename, 'w', encoding='utf-8') as f:
        f.write(f"// FFT Input : {NUM_FRAMES} frames x {NFFT} samples/frame\n")
        f.write(f"// Format    : 32-bit hex per line = RRRR0000\n")
        f.write(f"// Bit [31:16]: real (PCM 16-bit signed, bu 2)\n")
        f.write(f"// Bit [15: 0]: imag (= 0000, tin hieu thuc)\n")
        f.write(f"// Tong       : {NUM_FRAMES * NFFT} dong\n")
        f.write(f"// Nguon      : Sliding window HOP={HOP_SIZE}, NFFT={NFFT}\n\n")

        total_written = 0
        for frame_idx in range(NUM_FRAMES):
            start = frame_idx * HOP_SIZE
            end   = start + NFFT
            frame = audio_samples[start:end]
            if len(frame) < NFFT:
                frame = frame + [0] * (NFFT - len(frame))

            f.write(f"// --- Frame {frame_idx:02d} (sample [{start}:{end}]) ---\n")
            for sample in frame:
                real16 = int(sample) & 0xFFFF
                f.write(f"{real16:04X}0000\n")
                total_written += 1

    print(f"   -> Đã xuất '{filename}': {NUM_FRAMES} frames x {NFFT} samples = {total_written} dòng.")


def export_cnn_output_mem(logits, filename):
    with open(filename, 'w', encoding='utf-8') as f:
        f.write("// CNN Output: 3 class logits (Gold Reference)\n")
        f.write("// Format    : 16-bit signed, hex, 1 value per line\n")
        f.write("// Thu tu    : logit[0]=CUU, logit[1]=CUOP, logit[2]=UNKNOWN\n\n")
        for c, v in enumerate(logits):
            signed_val = wrap_signed(int(v), 16)
            f.write(f"{int(v) & 0xFFFF:04X}  // logit[{c}] = signed={signed_val}\n")

    print(f"   -> Đã xuất '{filename}': 3 giá trị logit.")


def export_fft_input_mem_batch(audio_samples_list, filename):
    with open(filename, 'w', encoding='utf-8') as f:
        f.write(f"// FFT Input : {NUM_FRAMES} frames x {NFFT} samples/frame per case\n")
        f.write(f"// Total cases: {len(audio_samples_list)}\n")
        f.write(f"// Format    : 32-bit hex per line = RRRR0000\n")
        f.write(f"// Bit [31:16]: real (PCM 16-bit signed, bu 2)\n")
        f.write(f"// Bit [15: 0]: imag (= 0000, tin hieu thuc)\n")
        f.write(f"// Tong       : {len(audio_samples_list) * NUM_FRAMES * NFFT} dong\n\n")

        total_written = 0
        for case_idx, audio_samples in enumerate(audio_samples_list):
            f.write(f"// === Case {case_idx + 1:02d} ===\n")
            for frame_idx in range(NUM_FRAMES):
                start = frame_idx * HOP_SIZE
                end   = start + NFFT
                frame = audio_samples[start:end]
                if len(frame) < NFFT:
                    frame = frame + [0] * (NFFT - len(frame))

                for sample in frame:
                    real16 = int(sample) & 0xFFFF
                    f.write(f"{real16:04X}0000\n")
                    total_written += 1

    print(f"   -> Đã xuất '{filename}': {len(audio_samples_list)} case, {total_written} dòng.")


def export_cnn_output_mem_batch(logits_list, filename):
    with open(filename, 'w', encoding='utf-8') as f:
        f.write("// CNN Output: 3 class logits per case (Gold Reference)\n")
        f.write("// Format    : 16-bit signed, hex, 1 value per line\n")
        f.write("// Thu tu    : logit[0]=CUU, logit[1]=CUOP, logit[2]=UNKNOWN\n")
        f.write(f"// Total cases: {len(logits_list)}\n\n")
        for case_idx, logits in enumerate(logits_list):
            f.write(f"// === Case {case_idx + 1:02d} ===\n")
            for c, v in enumerate(logits):
                signed_val = wrap_signed(int(v), 16)
                f.write(f"{int(v) & 0xFFFF:04X}  // logit[{c}] = signed={signed_val}\n")

    print(f"   -> Đã xuất '{filename}': {len(logits_list)} case x 3 logit.")

# ============================================================
# 5. CNN BACKEND – BIT-TRUE GOLDEN MODEL
# ============================================================

# ------ Data Loaders ------
def load_packed_weights_3x3(filename, out_ch, in_ch):
    with open(filename, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    weights = np.zeros((out_ch, in_ch, 3, 3), dtype=np.int64)
    idx = 0
    for o in range(out_ch):
        for c in range(in_ch):
            line = lines[idx]
            idx += 1
            vals = []
            for k in range(9):
                start = k * 4
                vals.append(hex_to_signed_16(line[start:start+4]))
            vals.reverse()
            weights[o, c] = np.array(vals, dtype=np.int64).reshape(3, 3)
    return weights

def load_bias32(filename, n):
    with open(filename, "r") as f:
        raw = [hex_to_signed_32(line) for line in f if line.strip()]
    return np.array(raw, dtype=np.int64)

def load_bias16(filename, n):
    with open(filename, "r") as f:
        raw = [hex_to_signed_16(line) for line in f if line.strip()]
    return np.array(raw, dtype=np.int64)

def load_linear1_weight(filename):
    w = np.zeros((128, 64, 5, 8), dtype=np.int64)
    with open(filename, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    idx = 0
    for node in range(128):
        for c in range(8):
            for r in range(5):
                line = lines[idx]
                for ch in range(64):
                    start = (63 - ch) * 4
                    w[node, ch, r, c] = hex_to_signed_16(line[start:start+4])
                idx += 1
    return w

def load_linear2_weight(filename):
    w = np.zeros((3, 128), dtype=np.int64)
    with open(filename, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    for cls in range(3):
        line = lines[cls]
        for n in range(128):
            start = (127 - n) * 4
            w[cls, n] = hex_to_signed_16(line[start:start+4])
    return w

# ------ Quantization Functions ------
def quantize_bittrue(mac, bias, accum_width, pixel_frac, weight_frac, out_frac):
    shift       = pixel_frac + weight_frac - out_frac
    round_const = 1 << (shift - 1)

    final_sum = int(mac) + int(bias)
    if final_sum < 0:
        final_sum = 0

    rounded       = (final_sum + round_const) & mask_bits(accum_width)
    hi            = accum_width - 2
    lo            = DATA_WIDTH + shift - 1
    overflow_bits = (rounded >> lo) & mask_bits(hi - lo + 1)

    if overflow_bits != 0:
        return 0x7FFF

    return (rounded >> shift) & 0xFFFF

def quantize_l1(mac, bias):
    return quantize_bittrue(mac, bias,
                            L1_ACCUM_WIDTH,
                            L1_PIXEL_FRAC, L1_WEIGHT_FRAC, L1_OUT_FRAC)

def quantize_l23(mac, bias):
    return quantize_bittrue(mac, bias,
                            L23_ACCUM_WIDTH,
                            L23_PIXEL_FRAC, L23_WEIGHT_FRAC, L23_OUT_FRAC)

def quantize_linear1(accum, bias_q8):
    final_sum = int(accum) + (int(bias_q8) << CLS_SHIFT_RIGHT)
    if final_sum < 0:
        final_sum = 0

    rounded       = (final_sum + CLS_ROUND_CONST) & mask_bits(CLS_L1_ACCUM_WIDTH)
    hi            = CLS_L1_ACCUM_WIDTH - 2
    lo            = DATA_WIDTH + CLS_SHIFT_RIGHT - 1
    overflow_bits = (rounded >> lo) & mask_bits(hi - lo + 1)

    if overflow_bits != 0:
        return 0x7FFF

    return (rounded >> CLS_SHIFT_RIGHT) & 0xFFFF

def layer2_bias_round_sat(acc_40, bias_16):
    acc_40  = wrap_signed(acc_40,  40)
    bias_16 = wrap_signed(bias_16, 16)

    bias_40    = wrap_signed(bias_16, 40)
    with_bias  = wrap_signed(acc_40 + wrap_signed(bias_40 << 8, 40), 40)

    rounded    = wrap_signed(with_bias + (1 << 7), 40)
    rounded_u  = rounded & mask_bits(40)
    upper      = (rounded_u >> 23) & mask_bits(17)

    if upper == 0x00000 or upper == 0x1FFFF:
        out_u = (rounded_u >> 8) & mask_bits(16)
    else:
        out_u = 0x7FFF if ((rounded_u >> 39) & 1) == 0 else 0x8000

    return wrap_signed(out_u, 16)

# ------ Layer Functions ------
def conv2d_quantized(x, weights, biases, quant_func):
    in_ch, h, w  = x.shape
    out_ch       = weights.shape[0]
    padded       = np.pad(x, ((0, 0), (1, 1), (1, 1)), mode="constant")
    y            = np.zeros((out_ch, h, w), dtype=np.int64)

    for c in range(w):
        for r in range(h):
            window = padded[:, r:r+3, c:c+3]
            for f_idx in range(out_ch):
                mac       = int(np.sum(window * weights[f_idx]))
                y[f_idx, r, c] = quant_func(mac, int(biases[f_idx]))
    return y

def maxpool2x2_column_major(x):
    ch, h, w    = x.shape
    out_h, out_w = h // 2, w // 2
    y           = np.zeros((ch, out_h, out_w), dtype=np.int64)

    for c in range(out_w):
        for r in range(out_h):
            y[:, r, c] = np.maximum.reduce([
                x[:, r*2,   c*2],
                x[:, r*2+1, c*2],
                x[:, r*2,   c*2+1],
                x[:, r*2+1, c*2+1],
            ])
    return y

def run_linear1(x):
    w   = load_linear1_weight(CLS_L1_WEIGHT_FILE)
    b   = load_bias16(CLS_L1_BIAS_FILE, 128)
    out = np.zeros(128, dtype=np.int64)

    for node in range(128):
        accum = 0
        for c in range(8):
            for r in range(5):
                for ch in range(64):
                    accum += int(x[ch, r, c]) * int(w[node, ch, r, c])
        out[node] = quantize_linear1(accum, int(b[node]))

    out_signed = np.zeros(128, dtype=np.int64)
    for i in range(128):
        out_signed[i] = wrap_signed(int(out[i]), 16)
    return out_signed

def run_linear2(x):
    w   = load_linear2_weight(CLS_L2_WEIGHT_FILE)
    b   = load_bias16(CLS_L2_BIAS_FILE, 3)
    out = []

    for cls in range(3):
        accum40 = 0
        for n in range(128):
            prod    = wrap_signed(int(x[n]) * int(w[cls, n]), 32)
            accum40 = wrap_signed(accum40 + wrap_signed(prod, 40), 40)
        out.append(layer2_bias_round_sat(accum40, int(b[cls])))
    return out

# ------ Top-level CNN ------
def run_cnn_backend_bittrue(spectrogram_2d):
    x = spectrogram_2d.reshape(L1_IN, MEL_BINS, NUM_FRAMES).astype(np.int64)

    w1 = load_packed_weights_3x3(L1_WEIGHT_FILE, L1_OUT, L1_IN)
    b1 = load_bias32(L1_BIAS_FILE, L1_OUT)
    w2 = load_packed_weights_3x3(L2_WEIGHT_FILE, L2_OUT, L2_IN)
    b2 = load_bias32(L2_BIAS_FILE, L2_OUT)
    w3 = load_packed_weights_3x3(L3_WEIGHT_FILE, L3_OUT, L3_IN)
    b3 = load_bias32(L3_BIAS_FILE, L3_OUT)

    x = conv2d_quantized(x, w1, b1, quantize_l1)
    x = maxpool2x2_column_major(x)       # → (16 × 20 × 32)

    x = conv2d_quantized(x, w2, b2, quantize_l23)
    x = maxpool2x2_column_major(x)       # → (32 × 10 × 16)

    x = conv2d_quantized(x, w3, b3, quantize_l23)
    x = maxpool2x2_column_major(x)       # → (64 × 5 × 8)

    hidden  = run_linear1(x)             # → 128 nodes, signed 16-bit
    logits  = run_linear2(hidden)        # → 3 logits, signed 16-bit

    return logits

# ============================================================
# 6. MAIN – BATCH TEST 30 FILE
# ============================================================
def main():
    parser = argparse.ArgumentParser(description="System Test: Audio -> Front-End -> CNN -> Export .mem")
    parser.add_argument("--export-case", type=int, default=None,
                        help="Chỉ số test case (1-based) cần xuất riêng sang hw_input.mem và hw_output.mem; bỏ trống để xuất toàn bộ 30 case")
    parser.add_argument("--export-dir", type=str, default=".",
                        help="Thư mục lưu hai file .mem xuất ra")
    args = parser.parse_args()

    LABEL_MAP = {0: "CỨU", 1: "CƯỚP", 2: "UNKNOWN"}

    export_dir = Path(args.export_dir)
    export_dir.mkdir(parents=True, exist_ok=True)
    input_mem_path = export_dir / OUTPUT_FFT_INPUT_MEM
    output_mem_path = export_dir / OUTPUT_CNN_OUTPUT_MEM

    # ── Xây dựng danh sách 30 test case ──────────────────────
    # Cấu trúc: file_audio_test/<subdir>/test_<prefix>_<1..10>.wav
    BASE_DIR = Path("file_audio_test")
    test_cases = []
    for subdir, prefix, label_id in [
        ("file_cuu",  "cuu",  0),
        ("file_cuop", "cuop", 1),
        ("file_unk",  "unk",  2),
    ]:
        for i in range(1, 11):
            wav_path = BASE_DIR / subdir / f"test_{prefix}_{i}.wav"
            test_cases.append((wav_path, label_id))

    # ── Tải tài nguyên dùng chung (chỉ load 1 lần) ───────────
    print("=== KHỞI TẠO TÀI NGUYÊN ===")
    mel_matrix = load_mel_rom(DEFAULT_MEL_ROM)
    log_lut    = load_log_lut(DEFAULT_LOG_LUT)

    # ── Header bảng kết quả ───────────────────────────────────
    W = 26  # độ rộng cột tên file
    print(f"\n=== BẮT ĐẦU BATCH TEST: {len(test_cases)} FILE ===\n")
    print(f"{'#':<4} {'FILE':<{W}} {'NHÃN THẬT':<10} {'DỰ ĐOÁN':<10} "
          f"{'LOGIT[CỨU,CƯỚP,UNK]':<30} STATUS")
    print("─" * 88)

    results = []
    exported_audio = []
    exported_logits = []

    for idx, (wav_path, true_label) in enumerate(test_cases, start=1):

        # Kiểm tra file tồn tại
        if not wav_path.exists():
            print(f"{idx:<4} {wav_path.name:<{W}} [KHÔNG TÌM THẤY FILE – BỎ QUA]")
            continue

        # ── Load audio (verbose=False: tắt diagnostic print) ──
        audio_samples, _ = load_wav_full(wav_path, verbose=False)

        # ── Trích xuất Log-Mel Spectrogram (logic giữ nguyên) ─
        spectrogram_2d = np.zeros((MEL_BINS, NUM_FRAMES), dtype=np.int32)
        for frame_idx in range(NUM_FRAMES):
            start_idx     = frame_idx * HOP_SIZE
            frame_samples = audio_samples[start_idx : start_idx + NFFT]
            fft_16_for_mel = build_fft_golden(frame_samples)
            mel_out        = build_log_mel_golden(fft_16_for_mel, mel_matrix, log_lut)
            for m in range(MEL_BINS):
                spectrogram_2d[m, frame_idx] = mel_out[m]

        # ── CNN Inference (logic giữ nguyên) ──────────────────
        logits          = run_cnn_backend_bittrue(spectrogram_2d)
        predicted_class = int(np.argmax(logits))
        correct         = (predicted_class == true_label)

        if args.export_case is not None:
            if idx == args.export_case:
                export_fft_input_mem(audio_samples, str(input_mem_path))
                export_cnn_output_mem(logits, str(output_mem_path))
                print(f"   [EXPORT MEM] File '{wav_path.name}' -> '{input_mem_path.name}', '{output_mem_path.name}'")
        else:
            exported_audio.append(audio_samples)
            exported_logits.append(logits)

        results.append({
            "file"    : wav_path.name,
            "true"    : true_label,
            "pred"    : predicted_class,
            "logits"  : logits,
            "correct" : correct,
        })

        # ── In kết quả từng file ──────────────────────────────
        logit_str = f"[{logits[0]:6d}, {logits[1]:6d}, {logits[2]:6d}]"
        status    = "✓" if correct else "✗  <- SAI"
        print(f"{idx:<4} {wav_path.name:<{W}} "
              f"{LABEL_MAP[true_label]:<10} "
              f"{LABEL_MAP[predicted_class]:<10} "
              f"{logit_str:<30} {status}")

    if args.export_case is None:
        export_fft_input_mem_batch(exported_audio, str(input_mem_path))
        export_cnn_output_mem_batch(exported_logits, str(output_mem_path))
        print(f"   [EXPORT MEM] Đã gom toàn bộ {len(exported_audio)} case vào '{input_mem_path.name}' và '{output_mem_path.name}'")

    # ── Tổng hợp kết quả ──────────────────────────────────────
    print("\n" + "═" * 88)
    print("=== KẾT QUẢ TỔNG HỢP ===\n")

    total_files   = len(results)
    total_correct = sum(1 for r in results if r["correct"])

    for lid, lname in LABEL_MAP.items():
        cls_res  = [r for r in results if r["true"] == lid]
        cls_ok   = sum(1 for r in cls_res if r["correct"])
        pct      = 100.0 * cls_ok / len(cls_res) if cls_res else 0.0
        bar_len  = int(pct / 5)          # mỗi █ = 5%
        bar      = "█" * bar_len + "░" * (20 - bar_len)
        print(f"  {lname:<10}: {cls_ok:2d}/{len(cls_res):2d}  [{bar}]  {pct:.0f}%")

    print()
    overall_pct = 100.0 * total_correct / total_files if total_files else 0.0
    print(f"  TỔNG CỘNG : {total_correct}/{total_files} đúng  –  Accuracy: {overall_pct:.1f}%")

    # Liệt kê các file dự đoán sai (nếu có)
    wrong = [r for r in results if not r["correct"]]
    if wrong:
        print(f"\n  Danh sách {len(wrong)} file dự đoán SAI:")
        for r in wrong:
            print(f"    • {r['file']:<{W}}  "
                  f"Thật: {LABEL_MAP[r['true']]}  "
                  f"->  Dự đoán: {LABEL_MAP[r['pred']]}  "
                  f"Logits: {r['logits']}")
    else:
        print("\n  Tất cả file dự đoán ĐÚNG!")

    print("═" * 88)


if __name__ == "__main__":
    main()