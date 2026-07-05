# config.py

# ── Đường dẫn ───────────────────────────────────────
DATA_DIR = r"D:\NAM4\DOAN2\Python\dataset_wav"

FOLDER_LIST = [
    rf"{DATA_DIR}\cuu",
    rf"{DATA_DIR}\cuop",
    rf"{DATA_DIR}\unknown",
]

LABEL_IDS   = [0, 1, 2]
LABEL_NAMES = ["cuu", "cuop", "unknown"]

CHECKPOINT_PATH = "audio_cnn.pth"

# ── Tham số Phần cứng (Hardware / Fixed-point) ──────
# (THÊM PHẦN NÀY ĐỂ FIX LỖI)
HW_FRAC_BITS       = 8       # Độ phân giải Weights/Biases (Q8.8)
HW_INPUT_FRAC_BITS = 10      # Độ phân giải Input Spectrogram (Q6.10)
HW_SCALE_FACTOR    = 1024.0  # Hệ số Scale đầu vào (2^10)

# ── Xử lý âm thanh ──────────────────────────────────
SAMPLE_RATE = 16000
N_MELS      = 40
FMAX        = 8000
MAX_FRAMES  = 64

# ── Huấn luyện ──────────────────────────────────────
BATCH_SIZE    = 16
EPOCHS        = 30  
LEARNING_RATE = 0.001
VAL_SPLIT     = 0.2
NUM_CLASSES   = 3

# ── Early stopping ───────────────────────────────────
PATIENCE = 6