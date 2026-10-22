param(
  [Parameter(Mandatory = $true)]
  [string]$Path
)

# 对 Windows 可执行文件做 Authenticode 签名。
# 未配置 WINDOWS_CERT_PFX 时直接跳过，不让无证书的构建失败。
# 证书内容用 base64 存，避免 CI 日志/缓存里出现二进制。

$ErrorActionPreference = 'Stop'

$pfxBase64 = $env:WINDOWS_CERT_PFX
if ([string]::IsNullOrWhiteSpace($pfxBase64)) {
  Write-Host '未配置 WINDOWS_CERT_PFX，跳过代码签名。'
  exit 0
}

function Find-SignTool {
  $cmd = Get-Command 'signtool.exe' -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $kits = 'C:\Program Files (x86)\Windows Kits\10\bin'
  if (Test-Path $kits) {
    $hit = Get-ChildItem $kits -Recurse -Filter 'signtool.exe' -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -match '\\x64\\' } |
      Sort-Object -Property FullName -Descending |
      Select-Object -First 1
    if ($hit) { return $hit.FullName }
  }
  throw '找不到 signtool.exe（需要安装 Windows SDK Build Tools）'
}

$targets = @()
foreach ($p in $Path.Split(';')) {
  if ([string]::IsNullOrWhiteSpace($p)) { continue }
  if (Test-Path -LiteralPath $p -PathType Leaf) {
    $targets += (Resolve-Path -LiteralPath $p).Path
  } else {
    $targets += @(Get-ChildItem -Path $p -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
  }
}
if ($targets.Count -eq 0) { throw "没有匹配到待签名文件：$Path" }

$signtool = Find-SignTool
Write-Host "signtool: $signtool"

$pfxPath = Join-Path $env:RUNNER_TEMP 'afrp-sign.pfx'
try {
  [IO.File]::WriteAllBytes($pfxPath, [Convert]::FromBase64String(($pfxBase64 -replace '\s', '')))

  $signArgs = @('sign', '/tr', 'http://timestamp.digicert.com', '/td', 'sha256', '/fd', 'sha256', '/f', $pfxPath)
  $pwd = $env:WINDOWS_CERT_PWD
  if (-not [string]::IsNullOrEmpty($pwd)) { $signArgs += @('/p', $pwd) }

  foreach ($f in $targets) {
    Write-Host "签名: $f"
    & $signtool @signArgs $f
    if ($LASTEXITCODE -ne 0) { throw "签名失败($LASTEXITCODE)：$f" }
    $sig = Get-AuthenticodeSignature -FilePath $f
    Write-Host "  签名状态: $($sig.Status) / $($sig.SignerCertificate.Subject)"
    if ($sig.Status -ne 'Valid') { throw "签名校验未通过：$f -> $($sig.Status)" }
  }
} finally {
  Remove-Item $pfxPath -Force -ErrorAction SilentlyContinue
}
