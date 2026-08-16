# =====================================================================
#  KPOP之王巔峰賽 — 打包網頁版（可上傳到 Netlify / GitHub Pages / Vercel）
#
#  產出：D:\kpop\docs\   ← 這整個資料夾就是「網頁版」，可直接部署
#        docs\index.html      主程式
#        docs\assets\...      壓縮過、檔名全英數的素材
#        docs\部署說明.txt     三種免費部署方式的步驟
#
#  叫 docs 是因為 GitHub Pages 只認 docs 這個資料夾名稱，
#  拖去 Netlify 的話資料夾叫什麼都可以。
#
#  用法：雙擊 D:\kpop\建立網頁版.bat
# =====================================================================
[CmdletBinding()]
param(
  [string]$Root,
  [string]$Out           = "docs",
  [int]$VideoMaxWidth    = 854,    # 網頁版影片寬度上限
  [int]$VideoCrf         = 30,     # 影片壓縮率，越大檔案越小畫質越差
  [string]$AudioBitrate  = "128k",
  [int]$ImageMaxWidth    = 1400,
  [switch]$NoCompress,             # 不壓縮，直接複製原檔（檔案會很大）
  [switch]$Clean                   # 先清空輸出資料夾
)

# ── Windows PowerShell 5.1 的地雷 ──────────────────────────────────
# $ErrorActionPreference = "Stop" 之下，原生程式（git / ffmpeg / python）
# 只要往 stderr 寫東西就會被當成終止錯誤，整支腳本直接掛掉（NativeCommandError）。
# git 連「Rebasing (1/1)」這種進度訊息都是走 stderr，所以這裡一律用 Continue，
# 改成每一步自己檢查 $LASTEXITCODE；真正需要中斷的 cmdlet 才單獨加 -ErrorAction Stop。
$ErrorActionPreference = "Continue"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$ProgressPreference = "SilentlyContinue"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
  $PSNativeCommandUseErrorActionPreference = $false
}

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$appDir = Split-Path -Parent $scriptDir
if (-not $Root) { $Root = Split-Path -Parent $appDir }
$outDir = Join-Path $Root $Out
$assetsDir = Join-Path $outDir "assets"

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Magenta
Write-Host "  KPOP之王巔峰賽 — 打包網頁版" -ForegroundColor Magenta
Write-Host "==========================================================" -ForegroundColor Magenta
Write-Host ""

