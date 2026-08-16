# =====================================================================
#  KPOP之王巔峰賽 - 題庫自動掃描腳本
#  用法：直接執行 D:\kpop\更新題庫.bat 即可
#  功能：掃描 D:\kpop 底下四關素材，自動產生 app\quiz-data.js
# =====================================================================
$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$appDir  = Split-Path -Parent $scriptDir          # ...\app
$root    = Split-Path -Parent $appDir             # D:\kpop
$outFile = Join-Path $appDir "quiz-data.js"

Write-Host ""
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "  KPOP之王巔峰賽 - 題庫掃描" -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "素材根目錄： $root"
Write-Host ""

$IMG = @(".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp", ".avif")
$AUD = @(".mp3", ".m4a", ".wav", ".ogg", ".oga", ".aac", ".flac", ".opus")
$VID = @(".mp4", ".webm", ".mov", ".mkv", ".m4v", ".ogv")

# ---------- 小工具 ----------
function Get-Rel([string]$full) {
  $r = $root.TrimEnd('\')
  if ($full.StartsWith($r, [System.StringComparison]::OrdinalIgnoreCase)) {
    $full = $full.Substring($r.Length).TrimStart('\', '/')
  }
  return (($full -replace '\\', '/').TrimStart('/'))
}

function Find-Dir([string[]]$patterns, $parent) {
  if (-not $parent) { return $null }
  foreach ($p in $patterns) {
    $d = Get-ChildItem -LiteralPath $parent -Directory -ErrorAction SilentlyContinue |
         Where-Object { $_.Name -like $p } | Select-Object -First 1
    if ($d) { return $d }
  }
  return $null
}

function Get-Media($dir, [string[]]$exts) {
  if (-not $dir) { return @() }
  $p = $dir
  if ($dir -isnot [string]) { $p = $dir.FullName }
  if (-not (Test-Path -LiteralPath $p)) { return @() }
  return @(Get-ChildItem -LiteralPath $p -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $exts -contains $_.Extension.ToLower() } |
    Sort-Object Name)
}

# 檔名規則： 團體_名稱.副檔名   例：IVE_WonYoung.png / ITZY_CAKE.mp3
function Split-Name([string]$base) {
  $i = $base.IndexOf('_')
  if ($i -gt 0) {
    return [pscustomobject]@{ group = $base.Substring(0, $i); name = $base.Substring($i + 1) }
  }
  return [pscustomobject]@{ group = ""; name = $base }
}

function New-Id([string]$prefix, [int]$n) { return ("{0}-{1:d3}" -f $prefix, $n) }

# ---------- 定位各關資料夾 ----------
$dirL1  = Find-Dir @("第一關*", "level1*", "*快看快答*")     $root
$dirL2  = Find-Dir @("第二關*", "level2*", "*前奏*")         $root
$dirL3  = Find-Dir @("第三關*", "level3*", "*舞蹈*")         $root
$dirL4  = Find-Dir @("第四關*", "level4*", "*五官*")         $root
$dirBgm = Find-Dir @("介面音樂*", "bgm*", "*背景音樂*")       $root
$dirCover = Find-Dir @("封面*", "cover*", "*主視覺*")          $root

$QPAT = @("題目", "题目", "question*", "Q")
$APAT = @("答案", "answer*", "A")

$warn = New-Object System.Collections.ArrayList

# ---------- 第一關：偶像快看快答 ----------
$l1 = New-Object System.Collections.ArrayList
$n = 0
foreach ($f in (Get-Media $dirL1 $IMG)) {
  $n++
  $p = Split-Name([System.IO.Path]::GetFileNameWithoutExtension($f.Name))
  [void]$l1.Add([ordered]@{
    id    = New-Id "L1" $n
    group = $p.group
    name  = $p.name
    image = Get-Rel $f.FullName
  })
}

# ---------- 第二關：聽前奏猜歌 ----------
$l2 = New-Object System.Collections.ArrayList
if ($dirL2) {
  $qd = Find-Dir $QPAT $dirL2.FullName
  $ad = Find-Dir $APAT $dirL2.FullName
  $qs = @{}; $as = @{}
  foreach ($f in (Get-Media $qd ($AUD + $VID))) { $qs[[System.IO.Path]::GetFileNameWithoutExtension($f.Name)] = $f }
  foreach ($f in (Get-Media $ad ($VID + $AUD))) { $as[[System.IO.Path]::GetFileNameWithoutExtension($f.Name)] = $f }
  $keys = @($qs.Keys) + @($as.Keys) | Select-Object -Unique | Sort-Object
  $n = 0
  foreach ($k in $keys) {
    $n++
    $p = Split-Name $k
    $item = [ordered]@{
      id     = New-Id "L2" $n
      group  = $p.group
      title  = $p.name
      clip   = $null
      answer = $null
      introSeconds = 12
    }
    if ($qs.ContainsKey($k)) { $item.clip   = Get-Rel $qs[$k].FullName }
    if ($as.ContainsKey($k)) { $item.answer = Get-Rel $as[$k].FullName }
    if (-not $item.clip)   { [void]$warn.Add("第二關『$k』沒有題目前奏檔，將自動播放答案影片前 12 秒的音訊。") }
    if (-not $item.answer) { [void]$warn.Add("第二關『$k』沒有答案影片，公布答案時只會顯示歌名。") }
    [void]$l2.Add($item)
  }
}

# ---------- 第三關：看舞蹈猜歌 ----------
$l3 = New-Object System.Collections.ArrayList
if ($dirL3) {
  $qd = Find-Dir $QPAT $dirL3.FullName
  $ad = Find-Dir $APAT $dirL3.FullName
  $qs = @{}; $as = @{}
  foreach ($f in (Get-Media $qd $VID)) { $qs[[System.IO.Path]::GetFileNameWithoutExtension($f.Name) -replace '_question$', ''] = $f }
  foreach ($f in (Get-Media $ad $VID)) { $as[[System.IO.Path]::GetFileNameWithoutExtension($f.Name) -replace '_answer$', '']   = $f }
  # 沒有分「題目/答案」子資料夾時，直接把整個資料夾的影片當作答案 MV（題目由前端即時遮蔽）
  if (-not $qd -and -not $ad) {
    foreach ($f in (Get-Media $dirL3 $VID)) { $as[[System.IO.Path]::GetFileNameWithoutExtension($f.Name)] = $f }
  }
  $keys = @($qs.Keys) + @($as.Keys) | Select-Object -Unique | Sort-Object
  $n = 0
  foreach ($k in $keys) {
    $n++
    $p = Split-Name $k
    $item = [ordered]@{
      id       = New-Id "L3" $n
      group    = $p.group
      title    = $p.name
      question = $null
      answer   = $null
      autoMask = $false
    }
    if ($qs.ContainsKey($k)) { $item.question = Get-Rel $qs[$k].FullName }
    if ($as.ContainsKey($k)) { $item.answer   = Get-Rel $as[$k].FullName }
    if (-not $item.question) {
      $item.autoMask = $true
      [void]$warn.Add("第三關『$k』沒有現成剪影影片，將由前端即時濾鏡自動生成黑影題目。")
    }
    [void]$l3.Add($item)
  }
}

# ---------- 第四關：看五官猜偶像 ----------
$l4 = New-Object System.Collections.ArrayList
if ($dirL4) {
  $qd = Find-Dir $QPAT $dirL4.FullName
  $ad = Find-Dir $APAT $dirL4.FullName
  $eyeQ   = Get-Media (Find-Dir @("眼睛", "eye*")        $(if ($qd) { $qd.FullName })) $IMG
  $mouQ   = Get-Media (Find-Dir @("嘴巴", "mouth*")      $(if ($qd) { $qd.FullName })) $IMG
  $lsQ    = Get-Media (Find-Dir @("手燈", "手灯", "light*") $(if ($qd) { $qd.FullName })) $IMG
  $eyeA   = Get-Media (Find-Dir @("眼睛", "eye*")        $(if ($ad) { $ad.FullName })) $IMG
  $mouA   = Get-Media (Find-Dir @("嘴巴", "mouth*")      $(if ($ad) { $ad.FullName })) $IMG

  $eyeAMap = @{}; foreach ($f in $eyeA) { $eyeAMap[[System.IO.Path]::GetFileNameWithoutExtension($f.Name)] = $f }
  $mouAMap = @{}; foreach ($f in $mouA) { $mouAMap[[System.IO.Path]::GetFileNameWithoutExtension($f.Name)] = $f }
  $lsMap   = @{}; foreach ($f in $lsQ)  { $lsMap[[System.IO.Path]::GetFileNameWithoutExtension($f.Name)]   = $f }

  # 可選：在第四關資料夾放 配對.csv（每行「眼睛檔名,嘴巴檔名[,手燈檔名]」，不含副檔名）指定配對
  $pairFile = $null
  foreach ($cand in @("配對.csv", "pairs.csv")) {
    $t = Join-Path $dirL4.FullName $cand
    if (Test-Path -LiteralPath $t) { $pairFile = $t; break }
  }

  $pairs = New-Object System.Collections.ArrayList
  if ($pairFile) {
    foreach ($line in (Get-Content -LiteralPath $pairFile -Encoding UTF8)) {
      $line = $line.Trim()
      if (-not $line -or $line.StartsWith("#")) { continue }
      $c = $line.Split(',')
      $e = $eyeQ | Where-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $c[0].Trim() } | Select-Object -First 1
      $m = $null
      if ($c.Length -gt 1) { $m = $mouQ | Where-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $c[1].Trim() } | Select-Object -First 1 }
      $l = $null
      if ($c.Length -gt 2) { $l = $lsQ  | Where-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $c[2].Trim() } | Select-Object -First 1 }
      if ($e -or $m) { [void]$pairs.Add(@($e, $m, $l)) }
    }
  } else {
    $cnt = [Math]::Max($eyeQ.Count, $mouQ.Count)
    for ($i = 0; $i -lt $cnt; $i++) {
      $e = $null; $m = $null
      if ($i -lt $eyeQ.Count) { $e = $eyeQ[$i] }
      if ($i -lt $mouQ.Count) { $m = $mouQ[$i] }
      [void]$pairs.Add(@($e, $m, $null))
    }
  }

  $n = 0
  foreach ($pr in $pairs) {
    $n++
    $e = $pr[0]; $m = $pr[1]; $l = $pr[2]
    $eBase = ""; $mBase = ""
    if ($e) { $eBase = [System.IO.Path]::GetFileNameWithoutExtension($e.Name) }
    if ($m) { $mBase = [System.IO.Path]::GetFileNameWithoutExtension($m.Name) }
    $ep = Split-Name $eBase
    $mp = Split-Name $mBase

    if (-not $l) {
      if ($ep.group -and $lsMap.ContainsKey($ep.group)) { $l = $lsMap[$ep.group] }
      elseif ($mp.group -and $lsMap.ContainsKey($mp.group)) { $l = $lsMap[$mp.group] }
      elseif ($lsQ.Count -gt 0) { $l = $lsQ[0] }
    }

    $item = [ordered]@{ id = New-Id "L4" $n; eyes = $null; mouth = $null; lightstick = $null }
    if ($e) {
      $a = $null
      if ($eyeAMap.ContainsKey($eBase)) { $a = Get-Rel $eyeAMap[$eBase].FullName }
      $item.eyes = [ordered]@{ group = $ep.group; name = $ep.name; q = (Get-Rel $e.FullName); a = $a }
      if (-not $a) { [void]$warn.Add("第四關眼睛『$eBase』找不到答案原圖（答案\眼睛\$eBase.png）。") }
    }
    if ($m) {
      $a = $null
      if ($mouAMap.ContainsKey($mBase)) { $a = Get-Rel $mouAMap[$mBase].FullName }
      $item.mouth = [ordered]@{ group = $mp.group; name = $mp.name; q = (Get-Rel $m.FullName); a = $a }
      if (-not $a) { [void]$warn.Add("第四關嘴巴『$mBase』找不到答案原圖（答案\嘴巴\$mBase.png）。") }
    }
    if ($l) {
      $lp = Split-Name([System.IO.Path]::GetFileNameWithoutExtension($l.Name))
      $item.lightstick = [ordered]@{ group = $lp.group; image = (Get-Rel $l.FullName) }
      if (-not $lp.group) { $item.lightstick.group = $lp.name }
    }
    [void]$l4.Add($item)
  }
}

