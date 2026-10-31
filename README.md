# windots

Bộ script tự động dựng lại môi trường Windows sau khi cài lại máy: cài **Scoop**, cài các app hằng ngày (Sublime Text 4, Node.js, VS Code, Google Chrome, Python, OpenCode...), khôi phục cấu hình PowerShell và dọn app rác của Windows 11.

## Cấu trúc

```
windots/
├─ install.ps1      # chạy trên máy mới: cài Scoop + apps + khôi phục cấu hình
├─ backup.ps1       # chạy trên máy hiện tại: chụp cấu hình PowerShell vào .\config
├─ debloat-app.ps1  # dọn app rác cài sẵn của Windows 11
├─ config/
│  ├─ PowerShell/            # PowerShell 7  -> %USERPROFILE%\Documents\PowerShell
│  │  ├─ Microsoft.PowerShell_profile.ps1
│  │  └─ powershell.config.json
│  └─ WindowsPowerShell/     # Windows PowerShell 5.1 -> %USERPROFILE%\Documents\WindowsPowerShell
│     └─ Microsoft.PowerShell_profile.ps1
└─ README.md
```

## 1. Sao lưu cấu hình hiện tại (máy đang dùng)

```powershell
.\backup.ps1
```

Script copy toàn bộ file trong `Documents\PowerShell` và `Documents\WindowsPowerShell` vào thư mục `config\` của project (bỏ qua file `*.bak*`, `*.log`, `*.tmp`).

- `.\backup.ps1 -Mirror` : xoá luôn file trong `config\` mà trên máy đã không còn, để repo luôn khớp máy.
- `.\backup.ps1 -Destination D:\path` : lưu sang thư mục khác.

Sau đó commit/push thư mục này (hoặc copy sang USB/OneDrive) để dùng cho lần cài lại.

## 2. Dựng máy mới

Mở **PowerShell thường** (không chạy bằng "Run as administrator" — Scoop cài theo user và sẽ từ chối nếu elevated):

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Script làm theo thứ tự, và **chạy lại nhiều lần vẫn an toàn** (idempotent):

1. Cài Scoop (`https://get.scoop.sh`), đặt ExecutionPolicy `RemoteSigned` cho user.
2. Thêm bucket `extras`, `nerd-fonts`.
3. Cài danh sách app trong `$DefaultApps` của `install.ps1`:
   - `sublime-text` (Sublime Text 4)
   - `nodejs-lts` (kèm npm)
   - `vscode` (lệnh `code`)
   - `googlechrome` (Google Chrome stable)
   - `python`
   - `opencode-desktop` + tạo shim lệnh `opencode` trong `~\.local\bin`
   - git, 7zip, aria2, dark, lessmsi, innounp, scoop-search, scoop-completion, JetBrainsMono Nerd Font
4. Khôi phục profile trong `config\` vào `Documents\PowerShell` và `Documents\WindowsPowerShell`. File đang có trên máy sẽ được sao lưu thành `*.bak.<thời-gian>` trước khi ghi đè.

> `config\` hiện đã chứa bản chụp profile của máy này, nên có thể copy nguyên thư mục `windots` sang máy mới là dùng được ngay.

### Tuỳ chọn

| Tham số | Ý nghĩa |
|---|---|
| `-SkipScoop` | Không cài/kiểm tra Scoop |
| `-SkipApps` | Không cài app |
| `-SkipConfig` | Không khôi phục cấu hình PowerShell |
| `-SymlinkConfig` | Link profile tới file trong repo thay vì copy (sửa repo là máy đổi theo; cần Developer Mode hoặc quyền admin, nếu lỗi sẽ tự fallback sang copy) |
| `-Apps main/git,extras/firefox` | Cài danh sách app khác thay cho danh sách mặc định |

Ví dụ chỉ muốn khôi phục cấu hình:

```powershell
.\install.ps1 -SkipScoop -SkipApps
```

Ví dụ chỉ cài thêm vài app lẻ:

```powershell
.\install.ps1 -SkipScoop -SkipConfig -Apps "main/wget,extras/firefox"
```

## 3. Dọn app rác Windows 11 (debloat)

Chạy **bằng PowerShell quyền admin** (để xoá cả bản provisioned, tránh app quay lại khi tạo user mới):

```powershell
# xem trước, không thay đổi gì
.\debloat-app.ps1 -DryRun

