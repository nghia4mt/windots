# windots

Bộ script tự động dựng lại môi trường Windows sau khi cài lại máy: cài **Scoop**, cài các app hằng ngày (Sublime Text 4, Node.js, VS Code, Google Chrome, Python, OpenCode...), khôi phục cấu hình PowerShell và dọn app rác của Windows 11.

## Cấu trúc

```
windots/
├─ install.ps1      # chạy trên máy mới: cài Scoop + apps + khôi phục cấu hình
├─ backup.ps1       # chạy trên máy hiện tại: chụp cấu hình PowerShell vào .\config
├─ debloat-app.ps1  # dọn app rác cài sẵn của Windows 11
├─ debloat.cmd      # double-click: tự tìm pwsh, xin quyền admin rồi chạy debloat
├─ config/
│  └─ PowerShell/            # PowerShell 7 -> %USERPROFILE%\Documents\PowerShell
│     ├─ Microsoft.PowerShell_profile.ps1
│     └─ powershell.config.json
└─ README.md
```

## 1. Sao lưu cấu hình hiện tại (máy đang dùng)

```powershell
.\backup.ps1
```

Script copy toàn bộ file trong `Documents\PowerShell` (PowerShell 7) vào thư mục `config\` của project (bỏ qua file `*.bak*`, `*.log`, `*.tmp`). Cấu hình Windows PowerShell 5.1 không còn được dùng.

- `.\backup.ps1 -Mirror` : xoá luôn file trong `config\` mà trên máy đã không còn, để repo luôn khớp máy.
- `.\backup.ps1 -Destination D:\path` : lưu sang thư mục khác.

Sau đó commit/push thư mục này (hoặc copy sang USB/OneDrive) để dùng cho lần cài lại.

## 2. Dựng máy mới

Mở **PowerShell 7** (không chạy bằng "Run as administrator" — Scoop cài theo user và sẽ từ chối nếu elevated). Script chỉ hỗ trợ PowerShell 7 (đã test với 7.6.9), không dùng Windows PowerShell 5.1:

```powershell
pwsh -File .\install.ps1
```

Script làm theo thứ tự, và **chạy lại nhiều lần vẫn an toàn** (idempotent):

1. Dọn **user PATH** và các biến môi trường dev còn trỏ tới profile cũ/máy cũ (ví dụ `C:\Users\<user-cu>\scoop\shims`, `JAVA_HOME`, `GHIDRA_INSTALL_DIR`) cùng các mục trùng — đây là nguyên nhân phổ biến của lỗi *"The system cannot find the path specified."*.
2. Cài Scoop (`https://get.scoop.sh`), đặt ExecutionPolicy `RemoteSigned` cho user.
3. Thêm bucket `extras`, `nerd-fonts`.
4. Cài danh sách app trong `$DefaultApps` của `install.ps1`:
   - `sublime-text` (Sublime Text 4)
   - `nodejs-lts` (kèm npm)
   - `vscode` (lệnh `code`)
   - `googlechrome` (Google Chrome stable)
   - `python`
   - OpenCode **V2** (desktop, tải từ opencode.ai) + tạo shim lệnh `opencode` trong `~\.local\bin`
   - git, 7zip, aria2, dark, lessmsi, innounp, scoop-search, scoop-completion, JetBrainsMono Nerd Font
