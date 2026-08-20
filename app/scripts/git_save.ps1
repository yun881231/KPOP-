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
  [switch]$Yes              # 不要問，直接執行
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

# --- 有什麼變更 ---
G add -A | Out-Null
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
