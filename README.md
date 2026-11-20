# AutoHotkey

Bộ phím tắt AutoHotkey v2 để quản lý tab File Explorer, định dạng SQL và chuyển log SQL thành câu lệnh trong SQL Server Management Studio (SSMS) hoặc DBeaver.

## Cài đặt và chạy

1. Tải `AutoHotkey-update.zip` từ [GitHub Releases](https://github.com/nguyentovan/AutoHotkey/releases/latest) rồi giải nén toàn bộ, hoặc clone repo.
2. Bấm đúp vào [RunMainAhk.cmd](RunMainAhk.cmd). Nếu chưa có `runtime\AutoHotkey64.exe`, launcher sẽ tự tải bản portable Windows x64 v2.0.31 từ release chính thức của AutoHotkey và kiểm tra SHA-256. Cần mạng cho lần tải đầu tiên.
3. Để dùng các phím tắt SQL, cài [.NET 10 Runtime (Windows x64)](https://dotnet.microsoft.com/en-us/download/dotnet/10.0). Cả hai công cụ SQL cần runtime này. Formatter đã có sẵn Python và SQLFluff.

Để dừng, nhấp chuột phải vào biểu tượng AutoHotkey ở khay hệ thống và chọn **Exit**.

Tính năng quản lý tab cần Windows 11 với File Explorer có hỗ trợ tab. Các phím tắt SQL hoạt động trong cửa sổ SSMS hoặc DBeaver đang được chọn.

### Cập nhật AutoHotkey portable

Để cập nhật, thoát AutoHotkey từ khay hệ thống, tải gói `AutoHotkey_<phiên-bản>.zip` trong **Assets** của bản mới rồi chép đè `runtime\AutoHotkey64.exe` bằng tệp cùng tên trong ZIP. Mở lại `RunMainAhk.cmd` để chạy bản mới. Shortcut trỏ tới `RunMainAhk.cmd` vẫn dùng được. [Các bản phát hành AutoHotkey v2](https://github.com/AutoHotkey/AutoHotkey/releases)

### Cập nhật bộ phím tắt qua GitHub Releases

Khi mở `RunMainAhk.cmd`, launcher kiểm tra release chính thức mới nhất trước khi xử lý runtime. Nếu GitHub không truy cập được và runtime đã có sẵn, launcher vẫn mở bộ phím tắt hiện tại.

- Với bản clone Git, launcher so commit của tag release với `HEAD`. Nếu có thể cập nhật fast-forward và các tệp Git theo dõi đang sạch, launcher hỏi trước khi cập nhật. Nhánh đã phân kỳ hoặc có chỉnh sửa cục bộ cần xử lý bằng Git.
- Với bản giải nén, launcher so SHA-256 của các tệp trong gói. Nếu có khác biệt, launcher hỏi trước khi tự tải và giải nén bản mới. Hãy từ chối nếu muốn giữ những chỉnh sửa cục bộ. Tệp `runtime\AutoHotkey64.exe` cập nhật riêng.

Khi phát hành, tạo tag dạng `v1.2.3` tại commit cần phát hành rồi chạy lệnh sau từ thư mục repo. Đính kèm cả `AutoHotkey-update.zip` và `SHA256SUMS` vào GitHub Release của tag đó. Người cài từ ZIP có thể tải gói `AutoHotkey-update.zip` trong **Assets**. Giữ danh sách tệp trong gói tương thích với các launcher đã phát hành.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\NewReleaseAssets.ps1 -Tag v1.2.3 -OutputDirectory "$env:TEMP\AutoHotkey-v1.2.3"
```

## File Explorer

- Nhấn **Win + E** để mở File Explorer. Nếu đã có cửa sổ Explorer, phím tắt đưa cửa sổ đó lên trước và mở tab mới.
- Khi một thư mục mở trong cửa sổ Explorer mới có một tab, script thử gộp thư mục đó vào cửa sổ Explorer đang có. Nếu cửa sổ đích đã có tab cho cùng thư mục, script ưu tiên dùng lại tab đó. Cửa sổ mở để hiện một mục đang được chọn được giữ riêng.

## SQL trong SSMS và DBeaver

Bôi đen câu SQL hoặc một khối log trong trình soạn thảo. Giữ **Ctrl**, nhấn **K**, rồi nhanh tay nhấn **G** hoặc **Y** khi vẫn giữ **Ctrl**. Sau đó thả phím.

| Phím tắt | Văn bản cần chọn | Kết quả |
| --- | --- | --- |
| **Ctrl + K**, **Ctrl + Y** | Đoạn SQL | Thay vùng chọn bằng SQL đã định dạng. |
| **Ctrl + K**, **Ctrl + G** | Một khối log SQL có câu lệnh và thông tin tham số | Chuyển log thành SQL, định dạng kết quả rồi thay vào vùng chọn. |

SSMS dùng T-SQL. Trong DBeaver, cả hai phím tắt chọn dialect dựa trên mục **Type** của tab SQL đang mở. Năm dialect được ưu tiên hỗ trợ là **SQL Server (T-SQL), PostgreSQL, MySQL, SQLite và Oracle**.

Phím tắt DBeaver cũng nhận diện thêm các driver khác. Chạy `Zea.SqlFormat.exe --dialects` để xem danh sách dialect của formatter CLI. Nếu thiếu thông tin kết nối hoặc formatter gặp lỗi, phím tắt báo lỗi và giữ nguyên vùng chọn.

SQL Server và MySQL có thể trả về nhãn cột ngầm định khác sau format, tùy biểu thức.

Cả hai lệnh chỉ thay văn bản trong trình soạn thảo. Bạn có thể dùng **Ctrl + Z** để hoàn tác.

### Ví dụ chuyển log thành SQL

**Trước khi chuyển đổi.** Chọn cả ba dòng log trong tab T-SQL, rồi nhấn **Ctrl + K**, **Ctrl + G**.

```text
DEBUG - PreparedStatement : [select customer_id,customer_name from dbo.Customers where customer_id=@param0 and customer_name=@param1;]
DEBUG - Parameters: [@param0=[ID,42], @param1=[NAME,O'Brien]]
DEBUG - Types: [@param0=[Int32, System.Int32], @param1=[String, System.String]]
```

**Sau khi chuyển đổi.** Converter thay `@param0` và `@param1` bằng giá trị tương ứng. Dấu nháy đơn trong `O'Brien` được nhân đôi trong chuỗi SQL.

```sql
select customer_id,customer_name from dbo.Customers where customer_id=42 and customer_name='O''Brien';
```

**Kết quả hotkey.** Hotkey định dạng câu SQL đã chuyển và chèn kết quả này vào vùng chọn.

```sql
SELECT customer_id
    ,customer_name
FROM dbo.Customers
WHERE customer_id = 42
    AND customer_name = 'O''Brien';
```

### Ví dụ định dạng câu SQL có sẵn

**Trước khi định dạng.** Chọn câu SQL này trong tab T-SQL, rồi nhấn **Ctrl + K**, **Ctrl + Y**.

```sql
select order_id,order_date from dbo.Orders where customer_id=42 order by order_date desc;
```

**Sau khi định dạng.**

```sql
SELECT order_id
    ,order_date
FROM dbo.Orders
WHERE customer_id = 42
ORDER BY order_date DESC;
```

Nếu thấy thông báo thiếu công cụ, kiểm tra xem `Zea.SqlLogConvert.exe` và `Zea.SqlFormat.exe` có nằm cạnh `Main.ahk` không. Ở cấu hình mặc định, lệnh chuyển log dùng cả hai tệp, còn lệnh định dạng dùng `Zea.SqlFormat.exe`.

## Nguồn và giấy phép công cụ SQL

Hai tệp `Zea.SqlFormat.exe` và `Zea.SqlLogConvert.exe` được build từ dự án Zea.SqlTools. Kho mã nguồn có mã của cả hai công cụ và hướng dẫn build bản formatter portable. [Mã nguồn Zea.SqlTools](https://github.com/nguyentovan/Zea.SqlTools) · [Hướng dẫn build formatter](https://github.com/nguyentovan/Zea.SqlTools/tree/master/src/Zea.SqlFormat#publish-a-standalone-windows-x64-exe)

`Zea.SqlFormat.exe` được phân phối theo GNU Affero General Public License v3.0. Formatter sử dụng Right Way SQL Formatter và đóng gói SQLFluff theo giấy phép MIT. [AGPL v3](https://github.com/nguyentovan/Zea.SqlTools/blob/master/LICENSE) · [Right Way và SQLFluff](https://github.com/nguyentovan/Zea.SqlTools/tree/master/src/Zea.SqlFormat#third-party-attribution) · [Giấy phép MIT của SQLFluff](https://github.com/nguyentovan/Zea.SqlTools/blob/master/src/Zea.SqlFormat/licenses/SQLFluff.txt)

## Tự chạy khi đăng nhập

Nhấn **Win + R**, nhập `shell:startup` và nhấn **Enter**. Tạo shortcut trỏ tới `RunMainAhk.cmd` trong thư mục vừa mở. Xóa shortcut đó nếu muốn tắt tự khởi động. [Hướng dẫn của Microsoft](https://support.microsoft.com/en-gb/windows/experience/startup-boot/configure-startup-applications-in-windows)