5. Khôi phục profile PowerShell 7 trong `config\` vào `Documents\PowerShell`. File đang có trên máy sẽ được sao lưu thành `*.bak.<thời-gian>` trước khi ghi đè.

> OpenCode V2 **không cài qua Scoop**: manifest `opencode-desktop` của Scoop vẫn là V1 (1.19.x) và V2 không hỗ trợ Windows package manager. Script tải installer chính thức từ `opencode.ai` và cài silent theo user (`/currentuser /S`), sau đó trỏ shim `opencode` vào `opencode-cli.exe` đi kèm. Nếu máy đã có V2 thì bỏ qua; nếu còn bản V1 cài bằng Scoop thì tự gỡ trước khi cài.

> `config\` hiện đã chứa bản chụp profile của máy này, nên có thể copy nguyên thư mục `windots` sang máy mới là dùng được ngay.

### Tuỳ chọn

| Tham số | Ý nghĩa |
|---|---|
| `-SkipScoop` | Không cài/kiểm tra Scoop |
| `-SkipApps` | Không cài app (gồm cả OpenCode V2) |
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

Cách dễ nhất: **double-click `debloat.cmd`** — file này tự tìm PowerShell 7, xin quyền admin (UAC) và giữ cửa sổ mở để xem kết quả/lỗi.

Hoặc mở **PowerShell 7 quyền admin** (`pwsh`, "Run as administrator") rồi chạy (để xoá cả bản provisioned, tránh app quay lại khi tạo user mới):

```powershell
# xem trước, không thay đổi gì
.\debloat-app.ps1 -DryRun

# dọn mặc định
.\debloat-app.ps1

# dọn sâu: Xbox, Phone Link, Copilot, Widgets, tìm kiếm Bing
.\debloat-app.ps1 -All

# kèm gỡ OneDrive + tạo restore point trước khi làm
.\debloat-app.ps1 -All -RemoveOneDrive -CreateRestorePoint

# gỡ Microsoft Edge (giữ WebView2) + chặn Edge tự cài lại
.\debloat-app.ps1 -RemoveEdge

