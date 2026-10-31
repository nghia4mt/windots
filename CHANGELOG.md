# Changelog

Mọi thay đổi đáng chú ý của repo này được ghi ở đây.
Định dạng theo [Keep a Changelog](https://keepachangelog.com/vi/1.1.0/) và [Semantic Versioning](https://semver.org/lang/vi/).

## [Unreleased]

### Added

- Mục "Quy trình Git (git flow)" trong README.
- `debloat-app.ps1`: tham số `-RemoveEdge` gỡ Microsoft Edge (app Appx + bản desktop qua `setup.exe`), xoá shortcut và chặn Edge Update/Windows Update cài lại, trong khi vẫn giữ Edge WebView2 và bật cập nhật WebView2.

## [1.0.0] - 2026-10-31

### Added

- `install.ps1`: cài Scoop, bucket `extras`/`nerd-fonts`, app list (Sublime Text 4, Node.js LTS, VS Code, Google Chrome stable, Python, OpenCode + CLI shim), khôi phục cấu hình PowerShell kèm backup `*.bak.<timestamp>`.
- `backup.ps1`: chụp cấu hình PowerShell (`Documents\PowerShell`, `Documents\WindowsPowerShell`) vào `config/`, hỗ trợ `-Mirror` và `-Destination`.
- `debloat-app.ps1`: dọn app rác Windows 11 với `-DryRun`, nhóm tuỳ chọn Xbox / Phone Link / OneDrive, tắt Copilot / Widgets / tìm kiếm Bing, danh sách `$Protected` chống xoá nhầm app hệ thống.
- Hỗ trợ cả PowerShell 7.6.9 và Windows PowerShell 5.1 (`debloat-app.ps1` tự relaunch sang 5.1 vì Appx cmdlets chỉ có ở đó).

### Notes

- `config/` chứa profile PowerShell mẫu của máy phát triển, dùng trực tiếp khi dựng máy mới.
