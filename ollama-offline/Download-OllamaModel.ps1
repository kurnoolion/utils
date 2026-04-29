<#
.SYNOPSIS
  Download GGUF model files from a HuggingFace repo by quantization.

.DESCRIPTION
  Given a HuggingFace repo URL (or "<user>/<repo>" id) and a quantization tag
  (e.g. Q8_0), lists the GGUF files in the repo, picks the matching ones
  (handles sharded files like *-00001-of-00003.gguf), and downloads them to
  a local directory.

  Designed to work from environments where 'ollama pull' is blocked but plain
  HTTPS to huggingface.co works.

.PARAMETER RepoUrl
  HuggingFace repo. Either a full URL like
    https://huggingface.co/Qwen/Qwen3-Embedding-4B-GGUF
  or just the id:
    Qwen/Qwen3-Embedding-4B-GGUF

.PARAMETER Quant
  Quantization tag, e.g. Q8_0, Q4_K_M, Q5_K_M, Q6_K, F16, BF16.
  Case-insensitive. Matches files containing that token before .gguf.

.PARAMETER OutputPath
  Local directory to download files into. Created if missing.

.PARAMETER Branch
  Git branch / revision in the HF repo. Default: main.

.PARAMETER ListOnly
  Only list matched files; do not download.

.EXAMPLE
  .\Download-OllamaModel.ps1 `
    -RepoUrl https://huggingface.co/Qwen/Qwen3-Embedding-4B-GGUF `
    -Quant Q8_0 `
    -OutputPath C:\models\qwen3-embedding-4b
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)] [string] $RepoUrl,
    [Parameter(Mandatory=$true)] [string] $Quant,
    [Parameter(Mandatory=$true)] [string] $OutputPath,
    [string] $Branch = 'main',
    [switch] $ListOnly
)

$ErrorActionPreference = 'Stop'

function Get-RepoId {
    param([Parameter(Mandatory=$true)][string] $Url)
    # Strip protocol and trailing /tree|/blob/...
    $clean = $Url -replace '^https?://(www\.)?huggingface\.co/', ''
    $clean = $clean -replace '/(tree|blob|resolve)/.*$', ''
    $clean = $clean.TrimEnd('/')
    if ($clean -notmatch '^[^/]+/[^/]+$') {
        throw "Could not parse '<user>/<repo>' from '$Url'."
    }
    return $clean
}

function Get-RepoFileList {
    param(
        [Parameter(Mandatory=$true)][string] $RepoId,
        [Parameter(Mandatory=$true)][string] $Branch
    )
    $api = "https://huggingface.co/api/models/$RepoId/tree/$Branch"
    try {
        $resp = Invoke-RestMethod -Uri $api -Method Get -ErrorAction Stop
    } catch {
        throw "Failed to list files at $api : $($_.Exception.Message)"
    }
    return @($resp | Where-Object { $_.type -eq 'file' })
}

function Select-QuantFiles {
    param(
        [Parameter(Mandatory=$true)][object[]] $Files,
        [Parameter(Mandatory=$true)][string]   $Quant
    )
    $ggufFiles = @($Files | Where-Object { $_.path -match '\.gguf$' })
    if ($ggufFiles.Count -eq 0) { return @() }

    $q = [regex]::Escape($Quant)
    # Match "<...>-Q8_0.gguf" OR "<...>-Q8_0-00001-of-00003.gguf" OR "<...>.Q8_0.gguf"
    $pattern = "(?i)[._-]$q(\.gguf|-\d+-of-\d+\.gguf)$"

    $matched = @($ggufFiles | Where-Object { $_.path -match $pattern })

    # Sort sharded files in numeric order so multi-part downloads are deterministic
    return @($matched | Sort-Object -Property path)
}

function Save-RepoFile {
    param(
        [Parameter(Mandatory=$true)][string] $RepoId,
        [Parameter(Mandatory=$true)][string] $Branch,
        [Parameter(Mandatory=$true)][string] $Filename,
        [Parameter(Mandatory=$true)][long]   $ExpectedSize,
        [Parameter(Mandatory=$true)][string] $OutputPath
    )
    $url  = "https://huggingface.co/$RepoId/resolve/$Branch/$Filename"
    $dest = Join-Path $OutputPath (Split-Path -Leaf $Filename)

    if (Test-Path $dest) {
        $existingSize = (Get-Item $dest).Length
        if ($existingSize -eq $ExpectedSize) {
            Write-Host "  [skip] $Filename already complete ($existingSize bytes)"
            return
        } else {
            Write-Host "  [redo] $Filename size mismatch (have $existingSize, want $ExpectedSize)"
            Remove-Item $dest -Force
        }
    }

    Write-Host "  [get ] $Filename ($ExpectedSize bytes)"

    # Prefer curl.exe (resumable, real progress bar) when available; else Invoke-WebRequest.
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        & curl.exe -L --fail --retry 3 --retry-delay 2 -o $dest --progress-bar $url
        if ($LASTEXITCODE -ne 0) { throw "curl.exe failed (exit $LASTEXITCODE) for $Filename" }
    } else {
        $oldPref = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'   # IWR is much faster without the progress UI
        try {
            Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
        } finally {
            $ProgressPreference = $oldPref
        }
    }

    $actualSize = (Get-Item $dest).Length
    if ($actualSize -ne $ExpectedSize) {
        throw "Download size mismatch for $Filename : got $actualSize, expected $ExpectedSize"
    }
}

# ------------ main ------------

$RepoId = Get-RepoId -Url $RepoUrl
Write-Host "Repo:    $RepoId"
Write-Host "Branch:  $Branch"
Write-Host "Quant:   $Quant"
Write-Host "Output:  $OutputPath"

if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

Write-Host "Listing files via HF API..."
$files = Get-RepoFileList -RepoId $RepoId -Branch $Branch
$ggufFiles = @($files | Where-Object { $_.path -match '\.gguf$' })
if ($ggufFiles.Count -eq 0) {
    $hint = ""
    if ($RepoId -notmatch '(?i)gguf$') {
        $hint = " (try '$RepoId-GGUF' — many HF repos publish GGUFs in a sibling repo)"
    }
    throw "No .gguf files in $RepoId@$Branch.$hint"
}

Write-Host "GGUF files in repo:"
$ggufFiles | ForEach-Object { Write-Host ("  - {0}  ({1} bytes)" -f $_.path, $_.size) }

$matched = Select-QuantFiles -Files $files -Quant $Quant
if ($matched.Count -eq 0) {
    $available = ($ggufFiles | ForEach-Object { $_.path }) -join ', '
    throw "No GGUF files match quant '$Quant'. Available: $available"
}

Write-Host "Matched for quant '$Quant':"
$matched | ForEach-Object { Write-Host ("  - {0}  ({1} bytes)" -f $_.path, $_.size) }

if ($ListOnly) {
    return
}

foreach ($f in $matched) {
    Save-RepoFile -RepoId $RepoId -Branch $Branch -Filename $f.path -ExpectedSize ([long]$f.size) -OutputPath $OutputPath
}

Write-Host ""
Write-Host "Done. Files in: $OutputPath"
Write-Host "Next: copy to your Linux box and run install-ollama-model.sh"
