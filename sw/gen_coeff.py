import numpy as np
import librosa

# =========================
# PARAMETERS
# =========================
NUM_FILTERS = 40
NUM_BINS    = 512
N_FFT       = 1024
SAMPLE_RATE = 16000

# Generate Mel filter bank
mel_filters = librosa.filters.mel(
    sr=SAMPLE_RATE,
    n_fft=N_FFT,
    n_mels=NUM_FILTERS,
    fmin=0,
    fmax=SAMPLE_RATE // 2,
    norm=None
)
mel_filters = mel_filters[:, :NUM_BINS]

# Sửa lỗi tràn số Q0.15 (Chống phân cực ngược 0x8000)
def float_to_q15(x):
    x = np.clip(x, 0.0, 1.0)
    val = int(round(x * 32768))
    return min(val, 32767) # Ép tối đa là 32767 (0x7FFF) để an toàn cho signed/unsigned

# --- BƯỚC 1: LỌC VÀ CHỌN BỘ LỌC CHO TỪNG BIN ---
raw_slots = []
for k in range(NUM_BINS):
    active_filters = []
    for m in range(NUM_FILTERS):
        val = mel_filters[m][k]
        if val > 1e-6:
            active_filters.append([m, val])
            
    # Nếu có > 2 bộ lọc trùng bần, chọn 2 cái lớn nhất
    if len(active_filters) > 2:
        active_filters.sort(key=lambda x: x[1], reverse=True)
        active_filters = active_filters[:2]
        
    # SỬA LỖI 1: Luôn sắp xếp lại theo chỉ số bộ lọc để đảm bảo f0 < f1
    active_filters.sort(key=lambda x: x[0])
    raw_slots.append(active_filters)

# --- BƯỚC 2: TÌM LAST BIN THỰC TẾ TRÊN ROM (SỬA LỖI 2) ---
last_bin_of_filter = {}
for m in range(NUM_FILTERS):
    last_bin_of_filter[m] = -1

for k in range(NUM_BINS):
    for item in raw_slots[k]:
        m = item[0]
        last_bin_of_filter[m] = k # Cập nhật liên tục, vị trí cuối cùng xuất hiện sẽ là last bin

# --- BƯỚC 3: ĐÓNG GÓI PACKING 48-BIT ---
rom_data = []
for k in range(NUM_BINS):
    slots = raw_slots[k]
    
    f0 = f1 = 0
    w0 = w1 = 0
    done_f0 = done_f1 = 0
    
    if len(slots) >= 1:
        f0 = slots[0][0]
        w0 = float_to_q15(slots[0][1])
        if k == last_bin_of_filter[f0]:
            done_f0 = 1
            
    if len(slots) >= 2:
        f1 = slots[1][0]
        w1 = float_to_q15(slots[1][1])
        if k == last_bin_of_filter[f1]:
            done_f1 = 1
            
    # Đóng gói Word 48-bit theo đúng cấu trúc phần cứng của bạn
    word = (done_f1 << 45) | (done_f0 << 44) | (f1 << 38) | (f0 << 32) | (w1 << 16) | w0
    rom_data.append(word)

# Xuất file HEX sạch (Không chứa dòng text giải thích)
with open("mel_rom_48bit_with_flags.mem", "w") as f:
    for val in rom_data:
        f.write("{:012x}\n".format(val))

print("Done! Generated clean mel_rom_48bit_with_flags.mem")