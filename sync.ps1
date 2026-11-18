# 自动同步检查 + 一键回归
# 用法:
#   .\sync.ps1            检查同步状态 + 跑全部测试
#   .\sync.ps1 -Pull      先拉取远端再检查
#   .\sync.ps1 -Quick     只检查同步状态，不跑测试

param(
    [switch]$Pull,
    [switch]$Quick
)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$GODOT = "F:\Migrated\Desktop\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"

function Write-Head($text) {
    Write-Host ""
    Write-Host "==== $text ====" -ForegroundColor Cyan
}

function Fail($text) {
    Write-Host "  [失败] $text" -ForegroundColor Red
    $script:failed++
}

function Ok($text) {
    Write-Host "  [OK] $text" -ForegroundColor Green
}

$failed = 0

# ============================================================
Write-Head "1. Git 状态检查"

$branch = (git rev-parse --abbrev-ref HEAD 2>$null)
Write-Host "  当前分支: $branch"

# 未提交改动
$dirty = git status --porcelain
if (-not [string]::IsNullOrWhiteSpace($dirty)) {
    Write-Host "  有未提交的改动:" -ForegroundColor Yellow
    $dirty -split "`n" | Where-Object { $_ -ne '' } | Select-Object -First 15 | ForEach-Object {
        Write-Host "    $_"
    }
    $count = ($dirty -split "`n" | Where-Object { $_ -ne '' }).Count
    Write-Host "    共 $count 个文件" -ForegroundColor Yellow
} else {
    Ok "工作区干净"
}

# 是否有冲突标记残留
$conflictFiles = @()
Get-ChildItem -Path $root -Recurse -Include *.gd,*.json,*.md -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\\.godot\\' -and $_.FullName -notmatch '\\assets\\' } |
    ForEach-Object {
        $c = Select-String -Path $_.FullName -Pattern '^<<<<<<< ' -List -ErrorAction SilentlyContinue
        if ($c) { $conflictFiles += $_.FullName.Replace($root + '\', '') }
    }
if ($conflictFiles.Count -gt 0) {
    Fail "发现未解决的冲突标记:"
    $conflictFiles | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
} else {
    Ok "无冲突标记残留"
}

# ============================================================
Write-Head "2. 与远端同步"

git fetch origin 2>&1 | Out-Null

$local = git rev-parse HEAD 2>$null
$remote = git rev-parse origin/main 2>$null

if (-not $remote) {
    Fail "无法获取远端（检查网络或 remote 配置）"
} elseif ($local -eq $remote) {
    Ok "本地与远端一致 ($($local.Substring(0,7)))"
} else {
    # 落后多少
    $behind = git rev-list --count "HEAD..origin/main" 2>$null
    $ahead = git rev-list --count "origin/main..HEAD" 2>$null
    if ([int]$behind -gt 0 -and [int]$ahead -gt 0) {
        Fail "已分叉：落后 $behind 个提交，领先 $ahead 个提交"
        Write-Host "    建议：先 git pull --rebase origin main 再继续" -ForegroundColor Yellow
    } elseif ([int]$behind -gt 0) {
        Write-Host "  [注意] 落后远端 $behind 个提交" -ForegroundColor Yellow
        if ($Pull) {
            Write-Host "    正在拉取..." -ForegroundColor Yellow
            git pull --ff-only origin main 2>&1 | ForEach-Object { Write-Host "    $_" }
            if ($LASTEXITCODE -ne 0) {
                Fail "拉取失败（可能需要手动合并）"
            } else {
                Ok "已拉取到最新"
            }
        } else {
            Write-Host "    运行 .\sync.ps1 -Pull 可自动拉取" -ForegroundColor Yellow
        }
    } elseif ([int]$ahead -gt 0) {
        Write-Host "  [注意] 领先远端 $ahead 个提交（记得 push）" -ForegroundColor Yellow
        git log --oneline "origin/main..HEAD" | Select-Object -First 5 | ForEach-Object {
            Write-Host "    $_"
        }
    }
}

if ($Quick) {
    Write-Head "完成（-Quick 模式跳过测试）"
    if ($failed -gt 0) { exit 1 }
    exit 0
}

# ============================================================
Write-Head "3. 代码解析检查"

if (-not (Test-Path $GODOT)) {
    Fail "找不到 Godot 引擎: $GODOT"
} else {
    $scripts = @(
        "res://scripts/core/rules.gd",
        "res://scripts/core/ed_data.gd",
        "res://scripts/core/ed_battle.gd",
        "res://scripts/ui/editor.gd"
    )
    foreach ($s in $scripts) {
        $out = & $GODOT --headless --path $root --check-only --script $s 2>&1 | Out-String
        if ($out -match 'Parse Error') {
            Fail "$s 解析失败"
            ($out -split "`n" | Select-String 'Parse Error' | Select-Object -First 2) | ForEach-Object {
                Write-Host "      $($_.Line.Trim())" -ForegroundColor Red
            }
        } else {
            Ok "$s"
        }
    }
}

# ============================================================
Write-Head "4. 回归测试"

if (Test-Path $GODOT) {
    & $GODOT --headless --path $root --import *> $null 2>&1

    $tests = Get-ChildItem "$root\tools\test_*.gd" | ForEach-Object { $_.BaseName }
    Write-Host "  共 $($tests.Count) 个测试" -ForegroundColor Gray

    $logDir = Join-Path $env:TEMP "wujiang_sync"
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null

    foreach ($t in $tests) {
        $log = Join-Path $logDir "$t.log"
        $err = Join-Path $logDir "$t.err"
        $proc = Start-Process -FilePath $GODOT `
            -ArgumentList @('--headless', '--path', $root, '--script', "res://tools/$t.gd") `
            -RedirectStandardOutput $log -RedirectStandardError $err `
            -NoNewWindow -PassThru
        if (-not $proc.WaitForExit(90000)) {
            $proc.Kill()
            Fail "$t 超时"
            continue
        }
        $logText = if (Test-Path $log) { Get-Content $log -Encoding UTF8 } else { @() }
        $errText = if (Test-Path $err) { Get-Content $err -Encoding UTF8 } else { @() }

        $failCount = ($logText | Select-String -Pattern '✖' | Measure-Object).Count
        $scriptErrors = ($errText | Select-String -Pattern 'SCRIPT ERROR' | Measure-Object).Count

        if ($failCount -gt 0) {
            Fail "$t : $failCount 项失败"
            ($logText | Select-String -Pattern '✖' | Select-Object -First 3) | ForEach-Object {
                Write-Host "      $($_.Line.Trim())" -ForegroundColor Red
            }
        } elseif ($scriptErrors -gt 0) {
            Fail "$t : $scriptErrors 个脚本错误"
        } else {
            Ok "$t"
        }
    }

    Write-Host ""
    Write-Host "  详细日志: $logDir" -ForegroundColor Gray
}

# ============================================================
Write-Head "结果"
if ($failed -gt 0) {
    Write-Host "  有 $failed 项失败，请检查" -ForegroundColor Red
    exit 1
} else {
    Write-Host "  全部通过 ✓" -ForegroundColor Green
    exit 0
}
