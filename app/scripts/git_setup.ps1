# =====================================================================
#  KPOP之王巔峰賽 — GitHub 版本控制  一次性設定
#
#  做的事：
#    1. 找不到 Git 就自動下載免安裝版到 D:\kpop\tools\git\
#    2. 建立 .gitignore / .gitattributes / README.md
#    3. git init + 第一次 commit
#    4. 連到你的 GitHub repo 並推上去
#
#  用法：雙擊 D:\kpop\Git設定.bat
# =====================================================================
[CmdletBinding()]
param(
  [string]$Root,
  [string]$RemoteUrl,
  [string]$UserName,
  [string]$UserEmail
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$ProgressPreference = "SilentlyContinue"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
  $PSNativeCommandUseErrorActionPreference = $false
}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$appDir = Split-Path -Parent $scriptDir
if (-not $Root) { $Root = Split-Path -Parent $appDir }
$toolsDir = Join-Path $Root "tools"

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Magenta
Write-Host "  KPOP之王巔峰賽 — GitHub 版本控制設定" -ForegroundColor Magenta
Write-Host "==========================================================" -ForegroundColor Magenta
Write-Host ""

# ---------------------------------------------------------------------
# 1. Git
# ---------------------------------------------------------------------
function Find-Git {
  $c = @((Join-Path $toolsDir "git\cmd\git.exe"))
  $g = Get-Command git -ErrorAction SilentlyContinue
  if ($g -and $g.Source) { $c += $g.Source }
  $c += "C:\Program Files\Git\cmd\git.exe"
  $c += "C:\Program Files (x86)\Git\cmd\git.exe"
  if ($env:LOCALAPPDATA) { $c += (Join-Path $env:LOCALAPPDATA "Programs\Git\cmd\git.exe") }
  foreach ($p in $c) { if ($p -and (Test-Path -LiteralPath $p)) { return (Resolve-Path -LiteralPath $p).Path } }
  return $null
}

