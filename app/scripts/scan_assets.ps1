# =====================================================================
#  KPOP之王巔峰賽 - 題庫自動掃描腳本
#  用法：直接執行 D:\kpop\更新題庫.bat 即可
#  功能：掃描 D:\kpop 底下四關素材，自動產生 app\quiz-data.js
# =====================================================================
# ── Windows PowerShell 5.1 的地雷 ──────────────────────────────────
# $ErrorActionPreference = "Stop" 之下，原生程式（git / ffmpeg / python）
# 只要往 stderr 寫東西就會被當成終止錯誤，整支腳本直接掛掉（NativeCommandError）。
# git 連「Rebasing (1/1)」這種進度訊息都是走 stderr，所以這裡一律用 Continue，
# 改成每一步自己檢查 $LASTEXITCODE；真正需要中斷的 cmdlet 才單獨加 -ErrorAction Stop。
$ErrorActionPreference = "Continue"
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
$dirL5  = Find-Dir @("第五關*", "level5*", "*MV片段*")       $root
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
# 規則：眼睛與嘴巴一定「同一團、不同成員」
$l4 = New-Object System.Collections.ArrayList
$l4groups = New-Object System.Collections.ArrayList
if ($dirL4) {
  $qd = Find-Dir $QPAT $dirL4.FullName
  $ad = Find-Dir $APAT $dirL4.FullName
  $eyeQ = Get-Media (Find-Dir @("眼睛", "eye*")            $(if ($qd) { $qd.FullName })) $IMG
  $mouQ = Get-Media (Find-Dir @("嘴巴", "mouth*")          $(if ($qd) { $qd.FullName })) $IMG
  $lsQ  = Get-Media (Find-Dir @("手燈", "手灯", "light*")   $(if ($qd) { $qd.FullName })) $IMG
  $eyeA = Get-Media (Find-Dir @("眼睛", "eye*")            $(if ($ad) { $ad.FullName })) $IMG
  $mouA = Get-Media (Find-Dir @("嘴巴", "mouth*")          $(if ($ad) { $ad.FullName })) $IMG

  $eyeAMap = @{}; foreach ($f in $eyeA) { $eyeAMap[[System.IO.Path]::GetFileNameWithoutExtension($f.Name)] = $f }
  $mouAMap = @{}; foreach ($f in $mouA) { $mouAMap[[System.IO.Path]::GetFileNameWithoutExtension($f.Name)] = $f }
  $lsMap   = @{}
  foreach ($f in $lsQ) {
    $lb = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
    $lsMap[$lb] = Get-Rel $f.FullName
  }

  # 依團名分組
  $byGroup = [ordered]@{}
  function Ensure-Group([string]$g) {
    if (-not $byGroup.Contains($g)) {
      $byGroup[$g] = [ordered]@{ name = $g; lightstick = $null
                                 eyes = (New-Object System.Collections.ArrayList)
                                 mouths = (New-Object System.Collections.ArrayList) }
    }
  }
  foreach ($f in $eyeQ) {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
    $p = Split-Name $base
    if (-not $p.group -or -not $p.name) { [void]$warn.Add("第四關眼睛『$base』檔名不是「團名_成員」格式，已略過。"); continue }
    Ensure-Group $p.group
    $ansPath = $null
    if ($eyeAMap.ContainsKey($base)) { $ansPath = Get-Rel $eyeAMap[$base].FullName }
    [void]$byGroup[$p.group].eyes.Add([ordered]@{ name = $p.name; q = (Get-Rel $f.FullName); a = $ansPath })
  }
  foreach ($f in $mouQ) {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
    $p = Split-Name $base
    if (-not $p.group -or -not $p.name) { [void]$warn.Add("第四關嘴巴『$base』檔名不是「團名_成員」格式，已略過。"); continue }
    Ensure-Group $p.group
    $ansPath = $null
    if ($mouAMap.ContainsKey($base)) { $ansPath = Get-Rel $mouAMap[$base].FullName }
    [void]$byGroup[$p.group].mouths.Add([ordered]@{ name = $p.name; q = (Get-Rel $f.FullName); a = $ansPath })
  }
  foreach ($g in @($byGroup.Keys)) {
    if ($lsMap.ContainsKey($g)) { $byGroup[$g].lightstick = $lsMap[$g] }
    else { [void]$warn.Add("第四關團體『$g』沒有手燈圖（題目\手燈\$g.png），提示區會空白。") }
  }

  # 可選：配對.csv 指定固定配對（眼睛檔名,嘴巴檔名）
  $pairFile = $null
  foreach ($cand in @("配對.csv", "pairs.csv")) {
    $t = Join-Path $dirL4.FullName $cand
    if (Test-Path -LiteralPath $t) { $pairFile = $t; break }
  }

  $n = 0
  function Add-L4([string]$g, $eye, $mouth) {
    $script:n++
    $item = [ordered]@{
      id         = New-Id "L4" $script:n
      group      = $g
      lightstick = $byGroup[$g].lightstick
      eyes       = [ordered]@{ group = $g; name = $eye.name;   q = $eye.q;   a = $eye.a }
      mouth      = [ordered]@{ group = $g; name = $mouth.name; q = $mouth.q; a = $mouth.a }
    }
    [void]$l4.Add($item)
  }

  if ($pairFile) {
    foreach ($line in (Get-Content -LiteralPath $pairFile -Encoding UTF8)) {
      $line = $line.Trim()
      if (-not $line -or $line.StartsWith("#")) { continue }
      $c = $line.Split(',')
      if ($c.Length -lt 2) { continue }
      $eb = $c[0].Trim(); $mb = $c[1].Trim()
      $ep = Split-Name $eb; $mp = Split-Name $mb
      if ($ep.group -ne $mp.group) { [void]$warn.Add("配對.csv 這行不是同一團，已略過： $line"); continue }
      if ($ep.name -eq $mp.name)   { [void]$warn.Add("配對.csv 這行是同一個人，已略過： $line"); continue }
      if (-not $byGroup.Contains($ep.group)) { continue }
      $e = $byGroup[$ep.group].eyes   | Where-Object { $_.name -eq $ep.name } | Select-Object -First 1
      $m = $byGroup[$mp.group].mouths | Where-Object { $_.name -eq $mp.name } | Select-Object -First 1
      if ($e -and $m) { Add-L4 $ep.group $e $m }
    }
  } else {
    foreach ($g in @($byGroup.Keys)) {
      $E = @($byGroup[$g].eyes   | Sort-Object { $_.name })
      $M = @($byGroup[$g].mouths | Sort-Object { $_.name })
      if ($E.Count -eq 0 -or $M.Count -eq 0) {
        [void]$warn.Add("第四關團體『$g』只有眼睛或只有嘴巴，無法出題。")
        continue
      }
      $usedM = @{}
      $made = 0
      for ($i = 0; $i -lt $E.Count; $i++) {
        $pick = -1
        for ($k = 1; $k -le $M.Count; $k++) {
          $j = ($i + $k) % $M.Count
          if ($usedM.ContainsKey($j)) { continue }
          if ($M[$j].name -eq $E[$i].name) { continue }   # 不能是同一個人
          $pick = $j; break
        }
        if ($pick -lt 0) { continue }
        $usedM[$pick] = $true
        Add-L4 $g $E[$i] $M[$pick]
        $made++
      }
      if ($made -eq 0) {
        [void]$warn.Add("第四關團體『$g』的眼睛與嘴巴都是同一個人，湊不出「同團不同人」的題目。")
      }
    }
  }

  # 給前端做拖拉選項用的名冊
  foreach ($g in @($byGroup.Keys)) {
    [void]$l4groups.Add([ordered]@{
      name       = $g
      lightstick = $byGroup[$g].lightstick
      eyes       = @($byGroup[$g].eyes   | ForEach-Object { $_.name })
      mouths     = @($byGroup[$g].mouths | ForEach-Object { $_.name })
    })
  }
}

