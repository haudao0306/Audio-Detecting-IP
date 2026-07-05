#!/usr/bin/env python3
"""Export Python reference vectors for the rescue-word hardware pipeline.

Pipeline matched to the user's inference script:
audio -> normalize -> STFT(1024, win=512, hop=256) -> mel(40) -> log-mel
-> pad/trim to 40x64 -> optional CNN inference.
"""

import argparse
import json
import math
import sys
from pathlib import Path

import numpy as np


SR = 16000
N_FFT = 1024
WIN_LENGTH = 512
HOP_LENGTH = 256
N_MELS = 40
FMAX = 8000
MAX_FRAMES = 64
FFT_IWIDTH = 16
FFT_OWIDTH = 22
FFT_SCALE_SHIFT = int(math.log2(N_FFT)) - (FFT_OWIDTH - FFT_IWIDTH)
LABEL_NAMES = ["cuu", "cuop", "unknown"]


def i16(value):
    value = int(value)
    value = max(-(1 << 15), min((1 << 15) - 1, value))
    return value & 0xffff


def signed_to_hex(value, width):
    value = int(value)
    lo = -(1 << (width - 1))
    hi = (1 << (width - 1)) - 1
    value = max(lo, min(hi, value))
    return value & ((1 << width) - 1)


def pack_complex_i16(real, imag=0):
    return (i16(real) << 16) | i16(imag)


def quantize_q(value, total_bits, frac_bits):
    return np.round(value * (1 << frac_bits)).astype(np.int64)


def write_lines(path, lines):
    with path.open("w", encoding="ascii") as fp:
        for line in lines:
            fp.write(f"{line}\n")


def write_matrix_txt(path, matrix, row_name="row", col_name="col"):
    with path.open("w", encoding="ascii") as fp:
        fp.write(f"# {row_name} {col_name} value\n")
        for r in range(matrix.shape[0]):
            for c in range(matrix.shape[1]):
                fp.write(f"{r:4d} {c:4d} {matrix[r, c]: .9e}\n")


def make_librosa_features(y, librosa):
    mel_spec = librosa.feature.melspectrogram(
        y=y,
        sr=SR,
        n_fft=N_FFT,
        win_length=WIN_LENGTH,
        hop_length=HOP_LENGTH,
        n_mels=N_MELS,
        fmax=FMAX,
    )
    log_mel = librosa.power_to_db(mel_spec)

    if log_mel.shape[1] < MAX_FRAMES:
        pad_width = MAX_FRAMES - log_mel.shape[1]
        log_mel_40x64 = np.pad(log_mel, ((0, 0), (0, pad_width)), mode="constant")
    else:
        log_mel_40x64 = log_mel[:, :MAX_FRAMES]

    return mel_spec, log_mel, log_mel_40x64


def make_stft_reference(y, librosa):
    stft = librosa.stft(
        y,
        n_fft=N_FFT,
        hop_length=HOP_LENGTH,
        win_length=WIN_LENGTH,
        window="hann",
        center=True,
        pad_mode="constant",
    )
    power = np.abs(stft) ** 2
    return stft, power