# dọn mặc định
.\debloat-app.ps1

# dọn sâu: Xbox, Phone Link, Copilot, Widgets, tìm kiếm Bing
.\debloat-app.ps1 -All

# kèm gỡ OneDrive + tạo restore point trước khi làm
.\debloat-app.ps1 -All -RemoveOneDrive -CreateRestorePoint
```

Mặc định script xoá: Bing News/Weather/Finance/Sports/Travel, Get Help, Tips, Office Hub, Solitaire, 3D Viewer, Mixed Reality, Media Player cũ, Movies & TV, Feedback Hub, Maps, People, Skype, Teams (consumer), Clipchamp, Power Automate, To Do, Copilot, Outlook mới, Mail & Calendar, Cortana, Dev Home, Journal, Print3D, OneConnect, Spotify/Disney/TikTok cài sẵn...

| Tham số | Ý nghĩa |
|---|---|
| `-DryRun` | Chỉ liệt kê, không xoá/không sửa registry |
| `-IncludeXbox` | Xoá nhóm Xbox/Gaming |
| `-IncludePhoneLink` | Xoá Phone Link |
| `-RemoveOneDrive` | Gỡ OneDrive (không xoá dữ liệu trong thư mục OneDrive) |
| `-DisableCopilot` / `-DisableWidgets` / `-DisableBingSearch` | Tắt Copilot / nút Widgets / tìm kiếm web trong Start |
| `-CreateRestorePoint` | Tạo điểm khôi phục trước khi chạy |
| `-All` | Bật Xbox + Phone Link + Copilot + Widgets + Bing (không gồm OneDrive) |

An toàn: các app hệ thống/cần thiết (Store, Terminal, Calculator, Notepad, Paint, Photos, Camera, Snipping Tool, Clock, Sticky Notes, runtime VC++/XAML) nằm trong danh sách `$Protected` nên **không bao giờ bị xoá**, kể cả khi bạn sửa danh sách.

> Gọi bằng `pwsh` (PowerShell 7) vẫn được: script tự phát hiện và khởi động lại trong Windows PowerShell 5.1, vì `Get-AppxPackage`/`Remove-AppxPackage` chỉ hoạt động ở 5.1.

## 4. Thêm / bớt app

Mở `install.ps1`, sửa mảng `$DefaultApps` (định dạng `<bucket>/<app>`), thêm bucket mới vào `$Buckets` nếu cần. Tên app tìm bằng:

```powershell
scoop search <tên-app>
```

## Ghi chú

- Sau khi chạy xong, **mở terminal mới** để nhận PATH mới (`code`, `python`, `node`, `opencode`, `subl`, `chrome`...).
- Máy mới cần Internet; `install.ps1` không cần quyền admin, còn `debloat-app.ps1` nên chạy bằng admin.
- Chạy được trên cả **PowerShell 7.6.9** và **Windows PowerShell 5.1** (đã test): `install.ps1`/`backup.ps1` chạy trực tiếp; `debloat-app.ps1` tự relaunch sang 5.1 khi gọi bằng `pwsh` do giới hạn của Appx cmdlets.
- Cấu hình riêng của VS Code / Sublime / npm chưa nằm trong repo — chỉ cấu hình PowerShell. Muốn mang theo thì thêm đường dẫn vào `backup.ps1` / `install.ps1`.
- Chạy `.\backup.ps1` mỗi khi chỉnh profile để repo luôn là bản mới nhất.
