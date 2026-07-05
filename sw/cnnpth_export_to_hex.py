# cnnpth_export_to_hex.py

import torch
import numpy as np
import os

global_overflow_count = 0


# ============================================================
# FLOAT -> FIXED HEX
# ============================================================
def float_to_fixed_hex(f_val, total_bits=16, fraction_bits=8):
    global global_overflow_count

    scaled_val = round(float(f_val) * (1 << fraction_bits))

    min_val = -(1 << (total_bits - 1))
    max_val = (1 << (total_bits - 1)) - 1

    if scaled_val < min_val or scaled_val > max_val:
        global_overflow_count += 1

    scaled_val = max(min_val, min(scaled_val, max_val))

    if scaled_val < 0:
        scaled_val = (1 << total_bits) + scaled_val

    hex_chars = total_bits // 4

    return f"{scaled_val:0{hex_chars}X}"


# ============================================================
# CONV + BN FUSION
# ============================================================
def fuse_conv_and_bn(
    conv_w,
    conv_b,
    bn_w,
    bn_b,
    bn_mean,
    bn_var,
    eps=1e-5
):
    std = torch.sqrt(bn_var + eps)

    scale = bn_w / std

    scale_reshaped = scale.view(-1, 1, 1, 1)

    fused_w = conv_w * scale_reshaped

    if conv_b is None:
        conv_b = torch.zeros_like(bn_mean)

    fused_b = (conv_b - bn_mean) * scale + bn_b

    return fused_w, fused_b


# ============================================================
# EXPORT CONV WEIGHTS
#
# 1 line = 1 (out_channel, in_channel)
#
# [w8][w7][w6][w5][w4][w3][w2][w1][w0]
#
# width = 9 * 16 = 144 bit
# ============================================================
def export_conv_weights_packed(
    f_w,
    out_file,
    total_bits=16,
    frac_bits=8
):
    out_ch, in_ch, kh, kw = f_w.shape

    assert kh == 3
    assert kw == 3

    with open(out_file, "w") as f:

        for o in range(out_ch):

            for c in range(in_ch):

                taps = [
                    f_w[o, c, 0, 0].item(),  # w0
                    f_w[o, c, 0, 1].item(),  # w1
                    f_w[o, c, 0, 2].item(),  # w2

                    f_w[o, c, 1, 0].item(),  # w3
                    f_w[o, c, 1, 1].item(),  # w4
                    f_w[o, c, 1, 2].item(),  # w5

                    f_w[o, c, 2, 0].item(),  # w6
                    f_w[o, c, 2, 1].item(),  # w7
                    f_w[o, c, 2, 2].item(),  # w8
                ]

                line = ""

                for v in reversed(taps):
                    line += float_to_fixed_hex(
                        v,
                        total_bits,
                        frac_bits
                    )

                f.write(line + "\n")


# ============================================================
# MAIN
# ============================================================
def main():

    global global_overflow_count

    file_path = "audio_cnn.pth"

    if not os.path.exists(file_path):
        print(f"ERROR: Cannot find {file_path}")
        return

    state_dict = torch.load(
        file_path,
        map_location="cpu",
        weights_only=True
    )

    fusion_pairs = [
        ("features.0",  "features.1",  "features.0", 10),
        ("features.5",  "features.6",  "features.4", 8),
        ("features.10", "features.11", "features.8", 8)
    ]

    TOTAL_BITS = 16
    WEIGHT_FRAC = 8

    BIAS_TOTAL_BITS = 32

    print("")
    print("===================================================")
    print(" EXPORT CNN PARAMETERS")
    print("===================================================")

    # ========================================================
    # FEATURE EXTRACTOR
    # ========================================================
    for conv_name, bn_name, out_prefix, pixel_frac in fusion_pairs:

        try:

            conv_w = state_dict[f"{conv_name}.weight"]
            conv_b = state_dict.get(f"{conv_name}.bias", None)

            bn_w = state_dict[f"{bn_name}.weight"]
            bn_b = state_dict[f"{bn_name}.bias"]
            bn_mean = state_dict[f"{bn_name}.running_mean"]
            bn_var = state_dict[f"{bn_name}.running_var"]

            fused_w, fused_b = fuse_conv_and_bn(
                conv_w,
                conv_b,
                bn_w,
                bn_b,
                bn_mean,
                bn_var
            )

            local_overflow = global_overflow_count

            # =================================================
            # PACKED WEIGHT
            # =================================================
            w_file = f"{out_prefix}_fused_weight.hex"

            export_conv_weights_packed(
                fused_w,
                w_file,
                TOTAL_BITS,
                WEIGHT_FRAC
            )

            # =================================================
            # BIAS
            # =================================================
            b_file = f"{out_prefix}_fused_bias.hex"

            bias_frac_bits = pixel_frac + WEIGHT_FRAC

            with open(b_file, "w") as f:

                for val in fused_b.flatten():

                    f.write(
                        float_to_fixed_hex(
                            val.item(),
                            BIAS_TOTAL_BITS,
                            bias_frac_bits
                        )
                        + "\n"
                    )

            diff = global_overflow_count - local_overflow

            if diff > 0:
                warn = f"WARNING: {diff} overflow values clipped"
            else:
                warn = "SAFE"

            print(
                f"{conv_name} + {bn_name}"
                f" -> {w_file}"
                f" ({warn})"
            )

        except KeyError as e:

            print(f"Missing key: {e}")

    # ========================================================
    # CLASSIFIER 1
    # ========================================================
    print("")
    print("Export classifier.0")

    w1_tensor = state_dict["classifier.0.weight"]
    b1_tensor = state_dict["classifier.0.bias"]

    w1_reshaped = w1_tensor.view(
        128,
        64,
        5,
        8
    )

    with open("classifier.0_weight.hex", "w") as f:

        for node in range(128):

            for c in range(8):

                for r in range(5):

                    line = ""

                    for ch in reversed(range(64)):

                        line += float_to_fixed_hex(
                            w1_reshaped[node, ch, r, c].item(),
                            TOTAL_BITS,
                            WEIGHT_FRAC
                        )

                    f.write(line + "\n")

    with open("classifier.0_bias.hex", "w") as f:

        for val in b1_tensor.tolist():

            f.write(
                float_to_fixed_hex(
                    val,
                    TOTAL_BITS,
                    WEIGHT_FRAC
                )
                + "\n"
            )

    # ========================================================
    # CLASSIFIER 2
    # ========================================================
    print("Export classifier.3")

    w2_tensor = state_dict["classifier.4.weight"]
    b2_tensor = state_dict["classifier.4.bias"]

    with open("classifier.3_weight.hex", "w") as f:

        for node in range(3):

            line = ""

            for ch in reversed(range(128)):

                line += float_to_fixed_hex(
                    w2_tensor[node, ch].item(),
                    TOTAL_BITS,
                    WEIGHT_FRAC
                )

            f.write(line + "\n")

    with open("classifier.3_bias.hex", "w") as f:

        for node in range(3):

            f.write(
                float_to_fixed_hex(
                    b2_tensor[node].item(),
                    TOTAL_BITS,
                    WEIGHT_FRAC
                )
                + "\n"
            )

    print("")
    print("===================================================")
    print(
        f"TOTAL OVERFLOW COUNT = "
        f"{global_overflow_count}"
    )
    print("===================================================")


if __name__ == "__main__":
    main()