def make_fft_input_frames(y, librosa):
    padded = np.pad(y, (N_FFT // 2, N_FFT // 2), mode="constant")
    n_frames = 1 + (len(padded) - N_FFT) // HOP_LENGTH
    window = librosa.filters.get_window("hann", WIN_LENGTH, fftbins=True)
    window = librosa.util.pad_center(window, size=N_FFT)

    frames = np.zeros((n_frames, N_FFT), dtype=np.float32)
    for frame_idx in range(n_frames):
        start = frame_idx * HOP_LENGTH
        frames[frame_idx, :] = padded[start:start + N_FFT] * window
    return frames


def export_fft_input(frames, outdir):
    scale = (1 << (FFT_IWIDTH - 1)) - 1
    q_frames = np.round(frames * scale).astype(np.int64)

    mem_lines = []
    txt_lines = ["# frame sample real_i16 imag_i16 float_real"]
    for frame in range(min(MAX_FRAMES, q_frames.shape[0])):
        for sample in range(N_FFT):
            real = int(q_frames[frame, sample])
            mem_lines.append(f"{pack_complex_i16(real, 0):08x}")
            txt_lines.append(
                f"{frame:4d} {sample:4d} {real:7d} {0:7d} {frames[frame, sample]: .9e}"
            )

    write_lines(outdir / "fft_input_1024_complex_i16.mem", mem_lines)
    write_lines(outdir / "fft_input_1024_complex_i16.txt", txt_lines)
    return q_frames


def export_fft_expected(q_frames, outdir):
    scale = 1 << FFT_SCALE_SHIFT
    hex_digits = math.ceil((2 * FFT_OWIDTH) / 4)
    mem_lines = []
    txt_lines = ["# frame bin real_i22 imag_i22 packed_hex"]

    for frame in range(min(MAX_FRAMES, q_frames.shape[0])):
        spectrum = np.fft.fft(q_frames[frame, :], n=N_FFT) / scale
        for bin_idx in range(N_FFT):
            real = int(np.round(spectrum[bin_idx].real))
            imag = int(np.round(spectrum[bin_idx].imag))
            packed = (
                signed_to_hex(real, FFT_OWIDTH) << FFT_OWIDTH
            ) | signed_to_hex(imag, FFT_OWIDTH)
            mem_lines.append(f"{packed:0{hex_digits}x}")
            txt_lines.append(f"{frame:4d} {bin_idx:4d} {real:9d} {imag:9d} {packed:0{hex_digits}x}")

    write_lines(outdir / "fft_expected_1024_complex_i22.mem", mem_lines)
    write_lines(outdir / "fft_expected_1024_complex_i22.txt", txt_lines)


def export_log_mel_q(log_mel_40x64, outdir, total_bits, frac_bits):
    q = quantize_q(log_mel_40x64, total_bits, frac_bits)
    hex_digits = math.ceil(total_bits / 4)

    mem_lines = []
    txt_lines = [f"# mel time log_mel q{total_bits - frac_bits - 1}.{frac_bits} hex"]
    for mel in range(N_MELS):
        for time in range(MAX_FRAMES):
            qval = int(q[mel, time])
            hval = signed_to_hex(qval, total_bits)
            mem_lines.append(f"{hval:0{hex_digits}x}")
            txt_lines.append(
                f"{mel:4d} {time:4d} {log_mel_40x64[mel, time]: .9e} {qval:8d} {hval:0{hex_digits}x}"
            )

    write_lines(outdir / f"cnn_input_logmel_q{total_bits}_{frac_bits}.mem", mem_lines)
    write_lines(outdir / f"cnn_input_logmel_q{total_bits}_{frac_bits}.txt", txt_lines)


def export_system_input_audio(y, outdir):
    samples = [int(round(v * 32767)) for v in y]
    write_lines(outdir / "system_input_audio_i16.mem",
                [f"{i16(v):04x}" for v in samples])
    write_lines(outdir / "system_input_audio_i16.txt",
                ["# index sample_i16 hex"] +
                [f"{idx:6d} {v:7d} {i16(v):04x}" for idx, v in enumerate(samples)])
    return {
        "input_kind": "audio",
        "input_mem": "system_input_audio_i16.mem",
        "samples": len(samples),
        "format": "signed 16-bit PCM, one real audio sample per line",
    }


def export_system_input_fft(frames, outdir):
    q_frames = export_fft_input(frames, outdir)
    (outdir / "system_input_fft_1024_complex_i16.mem").write_text(
        (outdir / "fft_input_1024_complex_i16.mem").read_text(encoding="ascii"),
        encoding="ascii",
    )
    return {
        "input_kind": "fft",
        "input_mem": "system_input_fft_1024_complex_i16.mem",
        "frames": int(min(MAX_FRAMES, q_frames.shape[0])),
        "samples_per_frame": N_FFT,
        "format": "packed {real[15:0], imag[15:0]}, one FFT input sample per line",
    }


def write_system_expected(cnn_result, outdir):
    if cnn_result is None:
        return

    prediction = int(cnn_result["prediction"])
    write_lines(outdir / "system_expected_label.mem", [f"{prediction:02x}"])
    with (outdir / "system_expected.txt").open("w", encoding="ascii") as fp:
        fp.write("# Final system-level expected result\n")
        fp.write(f"prediction_index {prediction}\n")
        fp.write(f"prediction_label {cnn_result['label']}\n")
        fp.write(f"prediction_probability {cnn_result['probability']:.9e}\n")


def run_cnn_if_requested(log_mel_40x64, args, outdir):
    if not args.model_path:
        return None

    import torch

    if args.train_dir:
        sys.path.insert(0, str(args.train_dir))

    from train_cnn import AudioCNN

    model = AudioCNN(n_classes=len(LABEL_NAMES))
    model.load_state_dict(torch.load(args.model_path, map_location="cpu", weights_only=True))
    model.eval()

    x = torch.tensor(log_mel_40x64, dtype=torch.float32).unsqueeze(0).unsqueeze(0)
    with torch.no_grad():
        logits = model(x)
        probs = torch.softmax(logits, dim=1)[0].cpu().numpy()
        pred = int(logits.argmax(1).item())

    with (outdir / "cnn_logits_probs.txt").open("w", encoding="ascii") as fp:
        fp.write("# class label logit probability\n")
        for idx, label in enumerate(LABEL_NAMES):
            fp.write(f"{idx:2d} {label:8s} {float(logits[0, idx]): .9e} {probs[idx]: .9e}\n")
        fp.write(f"\nprediction {pred} {LABEL_NAMES[pred]} {probs[pred]:.9e}\n")

    return {"prediction": pred, "label": LABEL_NAMES[pred], "probability": float(probs[pred])}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--wav", required=True, help="Input wav file")
    parser.add_argument("--outdir", default="hw_vectors", type=Path)
    parser.add_argument("--model-path", default="", help="Optional audio_cnn.pth")
    parser.add_argument("--train-dir", default="", type=Path, help="Directory containing train_cnn.py")
    parser.add_argument("--q-total", type=int, default=16)
    parser.add_argument("--q-frac", type=int, default=8)
    parser.add_argument("--system-only", action="store_true",
                        help="Only export top-system input and final CNN expected output")
    parser.add_argument("--system-input", choices=["fft", "audio"], default="fft",
                        help="Top-system input format. Use fft if the top starts at the FFT module.")
    args = parser.parse_args()

    import librosa

    args.outdir.mkdir(parents=True, exist_ok=True)

    y, sr = librosa.load(args.wav, sr=SR)
    y = y / (np.max(np.abs(y)) + 1e-9)

    mel_spec, log_mel, log_mel_40x64 = make_librosa_features(y, librosa)
    stft, power = make_stft_reference(y, librosa)
    frames = make_fft_input_frames(y, librosa)
    cnn_result = run_cnn_if_requested(log_mel_40x64, args, args.outdir)

    if args.system_only:
        if args.system_input == "audio":
            system_input = export_system_input_audio(y, args.outdir)
        else:
            system_input = export_system_input_fft(frames, args.outdir)

        write_system_expected(cnn_result, args.outdir)

        summary = {
            "mode": "system_only",
            "wav": str(args.wav),
            "sr": SR,
            "n_fft": N_FFT,
            "win_length": WIN_LENGTH,
            "hop_length": HOP_LENGTH,
            "n_mels": N_MELS,
            "fmax": FMAX,
            "max_frames": MAX_FRAMES,
            "system_input": system_input,
            "expected_output": {
                "label_mem": "system_expected_label.mem" if cnn_result else None,
                "text": "system_expected.txt" if cnn_result else None,
                "cnn": cnn_result,
            },
            "note": "This mode is for top-level integration test: feed system_input and compare only final label/result.",
        }

        with (args.outdir / "system_summary.json").open("w", encoding="ascii") as fp:
            json.dump(summary, fp, indent=2)

        print(f"Exported SYSTEM-ONLY vectors to {args.outdir}")
        print(f"  system input   : {args.outdir / system_input['input_mem']}")
        if cnn_result:
            print(f"  expected label : {args.outdir / 'system_expected_label.mem'}")
            print(f"  expected result: {cnn_result['label']} ({cnn_result['probability'] * 100:.2f}%)")
        else:
            print("  expected result: skipped because --model-path was not provided")
        return

    np.save(args.outdir / "audio_norm_float.npy", y)
    np.save(args.outdir / "stft_complex.npy", stft)
    np.save(args.outdir / "power_spectrum_float.npy", power)
    np.save(args.outdir / "mel_power_float.npy", mel_spec)
    np.save(args.outdir / "log_mel_float.npy", log_mel)
    np.save(args.outdir / "cnn_input_log_mel_40x64_float.npy", log_mel_40x64)

    write_lines(args.outdir / "audio_norm_i16.mem",
                [f"{i16(round(v * 32767)):04x}" for v in y])
    q_frames = export_fft_input(frames, args.outdir)
    export_fft_expected(q_frames, args.outdir)
    write_matrix_txt(args.outdir / "mel_power_float.txt", mel_spec, "mel", "time")
    write_matrix_txt(args.outdir / "log_mel_float.txt", log_mel, "mel", "time")
    write_matrix_txt(args.outdir / "cnn_input_log_mel_40x64_float.txt",
                     log_mel_40x64, "mel", "time")
    export_log_mel_q(log_mel_40x64, args.outdir, args.q_total, args.q_frac)

    summary = {
        "wav": str(args.wav),
        "sr": SR,
        "n_fft": N_FFT,
        "win_length": WIN_LENGTH,
        "hop_length": HOP_LENGTH,
        "n_mels": N_MELS,
        "fmax": FMAX,
        "max_frames": MAX_FRAMES,
        "librosa_defaults_that_matter": {
            "stft_center": True,
            "stft_pad_mode": "constant",
            "window": "hann",
            "mel_htk": False,
            "mel_norm": "slaney",
            "power_to_db_ref": 1.0,
            "power_to_db_top_db": 80.0,
        },
        "audio_samples_after_resample": int(len(y)),
        "stft_shape": list(stft.shape),
        "mel_shape_before_pad_trim": list(log_mel.shape),
        "cnn_input_shape": [1, 1, N_MELS, MAX_FRAMES],
        "log_mel_quantization": {
            "total_bits": args.q_total,
            "frac_bits": args.q_frac,
        },
        "fft_core_reference": {
            "input_width": FFT_IWIDTH,
            "output_width": FFT_OWIDTH,
            "scale_shift": FFT_SCALE_SHIFT,
            "scale_divisor": 1 << FFT_SCALE_SHIFT,
        },
        "cnn": cnn_result,
    }

    with (args.outdir / "summary.json").open("w", encoding="ascii") as fp:
        json.dump(summary, fp, indent=2)

    print(f"Exported hardware vectors to {args.outdir}")
    print(f"  FFT input mem : {args.outdir / 'fft_input_1024_complex_i16.mem'}")
    print(f"  FFT expected  : {args.outdir / 'fft_expected_1024_complex_i22.mem'}")
    print(f"  CNN input mem : {args.outdir / f'cnn_input_logmel_q{args.q_total}_{args.q_frac}.mem'}")
    if cnn_result:
        print(f"  CNN prediction: {cnn_result['label']} ({cnn_result['probability'] * 100:.2f}%)")


if __name__ == "__main__":
    main()
