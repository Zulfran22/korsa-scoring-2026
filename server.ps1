<#
KORSA 2026 - server sync lokal (zero-install)

Menyajikan korsa-scoring-2026.html lewat HTTP dan menyimpan state skor di
memori + file korsa-state.json, supaya admin dan display bisa dibuka dari
DUA PERANGKAT BERBEDA selama satu jaringan WiFi/LAN.

Cara pakai:
  1. Taruh file ini di folder yang sama dengan korsa-scoring-2026.html.
  2. Jalankan:  powershell -ExecutionPolicy Bypass -File .\server.ps1
  3. Biarkan jendela ini tetap terbuka. Alamat yang tampil di layar
     dibuka di browser admin MAUPUN browser display - bukan file:// lagi.
  4. Kalau muncul prompt Windows Firewall, klik "Allow access" (jaringan
     Private/Domain) supaya perangkat lain bisa terhubung.

Tidak butuh Node/Python/instalasi apa pun - hanya .NET bawaan Windows.
#>

param(
  [int]$Port = 8080
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$htmlPath = Join-Path $root 'korsa-scoring-2026.html'
$statePath = Join-Path $root 'korsa-state.json'

if (-not (Test-Path $htmlPath)) {
  Write-Error "korsa-scoring-2026.html tidak ditemukan di $root - taruh server.ps1 di folder yang sama."
  exit 1
}

$state = '{}'
if (Test-Path $statePath) {
  try { $state = [System.IO.File]::ReadAllText($statePath, [System.Text.Encoding]::UTF8) } catch {}
}

function Read-Line {
  param($Stream)
  $bytes = New-Object System.Collections.Generic.List[byte]
  while ($true) {
    $b = $Stream.ReadByte()
    if ($b -eq -1) { break }
    if ($b -eq 10) { break }        # \n
    if ($b -ne 13) { $bytes.Add([byte]$b) }  # buang \r
  }
  return [System.Text.Encoding]::ASCII.GetString($bytes.ToArray())
}

function Read-Exact {
  param($Stream, [int]$Count)
  $buf = New-Object byte[] $Count
  $read = 0
  while ($read -lt $Count) {
    $n = $Stream.Read($buf, $read, $Count - $read)
    if ($n -le 0) { break }
    $read += $n
  }
  return $buf
}

function Send-Response {
  param($Stream, [string]$Status, [string]$ContentType, [byte[]]$BodyBytes)
  if ($null -eq $BodyBytes) { $BodyBytes = [byte[]]@() }
  $head = "HTTP/1.1 $Status`r`nContent-Type: $ContentType`r`nContent-Length: $($BodyBytes.Length)`r`nConnection: close`r`nAccess-Control-Allow-Origin: *`r`n`r`n"
  $headBytes = [System.Text.Encoding]::ASCII.GetBytes($head)
  $Stream.Write($headBytes, 0, $headBytes.Length)
  if ($BodyBytes.Length -gt 0) { $Stream.Write($BodyBytes, 0, $BodyBytes.Length) }
  $Stream.Flush()
}

$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $Port)
$listener.Start()

$hostName = [System.Net.Dns]::GetHostName()
$ips = [System.Net.Dns]::GetHostAddresses($hostName) | Where-Object { $_.AddressFamily -eq 'InterNetwork' }

Write-Host "=== KORSA 2026 sync server ===" -ForegroundColor Cyan
Write-Host "Buka salah satu alamat ini di browser ADMIN dan browser DISPLAY (perangkat lain, WiFi/LAN yang sama):"
foreach ($ip in $ips) { Write-Host ("  http://{0}:{1}/" -f $ip.IPAddressToString, $Port) -ForegroundColor Green }
Write-Host "Jangan pakai file:// lagi selama pakai server ini."
Write-Host "Biarkan jendela ini tetap terbuka selama acara. Tekan Ctrl+C untuk berhenti.`n"

while ($true) {
  $client = $listener.AcceptTcpClient()
  try {
    $client.NoDelay = $true
    $stream = $client.GetStream()
    $requestLine = Read-Line $stream
    if ([string]::IsNullOrEmpty($requestLine)) { continue }
    $parts = $requestLine -split ' '
    $method = $parts[0]
    $urlPath = $parts[1]

    $headers = @{}
    while ($true) {
      $line = Read-Line $stream
      if ([string]::IsNullOrEmpty($line)) { break }
      $idx = $line.IndexOf(':')
      if ($idx -gt 0) { $headers[$line.Substring(0, $idx).Trim().ToLower()] = $line.Substring($idx + 1).Trim() }
    }

    $bodyBytes = [byte[]]@()
    if ($headers.ContainsKey('content-length')) {
      $len = [int]$headers['content-length']
      if ($len -gt 0 -and $len -lt 2097152) { $bodyBytes = Read-Exact $stream $len }
    }

    if ($urlPath -eq '/api/state' -and $method -eq 'GET') {
      Send-Response $stream '200 OK' 'application/json; charset=utf-8' ([System.Text.Encoding]::UTF8.GetBytes($state))
    }
    elseif ($urlPath -eq '/api/state' -and $method -eq 'POST') {
      $bodyText = [System.Text.Encoding]::UTF8.GetString($bodyBytes)
      try {
        $null = $bodyText | ConvertFrom-Json
        $state = $bodyText
        [System.IO.File]::WriteAllText($statePath, $state, [System.Text.Encoding]::UTF8)
        Send-Response $stream '204 No Content' 'application/json' $null
      } catch {
        Send-Response $stream '400 Bad Request' 'text/plain' ([System.Text.Encoding]::UTF8.GetBytes('bad json'))
      }
    }
    elseif ($method -eq 'GET' -and ($urlPath -eq '/' -or $urlPath -eq '/korsa-scoring-2026.html')) {
      $htmlBytes = [System.IO.File]::ReadAllBytes($htmlPath)
      Send-Response $stream '200 OK' 'text/html; charset=utf-8' $htmlBytes
    }
    else {
      Send-Response $stream '404 Not Found' 'text/plain' ([System.Text.Encoding]::UTF8.GetBytes('Not found'))
    }
  } catch {
    Write-Warning "Request error: $_"
  } finally {
    $client.Close()
  }
}
