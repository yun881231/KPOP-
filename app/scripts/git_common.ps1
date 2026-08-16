# =====================================================================
#  KPOP之王巔峰賽 — Git 共用函式
#  由 git_setup.ps1 與 git_save.ps1 共同載入
# =====================================================================

# ── Windows PowerShell 5.1 的地雷 ──────────────────────────────────
# $ErrorActionPreference = "Stop" 之下，原生程式（git / ffmpeg / python）
# 只要往 stderr 寫東西就會被當成終止錯誤，整支腳本直接掛掉（NativeCommandError）。
# git 連「Rebasing (1/1)」這種進度訊息都是走 stderr，所以這裡一律用 Continue，
# 改成每一步自己檢查 $LASTEXITCODE；真正需要中斷的 cmdlet 才單獨加 -ErrorAction Stop。
$ErrorActionPreference = "Continue"

# 推送到 GitHub，並自動處理「遠端有你本機沒有的東西」造成的拒絕。
# 回傳 $true = 推送成功
# 綁定 upstream 純粹是方便，遠端追蹤分支還沒建立時不該讓整支腳本掛掉
function Set-Upstream {
  param([string]$GitExe, [string]$RepoRoot, [string]$Branch)
  & $GitExe -C $RepoRoot rev-parse --verify --quiet ("refs/remotes/origin/" + $Branch) 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { return }
  & $GitExe -C $RepoRoot branch --set-upstream-to=("origin/" + $Branch) 2>&1 | Out-Null
}

