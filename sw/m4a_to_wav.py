import os
from pydub import AudioSegment

# Đường dẫn FFmpeg
os.environ["PATH"] += os.pathsep + r"D:\ffmpeg\bin"
AudioSegment.converter = r"D:\ffmpeg\bin\ffmpeg.exe"
AudioSegment.ffprobe = r"D:\ffmpeg\bin\ffprobe.exe"

def convert_m4a_to_wav(src_file, dst_file):
    """Chuyển file m4a sang wav 16 kHz, mono"""
    try:
        audio = AudioSegment.from_file(src_file, format="m4a")
        audio = audio.set_channels(1)      # mono
        audio = audio.set_frame_rate(16000) # 16 kHz
        audio.export(dst_file, format="wav")
        print(f"✅ {src_file} -> {dst_file}")
        return True
    except Exception as e:
        print(f"❌ Lỗi {src_file}: {e}")
        return False


if __name__ == "__main__":

    # Thư mục chứa file m4a
    src_folder = r"D:\file_test"

    # Thư mục lưu file wav
    dst_folder = r"D:\file_test_wav"

    # Tạo thư mục đích nếu chưa tồn tại
    os.makedirs(dst_folder, exist_ok=True)

    # Duyệt tất cả file trong thư mục
    for file_name in os.listdir(src_folder):
        if file_name.lower().endswith(".m4a"):
            src_path = os.path.join(src_folder, file_name)

            # Đổi đuôi .m4a thành .wav
            wav_name = os.path.splitext(file_name)[0] + ".wav"
            dst_path = os.path.join(dst_folder, wav_name)

            convert_m4a_to_wav(src_path, dst_path)

    print("Hoàn tất chuyển đổi!")