# ---------------------------------------------------------------------
# ffmpeg（用來壓縮影片；沒有的話就直接複製原檔）
# ---------------------------------------------------------------------
function Find-Ffmpeg {
  $c = @((Join-Path $Root "tools\ffmpeg\bin\ffmpeg.exe"))
  $g = Get-Command ffmpeg -ErrorAction SilentlyContinue
  if ($g -and $g.Source) { $c += $g.Source }
  $c += "C:\ffmpeg\bin\ffmpeg.exe"
  $c += "C:\Program Files\ffmpeg\bin\ffmpeg.exe"
  if ($env:LOCALAPPDATA) { $c += (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\ffmpeg.exe") }
  foreach ($p in $c) { if ($p -and (Test-Path -LiteralPath $p)) { return (Resolve-Path -LiteralPath $p).Path } }
  return $null
}
$ffmpeg = Find-Ffmpeg
$compress = (-not $NoCompress) -and $ffmpeg
if (-not $ffmpeg) {
  Write-Host "找不到 ffmpeg，影片將原檔複製（檔案會很大，部署可能超過額度）。" -ForegroundColor Yellow
  Write-Host "想壓縮的話請先執行一次「產生第三關剪影.bat」讓它自動安裝 ffmpeg。" -ForegroundColor Yellow
  Write-Host ""
}

# ---------------------------------------------------------------------
# 先重新掃描題庫
# ---------------------------------------------------------------------
$scan = Join-Path $scriptDir "scan_assets.ps1"
if (Test-Path -LiteralPath $scan) { & $scan | Out-Null }

$jsonPath = Join-Path $appDir "quiz-data.json"
if (-not (Test-Path -LiteralPath $jsonPath)) { throw "找不到 $jsonPath，請先執行「更新題庫.bat」。" }
$data = Get-Content -LiteralPath $jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json

if ($Clean -and (Test-Path -LiteralPath $outDir)) { Remove-Item -LiteralPath $outDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $assetsDir | Out-Null

# ---------------------------------------------------------------------
# 路徑轉英數（部署到網路上時中文路徑最容易出包）
# ---------------------------------------------------------------------
$SEGMAP = @{
  "題目" = "q"; "题目" = "q"; "答案" = "a"
  "眼睛" = "eye"; "嘴巴" = "mouth"; "手燈" = "light"; "手灯" = "light"
  "介面音樂" = "bgm"; "封面" = "cover"; "原始MV" = "raw"
}
function Convert-Seg([string]$seg, [bool]$isFile) {
  if ($SEGMAP.ContainsKey($seg)) { return $SEGMAP[$seg] }
  if ($seg -like "第一關*" -or $seg -like "level1*") { return "level1" }
  if ($seg -like "第二關*" -or $seg -like "level2*") { return "level2" }
  if ($seg -like "第三關*" -or $seg -like "level3*") { return "level3" }
  if ($seg -like "第四關*" -or $seg -like "level4*") { return "level4" }
  if ($isFile) {
    $ext  = [System.IO.Path]::GetExtension($seg).ToLower()
    $base = [System.IO.Path]::GetFileNameWithoutExtension($seg)
    $safe = ($base -replace '[^A-Za-z0-9._\-]', '_') -replace '_+', '_'
    $safe = $safe.Trim('_')
    if (-not $safe) { $safe = "file" }
    return $safe + $ext
  }
  $safe = ($seg -replace '[^A-Za-z0-9._\-]', '_') -replace '_+', '_'
  $safe = $safe.Trim('_')
  if (-not $safe) { $safe = "d" }
  return $safe
}

$map  = @{}   # 來源相對路徑 → 網頁版相對路徑
$used = @{}
$stats = [ordered]@{ video = 0; audio = 0; image = 0; converted = 0; external = 0; skipped = 0; srcBytes = 0; outBytes = 0 }
$ffprobe = $null
if ($ffmpeg) {
  $cand = Join-Path (Split-Path -Parent $ffmpeg) "ffprobe.exe"
  if (Test-Path -LiteralPath $cand) { $ffprobe = $cand }
  else { $g = Get-Command ffprobe -ErrorAction SilentlyContinue; if ($g) { $ffprobe = $g.Source } }
}

# .avif / .webp 在舊一點的手機瀏覽器（iOS 15 以前）開不了，統一轉成 jpg/png
$LEGACY_IMG = @(".avif", ".webp")

function Test-HasAlpha([string]$file) {
  if (-not $ffprobe) { return $true }   # 問不到就當作有透明，轉 png 比較安全
  try {
    $fmt = & $ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt -of csv=p=0 $file 2>$null
    return ("$fmt" -match "a|rgba|argb|ya|pal8")
  } catch { return $true }
}

function Add-Asset([string]$rel, [switch]$Silent) {
  if (-not $rel) { return $null }

  # 外連圖床（http/https///）→ 原樣保留，不需要打包
  if ($rel -match '^(https?:)?//' -or $rel -match '^data:') {
    $stats.external++
    return $rel
  }
  if ($map.ContainsKey($rel)) { return $map[$rel] }

  $src = Join-Path $Root ($rel -replace '/', '\')
  if (-not (Test-Path -LiteralPath $src)) {
    Write-Host ("   ! 找不到素材，已略過： " + $rel) -ForegroundColor Yellow
    $stats.skipped++
    return $null
  }

  $segs = $rel.Split('/')
  $parts = @()
  for ($i = 0; $i -lt $segs.Length; $i++) {
    $parts += (Convert-Seg $segs[$i] ($i -eq $segs.Length - 1))
  }
  $ext   = [System.IO.Path]::GetExtension($parts[-1]).ToLower()
  $baseN = [System.IO.Path]::GetFileNameWithoutExtension($parts[-1])
  $isVid = @(".mp4",".webm",".mov",".mkv",".m4v",".ogv") -contains $ext
  $isAud = @(".mp3",".m4a",".wav",".ogg",".oga",".aac",".flac",".opus") -contains $ext
  $isImg = @(".png",".jpg",".jpeg",".webp",".gif",".bmp",".avif") -contains $ext
  $srcLen = (Get-Item -LiteralPath $src).Length

  # ---- 先決定最終副檔名（可能會轉檔）----
  $tmpOut = $null
  $finalExt = $ext
  if ($isVid -and $compress) {
    $finalExt = ".mp4"
  }
  elseif ($isImg -and $ffmpeg) {
    $needConv = ($LEGACY_IMG -contains $ext)
    $needResize = ($srcLen -gt 300KB)
    if ($needConv -or $needResize) {
      $targetExt = $ext
      if ($needConv) { if (Test-HasAlpha $src) { $targetExt = ".png" } else { $targetExt = ".jpg" } }
      if ($targetExt -eq ".gif") { $targetExt = ".gif" }
      $tmpOut = Join-Path ([System.IO.Path]::GetTempPath()) ("kpopimg_" + [System.Guid]::NewGuid().ToString("N") + $targetExt)
      $ia = @("-y","-hide_banner","-loglevel","error","-i",$src,
              "-vf",("scale='min({0},iw)':-2:flags=lanczos" -f $ImageMaxWidth))
      if ($targetExt -eq ".jpg") { $ia += @("-q:v","3") }
      $ia += $tmpOut
      & $ffmpeg @ia 2>&1 | Out-Null
      if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $tmpOut)) {
        $finalExt = $targetExt
        if ($needConv) {
          $stats.converted++
          if (-not $Silent) { Write-Host ("   ◆ 轉檔相容格式 " + $segs[-1] + " → " + $baseN + $targetExt) -ForegroundColor DarkCyan }
        }
      } else {
        Remove-Item -LiteralPath $tmpOut -Force -ErrorAction SilentlyContinue
        $tmpOut = $null
        if ($needConv -and -not $Silent) {
          Write-Host ("   ! 轉檔失敗，沿用原格式（舊手機可能看不到）： " + $segs[-1]) -ForegroundColor Yellow
        }
      }
    }
  }
  $parts[-1] = $baseN + $finalExt

  # ---- 產生不重複的輸出路徑 ----
  $web = ($parts -join '/')
  $n = 1
  while ($used.ContainsKey($web)) {
    $n++
    $tmp = $parts.Clone(); $tmp[-1] = "$baseN-$n$finalExt"
    $web = ($tmp -join '/')
  }
  $used[$web] = $true

  $dst = Join-Path $assetsDir ($web -replace '/', '\')
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
  $stats.srcBytes += $srcLen

  if ($tmpOut) {
    Move-Item -LiteralPath $tmpOut -Destination $dst -Force
    $stats.image++
  }
  elseif ($isVid -and $compress) {
    if (-not $Silent) { Write-Host ("   ▶ 壓縮影片 " + $segs[-1] + "  (" + [math]::Round($srcLen/1MB,1) + " MB)") -ForegroundColor Cyan }
    $a = @("-y","-hide_banner","-loglevel","error","-i",$src,
           "-vf",("scale='min({0},iw)':-2" -f $VideoMaxWidth),
           "-c:v","libx264","-preset","veryfast","-crf","$VideoCrf",
           "-pix_fmt","yuv420p","-movflags","+faststart")
    if ($Silent) { $a += "-an" } else { $a += @("-c:a","aac","-b:a",$AudioBitrate) }
    $a += $dst
    & $ffmpeg @a 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
      Write-Host ("   ! 壓縮失敗改用原檔： " + $segs[-1]) -ForegroundColor Yellow
      Copy-Item -LiteralPath $src -Destination $dst -Force
    }
    $stats.video++
  }
  else {
    Copy-Item -LiteralPath $src -Destination $dst -Force
    if ($isVid) { $stats.video++ } elseif ($isAud) { $stats.audio++ } else { $stats.image++ }
  }
  if (Test-Path -LiteralPath $dst) { $stats.outBytes += (Get-Item -LiteralPath $dst).Length }

  $map[$rel] = $web
  return $web
}

# ---------------------------------------------------------------------
# 逐項搬素材並改寫路徑
# ---------------------------------------------------------------------
Write-Host "正在整理素材…" -ForegroundColor Cyan

if ($data.bgm) { $data.bgm = @($data.bgm | ForEach-Object { Add-Asset $_ } | Where-Object { $_ }) }

if ($data.cover) {
  if ($data.cover.background) { $data.cover.background = Add-Asset $data.cover.background }
  if ($data.cover.hero)       { $data.cover.hero       = Add-Asset $data.cover.hero }
  if ($data.cover.photos)     { $data.cover.photos     = @($data.cover.photos | ForEach-Object { Add-Asset $_ } | Where-Object { $_ }) }
}

foreach ($q in $data.levels.level1.questions) { $q.image = Add-Asset $q.image }
foreach ($q in $data.levels.level2.questions) {
  if ($q.clip)   { $q.clip   = Add-Asset $q.clip }
  if ($q.answer) { $q.answer = Add-Asset $q.answer }
}
foreach ($q in $data.levels.level3.questions) {
  if ($q.question) { $q.question = Add-Asset $q.question -Silent }   # 題目影片一定要無聲
  if ($q.answer)   { $q.answer   = Add-Asset $q.answer }
}
foreach ($q in $data.levels.level4.questions) {
  foreach ($part in @("eyes", "mouth")) {
    if ($q.$part) {
      if ($q.$part.q) { $q.$part.q = Add-Asset $q.$part.q }
      if ($q.$part.a) { $q.$part.a = Add-Asset $q.$part.a }
    }
  }
  if ($q.lightstick -and $q.lightstick.image) { $q.lightstick.image = Add-Asset $q.lightstick.image }
}

$data.assetBase = "assets"
$data.root = "(web)"

# ---------------------------------------------------------------------
# 產生 docs\
# ---------------------------------------------------------------------
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$json = $data | ConvertTo-Json -Depth 12
$header = @"
/* KPOP之王巔峰賽 — 網頁版題庫（由 建立網頁版.bat 自動產生，請勿手改）
   產生時間：$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) */
window.QUIZ_DATA =
"@
[System.IO.File]::WriteAllText((Join-Path $outDir "quiz-data.js"),
  $header + [Environment]::NewLine + $json + ";" + [Environment]::NewLine, $utf8NoBom)

Copy-Item -LiteralPath (Join-Path $appDir "index.html") -Destination (Join-Path $outDir "index.html") -Force
Copy-Item -LiteralPath (Join-Path $appDir "styles.css") -Destination (Join-Path $outDir "styles.css") -Force
$vendorSrc = Join-Path $appDir "vendor"
$vendorDst = Join-Path $outDir "vendor"
New-Item -ItemType Directory -Force -Path $vendorDst | Out-Null
Get-ChildItem -LiteralPath $vendorSrc -File | ForEach-Object {
  Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $vendorDst $_.Name) -Force
}

# GitHub Pages 用：不要讓 Jekyll 動我們的檔案
[System.IO.File]::WriteAllText((Join-Path $outDir ".nojekyll"), "", $utf8NoBom)

$deployTxt = @"
=====================================================================
 KPOP之王巔峰賽 — 網頁版部署說明
=====================================================================
這個資料夾就是完整的網頁版，純前端、不需要後端。
把它整包放到任何免費靜態網站空間就會有公開網址。


【方法 A】Netlify Drop —— 最快，不用註冊、不用打指令
---------------------------------------------------------------------
 1. 瀏覽器打開   https://app.netlify.com/drop
 2. 把這個 docs 資料夾「整個」拖進網頁中央的框框
 3. 等上傳完（看素材大小，通常 1~3 分鐘）
 4. 畫面上會出現一個網址，例如
       https://sparkly-cat-123456.netlify.app
    這就是可以直接傳給朋友的連結，手機電腦都能開
 5. （可選）免費註冊 Netlify 帳號就能保留這個網址、改成好記的名字
    以後要更新，重新拖一次資料夾覆蓋即可


【方法 B】GitHub Pages —— 和你現有的版控整合
---------------------------------------------------------------------
 1. 在 D:\kpop 執行「Git存檔.bat」，把 docs 資料夾一起推上 GitHub
 2. 到 GitHub 你的 repo 頁面 → 上方 Settings
 3. 左邊選 Pages
 4. Source 選 "Deploy from a branch"
    Branch 選 main ，資料夾選 /docs ，按 Save
 5. 等 1~2 分鐘，網址會長這樣
       https://你的帳號.github.io/repo名稱/
 6. 以後每次跑「建立網頁版.bat」+「Git存檔.bat」就會自動更新線上版

 ※ repo 如果是 Private，GitHub Pages 需要付費方案才能發佈；
   想用免費方案的話把 repo 改成 Public，或改用方法 A。


【方法 C】Vercel —— 想要自訂網域時
---------------------------------------------------------------------
 1. https://vercel.com 用 GitHub 帳號登入
 2. Add New → Project → 選你的 repo
 3. Framework Preset 選 "Other"
    Root Directory 填 docs
    Build Command 留空，Output Directory 填 .
 4. Deploy，完成後會給你 https://xxx.vercel.app


=====================================================================
 注意事項
=====================================================================
 · 手機也能玩，橫著拿體驗最好。
 · 朋友第一次點畫面後背景音樂才會播（瀏覽器的自動播放限制）。
 · 影片已經壓縮過，但如果素材很多、網路慢，第一次載入會等一下。
   想更小可以重跑： 建立網頁版.bat -VideoMaxWidth 640 -VideoCrf 32
 · 素材更新後要重跑「建立網頁版.bat」再重新部署一次。
 · 這是公開網址，任何拿到連結的人都能看到裡面的照片與 MV，
   注意版權與隱私，不要放不能公開的東西。
"@
[System.IO.File]::WriteAllText((Join-Path $outDir "部署說明.txt"), ($deployTxt -replace "`r?`n", "`r`n"), $utf8NoBom)

# ---------------------------------------------------------------------
# 健檢：把題庫裡每一個路徑都實際比對一次，確認檔案真的在 docs 裡面
# ---------------------------------------------------------------------
Write-Host ""
Write-Host "健檢中（確認每個路徑都真的有檔案）…" -ForegroundColor Cyan

$refs = New-Object System.Collections.ArrayList
function Note([string]$v) { if ($v) { [void]$refs.Add($v) } }
foreach ($x in $data.bgm) { Note $x }
if ($data.cover) {
  Note $data.cover.background; Note $data.cover.hero
  foreach ($x in $data.cover.photos) { Note $x }
}
foreach ($q in $data.levels.level1.questions) { Note $q.image }
foreach ($q in $data.levels.level2.questions) { Note $q.clip; Note $q.answer }
foreach ($q in $data.levels.level3.questions) { Note $q.question; Note $q.answer }
foreach ($q in $data.levels.level4.questions) {
  foreach ($part in @("eyes","mouth")) { if ($q.$part) { Note $q.$part.q; Note $q.$part.a } }
  if ($q.lightstick) { Note $q.lightstick.image }
}

$badPath = New-Object System.Collections.ArrayList
$missing = New-Object System.Collections.ArrayList
$extern  = New-Object System.Collections.ArrayList
$okCount = 0
foreach ($r in ($refs | Select-Object -Unique)) {
  if ($r -match '^(https?:)?//' -or $r -match '^data:') { [void]$extern.Add($r); continue }
  if ($r -match '^[A-Za-z]:[\\/]' -or $r -match '^file:') { [void]$badPath.Add($r); continue }
  if (Test-Path -LiteralPath (Join-Path $assetsDir ($r -replace '/', '\'))) { $okCount++ }
  else { [void]$missing.Add($r) }
}

# --- 健檢 2：docs 底下的檔案會不會被 .gitignore 擋掉（GitHub Pages 最常見的坑）---
function Find-GitExe {
  $c = @((Join-Path $Root "tools\git\cmd\git.exe"))
  $g = Get-Command git -ErrorAction SilentlyContinue
  if ($g -and $g.Source) { $c += $g.Source }
  $c += "C:\Program Files\Git\cmd\git.exe"
  foreach ($p in $c) { if ($p -and (Test-Path -LiteralPath $p)) { return $p } }
  return $null
}
function Test-GitIgnored([string]$Exe, [string]$RepoRoot, [string]$RelPath) {
  $old = $ErrorActionPreference
  $ErrorActionPreference = "SilentlyContinue"
  & $Exe -C $RepoRoot check-ignore -q -- $RelPath 2>&1 | Out-Null
  $code = $LASTEXITCODE
  $ErrorActionPreference = $old
  return ($code -eq 0)
}

$gitIgnored = New-Object System.Collections.ArrayList
$gitExe = Find-GitExe
if ($gitExe -and (Test-Path -LiteralPath (Join-Path $Root ".git"))) {
  $probe = @(($Out + "/index.html"), ($Out + "/quiz-data.js"), ($Out + "/styles.css"))
  foreach ($k in $used.Keys) { $probe += ($Out + "/assets/" + $k) }
  foreach ($p in $probe) {
    if (Test-GitIgnored $gitExe $Root $p) { [void]$gitIgnored.Add($p) }
  }
}

$listLines = @("KPOP之王巔峰賽 — 網頁版資產清單",
               "產生時間：" + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),
               "assetBase = assets",
               "",
               "本地檔案（" + $okCount + " 個，全部已確認存在）：")
foreach ($r in ($refs | Select-Object -Unique | Sort-Object)) {
  if ($r -notmatch '^(https?:)?//' -and $r -notmatch '^data:') { $listLines += ("  assets/" + $r) }
}
if ($extern.Count -gt 0) {
  $listLines += @("", "外連圖片（不打包，由對方瀏覽器直接抓）：")
  foreach ($r in $extern) { $listLines += ("  " + $r) }
}
if ($missing.Count -gt 0) {
  $listLines += @("", "!! 缺少的檔案：")
  foreach ($r in $missing) { $listLines += ("  assets/" + $r) }
}
[System.IO.File]::WriteAllText((Join-Path $outDir "資產清單.txt"),
  (($listLines -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))

# ---------------------------------------------------------------------
# 報表
# ---------------------------------------------------------------------
$total = (Get-ChildItem -LiteralPath $outDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "  網頁版打包完成" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ("  輸出資料夾： " + $outDir) -ForegroundColor Cyan
Write-Host ("  影片 {0} 支 · 音檔 {1} 個 · 圖片 {2} 張" -f $stats.video, $stats.audio, $stats.image)
if ($stats.skipped -gt 0) { Write-Host ("  略過（找不到檔案）： {0} 個" -f $stats.skipped) -ForegroundColor Yellow }
if ($compress -and $stats.srcBytes -gt 0) {
  Write-Host ("  素材壓縮： {0} MB → {1} MB（省下 {2}%）" -f `
    [math]::Round($stats.srcBytes/1MB,1), [math]::Round($stats.outBytes/1MB,1),
    [math]::Round((1 - $stats.outBytes / $stats.srcBytes) * 100)) -ForegroundColor Cyan
}
Write-Host ("  網頁版總大小： {0} MB" -f [math]::Round($total/1MB,1)) -ForegroundColor Cyan
if ($stats.converted -gt 0) { Write-Host ("  轉成相容格式： {0} 張（.avif/.webp → .jpg/.png，舊手機才看得到）" -f $stats.converted) -ForegroundColor Cyan }
if ($stats.external -gt 0)  { Write-Host ("  外連圖片： {0} 個（不打包）" -f $stats.external) -ForegroundColor Cyan }
Write-Host ""
Write-Host "----------------------------------------------------------"
if ($badPath.Count -eq 0 -and $missing.Count -eq 0 -and $gitIgnored.Count -eq 0) {
  Write-Host ("  健檢通過：{0} 個檔案路徑全部正確，沒有任何本機絕對路徑。" -f $okCount) -ForegroundColor Green
  if ($gitExe) { Write-Host ("  {0}\ 底下的檔案都不會被 .gitignore 擋掉，可以安全推上 GitHub Pages。" -f $Out) -ForegroundColor Green }
} else {
  if ($gitIgnored.Count -gt 0) {
    Write-Host ("  !! 有 {0} 個檔案被 .gitignore 擋住，推上 GitHub 後網頁會看不到它們：" -f $gitIgnored.Count) -ForegroundColor Red
    foreach ($p in ($gitIgnored | Select-Object -First 10)) { Write-Host ("     " + $p) -ForegroundColor Red }
    if ($gitIgnored.Count -gt 10) { Write-Host ("     …其餘 " + ($gitIgnored.Count - 10) + " 個") -ForegroundColor Red }
    Write-Host "     → 檢查 D:\kpop\.gitignore，素材規則前面都要加「/」鎖定根目錄，" -ForegroundColor Yellow
    Write-Host "       例如寫成 /cover/ 而不是 cover/，否則會連 docs 底下的同名資料夾一起排除。" -ForegroundColor Yellow
  }
  if ($badPath.Count -gt 0) {
    Write-Host "  !! 發現本機絕對路徑（別人的電腦讀不到）：" -ForegroundColor Red
    foreach ($r in $badPath) { Write-Host ("     " + $r) -ForegroundColor Red }
  }
  if ($missing.Count -gt 0) {
    Write-Host ("  !! 有 {0} 個檔案在 docs 裡找不到，朋友會看到「找不到圖片」：" -f $missing.Count) -ForegroundColor Red
    foreach ($r in ($missing | Select-Object -First 12)) { Write-Host ("     assets/" + $r) -ForegroundColor Red }
    Write-Host "     → 通常是原始素材被刪或改名，補回去後再跑一次即可。" -ForegroundColor Yellow
  }
}
Write-Host ("  完整清單： " + (Join-Path $outDir "資產清單.txt")) -ForegroundColor DarkGray
Write-Host "----------------------------------------------------------"
Write-Host ""
Write-Host "  下一步：把 docs 資料夾拖到 https://app.netlify.com/drop" -ForegroundColor Yellow
Write-Host "  就會拿到一個可以傳給朋友的公開網址。" -ForegroundColor Yellow
Write-Host ("  詳細步驟看： " + (Join-Path $outDir "部署說明.txt")) -ForegroundColor DarkGray
Write-Host ""