function Install-Git {
  New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null
  $url = $null
  try {
    $rel = Invoke-RestMethod -UseBasicParsing -Headers @{ "User-Agent" = "kpop-quiz" } `
             -Uri "https://api.github.com/repos/git-for-windows/git/releases/latest"
    $asset = $rel.assets | Where-Object { $_.name -like "PortableGit-*-64-bit.7z.exe" } | Select-Object -First 1
    if ($asset) { $url = $asset.browser_download_url }
  } catch { }
  if (-not $url) {
    $url = "https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/PortableGit-2.47.1-64-bit.7z.exe"
  }

  $exe = Join-Path $toolsDir "PortableGit.exe"
  Write-Host "  下載免安裝版 Git（約 45 MB）…" -ForegroundColor Cyan
  Write-Host ("  " + $url) -ForegroundColor DarkGray
  Invoke-WebRequest -Uri $url -OutFile $exe -UseBasicParsing

  $dest = Join-Path $toolsDir "git"
  if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
  Write-Host "  解壓縮中（約 1~2 分鐘）…" -ForegroundColor Cyan
  Start-Process -FilePath $exe -ArgumentList @("-o`"$dest`"", "-y") -Wait -NoNewWindow
  Remove-Item -LiteralPath $exe -Force -ErrorAction SilentlyContinue

  $git = Join-Path $dest "cmd\git.exe"
  if (-not (Test-Path -LiteralPath $git)) { throw "解壓後找不到 git.exe" }
  Write-Host "  Git 安裝完成" -ForegroundColor Green
  return $git
}

$git = Find-Git
if (-not $git) {
  Write-Host "找不到 Git。" -ForegroundColor Yellow
  Write-Host "可以自動下載免安裝版到 $toolsDir\git\（不會安裝到系統、不會改登錄檔）。"
  $ans = Read-Host "要現在自動下載嗎？(Y/N)"
  if ($ans -notmatch '^[Yy]') { Write-Host "已取消。" -ForegroundColor Yellow; return }
  $git = Install-Git
}
Write-Host ("  Git： " + $git) -ForegroundColor DarkGray
Write-Host ("  " + (& $git --version)) -ForegroundColor DarkGray
Write-Host ""

# 用 $args 收全部參數，才不會把 -A / -m 這種旗標當成 PowerShell 參數
function Git { & $git -C $Root @args }
function GitQuiet { try { return (& $git -C $Root @args 2>$null) } catch { return $null } }

# ---------------------------------------------------------------------
# 2. .gitignore / .gitattributes / README.md
# ---------------------------------------------------------------------
$gitignore = @'
# ============================================================
#  KPOP之王巔峰賽 — 版控範圍設定
#  只版控「程式」，影音素材檔案太大不進 Git（GitHub 單檔上限 100MB）
#  素材請另外備份（外接硬碟 / 雲端硬碟）
# ============================================================

# --- 素材資料夾（全部排除）---
第一關_偶像快看快答/
第二關_聽前奏猜歌/
第三關_看舞蹈猜歌/
第四關_看五官猜偶像/
介面音樂/
封面/
level1_*/
level2_*/
level3_*/
level4_*/
cover/

# --- 自動下載的工具（ffmpeg / python / git）---
tools/

# --- 大型簡報與 Office 暫存檔 ---
*.pptx
*.ppt
~$*

# --- 系統與編輯器雜物 ---
Thumbs.db
desktop.ini
.DS_Store
node_modules/
*.log
'@

$gitattributes = @'
# 全部檔案都不做換行轉換，確保 .bat / .ps1 原樣往返
* -text
*.onnx binary
*.mp4 binary
*.png binary
*.jpg binary
*.mp3 binary
'@

$readme = @'
# 🎤 KPOP之王巔峰賽

離線可跑的 K-POP 四關互動測驗 Web App。React 18 + Tailwind CSS，
免安裝、免建置、免伺服器 —— 雙擊 `啟動遊戲.bat` 就能玩。

## 四大關卡

| 關卡 | 玩法 |
|---|---|
| 第一關 偶像快看快答 | 照片只閃 1 秒後自動隱藏，公布答案顯示原圖與姓名 |
| 第二關 聽前奏猜歌 | 播放前奏、可重複聆聽，公布答案播完整 MV |
| 第三關 看舞蹈猜歌 | 靜音＋人物全黑剪影的舞蹈影片，公布答案播原版 MV |
| 第四關 看五官猜偶像 | 眼睛＋嘴巴＋手燈三格提示，公布答案揭曉兩位偶像 |

還有多隊計分板、每題倒數計時、答對答錯音效、背景音樂自動 ducking。

## 快速開始

| 我想做什麼 | 雙擊 |
|---|---|
| 開始玩 | `啟動遊戲.bat` |
| 新增素材後重建題庫 | `更新題庫.bat` |
| 把原版 MV 自動做成第三關黑影題目 | `產生第三關剪影.bat` |
| 存一版到 GitHub | `Git存檔.bat` |

詳細說明請看 [使用說明.md](使用說明.md)。

## 注意：素材不在這個 repo 裡

影音素材（偶像照片、MV、前奏音檔、背景音樂）因為檔案太大沒有納入版控。
clone 下來之後，請依照 `使用說明.md` 的目錄規範把素材放回這些資料夾，
再執行 `更新題庫.bat` 重建題庫即可。
'@

$paths = @{
  ".gitignore"     = $gitignore
  ".gitattributes" = $gitattributes
  "README.md"      = $readme
}
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
foreach ($k in $paths.Keys) {
  $f = Join-Path $Root $k
  if (Test-Path -LiteralPath $f) {
    Write-Host ("  · " + $k + " 已存在，保留原檔") -ForegroundColor DarkGray
  } else {
    [System.IO.File]::WriteAllText($f, ($paths[$k] -replace "`r?`n", "`r`n"), $utf8NoBom)
    Write-Host ("  ✔ 建立 " + $k) -ForegroundColor Green
  }
}
Write-Host ""

# ---------------------------------------------------------------------
# 3. git init + 身分設定
# ---------------------------------------------------------------------
if (-not (Test-Path -LiteralPath (Join-Path $Root ".git"))) {
  Git init | Out-Null
  Git symbolic-ref HEAD refs/heads/main | Out-Null
  Write-Host "  ✔ 已建立 Git 倉庫" -ForegroundColor Green
} else {
  Write-Host "  · Git 倉庫已存在" -ForegroundColor DarkGray
}

Git config core.quotepath false | Out-Null   # 讓中文檔名正常顯示
Git config core.autocrlf false | Out-Null

$curName = GitQuiet config user.name
if (-not $curName) {
  if (-not $UserName) { $UserName = Read-Host "你的名字（會顯示在 commit 紀錄上，例如 YUN）" }
  if ($UserName) { Git config user.name $UserName | Out-Null }
}
$curMail = GitQuiet config user.email
if (-not $curMail) {
  if (-not $UserEmail) { $UserEmail = Read-Host "你的 GitHub Email" }
  if ($UserEmail) { Git config user.email $UserEmail | Out-Null }
}

# ---------------------------------------------------------------------
# 4. 第一次 commit
# ---------------------------------------------------------------------
Write-Host ""
Write-Host "正在把程式加入版控…" -ForegroundColor Cyan
Git add -A | Out-Null
$staged = @(Git diff --cached --name-only)
if ($staged.Count -eq 0) {
  Write-Host "  · 沒有新的變更需要 commit" -ForegroundColor DarkGray
} else {
  Write-Host ("  納入版控的檔案共 " + $staged.Count + " 個：") -ForegroundColor DarkGray
  $staged | Select-Object -First 30 | ForEach-Object { Write-Host ("    " + $_) -ForegroundColor DarkGray }
  if ($staged.Count -gt 30) { Write-Host ("    …其餘 " + ($staged.Count - 30) + " 個") -ForegroundColor DarkGray }
  Git commit -m "初版：KPOP之王巔峰賽 四關測驗 App" | Out-Null
  Write-Host "  ✔ 已建立第一個版本" -ForegroundColor Green
}

# ---------------------------------------------------------------------
# 5. 連到 GitHub
# ---------------------------------------------------------------------
$existing = GitQuiet remote get-url origin
if ($existing) {
  Write-Host ""
  Write-Host ("  · 已設定的 GitHub 位置： " + $existing) -ForegroundColor DarkGray
  $RemoteUrl = $existing
} else {
  if (-not $RemoteUrl) {
    Write-Host ""
    Write-Host "----------------------------------------------------------" -ForegroundColor Yellow
    Write-Host " 接下來要在 GitHub 上開一個空的 repo" -ForegroundColor Yellow
    Write-Host "----------------------------------------------------------" -ForegroundColor Yellow
    Write-Host " 1. 我幫你開瀏覽器到 https://github.com/new"
    Write-Host " 2. Repository name 填：kpop-quiz-king（或你喜歡的名字）"
    Write-Host " 3. 選 Private"
    Write-Host " 4. 下面三個勾勾（README / .gitignore / license）"
    Write-Host "    全部不要勾，保持空的 repo"
    Write-Host " 5. 按 Create repository"
    Write-Host " 6. 複製上方那串網址，貼回這個視窗"
    Write-Host ""
    try { Start-Process "https://github.com/new" } catch { }
    $RemoteUrl = Read-Host "請貼上 repo 網址（例如 https://github.com/你的帳號/kpop-quiz-king.git）"
  }
  if (-not $RemoteUrl) {
    Write-Host ""
    Write-Host "沒有輸入網址，先跳過推送。" -ForegroundColor Yellow
    Write-Host "本機版控已經建立好了，之後隨時再執行一次這支就能連 GitHub。" -ForegroundColor Yellow
    return
  }
  $RemoteUrl = $RemoteUrl.Trim()
  if ($RemoteUrl -notmatch '\.git$' -and $RemoteUrl -match '^https://github\.com/') { $RemoteUrl += ".git" }
  Git remote add origin $RemoteUrl | Out-Null
  Write-Host ("  ✔ 已設定 GitHub 位置： " + $RemoteUrl) -ForegroundColor Green
}

. (Join-Path $scriptDir "git_common.ps1")

Write-Host "（第一次推送會跳出瀏覽器要你登入 GitHub 授權，登入完就會自動繼續）" -ForegroundColor DarkGray
Git branch -M main | Out-Null
$ok = Invoke-SmartPush -GitExe $git -RepoRoot $Root -Branch "main"

if ($ok) {
  Write-Host ""
  Write-Host "==========================================================" -ForegroundColor Green
  Write-Host "  完成！程式已經備份到 GitHub" -ForegroundColor Green
  Write-Host "==========================================================" -ForegroundColor Green
  Write-Host ("  " + ($RemoteUrl -replace '\.git$', '')) -ForegroundColor Cyan
  Write-Host ""
  Write-Host "  以後每次改完東西，雙擊「Git存檔.bat」就會存一版並推上去。"
  Write-Host "  想回到舊版本：到 GitHub 網頁點 Commits，任何一版都能看與下載。"
} else {
  Write-Host ""
  Write-Host "本機版控已經建立好了，內容不會不見。" -ForegroundColor Yellow
  Write-Host "照上面的提示處理完，再跑一次「Git存檔.bat」即可。" -ForegroundColor Yellow
}
Write-Host ""
