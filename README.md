# VietVideo iOS Beta 0.2

Bản chuyển sang iPhone đang phát triển, **chưa đủ chức năng 4.4.4 Windows**. Bản 0.1 kiểm tra hai giọng đã build và qua kiểm tra suy luận trong simulator; người dùng đã thử trên iPhone 14 Plus/iOS 27.0 và báo có vẻ ổn.

Bản 0.2 thêm chọn video từ Ảnh/Tệp, lưu/mở dự án, nhận diện và dịch bằng Gemini, chọn nhiều ngôn ngữ, lưu key trong Keychain, sửa/nhập/xuất SRT, nhận diện lại khoảng thiếu theo cửa sổ 10 giây, tự thử lại tối đa 3 lần khi kết quả rỗng, xuất MP4 với phụ đề Việt và giữ âm lượng tiếng gốc. Có tùy chọn cỡ chữ/màu/vị trí và chia sẻ kết quả ra Tệp/Ảnh. Bản này chưa gọi Gemini thật trong CI.

Hai giọng hiện vẫn đọc câu mẫu. Chưa chuyển phát âm văn bản bất kỳ, lồng tiếng video, tìm/tải video từ link, làm mờ chữ, logo và retiming. Không dùng giọng iOS thay cho hai giọng đã chọn. Không gọi bản này là full 4.4.4.

Video/dự án ở Tệp → Trên iPhone → VietVideo iOS → VietVideo. Gemini cần Internet, dùng hạn mức và xử lý âm thanh gửi lên Google khi người dùng bấm nhận diện/dịch. Key chỉ nằm ở Keychain, không vào GitHub hay URL yêu cầu. Giữ ứng dụng mở trong lúc xử lý; khi về nền, app yêu cầu dừng và giữ dự án/cache đã hoàn thành.

## Build và cài

Dùng workflow **VietVideo iOS beta**. Giữ Actions secret `VIETVIDEO_CALIBRATION_B64` đã thiết lập trong kho Vietvideo. Tải artifact **VietVideo-iOS-Beta-0.2**, giải nén lấy IPA, nhập iLoader để ký/cài. Bundle identifier giữ nguyên để cập nhật bản thử trước.

Nếu thiếu secret, chỉ kiểm tra biên dịch, không phát hành IPA thiếu bộ giọng. Các model công khai được cố định revision và kiểm tra SHA-256. Không đưa `.local` hoặc `Assets/Calibration` lên GitHub. IPA chứa dữ liệu cần tạo giọng, nên chỉ chia sẻ trong phạm vi được phép.

## Kiểm tra

CI không có Gemini API key. XCTest kiểm tra SRT/Unicode/mốc thời gian, kiểm tra dữ liệu nhận diện, hai giọng ONNX, tách âm thanh, xuất phụ đề lên video ngang/dọc, tiếng gốc và hủy không phá kết quả cũ. Việc nhận diện/dịch thực tế và chất lượng trên iPhone vẫn cần kiểm tra bằng key của người dùng.

Mã nền chuyển từ bản Windows theo GPL-3.0 (`LICENSE`). ONNX Runtime dùng MIT. Xem model cards/giấy phép ở nguồn Hugging Face trong `Assets/model-manifest.json` trước khi phân phối lại model. `THIRD_PARTY-Windows.md` là hồ sơ gốc, không khẳng định mọi thư viện Windows đã chuyển lên iOS.
