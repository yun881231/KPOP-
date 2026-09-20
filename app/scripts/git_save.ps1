# =====================================================================
#  KPOP之王巔峰賽 — 存一版並推上 GitHub
#  用法：雙擊 D:\kpop\Git存檔.bat
# =====================================================================
[CmdletBinding()]
param(
  [string]$Root,
  [string]$Message,
  [ValidateSet("auto", "force", "rebase")]
  [string]$Mode = "auto",   # auto=自動判斷 / force=用本機覆蓋遠端 / rebase=把遠端接進來
  [switch]$Yes,             # 不要問，直接執行
  [switch]$BuildWeb,        # 推之前先重建網頁版 docs（封面圖／背景音樂會一起更新）
  [switch]$NoBuild,         # 不要問也不要重建，直接用現有的 docs
  [switch]$Reindex,         # 砍掉整個索引重建 → 遠端的檔名（含大小寫）完全等於本機
  [switch]$NoReindex        # 就算是 force 模式也不要重建索引
)

# ── Windows PowerShell 5.1 的地雷 ──────────────────────────────────
# $ErrorActionPreference = "Stop" 之下，原生程式（git / ffmpeg / python）
# 只要往 stderr 寫東西就會被當成終止錯誤，整支腳本直接掛掉（NativeCommandError）。
# git 連「Rebasing (1/1)」這種進度訊息都是走 stderr，所以這裡一律用 Continue，
# 改成每一步自己檢查 $LASTEXITCODE；真正需要中斷的 cmdlet 才單獨加 -ErrorAction Stop。
$ErrorActionPreference = "Continue"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
  $PSNativeCommandUseErrorActionPreference = $false
}
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$appDir = Split-Path -Parent $scriptDir
if (-not $Root) { $Root = Split-Path -Parent $appDir }
$toolsDir = Join-Path $Root "tools"

