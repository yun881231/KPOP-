# =====================================================================
#  KPOP之王巔峰賽 — Git 共用函式
#  由 git_setup.ps1 與 git_save.ps1 共同載入
# =====================================================================
#
#  ── Windows PowerShell 5.1 的地雷（本檔案的設計重點）──────────────
#  只要對原生程式用了 2> 或 2>&1 重導向，PowerShell 就會把 stderr 的
#  每一行包成 ErrorRecord。git 連「Rebasing (1/1)」「fatal: ...」這種
#  訊息都是走 stderr，於是：
#     $ErrorActionPreference = "Stop"  → 整支腳本直接中斷
#     $ErrorActionPreference = "Continue" → 不中斷但畫面噴一大片紅字
#  所以這裡「完全不使用 2> 重導向」，一律透過 Invoke-Git 包裝，
#  在呼叫期間暫時把 ErrorActionPreference 設成 SilentlyContinue，
#  成敗一律用 $LASTEXITCODE 判斷。
# =====================================================================

$ErrorActionPreference = "Continue"

# 執行 git 並取回結果，永遠不會因為 stderr 而中斷或噴紅字。
#   .Code = 結束代碼（0 = 成功）
#   .Text = stdout + stderr 合併後的純文字
function Invoke-Git {
  param(
    [Parameter(Mandatory = $true)][string]$Exe,
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [Parameter(Mandatory = $true)][string[]]$GitArgs,
    [switch]$Show           # 加上這個才把 git 的輸出印到畫面
  )
  $old = $ErrorActionPreference
  $ErrorActionPreference = "SilentlyContinue"
  $lines = & $Exe -C $RepoRoot @GitArgs 2>&1
  $code = $LASTEXITCODE
  $ErrorActionPreference = $old

  $text = ""
  if ($null -ne $lines) {
    $arr = @($lines | ForEach-Object { "$_" })
    $text = ($arr -join "`n")
    if ($Show) { foreach ($l in $arr) { if ($l) { Write-Host ("   " + $l) -ForegroundColor DarkGray } } }
  }
  return [pscustomobject]@{ Code = $code; Text = $text }
}

# 把本機分支跟遠端綁起來。直接寫設定檔，不用 --set-upstream-to，
# 所以遠端追蹤分支還沒建立時也不會失敗。
function Set-Upstream {
  param([string]$GitExe, [string]$RepoRoot, [string]$Branch)
  Invoke-Git $GitExe $RepoRoot @("config", ("branch.$Branch.remote"), "origin") | Out-Null
  Invoke-Git $GitExe $RepoRoot @("config", ("branch.$Branch.merge"), ("refs/heads/" + $Branch)) | Out-Null
}

