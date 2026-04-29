<#
.SYNOPSIS
  Tests for Download-OllamaModel.ps1. No external dependencies (no Pester).

.DESCRIPTION
  Run on the work PC:
    .\Test-DownloadOllamaModel.ps1
  Optional integration test that hits the real HuggingFace API:
    .\Test-DownloadOllamaModel.ps1 -Online
#>
[CmdletBinding()]
param(
    [switch] $Online
)

$ErrorActionPreference = 'Stop'

# Dot-source the script under test so its functions are in scope.
$scriptUnderTest = Join-Path $PSScriptRoot 'Download-OllamaModel.ps1'
if (-not (Test-Path $scriptUnderTest)) {
    throw "Cannot find $scriptUnderTest"
}

# Importing requires bypassing param() — extract function definitions only.
$content   = Get-Content -Raw $scriptUnderTest
$startIdx  = $content.IndexOf('function Get-RepoId')
$endMarker = '# ------------ main ------------'
$endIdx    = $content.IndexOf($endMarker)
if ($startIdx -lt 0 -or $endIdx -lt 0) { throw "Could not locate function block in $scriptUnderTest" }
$funcBlock = $content.Substring($startIdx, $endIdx - $startIdx)
Invoke-Expression $funcBlock

$script:Pass = 0
$script:Fail = 0

function Assert-Equal {
    param($Expected, $Actual, [string]$Name)
    if ($Expected -eq $Actual) {
        $script:Pass++
        Write-Host "  PASS  $Name"
    } else {
        $script:Fail++
        Write-Host "  FAIL  $Name"
        Write-Host "        expected: $Expected"
        Write-Host "        actual:   $Actual"
    }
}

function Assert-Throws {
    param([scriptblock]$Block, [string]$Name)
    try {
        & $Block
        $script:Fail++
        Write-Host "  FAIL  $Name (did not throw)"
    } catch {
        $script:Pass++
        Write-Host "  PASS  $Name"
    }
}

function Assert-ArrayEqual {
    param([string[]]$Expected, [string[]]$Actual, [string]$Name)
    $e = ($Expected -join '|')
    $a = ($Actual -join '|')
    Assert-Equal -Expected $e -Actual $a -Name $Name
}

# ---- Get-RepoId ----
Write-Host "Get-RepoId"
Assert-Equal 'Qwen/Qwen3-Embedding-4B-GGUF' (Get-RepoId 'https://huggingface.co/Qwen/Qwen3-Embedding-4B-GGUF') 'full https URL'
Assert-Equal 'Qwen/Qwen3-Embedding-4B-GGUF' (Get-RepoId 'http://huggingface.co/Qwen/Qwen3-Embedding-4B-GGUF/tree/main') 'URL with /tree/main'
Assert-Equal 'Qwen/Qwen3-Embedding-4B-GGUF' (Get-RepoId 'https://www.huggingface.co/Qwen/Qwen3-Embedding-4B-GGUF/blob/main/README.md') 'URL with /blob/.../file'
Assert-Equal 'Qwen/Qwen3-Embedding-4B-GGUF' (Get-RepoId 'Qwen/Qwen3-Embedding-4B-GGUF') 'plain id'
Assert-Equal 'Qwen/Qwen3-Embedding-4B-GGUF' (Get-RepoId 'https://huggingface.co/Qwen/Qwen3-Embedding-4B-GGUF/') 'trailing slash'
Assert-Throws { Get-RepoId 'not-a-repo' } 'rejects single-segment'
Assert-Throws { Get-RepoId 'https://huggingface.co/onlyone' } 'rejects URL missing repo segment'

