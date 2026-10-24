# eraBACK 更新プログラム（GitHub の Releases から最新版を取り、ゲームのファイルを入れ替える）
# 使い方：配布版のフォルダの「更新.bat」をダブルクリック。
#   このスクリプトは更新.bat が TEMP に写してから実行する（更新中に自分自身を入れ替えても壊れないように）。
# 入れ替えのルール：
#   ・manifest.txt に載っているファイル（ゲーム本体）だけを触る。自分で足したファイル（キャラCSV・口上など）は触らない
#   ・sav/（セーブ）・emuera.config・setting.json・更新.bat は上書きしない
#   ・自分で書き換えたゲーム本体のファイルは、上書きや削除の前に「更新バックアップ/日時/」へ写す
#   ・新しい版から無くなったファイルは消す（古い ERB が残ると関数の重複で起動できなくなるため）
param(
    [string]$Root = '',
    [string]$Repo = 'BluishCat/eraBACK',
    [string]$ZipPath = '',     # テスト用：GitHub を見ず、この zip を最新版として使う
    [switch]$Check,            # 新しい版があるかだけ調べる
    [switch]$DryRun,           # 何をするかだけ出す（何も変えない）
    [switch]$Force,            # 同じ版・古い版でも入れ替える
    [switch]$Yes               # 確認を省く
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
Add-Type -AssemblyName System.IO.Compression.FileSystem

# 上書きしないファイル（遊ぶ人の設定・実行中のバッチ）
$KeepFiles = @('emuera.config', 'setting.json', '更新.bat')

function Say([string]$m) { Write-Host $m }
function Fail([string]$m) { Write-Host ''; Write-Host "[中止] $m" -ForegroundColor Red; exit 1 }
function HashOf([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLower() }
function ReadManifest([string]$p) {
    $d = @{}
    foreach ($line in [IO.File]::ReadAllLines($p, [Text.Encoding]::UTF8)) {
        if ($line.Trim() -eq '') { continue }
        $i = $line.IndexOf('  ')
        if ($i -lt 64) { continue }
        $d[$line.Substring($i + 2)] = $line.Substring(0, $i).ToLower()
    }
    $d
}
function ToVersion([string]$s) {
    $t = $s.Trim().TrimStart('v')
    $m = [regex]::Match($t, '^\d+(\.\d+){0,3}')
    if ($m.Success) { try { return [version]$m.Value } catch {} }
    $null
}

if ($Root -eq '') { $Root = Split-Path -Parent (Split-Path -Parent $PSCommandPath) }
$Root = $Root.TrimEnd('\', '/')
$manifestPath = Join-Path $Root 'manifest.txt'
$versionPath = Join-Path $Root 'version.txt'
if (-not (Test-Path -LiteralPath $manifestPath) -or -not (Test-Path -LiteralPath $versionPath)) {
    Fail "このフォルダは配布版ではありません（manifest.txt・version.txt が無い）。配布版のフォルダで実行してください。`n  （開発用のフォルダを上書きしてしまわないための確認です）"
}
$localVer = ([IO.File]::ReadAllText($versionPath)).Trim()
Say "いまの版：$localVer"

# ゲームが動いていれば止める（exe を入れ替えられない）
$running = Get-Process -ErrorAction SilentlyContinue | Where-Object {
    $_.ProcessName -like 'Emuera*' -and $_.Path -and $_.Path.StartsWith($Root, [StringComparison]::OrdinalIgnoreCase)
}
if ($running -and -not $DryRun -and -not $Check) { Fail 'ゲームが起動中です。閉じてからもう一度実行してください。' }

# 最新版の情報を取る
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('eraBACK_update_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
$zip = Join-Path $tmp 'new.zip'
$remoteVer = ''
$notes = ''
try {
    if ($ZipPath -ne '') {
        Copy-Item -LiteralPath $ZipPath -Destination $zip
        $remoteVer = '(zip 指定)'
    } else {
        Say "GitHub（$Repo）の最新版を調べています…"
        try {
            $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" `
                -Headers @{ 'User-Agent' = 'eraBACK-updater'; 'Accept' = 'application/vnd.github+json' }
        } catch {
            Fail "最新版を調べられませんでした（ネットワークか、まだリリースが無い）。`n  $($_.Exception.Message)"
        }
        $remoteVer = ([string]$rel.tag_name).Trim().TrimStart('v')
        $notes = [string]$rel.body
        $asset = $rel.assets | Where-Object { $_.name -like 'eraBACK*.zip' } | Select-Object -First 1
        if (-not $asset) { Fail "リリース $($rel.tag_name) に eraBACK の zip が付いていません。" }
        Say "最新の版：$remoteVer"
        $lv = ToVersion $localVer; $rv = ToVersion $remoteVer
        $newer = if ($lv -and $rv) { $rv -gt $lv } else { $remoteVer -ne $localVer }
        if (-not $newer -and -not $Force) { Say '最新の版です。更新は要りません。'; exit 0 }
        if ($Check) { Say "新しい版 $remoteVer があります。「更新.bat」で更新できます。"; exit 0 }
        if ($notes.Trim() -ne '') {
            Say ''; Say '--- 更新の内容 ---'
            ($notes -split "`r?`n" | Select-Object -First 25) | ForEach-Object { Say "  $_" }
            Say '------------------'
        }
        if (-not $Yes -and -not $DryRun) {
            $a = Read-Host '更新しますか？ (y/N)'
            if ($a -notmatch '^[yY]') { Say '更新をやめました。'; exit 0 }
        }
        Say 'ダウンロードしています…'
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing -Headers @{ 'User-Agent' = 'eraBACK-updater' }
        if ($asset.digest -and ([string]$asset.digest).StartsWith('sha256:')) {
            $want = ([string]$asset.digest).Substring(7).ToLower()
            if ((HashOf $zip) -ne $want) { Fail 'ダウンロードしたファイルが壊れています（ハッシュが合わない）。もう一度試してください。' }
        }
    }

    # 展開（zip の最上位が1つのフォルダならその中を見る）
    $ex = Join-Path $tmp 'x'
    [IO.Compression.ZipFile]::ExtractToDirectory($zip, $ex)
    $src = $ex
    if (-not (Test-Path -LiteralPath (Join-Path $src 'manifest.txt'))) {
        $subs = @(Get-ChildItem -LiteralPath $ex -Directory)
        if ($subs.Count -eq 1) { $src = $subs[0].FullName }
    }
    $newManifestPath = Join-Path $src 'manifest.txt'
    if (-not (Test-Path -LiteralPath $newManifestPath)) { Fail '新しい版に manifest.txt がありません。' }
    $newVer = ([IO.File]::ReadAllText((Join-Path $src 'version.txt'))).Trim()
    if ($ZipPath -ne '') {
        $lv = ToVersion $localVer; $rv = ToVersion $newVer
        $newer = if ($lv -and $rv) { $rv -gt $lv } else { $newVer -ne $localVer }
        if (-not $newer -and -not $Force) { Say "zip の版（$newVer）はいまの版以下です。更新は要りません。"; exit 0 }
        if (-not $Yes -and -not $DryRun) {
            $a = Read-Host "zip の版 $newVer に更新しますか？ (y/N)"
            if ($a -notmatch '^[yY]') { Say '更新をやめました。'; exit 0 }
        }
    }

    $new = ReadManifest $newManifestPath
    $old = ReadManifest $manifestPath

    # 触る前に、新しい版が壊れていないか確かめる
    foreach ($p in $new.Keys) {
        $f = Join-Path $src ($p -replace '/', '\')
        if (-not (Test-Path -LiteralPath $f)) { Fail "新しい版にファイルが足りません：$p" }
        if ((HashOf $f) -ne $new[$p]) { Fail "新しい版のファイルが壊れています：$p" }
    }

    # 計画を立てる
    $toAdd = @(); $toUpdate = @(); $toBackup = @(); $toRemove = @(); $same = 0; $kept = @()
    foreach ($p in ($new.Keys | Sort-Object)) {
        $dst = Join-Path $Root ($p -replace '/', '\')
        if (-not (Test-Path -LiteralPath $dst)) { $toAdd += $p; continue }
        if ($KeepFiles -contains $p) { $kept += $p; continue }
        $h = HashOf $dst
        if ($h -eq $new[$p]) { $same++; continue }
        if ($old.ContainsKey($p) -and $h -eq $old[$p]) { $toUpdate += $p }
        else { $toUpdate += $p; $toBackup += $p }   # 自分で書き換えたファイル
    }
    foreach ($p in ($old.Keys | Sort-Object)) {
        if ($new.ContainsKey($p) -or ($KeepFiles -contains $p)) { continue }
        $dst = Join-Path $Root ($p -replace '/', '\')
        if (-not (Test-Path -LiteralPath $dst)) { continue }
        $toRemove += $p
        if ((HashOf $dst) -ne $old[$p]) { $toBackup += $p }
    }

    Say ''
    Say "追加 $($toAdd.Count) 件／更新 $($toUpdate.Count) 件／削除 $($toRemove.Count) 件／変更なし $same 件"
    if ($kept.Count -gt 0) { Say "上書きしない設定ファイル：$($kept -join '、')" }
    if ($toBackup.Count -gt 0) { Say "自分で書き換えたファイル $($toBackup.Count) 件は、更新前に「更新バックアップ」へ写します。" }
    if ($DryRun) {
        Say ''; Say '（確認だけ。何も変えていません）'
        foreach ($p in $toAdd) { Say "  + $p" }
        foreach ($p in $toUpdate) { Say ("  ~ $p" + $(if ($toBackup -contains $p) { '（書き換え済み→バックアップ）' } else { '' })) }
        foreach ($p in $toRemove) { Say ("  - $p" + $(if ($toBackup -contains $p) { '（書き換え済み→バックアップ）' } else { '' })) }
        exit 0
    }

    # 入れ替える
    if ($toBackup.Count -gt 0) {
        $bk = Join-Path $Root ('更新バックアップ\' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
        foreach ($p in $toBackup) {
            $from = Join-Path $Root ($p -replace '/', '\')
            $to = Join-Path $bk ($p -replace '/', '\')
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $to) | Out-Null
            Copy-Item -LiteralPath $from -Destination $to -Force
        }
        Say "バックアップ：$bk"
    }
    foreach ($p in ($toAdd + $toUpdate)) {
        $from = Join-Path $src ($p -replace '/', '\')
        $to = Join-Path $Root ($p -replace '/', '\')
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $to) | Out-Null
        Copy-Item -LiteralPath $from -Destination $to -Force
    }
    foreach ($p in $toRemove) {
        $to = Join-Path $Root ($p -replace '/', '\')
        Remove-Item -LiteralPath $to -Force
        # 空になったフォルダを片づける
        $dir = Split-Path -Parent $to
        while ($dir.Length -gt $Root.Length -and (Test-Path -LiteralPath $dir) -and -not (Get-ChildItem -LiteralPath $dir -Force)) {
            Remove-Item -LiteralPath $dir -Force
            $dir = Split-Path -Parent $dir
        }
    }
    Copy-Item -LiteralPath $newManifestPath -Destination $manifestPath -Force
    Copy-Item -LiteralPath (Join-Path $src 'version.txt') -Destination $versionPath -Force
    Say ''
    Say "更新が終わりました：$localVer → $newVer"
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