# ---------- 封面素材 ----------
# 檔名含「背景 / background」→ 全螢幕動態背景（圖片或影片）
# 檔名含「主視覺 / hero / cover」→ 中央主視覺卡片
# 其餘圖片 → 會飄動的照片牆
$coverBg = $null
$coverBgIsVideo = $false
$coverHero = $null
$coverPhotos = New-Object System.Collections.ArrayList

foreach ($f in (Get-Media $dirCover ($IMG + $VID))) {
  $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
  $isVid = $VID -contains $f.Extension.ToLower()
  if (($base -like "*背景*" -or $base -like "background*" -or $base -like "bg") -and -not $coverBg) {
    $coverBg = Get-Rel $f.FullName
    $coverBgIsVideo = $isVid
  } elseif (($base -like "*主視覺*" -or $base -like "hero*" -or $base -like "cover*") -and -not $coverHero -and -not $isVid) {
    $coverHero = Get-Rel $f.FullName
  } elseif (-not $isVid) {
    [void]$coverPhotos.Add((Get-Rel $f.FullName))
  } elseif (-not $coverBg) {
    $coverBg = Get-Rel $f.FullName
    $coverBgIsVideo = $true
  }
}

# 封面資料夾沒放照片時，自動借用第一關的偶像照當照片牆
$coverFallback = $false
if ($coverPhotos.Count -eq 0 -and -not $coverHero) {
  $coverFallback = $true
  foreach ($q in ($l1 | Select-Object -First 12)) { [void]$coverPhotos.Add($q.image) }
}

