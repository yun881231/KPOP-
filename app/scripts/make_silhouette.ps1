# =====================================================================
#  KPOP之王巔峰賽 — 第三關「看舞蹈猜歌」自動題目產生器
#
#  預設效果：背景完全保留原樣，只把人物塗成全黑剪影，並抽掉音訊。
#  用 RVM (Robust Video Matting) AI 人物去背模型，逐格穩定不閃爍。
#
#  用法：把原版 MV 放進 第三關_看舞蹈猜歌\原始MV\ ，雙擊 產生第三關剪影.bat
# =====================================================================
[CmdletBinding()]
param(
  [ValidateSet("ai", "threshold")]
  [string]$Mode        = "ai",    # ai = 人物全黑背景保留；threshold = 整個畫面黑白剪影
  [string]$Root,
  [string]$SourceDir,
  [double]$Hardness    = 0.7,     # 剪影邊緣硬度 0~1
  [int]$Dilate         = 3,       # 黑色範圍外擴像素，可蓋掉頭髮邊緣殘影
  [double]$Ratio       = 0,       # 模型內部縮放，0 = 自動
  [int]$Fps            = 30,      # 題目影片影格率上限（越低處理越快）
  [int]$MaxWidth       = 960,     # 題目影片寬度上限
  [int]$Crf            = 23,
  [int]$AnswerMaxWidth = 1280,    # 答案影片寬度上限（0 = 原檔複製）
  [int]$AnswerCrf      = 23,
  [int]$Threshold      = 110,     # 只有 -Mode threshold 用得到
  [double]$Blur        = 2,
  [switch]$Invert,
  [double]$Start       = -1,
  [double]$End         = -1,
  [switch]$Overwrite,
  [switch]$NoRescan
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$ProgressPreference = "SilentlyContinue"
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$appDir = Split-Path -Parent $scriptDir
if (-not $Root) { $Root = Split-Path -Parent $appDir }
$toolsDir = Join-Path $Root "tools"

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Magenta
Write-Host "  第三關 看舞蹈猜歌 — 自動題目產生器" -ForegroundColor Magenta
Write-Host "==========================================================" -ForegroundColor Magenta
if ($Mode -eq "ai") {
  Write-Host "  模式：AI 人物去背（背景保留原樣，人物全黑）" -ForegroundColor Cyan
} else {
  Write-Host "  模式：亮度門檻（整個畫面壓成黑白剪影）" -ForegroundColor Cyan
}
Write-Host ""

# =====================================================================
#  ffmpeg
# =====================================================================
function Find-Ffmpeg {
  $c = @((Join-Path $toolsDir "ffmpeg\bin\ffmpeg.exe"))
  $g = Get-Command ffmpeg -ErrorAction SilentlyContinue
  if ($g) { $c += $g.Source }
  $c += "C:\ffmpeg\bin\ffmpeg.exe"
  $c += "C:\Program Files\ffmpeg\bin\ffmpeg.exe"
  if ($env:LOCALAPPDATA) { $c += (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\ffmpeg.exe") }
  foreach ($p in $c) { if ($p -and (Test-Path -LiteralPath $p)) { return (Resolve-Path -LiteralPath $p).Path } }
  return $null
}

function Install-Ffmpeg {
  $zip = Join-Path $toolsDir "ffmpeg.zip"
  $url = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
  New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null
  Write-Host "  下載 ffmpeg（約 80 MB）…" -ForegroundColor Cyan
  Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
  $tmp = Join-Path $toolsDir "_unzip_ff"
  if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
  Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
  $inner = Get-ChildItem -LiteralPath $tmp -Directory | Select-Object -First 1
  $dest = Join-Path $toolsDir "ffmpeg"
  if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
  Move-Item -LiteralPath $inner.FullName -Destination $dest
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
  $exe = Join-Path $dest "bin\ffmpeg.exe"
  if (-not (Test-Path -LiteralPath $exe)) { throw "解壓後找不到 ffmpeg.exe" }
  Write-Host "  ffmpeg 安裝完成" -ForegroundColor Green
  return $exe
}

# =====================================================================
#  Python（只在 AI 模式需要；用免安裝版，全部關在 D:\kpop\tools\ 裡）
# =====================================================================
function Find-Python {
  $local = Join-Path $toolsDir "python\python.exe"
  if (Test-Path -LiteralPath $local) { return (Resolve-Path -LiteralPath $local).Path }
  foreach ($n in @("py", "python", "python3")) {
    $g = Get-Command $n -ErrorAction SilentlyContinue
    if ($g -and $g.Source -and (Test-Path -LiteralPath $g.Source)) {
      # 排除 Windows 的 Microsoft Store 假捷徑
      if ($g.Source -notlike "*WindowsApps*") { return $g.Source }
    }
  }
  return $null
}

function Install-Python {
  $pyDir = Join-Path $toolsDir "python"
  $zip = Join-Path $toolsDir "python-embed.zip"
  $url = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip"
  New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null

  Write-Host "  下載免安裝版 Python（約 11 MB）…" -ForegroundColor Cyan
  Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
  if (Test-Path -LiteralPath $pyDir) { Remove-Item -LiteralPath $pyDir -Recurse -Force }
  Expand-Archive -LiteralPath $zip -DestinationPath $pyDir -Force
  Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue

  # 免安裝版預設不吃 site-packages，要把 import site 那行打開
  Get-ChildItem -LiteralPath $pyDir -Filter "python*._pth" | ForEach-Object {
    $t = Get-Content -LiteralPath $_.FullName
    $t = $t -replace '^#\s*import site', 'import site'
    if ($t -notcontains 'import site') { $t += 'import site' }
    Set-Content -LiteralPath $_.FullName -Value $t -Encoding ASCII
  }

  $py = Join-Path $pyDir "python.exe"
  Write-Host "  安裝 pip…" -ForegroundColor Cyan
  $getpip = Join-Path $pyDir "get-pip.py"
  Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile $getpip -UseBasicParsing
  & $py $getpip --no-warn-script-location | Out-Null
  Remove-Item -LiteralPath $getpip -Force -ErrorAction SilentlyContinue
  Write-Host "  Python 安裝完成" -ForegroundColor Green
  return $py
}

function Ensure-PyPackages([string]$py) {
  & $py -c "import cv2, numpy, onnxruntime" 2>$null
  if ($LASTEXITCODE -eq 0) { return }
  Write-Host "  安裝 AI 去背需要的套件（onnxruntime / opencv / numpy，約 120 MB，只需一次）…" -ForegroundColor Cyan
  & $py -m pip install --no-warn-script-location --disable-pip-version-check -q `
        onnxruntime opencv-python-headless numpy
  if ($LASTEXITCODE -ne 0) { throw "套件安裝失敗" }
  & $py -c "import cv2, numpy, onnxruntime" 2>$null
  if ($LASTEXITCODE -ne 0) { throw "套件安裝後仍無法載入（可能缺少 Microsoft Visual C++ 執行階段）" }
  Write-Host "  套件安裝完成" -ForegroundColor Green
}

function Ensure-Model {
  $modelDir = Join-Path $appDir "models"
  $model = Join-Path $modelDir "rvm_mobilenetv3_fp32.onnx"
  if (Test-Path -LiteralPath $model) { return $model }
  New-Item -ItemType Directory -Force -Path $modelDir | Out-Null
  Write-Host "  下載人物去背模型（約 15 MB）…" -ForegroundColor Cyan
  Invoke-WebRequest -UseBasicParsing -OutFile $model `
    -Uri "https://github.com/PeterL1n/RobustVideoMatting/releases/download/v1.0.0/rvm_mobilenetv3_fp32.onnx"
  return $model
}

# =====================================================================
#  準備環境
# =====================================================================
$ffmpeg = Find-Ffmpeg
$python = $null

$need = @()
if (-not $ffmpeg) { $need += "ffmpeg（影片轉檔，約 80 MB）" }
if ($Mode -eq "ai") {
  $python = Find-Python
  if (-not $python) { $need += "免安裝版 Python + AI 套件（約 130 MB）" }
}

if ($need.Count -gt 0) {
  Write-Host "第一次執行需要先準備這些工具：" -ForegroundColor Yellow
  foreach ($x in $need) { Write-Host ("   - " + $x) -ForegroundColor Yellow }
  Write-Host "全部只會下載到 $toolsDir，不會安裝到系統、不會改登錄檔。"
  Write-Host "（下載完成後，以後每次執行都是直接開跑。）"
  $ans = Read-Host "要現在自動下載嗎？(Y/N)"
  if ($ans -notmatch '^[Yy]') {
    Write-Host ""
    Write-Host "已取消。你也可以改用不需要 AI 的門檻模式：" -ForegroundColor Yellow
    Write-Host "   產生第三關剪影.bat -Mode threshold" -ForegroundColor Cyan
    Write-Host "或者什麼都不做 —— 只要把原版 MV 放進「答案」資料夾，" -ForegroundColor Yellow
    Write-Host "遊戲會在瀏覽器裡即時把畫面壓黑當題目。" -ForegroundColor Yellow
    return
  }
  if (-not $ffmpeg) { $ffmpeg = Install-Ffmpeg }
  if ($Mode -eq "ai" -and -not $python) { $python = Install-Python }
}

if ($Mode -eq "ai") {
  Ensure-PyPackages $python
  $model = Ensure-Model
  Write-Host ("  Python： " + $python) -ForegroundColor DarkGray
}
Write-Host ("  ffmpeg： " + $ffmpeg) -ForegroundColor DarkGray

# =====================================================================
#  找資料夾與影片
# =====================================================================
$lv3 = Get-ChildItem -LiteralPath $Root -Directory |
       Where-Object { $_.Name -like "第三關*" -or $_.Name -like "level3*" -or $_.Name -like "*舞蹈*" } |
       Select-Object -First 1
if (-not $lv3) { throw "找不到第三關資料夾（$Root 底下應該要有「第三關_看舞蹈猜歌」）" }

if ($SourceDir) { $srcDir = $SourceDir } else { $srcDir = Join-Path $lv3.FullName "原始MV" }
$qDir = Join-Path $lv3.FullName "題目"
$aDir = Join-Path $lv3.FullName "答案"
foreach ($d in @($srcDir, $qDir, $aDir)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }

$VIDEO_EXT = @(".mp4", ".mov", ".mkv", ".webm", ".m4v", ".avi", ".ts", ".wmv", ".flv")
$videos = @(Get-ChildItem -LiteralPath $srcDir -File -ErrorAction SilentlyContinue |
            Where-Object { $VIDEO_EXT -contains $_.Extension.ToLower() } | Sort-Object Name)

Write-Host ""
Write-Host ("來源資料夾： " + $srcDir)
Write-Host ("待處理影片： " + $videos.Count + " 支")
Write-Host ""

if ($videos.Count -eq 0) {
  Write-Host "這個資料夾裡面沒有影片。" -ForegroundColor Yellow
  Write-Host "把原版 MV（檔名請用「團體_歌名.mp4」）放進去，再執行一次就好：" -ForegroundColor Yellow
  Write-Host ("  " + $srcDir) -ForegroundColor Cyan
  return
}

# =====================================================================
#  處理
# =====================================================================
function Invoke-Ffmpeg([string[]]$FfArgs) {
  $out = & $ffmpeg @FfArgs 2>&1
  if ($LASTEXITCODE -ne 0) { throw ("ffmpeg 失敗：`n" + (($out | Select-Object -Last 12) -join "`n")) }
}

function Get-ClipArgs {
  $a = @()
  if ($Start -ge 0) { $a += @("-ss", ("{0}" -f $Start)) }
  if ($Start -ge 0 -and $End -gt $Start) { $a += @("-t", ("{0}" -f ($End - $Start))) }
  return $a
}

$darkVal = 16; $lightVal = 235
if ($Invert) { $darkVal = 235; $lightVal = 16 }
$fp = @(("scale={0}:-2:flags=bicubic" -f $MaxWidth), "format=gray")
if ($Blur -gt 0) { $fp += ("boxblur={0}:1" -f $Blur) }
$fp += ("lutyuv=y='if(lt(val,{0}),{1},{2})'" -f $Threshold, $darkVal, $lightVal)
$fp += "format=yuv420p"
$vfThreshold = $fp -join ","

$done = 0
foreach ($v in $videos) {
  $stem = [System.IO.Path]::GetFileNameWithoutExtension($v.Name)
  $qOut = Join-Path $qDir ($stem + ".mp4")
  $aOut = Join-Path $aDir ($stem + ".mp4")
  Write-Host ("▶ 處理中：" + $stem) -ForegroundColor Cyan

  try {
    $qExists = (Test-Path -LiteralPath $qOut) -and (-not $Overwrite)
    $aExists = (Test-Path -LiteralPath $aOut) -and (-not $Overwrite)

    if ($Mode -eq "ai") {
      if ($qExists) {
        Write-Host "   · 題目影片已存在，略過（要重做請加 -Overwrite）" -ForegroundColor DarkGray
      } else {
        $pyArgs = @((Join-Path $scriptDir "blackout_people.py"),
                    "--input", $v.FullName, "--question", $qOut,
                    "--model", $model, "--ffmpeg", $ffmpeg,
                    "--hardness", "$Hardness", "--dilate", "$Dilate",
                    "--fps", "$Fps", "--maxwidth", "$MaxWidth", "--crf", "$Crf")
        if ($Ratio -gt 0) { $pyArgs += @("--ratio", "$Ratio") }
        if ($Start -ge 0) { $pyArgs += @("--start", "$Start") }
        if ($End -gt 0)   { $pyArgs += @("--end", "$End") }
        & $python @pyArgs
        if ($LASTEXITCODE -ne 0) { throw "AI 去背失敗" }
      }
    } else {
      if ($qExists) {
        Write-Host "   · 題目影片已存在，略過（要重做請加 -Overwrite）" -ForegroundColor DarkGray
      } else {
        $a1 = @("-y", "-hide_banner", "-loglevel", "error") + (Get-ClipArgs)
        $a1 += @("-i", $v.FullName, "-an", "-vf", $vfThreshold,
                 "-c:v", "libx264", "-preset", "veryfast", "-crf", "$Crf",
                 "-pix_fmt", "yuv420p", "-movflags", "+faststart", $qOut)
        Invoke-Ffmpeg $a1
        Write-Host ("   ✔ 題目 → 題目\" + $stem + ".mp4") -ForegroundColor Green
      }
    }

    # --- 答案：原版影片 ---
    if ($aExists) {
      Write-Host "   · 答案影片已存在，略過" -ForegroundColor DarkGray
    } elseif ($AnswerMaxWidth -le 0 -and $v.Extension.ToLower() -eq ".mp4") {
      Copy-Item -LiteralPath $v.FullName -Destination $aOut -Force
      Write-Host ("   ✔ 答案 → 答案\" + $stem + ".mp4（原檔複製）") -ForegroundColor Green
    } else {
      $a2 = @("-y", "-hide_banner", "-loglevel", "error") + (Get-ClipArgs)
      $a2 += @("-i", $v.FullName)
      if ($AnswerMaxWidth -gt 0) { $a2 += @("-vf", ("scale='min({0},iw)':-2" -f $AnswerMaxWidth)) }
      $a2 += @("-c:v", "libx264", "-preset", "veryfast", "-crf", "$AnswerCrf",
               "-c:a", "aac", "-b:a", "160k", "-pix_fmt", "yuv420p",
               "-movflags", "+faststart", $aOut)
      Invoke-Ffmpeg $a2
      Write-Host ("   ✔ 答案 → 答案\" + $stem + ".mp4") -ForegroundColor Green
    }
    $done++
  } catch {
    Write-Host ("   ✖ 失敗：" + $_.Exception.Message) -ForegroundColor Red
  }
  Write-Host ""
}

Write-Host ("完成 {0}/{1} 支。" -f $done, $videos.Count) -ForegroundColor Green

if (-not $NoRescan) {
  $ps1 = Join-Path $scriptDir "scan_assets.ps1"
  if (Test-Path -LiteralPath $ps1) {
    Write-Host ""
    Write-Host "↻ 重新掃描題庫…" -ForegroundColor Cyan
    & $ps1
  }
}
