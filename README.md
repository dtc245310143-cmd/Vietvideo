# VietVideo iOS — voice compatibility gate

**Trạng thái: kiểm tra bộ giọng, CHƯA phải bản iOS đầy đủ của VietVideo 4.4.4.**

Đích: iPhone 14 Plus, iOS 27.0. Build bằng GitHub Actions macOS; tạo IPA chưa ký để iLoader ký/cài. Không cần máy tính làm máy chủ khi chạy.

## Đã có

- Lõi ONNX chạy trực tiếp trên iOS bằng Swift/Accelerate, chuyển từ bộ tạo giọng v3 Turbo của bản 4.4.4.
- Giữ hai speaker anchors và reference codes gốc; giọng thứ hai tiếp tục tắt reference codes như bản Windows.
- Tạo, phát và chia sẻ WAV của một câu mẫu đã chuẩn hóa/tokenize bằng đúng công cụ Windows.
- Nút dừng, kiểm tra tensor, kiểm tra âm thanh hữu hạn/không im lặng, giải phóng bộ nhớ tạm theo khung.
- Workflow build IPA và kiểm tra suy luận của hai giọng trên simulator. IPA vẫn được lưu nếu build thiết bị đạt nhưng kiểm tra simulator thất bại.

## Chưa có / cần đạt trước khi làm bản đầy đủ

- Chưa build trên macOS hoặc thử trên iPhone thật. Không có cam kết tương thích/chất lượng/tốc độ cho tới khi các bước đó đạt.
- Chỉ phát câu mẫu cố định; chưa có chuẩn hóa/phát âm tiếng Việt cho văn bản bất kỳ trên iOS. Không thay bằng giọng hệ thống iOS.
- Chưa chuyển giao diện tìm kiếm/tải YouTube, Bilibili, Douyin; Gemini; sửa SRT; nhận diện lại; trộn tiếng gốc; phụ đề; làm mờ; logo; retiming; xuất/lưu dự án.
- Chưa phải bản thay thế Windows, không phát hành với tên “full 4.4.4”. Bản Windows gốc không bị sửa.

## Build trong kho Vietvideo

1. Đưa các tệp được Git theo dõi lên nhánh `main`. **Không tải thư mục `.local` hoặc `Assets/Calibration` lên kho công khai.**
2. Mở Settings → Secrets and variables → Actions → New repository secret.
3. Tên: `VIETVIDEO_CALIBRATION_B64`. Giá trị là toàn bộ nội dung tệp `.local/calibration-secret.txt` trong bản chuẩn bị trên máy của bạn. Không gửi giá trị này vào chat.
4. Mở Actions → **iOS voice compatibility** → Run workflow. Workflow tải model công khai được cố định phiên bản và kiểm tra SHA-256, ghép dữ liệu giọng riêng trong máy build.
5. Khi build xong, tải artifact **VietVideo-VoiceCheck**, giải nén lấy `VietVideo-VoiceCheck-unsigned.ipa`, rồi nhập vào iLoader để ký/cài.
6. Trên iPhone, tạo lần lượt hai mẫu, nghe và ghi lại thời gian tạo. Nếu ứng dụng bị thoát khi nạp giọng, cần xem giới hạn bộ nhớ trước khi tiếp tục phần video.

Hai giọng chạy offline. Khi chuyển phần Gemini, nhận diện/dịch vẫn cần Internet như bản Windows.

## Dữ liệu và giấy phép

Không có API key hay tài khoản Apple trong kho. Không đưa hai mẫu giọng riêng vào Git; chúng chỉ được ghép lúc build qua Actions secret. IPA chứa dữ liệu cần để tạo hai giọng, vì vậy giữ artifact riêng; GitHub secret không bảo vệ được dữ liệu sau khi đóng vào IPA.

Model tải từ các revision Hugging Face trong `Assets/model-manifest.json`; xem model cards/giấy phép tại nguồn trước khi phân phối lại. Mã chuyển từ bản Windows đi kèm GPL-3.0, xem `LICENSE`. ONNX Runtime dùng MIT. `THIRD_PARTY-Windows.md` là hồ sơ của bản gốc, không có nghĩa các thư viện Windows đã được chuyển hết lên iOS.

## Kiểm tra tại Windows

`python -m unittest discover -s Scripts -p 'test_*.py'` kiểm tra tải model không ghi đè file cũ khi tải hỏng. Các XCTest iOS chỉ chạy được trên macOS/GitHub Actions.