# ---------- 背景音樂 ----------
$bgm = New-Object System.Collections.ArrayList
foreach ($f in (Get-Media $dirBgm $AUD)) { [void]$bgm.Add((Get-Rel $f.FullName)) }

# ---------- 組出 JSON ----------
$payload = [ordered]@{
  generatedAt = (Get-Date).ToString("s")
  root        = $root
  bgm         = @($bgm)
  cover       = [ordered]@{
    background      = $coverBg
    backgroundIsVideo = $coverBgIsVideo
    hero            = $coverHero
    photos          = @($coverPhotos)
    usingFallback   = $coverFallback
  }
  levels      = [ordered]@{
    level1 = [ordered]@{ id = "level1"; title = "偶像快看快答";   questions = @($l1) }
    level2 = [ordered]@{ id = "level2"; title = "聽前奏猜歌";     questions = @($l2) }
    level3 = [ordered]@{ id = "level3"; title = "看舞蹈猜歌";     questions = @($l3) }
    level4 = [ordered]@{ id = "level4"; title = "看五官猜偶像";   questions = @($l4) }
  }
}

$json = $payload | ConvertTo-Json -Depth 12
$header = @"
/* ===================================================================
   KPOP之王巔峰賽 - 自動產生的題庫檔
   由 更新題庫.bat / scan_assets.ps1 產生，請勿手動覆寫（會被蓋掉）
   產生時間：$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
   =================================================================== */