function Invoke-SmartPush {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$GitExe,
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [string]$Branch = "main",
    [switch]$AutoYes
  )

  $STARTER = @("README.md", "readme.md", "Readme.md", "README", "LICENSE", "LICENSE.md",
               "license", ".gitignore", ".gitattributes", ".gitkeep")

  function _Git { & $GitExe -C $RepoRoot @args }

  Write-Host ""
  Write-Host "推送到 GitHub…" -ForegroundColor Cyan
  _Git push origin ("HEAD:refs/heads/" + $Branch)
  if ($LASTEXITCODE -eq 0) {
    Set-Upstream $GitExe $RepoRoot $Branch
    return $true
  }

  # -------------------------------------------------------------------
  # 被拒絕了，先把遠端抓下來看看到底是什麼狀況
  # -------------------------------------------------------------------
  Write-Host ""
  Write-Host "----------------------------------------------------------" -ForegroundColor Yellow
  Write-Host " 推送被拒絕，正在自動判斷原因…" -ForegroundColor Yellow
  Write-Host "----------------------------------------------------------" -ForegroundColor Yellow

  _Git fetch origin 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "連不上 GitHub（網路或登入問題）。" -ForegroundColor Red
    Write-Host "這一版已經存在本機不會不見，網路好了再跑一次「Git存檔.bat」即可。" -ForegroundColor Yellow
    return $false
  }

  $remoteRef = "origin/" + $Branch
  _Git rev-parse --verify --quiet $remoteRef | Out-Null
  if ($LASTEXITCODE -ne 0) {
    # 遠端分支名不叫 main，找找看實際叫什麼
    $head = (_Git symbolic-ref --quiet refs/remotes/origin/HEAD) 2>$null
    if ($head) { $remoteRef = ($head -replace '^refs/remotes/', '') }
    else {
      $first = @(_Git branch -r) | Where-Object { $_ -notmatch 'HEAD' } | Select-Object -First 1
      if ($first) { $remoteRef = $first.Trim() }
    }
  }

  $remoteFiles = @(_Git ls-tree -r --name-only $remoteRef)
  $remoteCount = 0
  $c = (_Git rev-list --count $remoteRef) 2>$null
  if ($c) { $remoteCount = [int]$c }
  $extra = @($remoteFiles | Where-Object { $STARTER -notcontains $_ })

  Write-Host ""
  Write-Host ("GitHub 上目前有 {0} 個版本、{1} 個檔案：" -f $remoteCount, $remoteFiles.Count)
  foreach ($f in ($remoteFiles | Select-Object -First 10)) { Write-Host ("   " + $f) -ForegroundColor DarkGray }
  if ($remoteFiles.Count -gt 10) { Write-Host ("   …其餘 " + ($remoteFiles.Count - 10) + " 個") -ForegroundColor DarkGray }
  Write-Host ""

  # -------------------------------------------------------------------
  # 情況一：遠端只有 GitHub 自動產生的 README（建 repo 時勾了 Add a README）
  # -------------------------------------------------------------------
  if ($remoteCount -le 3 -and $extra.Count -eq 0) {
    Write-Host "判斷結果：GitHub 上只有建立 repo 時自動產生的起始檔案" -ForegroundColor Green
    Write-Host "（你在建 repo 時勾了「Add a README file」，那個 commit 跟你本機的歷史是分開的）。"
    Write-Host ""
    Write-Host "建議：用你本機這份完整的專案覆蓋掉那個空的 README。" -ForegroundColor Cyan
    Write-Host "你本機的所有版本紀錄都會完整保留，只有 GitHub 上那個自動 README 會被取代。"
    Write-Host ""
    $ans = "Y"
    if (-not $AutoYes) { $ans = Read-Host "要用本機版本覆蓋 GitHub 嗎？(Y/N)" }
    if ($ans -notmatch '^[Yy]') {
      Write-Host ""
      Write-Host "已取消。這一版仍然存在本機。" -ForegroundColor Yellow
      Write-Host "想改成「保留遠端 README 再接上去」的話，執行：" -ForegroundColor Yellow
      Write-Host ("  Git存檔.bat -Mode rebase") -ForegroundColor Cyan
      return $false
    }
    Write-Host ""
    Write-Host "覆蓋中…" -ForegroundColor Cyan
    _Git push --force-with-lease origin ("HEAD:refs/heads/" + $Branch)
    if ($LASTEXITCODE -eq 0) {
      Set-Upstream $GitExe $RepoRoot $Branch
      Write-Host ""
      Write-Host "  完成，GitHub 上已經是你本機這份了。" -ForegroundColor Green
      return $true
    }
    Write-Host "覆蓋失敗，請把畫面截圖給我看。" -ForegroundColor Red
    return $false
  }

  # -------------------------------------------------------------------
  # 情況二：遠端有真的內容 → 先把遠端的接到本機下面再推
  # -------------------------------------------------------------------
  Write-Host "判斷結果：GitHub 上有你本機沒有的真實內容。" -ForegroundColor Yellow
  Write-Host "先把遠端的版本接進來，再把你的新版本疊上去（rebase）。"
  Write-Host ""
  _Git pull --rebase origin $Branch
  if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "合併成功，重新推送…" -ForegroundColor Cyan
    _Git push origin ("HEAD:refs/heads/" + $Branch)
    if ($LASTEXITCODE -eq 0) {
      Set-Upstream $GitExe $RepoRoot $Branch
      Write-Host ""
      Write-Host "  完成。" -ForegroundColor Green
      return $true
    }
  }

  # rebase 卡住 → 還原到動作前的狀態，不要留半套
  _Git rebase --abort 2>&1 | Out-Null
  Write-Host ""
  Write-Host "自動合併失敗（同一個檔案兩邊都改過）。已還原，你的本機版本沒有受影響。" -ForegroundColor Red
  Write-Host ""
  Write-Host "兩個選擇：" -ForegroundColor Yellow
  Write-Host "  1. 用本機版本覆蓋 GitHub（遠端那些改動會不見）：" -ForegroundColor Yellow
  Write-Host "       Git存檔.bat -Mode force" -ForegroundColor Cyan
  Write-Host "  2. 到 GitHub 網頁看看遠端多了什麼，決定要保留哪一邊後再告訴我。" -ForegroundColor Yellow
  return $false
}
