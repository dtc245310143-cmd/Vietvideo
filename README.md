# VietVideo iOS 1.0.7

Ứng dụng iPhone độc lập, giao diện Studio, Khám phá, Dự án và Cài đặt; biểu tượng ứng dụng riêng. Giữ bundle ID của bản thử để cập nhật bằng iLoader.

- Nhập video từ Ảnh/Tệp hoặc link YouTube, Bilibili, Douyin; tìm kiếm có ảnh và thời lượng. Douyin dùng trình duyệt trong app để tìm/mở video rồi lấy danh sách. Đăng nhập/xác minh do người dùng thực hiện khi nguồn yêu cầu.
- Nhận diện nhiều ngôn ngữ và dịch bằng Gemini, sửa/nhập/xuất SRT, nhận diện lại khoảng thiếu; kết quả rỗng tự thử lại tối đa 3 lần. Không thể bảo đảm mọi lời thoại đều được nhận diện đúng.
- Xuất chỉ vietsub hoặc lồng tiếng bằng một trong bốn giọng đã chọn, tạo giọng trực tiếp trên iPhone. Có thể tắt phụ đề khi lồng tiếng. Cache câu đã tạo giúp tiếp tục công việc.
- Xuất nhiều câu: ghép tuần tự từng câu vào một tệp PCM trên đĩa, sau đó xuất video với một luồng giọng. Giải phóng bộ model trước khi xuất hình; tệp ghép tạm được dọn khi xong/hủy.
- Tiếng gốc mặc định 25% khi lồng tiếng, chọn 0/15/25/35/50/75/100; giữ mức cố định cả video. Câu dài được căn thời gian bằng cách kéo giãn đoạn hình/tiếng gốc, không bỏ bớt lời.
- Chọn vùng làm mờ/che chữ gốc trên khung xem trước, chỉnh kiểu/cỡ/vị trí phụ đề, thêm logo ở bốn góc.
- Xoá từng dự án ở mục Dự án, có xác nhận; dọn video, phụ đề và cache giọng của dự án. Không xoá các bản đã lưu ra Ảnh/thư mục khác.
- Lưu dự án và chia sẻ MP4/SRT ra Tệp/Ảnh. Dữ liệu ở Tệp → Trên iPhone → VietVideo → VietVideo.

Giữ app mở trong lúc xử lý; iOS có thể dừng công việc khi app về nền. Gemini cần mạng và hạn mức của key; key lưu ở Keychain, không đưa vào dự án/GitHub. Link nguồn có thể bị giới hạn bởi đăng nhập, xác minh, khu vực hoặc thay đổi của nền tảng. Không dùng máy chủ trung gian để tạo giọng hay tải video. Bộ lọc tiếng rè nhẹ không thể khôi phục mọi bản thu hỏng.

Giọng 3 lấy theo video mẫu 15:43:20; Giọng 4 lấy theo video mẫu 15:42:39. Nghe mẫu tổng hợp tại VoicePreviews/voice-3-revised-1.mp3 và VoicePreviews/voice-4-revised-1.mp3. Hai giọng gốc và cache lồng tiếng cũ được giữ. Các preset bổ sung chứa vector giọng và mã tham chiếu từ đoạn mẫu đã duyệt; MP3 đọc thử là câu tổng hợp mới.

## Build và cài

Workflow **VietVideo iOS** dùng Actions secret `VIETVIDEO_CALIBRATION_B64` đã thiết lập. Sau khi build và kiểm tra thành công, tải artifact **VietVideo-iOS-1.0.5**, giải nén IPA và dùng iLoader ký/cài. Thiếu secret chỉ kiểm tra biên dịch, không phát hành IPA thiếu giọng.

Model cố định revision và SHA-256; không đưa `.local`, `Assets/Calibration`, `Assets/Models` lên GitHub. IPA chứa dữ liệu tạo giọng, chỉ phân phối trong phạm vi được phép.

## Kiểm tra

CI kiểm tra parser/Unicode/mốc thời gian, bốn giọng ONNX với câu bất kỳ, phát âm/tokenization đối chiếu bản Windows, trộn tiếng gốc cố định, căn câu dài, phụ đề video ngang/dọc, che chữ/logo, hủy tác vụ và giới hạn cookie theo tên miền. CI không có Gemini API key; cần kiểm tra nhận diện thực tế, nguồn cần đăng nhập và hiệu năng video dài trên iPhone.

Mã nền theo GPL-3.0 (`LICENSE`). ONNX Runtime và YouTubeKit theo giấy phép của dự án; sea-g2p Apache-2.0. Xem model cards/giấy phép từ nguồn trong `Assets/model-manifest.json` trước khi phân phối lại model. `THIRD_PARTY-Windows.md` là hồ sơ gốc, không khẳng định mọi thư viện Windows đã chuyển lên iOS.


## Nền phụ đề 1.0.5

Trong Studio → Hình ảnh & phụ đề, bật Nền phụ đề rồi chọn Vàng, Đen hoặc Màu khác. Nền bo góc ôm theo câu; chữ tự chuyển đen/trắng để dễ đọc. Có xem trước và lưu màu theo dự án. Tắt Nền phụ đề để dùng kiểu chữ cũ. Giọng 3–4 đã thay bằng hai mẫu MP3 sửa lần 1 được người dùng duyệt. Hồ sơ giữ đoạn giọng tham chiếu và dùng phép chiếu Linear + LayerNorm đầy đủ, khớp bộ tạo bản MP3. Giọng 1–2 và âm thanh đã tạo bằng hai giọng cũ được giữ nguyên.

## Nhịp đọc tự nhiên 1.0.6

Video lồng tiếng giữ tốc độ đọc gốc của cả bốn giọng, không ép nhanh 15% khi thiếu thời gian. Câu dài tự giãn đoạn hình và tiếng gốc như cơ chế hiện có để giữ đủ lời; video có thể dài hơn. Khâu ghép giọng WAV 48 kHz chạy thẳng ở tốc độ tự nhiên, không qua bộ đổi tốc độ. Giữ 80 ms đầu và 240 ms sau vùng thoại rõ để tránh mất phụ âm nhỏ ở cuối câu. Những câu đã tạo trước đây được tạo lại một lần khi xuất để áp dụng cách xử lý mới; bản video xuất cũ và các dự án vẫn giữ nguyên.

## Tua video trong vùng che phụ đề 1.0.7

Mở Hình ảnh & phụ đề → Chọn vùng chữ gốc / xem trước. Kéo thanh thời gian để chọn đoạn video hoặc dùng nút lùi/tiến 5 giây, sau đó kéo trên ảnh để khoanh vùng che. Vùng che giữ nguyên khi tua và áp dụng cho toàn bộ video. Nhấn Dùng vùng này để lưu. Các yêu cầu khung hình cũ được hủy khi đổi mốc hoặc đóng màn hình; chỉ khung hình mới nhất được hiển thị. Mốc cuối video được đưa về khung hình hợp lệ trước điểm kết thúc.
