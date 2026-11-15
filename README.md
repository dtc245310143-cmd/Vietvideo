# VietVideo iOS 1.0.2

Ứng dụng iPhone độc lập, giao diện Studio, Khám phá, Dự án và Cài đặt; biểu tượng ứng dụng riêng. Giữ bundle ID của bản thử để cập nhật bằng iLoader.

- Nhập video từ Ảnh/Tệp hoặc link YouTube, Bilibili, Douyin; tìm kiếm có ảnh và thời lượng. Douyin dùng trình duyệt trong app để tìm/mở video rồi lấy danh sách. Đăng nhập/xác minh do người dùng thực hiện khi nguồn yêu cầu.
- Nhận diện nhiều ngôn ngữ và dịch bằng Gemini, sửa/nhập/xuất SRT, nhận diện lại khoảng thiếu; kết quả rỗng tự thử lại tối đa 3 lần. Không thể bảo đảm mọi lời thoại đều được nhận diện đúng.
- Xuất chỉ vietsub hoặc lồng tiếng bằng một trong hai giọng đã duyệt, tạo giọng trực tiếp trên iPhone. Có thể tắt phụ đề khi lồng tiếng. Cache câu đã tạo giúp tiếp tục công việc.
- Tiếng gốc mặc định 25% khi lồng tiếng, chọn 0/15/25/35/50/75/100; giữ mức cố định cả video. Câu dài được căn thời gian bằng cách kéo giãn đoạn hình/tiếng gốc, không bỏ bớt lời.
- Chọn vùng làm mờ/che chữ gốc trên khung xem trước, chỉnh kiểu/cỡ/vị trí phụ đề, thêm logo ở bốn góc.
- Xoá từng dự án ở mục Dự án, có xác nhận; dọn video, phụ đề và cache giọng của dự án. Không xoá các bản đã lưu ra Ảnh/thư mục khác.
- Lưu dự án và chia sẻ MP4/SRT ra Tệp/Ảnh. Dữ liệu ở Tệp → Trên iPhone → VietVideo → VietVideo.

Giữ app mở trong lúc xử lý; iOS có thể dừng công việc khi app về nền. Gemini cần mạng và hạn mức của key; key lưu ở Keychain, không đưa vào dự án/GitHub. Link nguồn có thể bị giới hạn bởi đăng nhập, xác minh, khu vực hoặc thay đổi của nền tảng. Không dùng máy chủ trung gian để tạo giọng hay tải video. Bộ lọc tiếng rè nhẹ không thể khôi phục mọi bản thu hỏng.

## Build và cài

Workflow **VietVideo iOS** dùng Actions secret `VIETVIDEO_CALIBRATION_B64` đã thiết lập. Sau khi build và kiểm tra thành công, tải artifact **VietVideo-iOS-1.0.2**, giải nén IPA và dùng iLoader ký/cài. Thiếu secret chỉ kiểm tra biên dịch, không phát hành IPA thiếu giọng.

Model cố định revision và SHA-256; không đưa `.local`, `Assets/Calibration`, `Assets/Models` lên GitHub. IPA chứa dữ liệu tạo giọng, chỉ phân phối trong phạm vi được phép.

## Kiểm tra

CI kiểm tra parser/Unicode/mốc thời gian, hai giọng ONNX với câu bất kỳ, phát âm/tokenization đối chiếu bản Windows, trộn tiếng gốc cố định, căn câu dài, phụ đề video ngang/dọc, che chữ/logo, hủy tác vụ và giới hạn cookie theo tên miền. CI không có Gemini API key; cần kiểm tra nhận diện thực tế, nguồn cần đăng nhập và hiệu năng video dài trên iPhone.

Mã nền theo GPL-3.0 (`LICENSE`). ONNX Runtime và YouTubeKit theo giấy phép của dự án; sea-g2p Apache-2.0. Xem model cards/giấy phép từ nguồn trong `Assets/model-manifest.json` trước khi phân phối lại model. `THIRD_PARTY-Windows.md` là hồ sơ gốc, không khẳng định mọi thư viện Windows đã chuyển lên iOS.

