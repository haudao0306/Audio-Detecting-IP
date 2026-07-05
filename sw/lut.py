import math

LUT_BITS  = 12
FRAC_BITS = 12
LUT_SIZE  = 1 << LUT_BITS   # 4096
FILE_OUT  = "log_lut.mem"

with open(FILE_OUT, "w") as f:
    for addr in range(LUT_SIZE):
        # x chạy từ 1.0 đến 1.999755...
        x   = 1.0 + addr / LUT_SIZE            
        
        # SỬA TẠI ĐÂY: Dùng round() thay vì int() để tăng độ chính xác dải động
        val = round(math.log2(x) * (1 << FRAC_BITS))  # Định dạng Q4.12
        
        # Đảm bảo không bị tràn số âm/dương ngoài ý muốn
        val = int(val) & 0xFFFF                
        
        f.write(f"{val:04X}\n")

print(f"Done! Generated high-accuracy {FILE_OUT} with {LUT_SIZE} entries.")