window.QUIZ_DATA =
"@
$content = $header + [Environment]::NewLine + $json + ";" + [Environment]::NewLine

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($outFile, $content, $utf8NoBom)

# 同時輸出一份純 JSON 方便檢視 / 手動編輯參考
[System.IO.File]::WriteAllText((Join-Path $appDir "quiz-data.json"), $json, $utf8NoBom)

# ---------- 報表 ----------
Write-Host "掃描完成！" -ForegroundColor Green
Write-Host ("  第一關 偶像快看快答 : {0} 題" -f $l1.Count)
Write-Host ("  第二關 聽前奏猜歌   : {0} 題" -f $l2.Count)
Write-Host ("  第三關 看舞蹈猜歌   : {0} 題" -f $l3.Count)
Write-Host ("  第四關 看五官猜偶像 : {0} 題" -f $l4.Count)
Write-Host ("  背景音樂            : {0} 首" -f $bgm.Count)
if ($coverFallback) {
  Write-Host ("  封面照片牆          : {0} 張（借用第一關照片，建議在「封面」資料夾放專屬圖）" -f $coverPhotos.Count)
} else {
  Write-Host ("  封面照片牆          : {0} 張" -f $coverPhotos.Count)
}
if ($coverBg)   { Write-Host ("  封面動態背景        : " + $coverBg) }
if ($coverHero) { Write-Host ("  封面主視覺          : " + $coverHero) }
Write-Host ""
if ($warn.Count -gt 0) {
  Write-Host "提醒：" -ForegroundColor Yellow
  foreach ($w in ($warn | Select-Object -Unique)) { Write-Host ("  - " + $w) -ForegroundColor Yellow }
  Write-Host ""
}
Write-Host ("題庫已寫入： " + $outFile) -ForegroundColor Cyan
Write-Host ""