# ---------- 第五關：看MV片段猜歌 ----------
# 題目\片段1\團體_歌名.jpg、題目\片段2\…、題目\片段3\…（同名檔案 = 同一題）
# 答案\團體_歌名.mp4（可省略，省略時公布答案只顯示歌名）
$l5 = New-Object System.Collections.ArrayList
if ($dirL5) {
  $qd = Find-Dir $QPAT $dirL5.FullName
  $ad = Find-Dir $APAT $dirL5.FullName

  # 三個片段資料夾，中英數字寫法都吃
  $shotDirs = @()
  foreach ($n in 1, 2, 3) {
    $d = Find-Dir @("片段$n", "片段 $n", "shot$n", "clip$n", "$n") $(if ($qd) { $qd.FullName })
    $shotDirs += , $d
  }

  # 每一題用「主檔名」當 key，把三個片段兜起來
  $byKey = [ordered]@{}
  for ($i = 0; $i -lt 3; $i++) {
    foreach ($f in (Get-Media $shotDirs[$i] $IMG)) {
      $k = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
      if (-not $byKey.Contains($k)) { $byKey[$k] = @($null, $null, $null) }
      $arr = $byKey[$k]; $arr[$i] = (Get-Rel $f.FullName); $byKey[$k] = $arr
    }
  }
  # 沒有分片段資料夾時的退路：直接掃 題目\ 底下的圖，一張圖當一題
  if ($byKey.Count -eq 0) {
    foreach ($f in (Get-Media $qd $IMG)) {
      $k = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
      if (-not $byKey.Contains($k)) { $byKey[$k] = @((Get-Rel $f.FullName), $null, $null) }
    }
  }

  $ansMap = @{}
  foreach ($f in (Get-Media $ad ($VID + $AUD))) { $ansMap[[System.IO.Path]::GetFileNameWithoutExtension($f.Name)] = $f }

  $n = 0
  foreach ($k in @($byKey.Keys)) {
    $shots = @($byKey[$k] | Where-Object { $_ })      # 只留真的存在的片段，保持 1→2→3 的順序
    if ($shots.Count -eq 0) { continue }
    $n++
    $p = Split-Name $k
    if (-not $p.group) { [void]$warn.Add("第五關『$k』檔名不是「團名_歌名」格式，團體會是空的。") }
    if ($shots.Count -lt 3) { [void]$warn.Add("第五關『$k』只有 $($shots.Count) 張片段圖（建議三張：片段1／片段2／片段3）。") }
    $item = [ordered]@{
      id     = New-Id "L5" $n
      group  = $p.group
      title  = $p.name
      shots  = @($shots)
      answer = $null
    }
    if ($ansMap.ContainsKey($k)) { $item.answer = Get-Rel $ansMap[$k].FullName }
    else { [void]$warn.Add("第五關『$k』沒有答案影片，公布答案時只會顯示歌名。") }
    [void]$l5.Add($item)
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

# 外連圖片（圖床）：在「封面」資料夾放一個 外連圖片.txt，一行一個網址
if ($dirCover) {
  foreach ($cand in @("外連圖片.txt", "圖床.txt", "links.txt")) {
    $lf = Join-Path $dirCover.FullName $cand
    if (Test-Path -LiteralPath $lf) {
      foreach ($line in (Get-Content -LiteralPath $lf -Encoding UTF8)) {
        $u = $line.Trim()
        if (-not $u -or $u.StartsWith("#")) { continue }
        if ($u -match '^(https?:)?//') { [void]$coverPhotos.Add($u) }
      }
      break
    }
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
  assetBase   = ".."          # 本機直接開檔用；網頁版打包時會改成 "assets"
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
    level4 = [ordered]@{ id = "level4"; title = "看五官猜偶像";   groups = @($l4groups); questions = @($l4) }
    level5 = [ordered]@{ id = "level5"; title = "看MV片段猜歌"; questions = @($l5) }
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
Write-Host ("  第四關 看五官猜偶像 : {0} 題（{1} 個團體，眼睛與嘴巴同團不同人）" -f $l4.Count, $l4groups.Count)
Write-Host ("  第五關 看MV片段猜歌 : {0} 題" -f $l5.Count)
Write-Host ("  背景音樂            : {0} 首" -f $bgm.Count)
if ($coverFallback) {
  Write-Host ("  封面照片牆          : {0} 張（借用第一關照片，建議在「封面」資料夾放專屬圖）" -f $coverPhotos.Count)
} else {
  Write-Host ("  封面照片牆          : {0} 張" -f $coverPhotos.Count)
}
$extLinks = @($coverPhotos | Where-Object { $_ -match '^(https?:)?//' }).Count
if ($extLinks -gt 0) { Write-Host ("  其中外連圖床        : {0} 張" -f $extLinks) }
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