# gỡ Edge + xoá luôn bookmark/password/history
.\debloat-app.ps1 -RemoveEdge -RemoveEdgeProfile
```

Có thể truyền tham số qua `debloat.cmd`:

```powershell
.\debloat.cmd -DryRun
.\debloat.cmd -All -RemoveEdge
```

> **Đừng** right-click `debloat-app.ps1` → "Run with PowerShell": Windows dùng Windows PowerShell 5.1, cửa sổ sẽ mở rồi đóng ngay (trông như "không có gì xảy ra"). Script giờ sẽ hiện cảnh báo và giữ cửa sổ 20 giây, nhưng cách đúng là dùng `debloat.cmd` hoặc `pwsh`.

Mặc định script xoá: Bing News/Weather/Finance/Sports/Travel, Get Help, Tips, Office Hub, Solitaire, 3D Viewer, Mixed Reality, Media Player cũ, Movies & TV, Feedback Hub, Maps, People, Skype, Teams (consumer), Clipchamp, Power Automate, To Do, Copilot, Outlook mới, Mail & Calendar, Cortana, Dev Home, Journal, Print3D, OneConnect, Spotify/Disney/TikTok cài sẵn...

| Tham số | Ý nghĩa |
|---|---|
| `-DryRun` | Chỉ liệt kê, không xoá/không sửa registry |
| `-IncludeXbox` | Xoá nhóm Xbox/Gaming |
| `-IncludePhoneLink` | Xoá Phone Link |
| `-RemoveOneDrive` | Gỡ OneDrive (không xoá dữ liệu trong thư mục OneDrive) |
| `-RemoveEdge` | Gỡ Microsoft Edge, xoá shortcut và chặn Edge Update/Windows Update cài lại. **Giữ nguyên Edge WebView2** (và vẫn bật cập nhật cho WebView2); dữ liệu duyệt web trong `%LOCALAPPDATA%\Microsoft\Edge` được giữ trừ khi dùng thêm `-RemoveEdgeProfile`. Cần admin. Trên Windows 11 24H2+ (Microsoft chặn gỡ Edge bằng command line), script tự chuyển sang xoá file/registry trực tiếp. |
| `-RemoveEdgeProfile` | Xoá luôn dữ liệu duyệt web Edge của user hiện tại (bookmark, password, history, cookie) trong `%LOCALAPPDATA%\Microsoft\Edge` + thư mục Edge cũ. Không thể hoàn tác. |
| `-DisableCopilot` / `-DisableWidgets` / `-DisableBingSearch` | Tắt Copilot / nút Widgets / tìm kiếm web trong Start |
| `-CreateRestorePoint` | Tạo điểm khôi phục trước khi chạy |
| `-All` | Bật Xbox + Phone Link + Copilot + Widgets + Bing (không gồm OneDrive và Edge) |

An toàn: các app hệ thống/cần thiết (Store, Terminal, Calculator, Notepad, Paint, Photos, Camera, Snipping Tool, Clock, Sticky Notes, runtime VC++/XAML) nằm trong danh sách `$Protected` nên **không bao giờ bị xoá**, kể cả khi bạn sửa danh sách.

> `-RemoveEdge` thử uninstaller chính thức trước (`setup.exe --uninstall --system-level`). Trên Windows 11 24H2+ / vùng ngoài EEA, Microsoft chặn lệnh này (exit code 93 hoặc 532), nên script tự xoá `Microsoft\Edge` + `Microsoft\EdgeCore`, registry và shortcut liên quan; **không đụng** `Microsoft\EdgeWebView` hay `Microsoft\EdgeUpdate`, và đặt policy `InstallDefault`/`Install{...}` trong `HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate` để Edge không quay lại. WebView2 (`{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}`) được đặt `Install=1`, `Update=1` nên vẫn còn và vẫn cập nhật bình thường. Muốn cài lại Edge: xoá các giá trị `Install*`/`Update*` trong `HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate` và `HKLM\SOFTWARE\Microsoft\EdgeUpdate` (cùng nhánh `WOW6432Node`), rồi chạy `winget install Microsoft.Edge`.

> Script chỉ chạy bằng **PowerShell 7** (`pwsh`). Từ bản 7.6, PowerShell 7 nạp trực tiếp được module `Appx`/`Dism` nên `debloat-app.ps1` không còn tự khởi động lại trong Windows PowerShell 5.1 như trước.

## 4. Thêm / bớt app

Mở `install.ps1`, sửa mảng `$DefaultApps` (định dạng `<bucket>/<app>`), thêm bucket mới vào `$Buckets` nếu cần. Tên app tìm bằng:

```powershell
scoop search <tên-app>
```

## 5. Quy trình Git (git flow)

- `main` — nhánh phát hành: chỉ nhận merge từ `release/*` / `hotfix/*`, mỗi bản có tag `vX.Y.Z`.
- `develop` — nhánh tích hợp: nhận `feature/*` và merge ngược từ `release/*`.
- `feature/<ten>` — tách từ `develop`, merge lại bằng `--no-ff`.
- `release/<x.y.z>` — tách từ `develop` → merge vào `main` + tag → merge ngược vào `develop` → xoá nhánh.
- `hotfix/<x.y.z>` — tách từ `main` → merge vào `main` + tag → merge vào `develop`.

```bash
git switch develop
git switch -c feature/them-app
# ... code ...
git add -A && git commit -m "feat: them app moi"
git switch develop
git merge --no-ff feature/them-app
git push origin develop
```

Bản phát hành hiện tại: tag [`v1.1.0`](https://github.com/nghia4mt/windots/releases/tag/v1.1.0).

## Ghi chú

- Sau khi chạy xong, **mở terminal mới** để nhận PATH mới (`code`, `python`, `node`, `opencode`, `subl`, `chrome`...).
- Máy mới cần Internet; `install.ps1` không cần quyền admin, còn `debloat-app.ps1` nên chạy bằng admin.
- Yêu cầu **PowerShell 7** (đã test với 7.6.9): `install.ps1`/`backup.ps1` dùng `#Requires -Version 7.0`; `debloat-app.ps1` kiểm tra phiên bản và báo rõ nếu bị chạy bằng Windows PowerShell 5.1. `debloat-app.ps1` nạp trực tiếp module `Appx`/`Dism` của Windows.
- Cấu hình riêng của VS Code / Sublime / npm chưa nằm trong repo — chỉ cấu hình PowerShell. Muốn mang theo thì thêm đường dẫn vào `backup.ps1` / `install.ps1`.
- Chạy `.\backup.ps1` mỗi khi chỉnh profile để repo luôn là bản mới nhất.
