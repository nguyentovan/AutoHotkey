# AutoHotkey

Bộ phím tắt AutoHotkey v2 để quản lý tab File Explorer, định dạng SQL và chuyển log SQL thành câu lệnh trong SQL Server Management Studio (SSMS) hoặc DBeaver.

## Cài đặt và chạy

1. Cài [AutoHotkey v2.0 trở lên](https://www.autohotkey.com/).
2. Clone kho này hoặc chọn **Code → Download ZIP** trên GitHub rồi giải nén. Giữ các tệp `.ahk` và hai tệp `.exe` đi kèm trong cùng một thư mục.
3. Bấm đúp vào [`Main.ahk`](Main.ahk). Đây là tệp khởi chạy. Để dừng, nhấp chuột phải vào biểu tượng AutoHotkey ở khay hệ thống và chọn **Exit**.

Tính năng quản lý tab cần Windows 11 với File Explorer có hỗ trợ tab. Các phím tắt SQL hoạt động trong cửa sổ SSMS hoặc DBeaver đang được chọn.

## File Explorer

- Nhấn **Win + E** để mở File Explorer. Nếu đã có cửa sổ Explorer, phím tắt đưa cửa sổ đó lên trước và mở tab mới.
- Khi một thư mục mở trong cửa sổ Explorer mới có một tab, script thử gộp thư mục đó vào cửa sổ Explorer đang có. Nếu cửa sổ đích đã có tab cho cùng thư mục, script ưu tiên dùng lại tab đó. Cửa sổ mở để hiện một mục đang được chọn được giữ riêng.

## SQL trong SSMS và DBeaver

Bôi đen câu SQL hoặc một khối log trong trình soạn thảo. Giữ **Ctrl**, nhấn **K**, rồi nhanh tay nhấn **G** hoặc **Y** khi vẫn giữ **Ctrl**. Sau đó thả phím.

| Phím tắt | Văn bản cần chọn | Kết quả |
| --- | --- | --- |
| **Ctrl + K**, **Ctrl + Y** | Đoạn SQL | Thay vùng chọn bằng SQL đã định dạng. |
| **Ctrl + K**, **Ctrl + G** | Một khối log SQL có câu lệnh và thông tin tham số | Chuyển log thành SQL, định dạng kết quả rồi thay vào vùng chọn. |

SSMS dùng T-SQL. Trong DBeaver, cả hai phím tắt lấy dialect từ mục **Type** của tab SQL đang chọn. Tích hợp DBeaver hiện nhận diện tab SQL Server và PostgreSQL. Nếu thiếu thông tin kết nối hoặc dialect chưa được hỗ trợ, hotkey báo lỗi và giữ nguyên vùng chọn.

Cả hai lệnh chỉ thay văn bản trong trình soạn thảo. Bạn có thể dùng **Ctrl + Z** để hoàn tác.

Nếu thấy thông báo thiếu công cụ, kiểm tra xem `Zea.SqlLogConvert.exe` và `Zea.SqlFormat.exe` có nằm cạnh `Main.ahk` không. Ở cấu hình mặc định, lệnh chuyển log dùng cả hai tệp, còn lệnh định dạng dùng `Zea.SqlFormat.exe`.

## Nguồn và giấy phép công cụ SQL

Hai tệp `Zea.SqlFormat.exe` và `Zea.SqlLogConvert.exe` được build từ dự án Zea.SqlTools. Kho mã nguồn có mã của cả hai công cụ và hướng dẫn build bản formatter portable. [Mã nguồn Zea.SqlTools](https://github.com/nguyentovan/Zea.SqlTools) · [Hướng dẫn build formatter](https://github.com/nguyentovan/Zea.SqlTools/tree/master/src/Zea.SqlFormat#publish-a-standalone-windows-x64-exe)

`Zea.SqlFormat.exe` được phân phối theo GNU Affero General Public License v3.0. Formatter sử dụng Right Way SQL Formatter và đóng gói SQLFluff theo giấy phép MIT. [AGPL v3](https://github.com/nguyentovan/Zea.SqlTools/blob/master/LICENSE) · [Ghi công Right Way và SQLFluff](https://github.com/nguyentovan/Zea.SqlTools/tree/master/src/Zea.SqlFormat#third-party-attribution) · [Giấy phép MIT của SQLFluff](https://github.com/nguyentovan/Zea.SqlTools/blob/master/src/Zea.SqlFormat/licenses/SQLFluff.txt)

## Tự chạy khi đăng nhập

Nhấn **Win + R**, nhập `shell:startup` và nhấn **Enter**. Tạo shortcut trỏ tới `Main.ahk` trong thư mục vừa mở. Xóa shortcut đó nếu muốn tắt tự khởi động. [Hướng dẫn của Microsoft](https://support.microsoft.com/en-gb/windows/experience/startup-boot/configure-startup-applications-in-windows)
