# eraBACK キャラ作成ツールの小さなサーバー（このパソコンの中だけで動く）
# 使い方：配布版のフォルダの「キャラ作成.bat」をダブルクリック。ブラウザが開き、ゲームのフォルダを相対パスで読み書きする。
#   ・127.0.0.1（このパソコン）からの接続だけ受ける。起動のたびに合言葉を変え、合言葉が無い API は断る
#   ・書ける場所は CSV/chara/（.csv）と ERB/口上/（.ERB の新しいフォルダ）だけ。.. や絶対パスは断る
#   ・このウィンドウを閉じるとサーバーも止まる
param(
    [string]$Root = '',
    [int]$Port = 0,        # 0 なら空いているポートを選ぶ
    [switch]$NoOpen        # ブラウザを開かない（試験用）
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
if ($Root -eq '') { $Root = Split-Path -Parent $PSScriptRoot }
$Root = [IO.Path]::GetFullPath($Root).TrimEnd('\')
$CharaDir = Join-Path $Root 'CSV\chara'
$KojoDir = Join-Path $Root 'ERB\口上'
$HtmlPath = Join-Path $Root 'キャラ作成.html'
$Utf8Bom = New-Object System.Text.UTF8Encoding($true)
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$MaxBody = 5MB

function Fail([string]$m) { Write-Host ''; Write-Host "[中止] $m" -ForegroundColor Red; exit 1 }
if (-not (Test-Path -LiteralPath $CharaDir)) { Fail "CSV\chara が見つかりません：$Root" }
if (-not (Test-Path -LiteralPath $HtmlPath)) { Fail "キャラ作成.html が見つかりません：$Root" }

# 待ち受け（127.0.0.1 だけ）
$listener = $null
for ($i = 0; $i -lt 30 -and $null -eq $listener; $i++) {
    $p = if ($Port -gt 0) { $Port } else { Get-Random -Minimum 49152 -Maximum 65000 }
    $l = New-Object System.Net.HttpListener
    $l.Prefixes.Add("http://127.0.0.1:$p/")
    try { $l.Start(); $listener = $l; $Port = $p } catch { $l.Close(); if ($Port -gt 0) { break } }
}
if ($null -eq $listener) { Fail '待ち受けを始められませんでした（ポートが使えません）' }
$Token = [guid]::NewGuid().ToString('N')
$Url = "http://127.0.0.1:$Port/?t=$Token"

function Send($ctx, [int]$code, [string]$body, [string]$type) {
    if ($type -eq '') { $type = 'application/json; charset=utf-8' }
    $bytes = $Utf8.GetBytes($body)
    $ctx.Response.StatusCode = $code
    $ctx.Response.ContentType = $type
    $ctx.Response.ContentLength64 = $bytes.Length
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $ctx.Response.OutputStream.Close()
}
function Json($o) { ConvertTo-Json -InputObject $o -Depth 6 -Compress }

# 基準のフォルダの下に収まる相対パスだけ通す
function SafePath([string]$base, [string]$rel) {
    if ([string]::IsNullOrWhiteSpace($rel)) { return $null }
    if ($rel -match '[:*?"<>|]' -or $rel.StartsWith('/') -or $rel.StartsWith('\')) { return $null }
    $parts = $rel -split '[\\/]'
    foreach ($q in $parts) {
        if ($q -eq '' -or $q -eq '.' -or $q -eq '..' -or $q.EndsWith('.') -or $q.EndsWith(' ')) { return $null }
    }
    $full = [IO.Path]::GetFullPath((Join-Path $base ($parts -join '\')))
    if (-not $full.StartsWith($base + '\', [StringComparison]::OrdinalIgnoreCase)) { return $null }
    return $full
}

function ReadBody($ctx) {
    if ($ctx.Request.ContentLength64 -gt $MaxBody) { throw '大きすぎます' }
    $sr = New-Object IO.StreamReader($ctx.Request.InputStream, $Utf8)
    $raw = $sr.ReadToEnd()
    if ($raw -eq '') { return $null }
    return ($raw | ConvertFrom-Json)
}

function Handle($ctx) {
    $req = $ctx.Request
    # 他のサイトからの横取り（DNS の付け替え）を防ぐ：Host がこのサーバー自身であること
    if ($req.Headers['Host'] -ne "127.0.0.1:$Port") { Send $ctx 403 'forbidden' 'text/plain; charset=utf-8'; return }
    $path = $req.Url.AbsolutePath
    $method = $req.HttpMethod

    if ($method -eq 'GET' -and ($path -eq '/' -or $path -eq '/index.html')) {
        Send $ctx 200 ([IO.File]::ReadAllText($HtmlPath, $Utf8)) 'text/html; charset=utf-8'
        return
    }
    if (-not $path.StartsWith('/api/')) { Send $ctx 404 'not found' 'text/plain; charset=utf-8'; return }
    if ($req.Headers['X-Token'] -ne $Token) { Send $ctx 403 'forbidden' 'text/plain; charset=utf-8'; return }

    if ($method -eq 'GET' -and $path -eq '/api/info') {
        Send $ctx 200 (Json @{ name = (Split-Path -Leaf $Root) }) ''
        return
    }
    if ($method -eq 'GET' -and $path -eq '/api/chara') {
        $list = @()
        $baseLen = $CharaDir.Length + 1
        foreach ($f in (Get-ChildItem -LiteralPath $CharaDir -Recurse -File -Filter '*.csv')) {
            $list += @{ path = $f.FullName.Substring($baseLen).Replace('\', '/'); text = [IO.File]::ReadAllText($f.FullName, $Utf8) }
        }
        Send $ctx 200 (Json @($list)) ''
        return
    }
    if ($method -eq 'POST' -and $path -eq '/api/chara') {
        $b = ReadBody $ctx
        $full = SafePath $CharaDir ([string]$b.path)
        if ($null -eq $full -or -not $full.EndsWith('.csv', [StringComparison]::OrdinalIgnoreCase)) { Send $ctx 400 '保存先が不正です' 'text/plain; charset=utf-8'; return }
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($full)) | Out-Null
        [IO.File]::WriteAllText($full, [string]$b.text, $Utf8Bom)
        Write-Host ('保存：CSV/chara/' + $b.path)
        Send $ctx 200 (Json @{ ok = $true }) ''
        return
    }
    if ($method -eq 'POST' -and $path -eq '/api/chara/delete') {
        $b = ReadBody $ctx
        $full = SafePath $CharaDir ([string]$b.path)
        if ($null -eq $full -or -not $full.EndsWith('.csv', [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $full -PathType Leaf)) { Send $ctx 400 '消す対象が不正です' 'text/plain; charset=utf-8'; return }
        Remove-Item -LiteralPath $full
        Write-Host ('削除：CSV/chara/' + $b.path)
        Send $ctx 200 (Json @{ ok = $true }) ''
        return
    }
    if ($method -eq 'POST' -and $path -eq '/api/kojo') {
        $b = ReadBody $ctx
        $folder = [string]$b.folder
        if ($folder -match '[\\/]') { Send $ctx 400 'フォルダ名が不正です' 'text/plain; charset=utf-8'; return }
        [IO.Directory]::CreateDirectory($KojoDir) | Out-Null
        $dir = SafePath $KojoDir $folder
        if ($null -eq $dir) { Send $ctx 400 'フォルダ名が不正です' 'text/plain; charset=utf-8'; return }
        if (Test-Path -LiteralPath $dir) { Send $ctx 200 (Json @{ exists = $true }) ''; return }
        # 先に全部の名前を確かめてから書く（途中で止まって中途半端なフォルダを残さない）
        $items = @($b.files.PSObject.Properties)
        foreach ($it in $items) {
            if ($it.Name -notmatch '^[^\\/:*?"<>|]+\.ERB$' -or $it.Name -match '^\.') { Send $ctx 400 'ファイル名が不正です' 'text/plain; charset=utf-8'; return }
        }
        [IO.Directory]::CreateDirectory($dir) | Out-Null
        foreach ($it in $items) { [IO.File]::WriteAllText((Join-Path $dir $it.Name), [string]$it.Value, $Utf8Bom) }
        Write-Host ('口上テンプレート：ERB/口上/' + $folder)
        Send $ctx 200 (Json @{ exists = $false }) ''
        return
    }
    Send $ctx 404 'not found' 'text/plain; charset=utf-8'
}

Write-Host 'eraBACK キャラ作成ツール'
Write-Host "  ゲームのフォルダ：$Root"
Write-Host "  アドレス：$Url"
Write-Host '  ブラウザが開きます。開かないときは上のアドレスを貼ってください。'
Write-Host '  このウィンドウを閉じるとツールも止まります。'
Write-Host ''
if (-not $NoOpen) { Start-Process $Url }

try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        try { Handle $ctx }
        catch {
            Write-Host ('エラー：' + $_.Exception.Message) -ForegroundColor Red
            try { Send $ctx 500 $_.Exception.Message 'text/plain; charset=utf-8' } catch {}
        }
    }
} finally {
    $listener.Close()
}
