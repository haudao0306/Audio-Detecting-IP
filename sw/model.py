# model.py

import torch
import torch.nn as nn
import config  # Import cấu hình tập trung

# ========================================================
# LỚP MÔ PHỎNG SAI SỐ LƯỢNG TỬ HÓA KÍCH HOẠT (ACTIVATION QUANT)
# ========================================================
class QuantizeSimulate(nn.Module):
    def __init__(self, frac_bits=config.HW_FRAC_BITS):
        super().__init__()
        self.frac_bits = frac_bits

    def forward(self, x):
        # Tính toán hệ số dịch bit dựa trên số bit thập phân được cấu hình
        scale = 2.0 ** self.frac_bits
        x_quant = torch.round(x * scale) / scale
        # Sử dụng mẹo STE (Straight-Through Estimator) để không làm đứt mạch Gradient khi Backprop
        return x + (x_quant - x).detach()


# ========================================================
# LỚP LỚP CONV2D LƯỢNG TỬ HÓA TRỌNG SỐ CHO PHẦN CỨNG (WEIGHT QAT)
# ========================================================
class QConv2d(nn.Conv2d):
    def __init__(self, *args, frac_bits=config.HW_FRAC_BITS, **kwargs):
        super().__init__(*args, **kwargs)
        self.frac_bits = frac_bits

    def forward(self, x):
        scale = 2.0 ** self.frac_bits
        # Lượng tử hóa ma trận Weights của bộ lọc 
        w_quant = torch.round(self.weight * scale) / scale
        w_qat = self.weight + (w_quant - self.weight).detach()
        
        # Lượng tử hóa Biases nếu lớp này có sử dụng bias
        b_qat = None
        if self.bias is not None:
            b_quant = torch.round(self.bias * scale) / scale
            b_qat = self.bias + (b_quant - self.bias).detach()
            
        return nn.functional.conv2d(
            x, w_qat, b_qat, self.stride, self.padding, self.dilation, self.groups
        )


# ========================================================
# LỚP LỚP TUYẾN TÍNH LƯỢNG TỬ HÓA CHO PHẦN CỨNG (LINEAR QAT)
# ========================================================
class QLinear(nn.Linear):
    def __init__(self, *args, frac_bits=config.HW_FRAC_BITS, **kwargs):
        super().__init__(*args, **kwargs)
        self.frac_bits = frac_bits

    def forward(self, x):
        scale = 2.0 ** self.frac_bits
        # Lượng tử hóa Weights
        w_quant = torch.round(self.weight * scale) / scale
        w_qat = self.weight + (w_quant - self.weight).detach()
        
        # Lượng tử hóa Biases
        b_qat = None
        if self.bias is not None:
            b_quant = torch.round(self.bias * scale) / scale
            b_qat = self.bias + (b_quant - self.bias).detach()
            
        return nn.functional.linear(x, w_qat, b_qat)


# ========================================================
# MẠNG CNN ĐẦY ĐỦ CHO AUDIO (MÔ PHỎNG PHẦN CỨNG BIT-TRUE)
# ========================================================
class AudioCNN(nn.Module):
    def __init__(self, n_classes=config.NUM_CLASSES):
        super().__init__()
        
        # CẬP NHẬT: Tầng lượng tử hóa đầu vào nhận config.HW_INPUT_FRAC_BITS (độ phân giải Q6.10 của Spectrogram)
        self.quant = QuantizeSimulate(frac_bits=config.HW_INPUT_FRAC_BITS) 

        # Trích xuất đặc trưng (Các lớp toán tử sử dụng QConv2d thay cho nn.Conv2d thông thường)
        self.features = nn.Sequential(
            QConv2d(1, 16, 3, padding=1),
            nn.BatchNorm2d(16),
            nn.ReLU(),
            nn.MaxPool2d(2),
            QuantizeSimulate(),  # Các tầng trung gian mặc định lượng tử hóa theo HW_FRAC_BITS (Q8.8)

            QConv2d(16, 32, 3, padding=1),
            nn.BatchNorm2d(32),
            nn.ReLU(),
            nn.MaxPool2d(2),
            QuantizeSimulate(),

            QConv2d(32, 64, 3, padding=1),
            nn.BatchNorm2d(64),
            nn.ReLU(),
            nn.MaxPool2d(2),
            QuantizeSimulate(),
        )

        # Tính toán tự động số lượng node đầu vào cho tầng Fully Connected
        with torch.no_grad():
            dummy = torch.zeros(1, 1, config.N_MELS, config.MAX_FRAMES)
            out = self.features(dummy)
            flat_dim = out.view(1, -1).size(1)

        # Bộ phân lớp (Sử dụng QLinear chuyên dụng phần cứng)
        self.classifier = nn.Sequential(
            QLinear(flat_dim, 128),  # Index 0 (Khớp với 128 nodes của Verilog)
            nn.ReLU(),               # Index 1
            QuantizeSimulate(),      # Index 2
            nn.Dropout(0.4),         # Index 3 (Thêm Dropout để chống Overfitting và đẩy lớp cuối xuống số 4)
            QLinear(128, n_classes)  # Index 4 (Đã khớp với state_dict['classifier.4.weight'])
        )       

    def forward(self, x):
        x = self.quant(x)       # Bước 1: Khớp định dạng Q6.10 đầu vào
        x = self.features(x)    # Bước 2: Tích chập + Pooling + Lượng tử hóa từng chặng
        x = x.view(x.size(0), -1) 
        x = self.classifier(x)  # Bước 3: Đưa qua lớp Dense kết nối đầy đủ
        return x

if __name__ == "__main__":
    # Test nhanh cấu trúc mô hình mạng
    model = AudioCNN()
    test_input = torch.randn(2, 1, config.N_MELS, config.MAX_FRAMES)
    test_output = model(test_input)
    print("Mô hình khởi tạo thành công!")
    print("Kích thước đầu ra kiểm thử:", test_output.shape) # Kỳ vọng: (2, 3) tương ứng batch_size=2 và 3 class