function Find-Git {
  $c = @((Join-Path $toolsDir "git\cmd\git.exe"))
  $g = Get-Command git -ErrorAction SilentlyContinue
  if ($g -and $g.Source) { $c += $g.Source }
  $c += "C:\Program Files\Git\cmd\git.exe"
  if ($env:LOCALAPPDATA) { $c += (Join-Path $env:LOCALAPPDATA "Programs\Git\cmd\git.exe") }
  foreach ($p in $c) { if ($p -and (Test-Path -LiteralPath $p)) { return (Resolve-Path -LiteralPath $p).Path } }
  return $null
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Magenta
Write-Host "  存檔到 GitHub" -ForegroundColor Magenta
Write-Host "==========================================================" -ForegroundColor Magenta

$git = Find-Git
if (-not $git) {
  Write-Host "找不到 Git。請先執行一次「Git設定.bat」。" -ForegroundColor Yellow
  return
}
if (-not (Test-Path -LiteralPath (Join-Path $Root ".git"))) {
  Write-Host "還沒建立版控。請先執行一次「Git設定.bat」。" -ForegroundColor Yellow
  return
}

. (Join-Path $scriptDir "git_common.ps1")

# 一律透過 Invoke-Git，避免 PowerShell 5.1 把 git 的 stderr 變成錯誤
# 不能有 param 區塊，否則 -A / -m 這種旗標會被 PowerShell 當成參數名
function G  { Invoke-Git $git $Root $args }
function GS { Invoke-Git $git $Root $args -Show }

# ── 推之前先把網頁版 docs 重建好 ────────────────────────────────────
#   docs\assets 底下的封面圖(cover)與背景音樂(bgm)都是「建立網頁版」產生的。
#   只改 D:\kpop\封面\ 或 介面音樂\ 而沒有重建 docs 的話，
#   推上 GitHub 的還是舊的那一份，GitHub Pages 自然看起來「沒更新」。
#   所以這裡會自己判斷素材有沒有比 docs 新，有的話預設幫你重建。
$docsDir  = Join-Path $Root "docs"
$buildPs1 = Join-Path $scriptDir "build_web.ps1"

$doBuild = $false
if ($BuildWeb) { $doBuild = $true }
elseif (-not $NoBuild -and (Test-Path -LiteralPath $buildPs1)) {
  $fresh = Test-WebBuildFresh $Root        # 比對素材指紋，換圖／刪圖／改名都算數
  if (-not (Test-Path -LiteralPath $docsDir)) {
    Write-Host ""
    Write-Host "還沒有網頁版 docs。" -ForegroundColor Yellow
  } elseif (-not $fresh) {
    Write-Host ""
    Write-Host "偵測到素材跟網頁版對不起來 —— 封面圖／背景音樂可能還是舊的一份。" -ForegroundColor Yellow
  }
  if ($Yes) {
    $doBuild = (-not $fresh)
  } else {
    Write-Host ""
    $def = $(if ($fresh) { "N" } else { "Y" })
    $ans = Read-Host ("要先重建網頁版 docs 嗎？封面圖與背景音樂會一起更新（Y/N，直接 Enter = " + $def + "）")
    if (-not $ans) { $ans = $def }
    $doBuild = ($ans -match '^[Yy]')
  }
}
if ($doBuild) {
  Write-Host ""
  Write-Host "重建網頁版 docs…" -ForegroundColor Cyan
  & $buildPs1
  Write-Host ""
}

# --- 把檔案放進索引 ---
#
#  force（強制覆蓋）模式預設會「整個索引砍掉重建」：
#    git rm -r --cached .   ← 只清索引，磁碟上的檔案一個都不會動
#    git add -A             ← 再照磁碟上的真實檔名重新加回來
#
#  為什麼要這麼做：Windows 不分大小寫，Git 也預設 core.ignorecase=true，
#  所以索引裡只要已經有 Fromis9.jpg，你之後 add 小寫的 fromis9.jpg，
#  Git 會判定「同一個路徑」而沿用舊拼法 —— 光靠 add 永遠改不掉大小寫。
#  把索引清空之後就沒有舊拼法可以沿用，每一個檔名（含大小寫）都會照磁碟重寫一次，
#  推上去的 GitHub 就會跟本機一模一樣。
$doReindex = $Reindex -or (($Mode -eq "force") -and (-not $NoReindex))

$beforeFiles = @()
if ($doReindex) {
  $beforeFiles = @((G ls-files).Text -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  Write-Host ""
  Write-Host "重建索引中（檔名含大小寫全部照本機重寫，磁碟上的檔案不會被動到）…" -ForegroundColor Cyan
  G rm -r --cached --quiet -- . | Out-Null
}

G add -A | Out-Null
# docs 一律強制納入版控。就算之後有人在 .gitignore 加了 cover/ 或 bgm/
# 這種沒鎖根目錄的規則，也不會再把 docs\assets\cover、docs\assets\bgm 吃掉。
if (Test-Path -LiteralPath $docsDir) { G add -f -- "docs" | Out-Null }

if ($doReindex) {
  # 比對重建前後，把「只有大小寫變了」的檔案列出來給你看
  $afterFiles = @((G ls-files).Text -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  $afterLower = @{}
  foreach ($a in $afterFiles) { $afterLower[$a.ToLowerInvariant()] = $a }
  $renamed = New-Object System.Collections.ArrayList
  foreach ($b in $beforeFiles) {
    $k = $b.ToLowerInvariant()
    if ($afterLower.ContainsKey($k) -and ($afterLower[$k] -cne $b)) {
      [void]$renamed.Add($b + "  ->  " + $afterLower[$k])
    }
  }
  if ($renamed.Count -gt 0) {
    Write-Host ""
    Write-Host ("檔名大小寫已改成跟本機一致（{0} 個）：" -f $renamed.Count) -ForegroundColor Yellow
    foreach ($line in $renamed) { Write-Host ("   " + $line) -ForegroundColor Yellow }
  } else {
    Write-Host "  索引重建完成，檔名大小寫本來就都一致。" -ForegroundColor DarkGray
  }
} else {
  # 一般存檔：只修「只有大小寫不同」的路徑（在 Windows 改檔名大小寫時 Git 看不見）
  $caseFixed = Repair-GitCase $git $Root @("docs", "app")
  if ($caseFixed.Count -gt 0) {
    Write-Host ""
    Write-Host "修正檔名大小寫（Windows 不分大小寫，Git 之前沒察覺）：" -ForegroundColor Yellow
    foreach ($line in $caseFixed) { Write-Host ("   " + $line) -ForegroundColor Yellow }
  }
}
$changes = @((G diff --cached --name-status).Text -split "`n" | Where-Object { $_ })
if ($changes.Count -eq 0) {
  Write-Host ""
  Write-Host "  沒有任何變更，不需要存檔。" -ForegroundColor DarkGray
  Write-Host ""
  return
}

Write-Host ""
Write-Host "這次的變更：" -ForegroundColor Cyan
foreach ($line in ($changes | Select-Object -First 40)) {
  $parts = $line -split "`t", 2
  $tag = switch ($parts[0].Substring(0, 1)) {
    "A" { "新增" }; "M" { "修改" }; "D" { "刪除" }; "R" { "改名" }; default { $parts[0] }
  }
  Write-Host ("   [" + $tag + "] " + $parts[1])
}
if ($changes.Count -gt 40) { Write-Host ("   …其餘 " + ($changes.Count - 40) + " 個") -ForegroundColor DarkGray }

# 讓你一眼看到網頁版的封面圖與背景音樂到底有沒有被帶上去
$covN = @($changes | Where-Object { $_ -match 'docs/assets/cover/' }).Count
$bgmN = @($changes | Where-Object { $_ -match 'docs/assets/bgm/' }).Count
$trkCov = @((G ls-files -- "docs/assets/cover").Text -split "`n" | Where-Object { $_ }).Count
$trkBgm = @((G ls-files -- "docs/assets/bgm").Text -split "`n" | Where-Object { $_ }).Count
Write-Host ""
Write-Host ("  網頁版封面圖 docs/assets/cover ： 這次異動 {0} 個，版控中共 {1} 個" -f $covN, $trkCov) -ForegroundColor Cyan
Write-Host ("  網頁版背景音樂 docs/assets/bgm ： 這次異動 {0} 個，版控中共 {1} 個" -f $bgmN, $trkBgm) -ForegroundColor Cyan
if ($trkCov -eq 0) {
  Write-Host "  ⚠ 版控裡一張封面圖都沒有 —— 執行一次「建立網頁版.bat」再存檔。" -ForegroundColor Yellow
}

# --- commit 訊息 ---
Write-Host ""
if (-not $Message) {
  $Message = Read-Host "這一版做了什麼？（直接按 Enter 用預設的時間戳記）"
}
if (-not $Message) { $Message = "更新 " + (Get-Date -Format "yyyy-MM-dd HH:mm") }

G commit -m $Message | Out-Null
$hash = (G rev-parse --short HEAD).Text.Trim()
Write-Host ("  ✔ 已存成版本 " + $hash + "：" + $Message) -ForegroundColor Green

# --- 推上去 ---
$rr = G remote get-url origin
$remote = ""
if ($rr.Code -eq 0) { $remote = $rr.Text.Trim() }
if (-not $remote) {
  Write-Host ""
  Write-Host "  還沒連到 GitHub，這一版先存在本機。" -ForegroundColor Yellow
  Write-Host "  執行「Git設定.bat」就能連上去並一次推送全部版本。" -ForegroundColor Yellow
  Write-Host ""
  return
}

if ($Mode -eq "force") {
  Write-Host ""
  Write-Host "用本機版本覆蓋 GitHub…" -ForegroundColor Cyan
  G fetch origin | Out-Null

  # --force-with-lease 比較安全，但它需要本機有 refs/remotes/origin/main 當「租約」，
  # 有些設定（例如 clone 時沒有抓 refspec）根本沒有這支 ref，這時它會直接拒絕。
  # 使用者已經明確說要用本機蓋掉遠端，所以第一次失敗就退回單純的 --force。
  $ok = $false
  $hasRef = ((G rev-parse --verify --quiet "refs/remotes/origin/main").Code -eq 0)
  if ($hasRef) {
    $ok = ((GS push --force-with-lease origin "HEAD:refs/heads/main").Code -eq 0)
    if (-not $ok) {
      Write-Host ""
      Write-Host "  安全模式被擋下來了，改用強制覆蓋…" -ForegroundColor Yellow
    }
  } else {
    Write-Host "  （本機沒有 origin/main 的追蹤紀錄，直接強制覆蓋）" -ForegroundColor DarkGray
  }
  if (-not $ok) { $ok = ((GS push --force origin "HEAD:refs/heads/main").Code -eq 0) }

  if ($ok) {
    Set-Upstream $git $Root "main"
    Write-Host ""
    Write-Host "  ✔ 完成，GitHub 上已經是你本機這份了" -ForegroundColor Green
    Write-Host ("  " + ($remote -replace '\.git$', '') + "/commits") -ForegroundColor Cyan
  } else {
    Write-Host ""
    Write-Host "  覆蓋失敗，請把畫面截圖給我看。" -ForegroundColor Red
    Write-Host "  常見原因：GitHub 帳號沒登入、或該分支開了保護規則。" -ForegroundColor DarkGray
  }
}
elseif ($Mode -eq "rebase") {
  Write-Host ""
  Write-Host "把 GitHub 上的版本接進來再推…" -ForegroundColor Cyan
  $rb = GS pull --rebase origin main
  $ok2 = $false
  if ($rb.Code -eq 0) { $ok2 = ((GS push origin "HEAD:refs/heads/main").Code -eq 0) }
  if ($ok2) {
    Write-Host ""
    Write-Host "  ✔ 完成" -ForegroundColor Green
    Set-Upstream $git $Root "main"
  } else {
    G rebase --abort | Out-Null
    Write-Host "  合併失敗，已還原。改用： Git存檔.bat -Mode force" -ForegroundColor Yellow
  }
}
else {
  $ok = Invoke-SmartPush -GitExe $git -RepoRoot $Root -Branch "main" -AutoYes:$Yes
  if ($ok) {
    Write-Host ("  " + ($remote -replace '\.git$', '') + "/commits") -ForegroundColor Cyan
  } else {
    Write-Host ""
    Write-Host "  這一版已經存在本機不會不見。" -ForegroundColor Yellow
  }
}
Write-Host ""