# 推送到 GitHub，並自動處理「遠端有你本機沒有的東西」造成的拒絕。
# 回傳 $true = 推送成功
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
  $target = "HEAD:refs/heads/" + $Branch

  Write-Host ""
  Write-Host "推送到 GitHub…" -ForegroundColor Cyan
  $r = Invoke-Git $GitExe $RepoRoot @("push", "origin", $target) -Show
  if ($r.Code -eq 0) {
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

  $f = Invoke-Git $GitExe $RepoRoot @("fetch", "origin")
  if ($f.Code -ne 0) {
    Write-Host ""
    Write-Host "連不上 GitHub（網路或登入問題）。" -ForegroundColor Red
    if ($f.Text) { Write-Host $f.Text -ForegroundColor DarkGray }
    Write-Host "這一版已經存在本機不會不見，網路好了再跑一次「Git存檔.bat」即可。" -ForegroundColor Yellow
    return $false
  }

  # 找出遠端分支實際叫什麼（不一定是 main）
  $remoteRef = "origin/" + $Branch
  if ((Invoke-Git $GitExe $RepoRoot @("rev-parse", "--verify", "--quiet", $remoteRef)).Code -ne 0) {
    $h = Invoke-Git $GitExe $RepoRoot @("symbolic-ref", "--quiet", "refs/remotes/origin/HEAD")
    if ($h.Code -eq 0 -and $h.Text) {
      $remoteRef = ($h.Text.Trim() -replace '^refs/remotes/', '')
    } else {
      $b = Invoke-Git $GitExe $RepoRoot @("branch", "-r")
      $first = @($b.Text -split "`n") | Where-Object { $_ -and $_ -notmatch 'HEAD' } | Select-Object -First 1
      if ($first) { $remoteRef = $first.Trim() }
    }
  }

  $lsr = Invoke-Git $GitExe $RepoRoot @("ls-tree", "-r", "--name-only", $remoteRef)
  $remoteFiles = @($lsr.Text -split "`n" | Where-Object { $_ })
  $cnt = Invoke-Git $GitExe $RepoRoot @("rev-list", "--count", $remoteRef)
  $remoteCount = 0
  if ($cnt.Code -eq 0 -and $cnt.Text.Trim() -match '^\d+$') { $remoteCount = [int]$cnt.Text.Trim() }
  $extra = @($remoteFiles | Where-Object { $STARTER -notcontains $_ })

  Write-Host ""
  Write-Host ("GitHub 上目前有 {0} 個版本、{1} 個檔案：" -f $remoteCount, $remoteFiles.Count)
  foreach ($x in ($remoteFiles | Select-Object -First 10)) { Write-Host ("   " + $x) -ForegroundColor DarkGray }
  if ($remoteFiles.Count -gt 10) { Write-Host ("   …其餘 " + ($remoteFiles.Count - 10) + " 個") -ForegroundColor DarkGray }
  Write-Host ""

  # -------------------------------------------------------------------
  # 情況一：遠端只有 GitHub 自動產生的 README（建 repo 時勾了 Add a README）
  # -------------------------------------------------------------------
  if ($remoteCount -le 3 -and $extra.Count -eq 0 -and $remoteFiles.Count -gt 0) {
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
      Write-Host "  Git存檔.bat -Mode rebase" -ForegroundColor Cyan
      return $false
    }
    Write-Host ""
    Write-Host "覆蓋中…" -ForegroundColor Cyan
    $p = Invoke-Git $GitExe $RepoRoot @("push", "--force-with-lease", "origin", $target) -Show
    if ($p.Code -eq 0) {
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
  $rb = Invoke-Git $GitExe $RepoRoot @("pull", "--rebase", "origin", $Branch) -Show
  if ($rb.Code -eq 0) {
    Write-Host ""
    Write-Host "合併成功，重新推送…" -ForegroundColor Cyan
    $p2 = Invoke-Git $GitExe $RepoRoot @("push", "origin", $target) -Show
    if ($p2.Code -eq 0) {
      Set-Upstream $GitExe $RepoRoot $Branch
      Write-Host ""
      Write-Host "  完成。" -ForegroundColor Green
      return $true
    }
  }

  # rebase 卡住 → 還原到動作前的狀態，不要留半套
  Invoke-Git $GitExe $RepoRoot @("rebase", "--abort") | Out-Null
  Write-Host ""
  Write-Host "自動合併失敗（同一個檔案兩邊都改過）。已還原，你的本機版本沒有受影響。" -ForegroundColor Red
  Write-Host ""
  Write-Host "兩個選擇：" -ForegroundColor Yellow
  Write-Host "  1. 用本機版本覆蓋 GitHub（遠端那些改動會不見）：" -ForegroundColor Yellow
  Write-Host "       Git存檔.bat -Mode force" -ForegroundColor Cyan
  Write-Host "  2. 到 GitHub 網頁看看遠端多了什麼，決定要保留哪一邊後再告訴我。" -ForegroundColor Yellow
  return $false
}

# 素材指紋：把所有原始素材的「檔名清單 + 檔案數 + 總大小 + 最新修改時間」
# 壓成一串字。刻意不是只看「最新修改時間」——
# 刪掉一張封面或把 BGM 改名的時候，剩下的檔案時間都沒變，
# 只看時間會誤判成「沒更新」，docs 裡的舊圖舊音樂就永遠推不掉。
function Get-AssetFingerprint([string]$RepoRoot) {
  $dirs = @("封面", "介面音樂")
  Get-ChildItem -LiteralPath $RepoRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "第*關*" } | ForEach-Object { $dirs += $_.Name }

  $count = 0; $bytes = [int64]0; $newest = [int64]0
  $names = New-Object System.Collections.ArrayList
  foreach ($d in $dirs) {
    $full = Join-Path $RepoRoot $d
    if (-not (Test-Path -LiteralPath $full)) { continue }
    foreach ($f in (Get-ChildItem -LiteralPath $full -File -Recurse -ErrorAction SilentlyContinue)) {
      $count++
      $bytes += $f.Length
      $t = $f.LastWriteTimeUtc.Ticks
      if ($t -gt $newest) { $newest = $t }
      [void]$names.Add(($f.FullName.Substring($RepoRoot.Length) -replace '\\', '/'))
    }
  }
  $joined = (($names | Sort-Object) -join "|")
  $md5 = [System.Security.Cryptography.MD5]::Create()
  $hash = [System.BitConverter]::ToString($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($joined))).Replace("-", "")
  return ("v1-{0}-{1}-{2}-{3}" -f $count, $bytes, $newest, $hash)
}

