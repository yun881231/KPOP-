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

$ErrorActionPreference = "Stop"
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

function Git { & $git -C $Root @args }
function GitQuiet { try { return (& $git -C $Root @args 2>$null) } catch { return $null } }

. (Join-Path $scriptDir "git_common.ps1")

# --- 有什麼變更 ---
Git add -A | Out-Null
$changes = @(Git diff --cached --name-status)
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

Git commit -m $Message | Out-Null
$hash = (Git rev-parse --short HEAD)
Write-Host ("  ✔ 已存成版本 " + $hash + "：" + $Message) -ForegroundColor Green

# --- 推上去 ---
$remote = GitQuiet remote get-url origin
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
  Git fetch origin 2>&1 | Out-Null
  Git push --force-with-lease origin "HEAD:refs/heads/main"
  if ($LASTEXITCODE -eq 0) {
    Git branch --set-upstream-to=origin/main 2>$null | Out-Null
    Write-Host ""
    Write-Host "  ✔ 完成，GitHub 上已經是你本機這份了" -ForegroundColor Green
    Write-Host ("  " + ($remote -replace '\.git$', '') + "/commits") -ForegroundColor Cyan
  } else {
    Write-Host "  覆蓋失敗，請把畫面截圖給我看。" -ForegroundColor Red
  }
}
elseif ($Mode -eq "rebase") {
  Write-Host ""
  Write-Host "把 GitHub 上的版本接進來再推…" -ForegroundColor Cyan
  Git pull --rebase origin main
  if ($LASTEXITCODE -eq 0) { Git push origin "HEAD:refs/heads/main" }
  if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "  ✔ 完成" -ForegroundColor Green
  } else {
    Git rebase --abort 2>&1 | Out-Null
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
