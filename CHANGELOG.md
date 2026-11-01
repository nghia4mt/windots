# Changelog

Mọi thay đổi đáng chú ý của repo này được ghi ở đây.
Định dạng theo [Keep a Changelog](https://keepachangelog.com/vi/1.1.0/) và [Semantic Versioning](https://semver.org/lang/vi/).

## [Unreleased]

### Added

- `debloat.cmd`: launcher cho debloat — tự tìm `pwsh`, xin quyền admin, chạy với `-NoExit` để cửa sổ không đóng mất kết quả.
- `debloat-app.ps1`: tham số `-RemoveEdgeProfile` xoá dữ liệu duyệt web Edge của user hiện tại (`%LOCALAPPDATA%\Microsoft\Edge`: bookmark, password, history, cookie) cùng các thư mục Edge cũ; dùng kèm `-RemoveEdge`.

### Changed

- `install.ps1`/`backup.ps1` yêu cầu **PowerShell 7** (`#Requires -Version 7.0`). `debloat-app.ps1` tự kiểm tra phiên bản, bỏ phần tự khởi động lại trong Windows PowerShell 5.1 và nạp trực tiếp module `Appx`/`Dism` trên PowerShell 7.6.9.
- `debloat-app.ps1` khi bị chạy bằng Windows PowerShell 5.1 (ví dụ right-click → "Run with PowerShell") sẽ hiện thông báo rõ ràng và giữ cửa sổ 20 giây thay vì đóng ngay.

### Fixed

- `install.ps1`: tự dọn user PATH và các biến môi trường dev phổ biến (`JAVA_HOME`, `GHIDRA_INSTALL_DIR`, `MAVEN_HOME`, `M2_HOME`, `GRADLE_HOME`, `ANDROID_HOME`, `ANDROID_SDK_ROOT`, `NVM_HOME`, `NVM_SYMLINK`) nếu trỏ tới đường dẫn không còn tồn tại, đồng thời bỏ mục PATH trùng — khắc phục lỗi *"The system cannot find the path specified."*.
- `debloat-app.ps1 -RemoveEdge` hoạt động thực tế trên Windows 11 24H2+ (26300): nếu Microsoft chặn uninstaller command line (exit code 93/532), script tự xoá `Microsoft\Edge` + `Microsoft\EdgeCore`, uninstall/App Paths/StartMenuInternet/EdgeUpdate ClientState và shortcut; giữ nguyên Edge WebView2 + Edge Update, đồng thời thêm `DoNotUpdateToEdgeWithChromium`. Đã test gỡ Edge 156.0.4314.58, WebView2 156.0.4314.58 vẫn chạy.

## [1.1.0] - 2026-10-31

### Added

- Mục "Quy trình Git (git flow)" trong README.
- `debloat-app.ps1`: tham số `-RemoveEdge` gỡ Microsoft Edge (app Appx + bản desktop qua `setup.exe`), xoá shortcut và chặn Edge Update/Windows Update cài lại, trong khi vẫn giữ Edge WebView2 và bật cập nhật WebView2.

### Changed

- `install.ps1`: chuyển OpenCode từ Scoop `opencode-desktop` (V1, 1.19.x) sang OpenCode **V2** desktop chính thức (tải từ `opencode.ai`, cài silent per-user), tự gỡ bản V1 Scoop nếu có và vẫn tạo shim lệnh `opencode` trỏ vào CLI đi kèm.

## [1.0.0] - 2026-10-31

### Added

- `install.ps1`: cài Scoop, bucket `extras`/`nerd-fonts`, app list (Sublime Text 4, Node.js LTS, VS Code, Google Chrome stable, Python, OpenCode + CLI shim), khôi phục cấu hình PowerShell kèm backup `*.bak.<timestamp>`.
- `backup.ps1`: chụp cấu hình PowerShell (`Documents\PowerShell`, `Documents\WindowsPowerShell`) vào `config/`, hỗ trợ `-Mirror` và `-Destination`.
- `debloat-app.ps1`: dọn app rác Windows 11 với `-DryRun`, nhóm tuỳ chọn Xbox / Phone Link / OneDrive, tắt Copilot / Widgets / tìm kiếm Bing, danh sách `$Protected` chống xoá nhầm app hệ thống.
- Hỗ trợ cả PowerShell 7.6.9 và Windows PowerShell 5.1 (`debloat-app.ps1` tự relaunch sang 5.1 vì Appx cmdlets chỉ có ở đó).

### Notes

- `config/` chứa profile PowerShell mẫu của máy phát triển, dùng trực tiếp khi dựng máy mới.