# docs 是不是已經對應到目前的素材？
function Get-AssetStampPath([string]$RepoRoot) { return (Join-Path $RepoRoot "docs\.assets-stamp") }
function Test-WebBuildFresh([string]$RepoRoot) {
  $stamp = Get-AssetStampPath $RepoRoot
  if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot "docs\quiz-data.js"))) { return $false }
  if (-not (Test-Path -LiteralPath $stamp)) { return $false }
  $old = (Get-Content -LiteralPath $stamp -Raw -ErrorAction SilentlyContinue)
  if (-not $old) { return $false }
  return ($old.Trim() -eq (Get-AssetFingerprint $RepoRoot))
}

# ── Windows 的大小寫地雷 ────────────────────────────────────────────
#  Windows 的檔案系統不分大小寫，Git 預設也跟著設 core.ignorecase=true。
#  於是：檔案當初以 Fromis9.jpg 進版控，之後你在磁碟上改成 fromis9.jpg，
#  Git 會認為「這是同一個路徑」→ 完全看不到有變更 → 索引裡永遠留著
#  Fromis9.jpg，推上 GitHub（Linux，分大小寫）也就一直是大寫那一個。
#
#  後果不只是難看：quiz-data.js 指向 cover/fromis9.jpg，
#  GitHub Pages 上卻只有 Fromis9.jpg → 404 → 那張封面變成「找不到圖片」。
#
#  這裡每次存檔都掃一次，把索引裡「只有大小寫不同」的路徑，
#  用 git rm --cached 砍掉舊拼法、再 git add 真正的檔名，讓兩邊對齊。
function Repair-GitCase([string]$GitExe, [string]$RepoRoot, [string[]]$Dirs) {
  $root = (Resolve-Path -LiteralPath $RepoRoot).Path.TrimEnd('\')
  $prefix = $root.Length + 1
  $fixed = New-Object System.Collections.ArrayList

  foreach ($d in $Dirs) {
    $scanDir = Join-Path $root $d
    if (-not (Test-Path -LiteralPath $scanDir)) { continue }

    # 磁碟上的真實檔名（大小寫照抄）
    $real = @{}
    foreach ($f in (Get-ChildItem -LiteralPath $scanDir -File -Recurse -ErrorAction SilentlyContinue)) {
      $rel = ($f.FullName.Substring($prefix) -replace '\\', '/')
      $real[$rel.ToLowerInvariant()] = $rel
    }

    $tracked = @((Invoke-Git $GitExe $RepoRoot @("ls-files", "--", $d)).Text -split "`n" |
                 ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($t in $tracked) {
      $k = $t.ToLowerInvariant()
      if (-not $real.ContainsKey($k)) { continue }   # 檔案真的被刪了 → 交給一般的 git add -A 處理
      $r = $real[$k]
      if ($r -cne $t) {                              # -cne = 區分大小寫的「不等於」
        Invoke-Git $GitExe $RepoRoot @("rm", "--cached", "--quiet", "--", $t) | Out-Null
        Invoke-Git $GitExe $RepoRoot @("add", "-f", "--", $r) | Out-Null
        [void]$fixed.Add(($t + "  ->  " + $r))
      }
    }
  }
  return @($fixed)
}