# ---- Select-QuantFiles ----
Write-Host "Select-QuantFiles"
$mockFiles = @(
    [pscustomobject]@{ type='file'; path='Qwen3-Embedding-4B-Q4_K_M.gguf'; size=2400000000 }
    [pscustomobject]@{ type='file'; path='Qwen3-Embedding-4B-Q5_0.gguf';   size=2700000000 }
    [pscustomobject]@{ type='file'; path='Qwen3-Embedding-4B-Q5_K_M.gguf'; size=2900000000 }
    [pscustomobject]@{ type='file'; path='Qwen3-Embedding-4B-Q6_K.gguf';   size=3300000000 }
    [pscustomobject]@{ type='file'; path='Qwen3-Embedding-4B-Q8_0.gguf';   size=4300000000 }
    [pscustomobject]@{ type='file'; path='Qwen3-Embedding-4B-f16.gguf';    size=8000000000 }
    [pscustomobject]@{ type='file'; path='README.md';                      size=17000 }
    [pscustomobject]@{ type='file'; path='.gitattributes';                 size=1500 }
)

$r = Select-QuantFiles -Files $mockFiles -Quant 'Q8_0'
Assert-ArrayEqual @('Qwen3-Embedding-4B-Q8_0.gguf') @($r | ForEach-Object { $_.path }) 'exact Q8_0 match'

$r = Select-QuantFiles -Files $mockFiles -Quant 'q4_k_m'
Assert-ArrayEqual @('Qwen3-Embedding-4B-Q4_K_M.gguf') @($r | ForEach-Object { $_.path }) 'case-insensitive Q4_K_M'

$r = Select-QuantFiles -Files $mockFiles -Quant 'F16'
Assert-ArrayEqual @('Qwen3-Embedding-4B-f16.gguf') @($r | ForEach-Object { $_.path }) 'F16 case-insensitive'

$r = Select-QuantFiles -Files $mockFiles -Quant 'Q5'
# 'Q5' is a prefix; pattern requires full token match -> nothing should match
Assert-Equal 0 @($r).Count 'partial Q5 does not match (should be Q5_0 or Q5_K_M)'

$r = Select-QuantFiles -Files $mockFiles -Quant 'Q5_0'
Assert-ArrayEqual @('Qwen3-Embedding-4B-Q5_0.gguf') @($r | ForEach-Object { $_.path }) 'Q5_0 not greedy onto Q5_K_M'

$r = Select-QuantFiles -Files $mockFiles -Quant 'Q9_0'
Assert-Equal 0 @($r).Count 'no match for Q9_0'

# Sharded files
$shardedFiles = @(
    [pscustomobject]@{ type='file'; path='Big-Model-Q8_0-00002-of-00003.gguf'; size=10000000000 }
    [pscustomobject]@{ type='file'; path='Big-Model-Q8_0-00001-of-00003.gguf'; size=10000000000 }
    [pscustomobject]@{ type='file'; path='Big-Model-Q8_0-00003-of-00003.gguf'; size=9000000000 }
    [pscustomobject]@{ type='file'; path='Big-Model-Q4_K_M.gguf';              size=4000000000 }
)
$r = Select-QuantFiles -Files $shardedFiles -Quant 'Q8_0'
$paths = @($r | ForEach-Object { $_.path })
Assert-Equal 3 $paths.Count 'sharded: 3 parts matched'
Assert-Equal 'Big-Model-Q8_0-00001-of-00003.gguf' $paths[0] 'sharded: sorted ascending'
Assert-Equal 'Big-Model-Q8_0-00003-of-00003.gguf' $paths[2] 'sharded: last part is 00003'

# ---- Online integration (optional) ----
if ($Online) {
    Write-Host "Online integration"
    $files = Get-RepoFileList -RepoId 'Qwen/Qwen3-Embedding-4B-GGUF' -Branch 'main'
    Assert-Equal $true ($files.Count -gt 0) 'HF API returns files'
    $matched = Select-QuantFiles -Files $files -Quant 'Q8_0'
    Assert-Equal 1 @($matched).Count 'HF live: exactly one Q8_0 file in real repo'
}

Write-Host ""
Write-Host "Pass: $script:Pass    Fail: $script:Fail"
if ($script:Fail -gt 0) { exit 1 }
