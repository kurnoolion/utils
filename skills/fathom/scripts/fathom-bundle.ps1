<#
.SYNOPSIS
  Fathom bundle for Windows — no Python needed. Packs the documents on your PC that match a question
  into one file you attach to a Claude, Gemini or ChatGPT chat.

.DESCRIPTION
  Walks the folders you name, extracts text from ordinary files, keeps the documents that match your
  query terms, and writes a single dated markdown file headed "Fathom corpus bundle" — the format the
  Fathom protocol recognizes as your internal evidence lane. Nothing leaves the machine unless you
  attach the file yourself.

  Formats handled with nothing installed: .md .txt .csv .json .log .html .htm .eml .docx .pptx .xlsx
  Handled through Office if it is installed (-UseOffice, on by default): .msg via Outlook. Each Office call runs
  in a separate process with a deadline (-OfficeTimeout, 60 s) because hidden Office instances can stall on an
  invisible prompt. PDFs are not extracted: the bundle lists them and you attach them next to it, since the
  chat reads PDFs natively. -ForceOffice sends .docx .pptx .xlsx .txt .md .html .csv .pdf through Office instead.

  DRM-protected files (enterprise document DRM) are encrypted on disk and are detected and SKIPPED; the bundle
  lists them so the reader knows what was not accessible. With -OfficeForDrm the script instead opens
  them through Word, Excel and PowerPoint as you, which the DRM agent may decrypt on the fly. Doing that
  exports protected content into an unprotected file: use it only with your DRM policy owner's approval.

.EXAMPLE
  .\fathom-bundle.ps1 -Paths D:\mail-export, D:\rf-team -Query "upper C-band filter decision" -Since 2026-01

.EXAMPLE
  .\fathom-bundle.ps1 -Paths "C:\Users\me\Documents\6G" -Query "dual-stack modem plenary" -Out C:\Temp\bundle.md

.NOTES
  If scripts are blocked:  powershell -ExecutionPolicy Bypass -File .\fathom-bundle.ps1 -Paths ... -Query ...
  Works on Windows PowerShell 5.1 and PowerShell 7.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string[]] $Paths,
  [string] $Query = "",
  [string] $Since = "",
  [string] $Out = "",
  [int] $MaxDocs = 12,
  [int] $MaxChars = 300000,
  [int] $MaxDocChars = 40000,
  [string] $Type = "",
  [bool] $UseOffice = $true,
  [switch] $OfficeForDrm,
  [switch] $ForceOffice,
  [int] $OfficeTimeout = 60
)

$ErrorActionPreference = "Continue"
$Paths = @($Paths | ForEach-Object { $_ -split ';' } | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ })
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue

$Stop = @("the","a","an","and","or","of","to","in","for","on","with","by","is","are","was","were","be","been","this","that","from","as","at","it","its","into","not","no")
$RecentBonusDate = (Get-Date).AddDays(-180).ToString("yyyy-MM-dd")

function Decode-Html([string] $s) {
  if ($null -eq $s) { return "" }
  try { return [System.Net.WebUtility]::HtmlDecode($s) } catch { return $s }
}
function Strip-Html([string] $s) {
  $s = [regex]::Replace($s, '(?is)<(script|style|nav|footer|header)[^>]*>.*?</\1>', ' ')
  $s = [regex]::Replace($s, '(?i)<br\s*/?>|</p>|</div>|</li>|</tr>|</h[1-6]>', "`n")
  $s = [regex]::Replace($s, '<[^>]+>', ' ')
  $s = Decode-Html $s
  $s = [regex]::Replace($s, '[ \t]+', ' ')
  $s = [regex]::Replace($s, "\n\s*\n+", "`n`n")
  return $s.Trim()
}
function Html-Title([string] $s) {
  $m = [regex]::Match($s, '(?is)<title[^>]*>(.*?)</title>')
  if ($m.Success) { return (Decode-Html $m.Groups[1].Value).Trim() } else { return $null }
}
function Read-ZipEntry($zip, [string] $name) {
  $e = $zip.GetEntry($name); if ($null -eq $e) { return $null }
  $sr = New-Object System.IO.StreamReader($e.Open(), [System.Text.Encoding]::UTF8)
  try { return $sr.ReadToEnd() } finally { $sr.Dispose() }
}
function Xml-Text([string] $xml, [string] $tag) {
  if ($null -eq $xml) { return "" }
  $parts = [regex]::Matches($xml, "<$tag(?:\s[^>]*)?>(.*?)</$tag>", 'Singleline') | ForEach-Object { $_.Groups[1].Value }
  return (Decode-Html (($parts -join ' ') -replace '\s+', ' ')).Trim()
}
function Extract-Docx([string] $p) {
  $zip = [System.IO.Compression.ZipFile]::OpenRead($p)
  try {
    $doc = Read-ZipEntry $zip 'word/document.xml'
    $doc = $doc -replace '</w:p>', "`n"
    $text = Decode-Html ([regex]::Replace($doc, '<[^>]+>', ''))
    $core = Read-ZipEntry $zip 'docProps/core.xml'
    $title = $null; $date = $null
    if ($core) {
      $m = [regex]::Match($core, '<dc:title>(.*?)</dc:title>'); if ($m.Success) { $title = $m.Groups[1].Value }
      $m = [regex]::Match($core, '<dcterms:modified[^>]*>(.*?)</dcterms:modified>'); if ($m.Success) { $date = $m.Groups[1].Value.Substring(0, 10) }
    }
    return @{ text = $text; title = $title; date = $date }
  } finally { $zip.Dispose() }
}
function Extract-Pptx([string] $p) {
  $zip = [System.IO.Compression.ZipFile]::OpenRead($p)
  try {
    $slides = $zip.Entries | Where-Object { $_.FullName -match '^ppt/slides/slide\d+\.xml$' } | Sort-Object { [int]([regex]::Match($_.FullName, '\d+').Value) }
    $i = 0
    $out = foreach ($s in $slides) { $i++; "[slide $i] " + (Xml-Text (Read-ZipEntry $zip $s.FullName) 'a:t') }
    return ($out -join "`n`n")
  } finally { $zip.Dispose() }
}
function Extract-Xlsx([string] $p) {
  $zip = [System.IO.Compression.ZipFile]::OpenRead($p)
  try { return (Xml-Text (Read-ZipEntry $zip 'xl/sharedStrings.xml') 't') } finally { $zip.Dispose() }
}
function Decode-Body([string] $body, [string] $enc) {
  try {
    if ($enc -match 'base64') { return [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($body -replace '\s', ''))) }
    if ($enc -match 'quoted-printable') {
      $b = $body -replace "=\r?\n", ''
      return [regex]::Replace($b, '=([0-9A-Fa-f]{2})', { param($m) [char][Convert]::ToInt32($m.Groups[1].Value, 16) })
    }
  } catch {}
  return $body
}
function Extract-Eml([string] $p) {
  $raw = [System.IO.File]::ReadAllText($p)
  $blank = New-Object regex "\r?\n\r?\n"
  $split = $blank.Split($raw, 2); if ($split.Count -lt 2) { $split = @($raw, "") }
  $hdrText = $split[0] -replace "\r?\n[ \t]+", ' '
  $h = @{}
  foreach ($line in ($hdrText -split "\r?\n")) { $m = [regex]::Match($line, '^([\w-]+):\s*(.*)$'); if ($m.Success) { $h[$m.Groups[1].Value.ToLower()] = $m.Groups[2].Value } }
  $body = $split[1]
  $ctype = $h['content-type']; $cte = $h['content-transfer-encoding']
  if ($ctype -match 'boundary="?([^";]+)"?') {
    $bnd = $Matches[1]
    $parts = $body -split ('--' + [regex]::Escape($bnd))
    $pick = $null; $pickEnc = ''; $isHtml = $false
    foreach ($part in $parts) {
      $ps = $blank.Split($part.Trim(), 2); if ($ps.Count -lt 2) { continue }
      if ($ps[0] -match 'Content-Type:\s*text/plain') { $pick = $ps[1]; $pickEnc = $ps[0]; $isHtml = $false; break }
      if ($null -eq $pick -and $ps[0] -match 'Content-Type:\s*text/html') { $pick = $ps[1]; $pickEnc = $ps[0]; $isHtml = $true }
    }
    if ($pick) { $body = Decode-Body $pick $pickEnc; if ($isHtml) { $body = Strip-Html $body } }
  } else {
    $body = Decode-Body $body $cte
    if ($ctype -match 'text/html') { $body = Strip-Html $body }
  }
  $date = $null
  if ($h['date']) { try { $date = ([DateTimeOffset]::Parse($h['date'])).ToString('yyyy-MM-dd') } catch {} }
  $head = @('From','To','Cc','Date','Subject') | Where-Object { $h[$_.ToLower()] } | ForEach-Object { "{0}: {1}" -f $_, $h[$_.ToLower()] }
  return @{ text = (($head -join "`n") + "`n`n" + $body); title = $h['subject']; date = $date; author = $h['from'] }
}
$script:Skipped = @(); $script:Pdfs = @(); $script:DrmWarned = $false
function Test-Encrypted($f, [string] $ext) {
  try {
    $fs = [System.IO.File]::OpenRead($f.FullName); $buf = New-Object byte[] 65536; $n = $fs.Read($buf, 0, 65536); $fs.Dispose()
    if ($n -eq 0) { return $false }
    $head = $buf[0..($n - 1)]
    if ($ext -in '.docx','.pptx','.xlsx') { try { $z = [System.IO.Compression.ZipFile]::OpenRead($f.FullName); $z.Dispose(); return $false } catch { return $true } }
    if ($ext -eq '.pdf') { return -not ([System.Text.Encoding]::ASCII.GetString($head, 0, [Math]::Min(8, $n)).TrimStart().StartsWith('%PDF')) }
    if ($ext -in '.md','.txt','.csv','.json','.log','.rst','.html','.htm','.xhtml','.eml') {
      try { [void](New-Object System.Text.UTF8Encoding($false, $true)).GetString($head) } catch {
        try { [void](New-Object System.Text.UnicodeEncoding($false, $false, $true)).GetString($head); return $false } catch { return $true } }
      $ctrl = 0; foreach ($b in $head) { if ($b -lt 9 -or ($b -gt 13 -and $b -lt 32)) { $ctrl++ } }
      return ($ctrl / $n) -gt 0.05
    }
  } catch {}
  return $false
}
function Test-Garbage([string] $t) {
  if ([string]::IsNullOrWhiteSpace($t)) { return $true }
  $n = [Math]::Min($t.Length, 20000); $bad = 0
  for ($i = 0; $i -lt $n; $i++) { $c = [int]$t[$i]; if ($c -lt 9 -or ($c -gt 13 -and $c -lt 32) -or $c -eq 0xFFFD) { $bad++ } }
  return ($bad / $n) -gt 0.05
}
function Warn-Drm {
  if (-not $script:DrmWarned) { $script:DrmWarned = $true
    Write-Warning "-OfficeForDrm: opening DRM-protected files through Office as the current user and writing their text to an unprotected bundle. Use only with your DRM policy owner's approval." }
}
# Office automation runs in a separate process with a deadline. Hidden Office instances can stall on an
# invisible prompt (Word's PDF conversion notice, Outlook's programmatic-access guard); a stalled call
# would otherwise hang the whole run. On timeout only the hidden instance the job started is killed.
function Invoke-Office([string] $app, [string] $path) {
  $started = Get-Date
  $job = Start-Job -ArgumentList $app, $path -ScriptBlock {
    param($app, $path)
    try {
      switch ($app) {
        'word'    { $w = New-Object -ComObject Word.Application; $w.Visible = $false; $w.DisplayAlerts = 0
                    $d = $w.Documents.Open($path, $false, $true, $false); $t = $d.Content.Text; $d.Close($false); $w.Quit(); $t }
        'excel'   { $x = New-Object -ComObject Excel.Application; $x.Visible = $false; $x.DisplayAlerts = $false
                    $wb = $x.Workbooks.Open($path, 0, $true); $out = @()
                    foreach ($ws in $wb.Worksheets) { $out += "[sheet $($ws.Name)]"; $v = $ws.UsedRange.Value2
                      if ($v -is [array]) { $rows = [Math]::Min($v.GetLength(0), 2000); $cols = $v.GetLength(1)
                        for ($r = 1; $r -le $rows; $r++) { $cells = @(); for ($c = 1; $c -le $cols; $c++) { if ($null -ne $v[$r, $c]) { $cells += [string]$v[$r, $c] } }; if ($cells.Count) { $out += ($cells -join ' | ') } } }
                      elseif ($null -ne $v) { $out += [string]$v } }
                    $wb.Close($false); $x.Quit(); ($out -join "`n") }
        'ppt'     { $pp = New-Object -ComObject PowerPoint.Application
                    $pres = $pp.Presentations.Open($path, -1, 0, 0); $out = @(); $i = 0
                    foreach ($sl in $pres.Slides) { $i++; $t = @(); foreach ($sh in $sl.Shapes) { if ($sh.HasTextFrame) { $t += $sh.TextFrame.TextRange.Text } }; $out += "[slide $i] " + ($t -join ' ') }
                    $pres.Close(); $pp.Quit(); ($out -join "`n`n") }
        'outlook' { $o = New-Object -ComObject Outlook.Application; $m = $o.Session.OpenSharedItem($path)
                    $date = ''; try { $date = $m.ReceivedTime.ToString('yyyy-MM-dd') } catch {}
                    "MSGMETA|$($m.Subject)|$date|$($m.SenderName)`nFrom: $($m.SenderName) <$($m.SenderEmailAddress)>`nTo: $($m.To)`nDate: $($m.ReceivedTime)`nSubject: $($m.Subject)`n`n$($m.Body)" }
      }
    } catch { "ERROR: " + $_.Exception.Message }
    finally { foreach ($v in 'w','x','pp','o') { $obj = Get-Variable $v -ValueOnly -ErrorAction SilentlyContinue; if ($obj) { try { [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($obj) } catch {} } }; [GC]::Collect(); [GC]::WaitForPendingFinalizers() }
  }
  $names = @{ word = 'WINWORD'; excel = 'EXCEL'; ppt = 'POWERPNT'; outlook = 'OUTLOOK' }
  $done = Wait-Job $job -Timeout $OfficeTimeout
  if ($done) { $out = (Receive-Job $job) -join "`n"; Remove-Job $job -Force
    if ($app -ne 'outlook') { Get-Process $names[$app] -ErrorAction SilentlyContinue | Where-Object { $_.StartTime -gt $started -and -not $_.MainWindowTitle } | Stop-Process -Force -ErrorAction SilentlyContinue }
    if ($out.StartsWith('ERROR: ')) { Write-Warning "skip ($app failed: $($out.Substring(7, [Math]::Min(80, $out.Length - 7)))): $path"; return $null }
    return $out }
  Stop-Job $job; Remove-Job $job -Force
  Get-Process $names[$app] -ErrorAction SilentlyContinue | Where-Object { $_.StartTime -gt $started -and -not $_.MainWindowTitle } | Stop-Process -Force -ErrorAction SilentlyContinue
  Write-Warning "skip ($app did not answer within ${OfficeTimeout}s, probably a hidden prompt): $path"; return $null
}
function Extract-Msg([string] $p) {
  if (-not $UseOffice) { return $null }
  $t = Invoke-Office 'outlook' $p; if ($null -eq $t) { return $null }
  $meta = ($t -split "`n", 2)[0] -split '\|'; $body = ($t -split "`n", 2)[1]
  return @{ text = $body; title = $meta[1]; date = $(if ($meta[2]) { $meta[2] } else { $null }); author = $meta[3] }
}
function Extract-Word([string] $p)  { if (-not $UseOffice) { return $null }; $t = Invoke-Office 'word' $p;  if ($null -eq $t) { return $null }; return @{ text = $t } }
function Extract-OfficeExcel([string] $p) { if (-not $UseOffice) { return $null }; $t = Invoke-Office 'excel' $p; if ($null -eq $t) { return $null }; return @{ text = $t } }
function Extract-OfficePpt([string] $p)   { if (-not $UseOffice) { return $null }; $t = Invoke-Office 'ppt' $p;   if ($null -eq $t) { return $null }; return @{ text = $t } }

function Extract-File($f) {
  $ext = $f.Extension.ToLower(); $p = $f.FullName
  $mtime = $f.LastWriteTime.ToString('yyyy-MM-dd')
  $r = $null; $kind = $ext.TrimStart('.')
  $officeable = $ext -in '.md','.txt','.csv','.html','.htm','.docx','.pptx','.xlsx','.pdf'
  $encrypted = ($ext -in '.md','.txt','.csv','.json','.log','.rst','.html','.htm','.xhtml','.eml','.docx','.pptx','.xlsx','.pdf') -and (Test-Encrypted $f $ext)
  if ($encrypted -or ($ForceOffice -and $officeable)) {
    if ($UseOffice -and $officeable -and ($ForceOffice -or $OfficeForDrm)) {
      if ($encrypted) { Warn-Drm }
      switch ($ext) {
        '.xlsx' { $r = Extract-OfficeExcel $p }
        '.pptx' { $r = Extract-OfficePpt $p }
        default { $r = Extract-Word $p }   # Word opens .docx .pdf .txt .md .html .csv
      }
      if ($null -eq $r -or (Test-Garbage $r.text)) {
        $why = $(if ($encrypted) { 'DRM-protected; Office route failed or returned unreadable content' } else { 'Office route returned unreadable content' })
        $script:Skipped += [pscustomobject]@{ path = $p; type = $kind; date = $mtime; reason = $why }; return $null }
      if ($encrypted) { $kind = $kind + '+drm' }
    } elseif ($encrypted) {
      $script:Skipped += [pscustomobject]@{ path = $p; type = $kind; date = $mtime; reason = 'appears DRM-protected or encrypted at rest' }
      return $null
    }
  }
  if ($null -eq $r) { switch ($ext) {
    { $_ -in '.md','.txt','.csv','.json','.log','.rst' } {
      $t = [System.IO.File]::ReadAllText($p); $m = [regex]::Match($t, '(?m)^#\s+(.+)$')
      $r = @{ text = $t; title = $(if ($m.Success) { $m.Groups[1].Value } else { $null }) } }
    { $_ -in '.html','.htm','.xhtml' } { $raw = [System.IO.File]::ReadAllText($p); $r = @{ text = (Strip-Html $raw); title = (Html-Title $raw) }; $kind = 'html' }
    '.docx' { $r = Extract-Docx $p }
    '.pptx' { $r = @{ text = (Extract-Pptx $p) } }
    '.xlsx' { $r = @{ text = (Extract-Xlsx $p) } }
    '.eml'  { $r = Extract-Eml $p }
    '.msg'  { $r = Extract-Msg $p; $kind = 'eml' }
    '.pdf'  { $script:Pdfs += [pscustomobject]@{ path = $p; date = $mtime }; return $null }   # web apps read PDFs natively: attach them alongside the bundle
    default { return $null }
  } }
  if ($null -eq $r -or [string]::IsNullOrWhiteSpace($r.text)) { return $null }
  $sha = [System.Security.Cryptography.SHA1]::Create()
  $id = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes("$p|$($f.LastWriteTimeUtc.Ticks)"))) -replace '-', '').Substring(0, 10).ToLower()
  return [pscustomobject]@{
    id = $id; path = $p; title = $(if ($r.title) { $r.title } else { $f.Name })
    date = $(if ($r.date) { $r.date } else { $mtime }); author = $r.author; type = $kind; text = $r.text
  }
}

# ---- collect
$docs = @()
foreach ($root in $Paths) {
  if (-not (Test-Path $root)) { Write-Warning "path not found: $root"; continue }
  Get-ChildItem -Path $root -Recurse -File | Where-Object { -not $_.Name.StartsWith('.') } | ForEach-Object {
    try { $d = Extract-File $_; if ($d) { $docs += $d } } catch { Write-Warning "skip ($($_.Exception.Message)): $($_.FullName)" }
  }
}
if ($script:Skipped.Count -gt 0) { $drm = @($script:Skipped | Where-Object { $_.reason -like "*DRM*" }).Count
  Write-Warning "$($script:Skipped.Count) file(s) could not be read and are listed at the end of the bundle ($drm appear DRM-protected: request decryption through your DRM workflow, or re-run with -OfficeForDrm after policy approval)." }
if ($script:Pdfs.Count -gt 0) { Write-Host "$($script:Pdfs.Count) PDF(s) listed in the bundle to attach separately (the chat reads PDFs natively)." }
if ($docs.Count -eq 0 -and $script:Skipped.Count -eq 0 -and $script:Pdfs.Count -eq 0) { Write-Error "no readable documents found under: $($Paths -join ', ')"; exit 1 }

# ---- match
$terms = @([regex]::Matches($Query, '[A-Za-z0-9][\w.\-/]*') | ForEach-Object { $_.Value.ToLower() } | Where-Object { $_.Length -gt 1 -and $Stop -notcontains $_ } | Select-Object -Unique)
$hits = foreach ($d in $docs) {
  if ($Type -and $d.type -ne $Type) { continue }
  if ($Since -and $d.date -lt $Since) { continue }
  $low = $d.text.ToLower(); $matched = @(); $total = 0
  foreach ($t in $terms) { $c = ([regex]::Matches($low, [regex]::Escape($t))).Count; if ($c -gt 0) { $matched += $t; $total += $c } }
  if ($terms.Count -gt 0 -and $matched.Count -eq 0) { continue }
  $score = $matched.Count * 10 + [Math]::Min($total, 50) + $(if ($d.date -ge $RecentBonusDate) { 5 } else { 0 })
  [pscustomobject]@{ score = $score; doc = $d; matched = $matched }
}
$hits = @($hits | Sort-Object -Property @{Expression = 'score'; Descending = $true}, @{Expression = { $_.doc.date }; Descending = $true})
if ($hits.Count -eq 0 -and $script:Skipped.Count -eq 0 -and $script:Pdfs.Count -eq 0) { Write-Error "no documents match: $($terms -join ' ')"; exit 1 }

# ---- write
$today = (Get-Date).ToString('yyyy-MM-dd')
if (-not $Out) { $Out = "fathom-bundle-$today.md" }
$sb = New-Object System.Text.StringBuilder
$budget = $MaxChars; $included = 0; $blocks = @()
foreach ($h in $hits | Select-Object -First $MaxDocs) {
  $d = $h.doc; $body = $d.text.Trim()
  if ($body.Length -gt $MaxDocChars) { $body = $body.Substring(0, $MaxDocChars) + "`n`n[… truncated at $MaxDocChars chars of $($d.text.Length); ask the author for the rest]" }
  $meta = "- path: $($d.path)`n- date: $($d.date) · type: $($d.type)" + $(if ($d.author) { " · author: $($d.author)" } else { "" })
  if ($h.matched.Count -gt 0) { $meta += "`n- matched terms: $($h.matched -join ', ')" }
  $block = "`n## [$($d.id)] $($d.title)`n$meta`n`n$body`n"
  if ($budget - $block.Length -lt 0 -and $included -gt 0) { break }
  $blocks += $block; $budget -= $block.Length; $included++
}
$q = $(if ($Query) { $Query } else { '(all documents)' }); $s = $(if ($Since) { $Since } else { 'any' })
[void]$sb.Append("# Fathom corpus bundle — $today`n`n")
[void]$sb.Append("Query: $q · since: $s · documents: $included of $($hits.Count) matched`n`n")
[void]$sb.Append("Internal material exported from the author's own files. Treat every item below as an internal source: keep the tags, add the (internal) marker, cite as path · title · date · author, and head the brief INTERNAL. Do not paste any of this text into a web search.`n`n---`n")
foreach ($b in $blocks) { [void]$sb.Append($b) }
if ($script:Pdfs.Count -gt 0) {
  [void]$sb.Append("`n---`n`n## Attach these PDFs separately ($($script:Pdfs.Count) file(s))`n`nThe chat reads PDFs natively; this bundler does not extract them. Attach the ones that matter next to this bundle.`n`n")
  foreach ($k in ($script:Pdfs | Select-Object -First 50)) { [void]$sb.Append("- $($k.path) (modified $($k.date))`n") }
}
if ($script:Skipped.Count -gt 0) {
  [void]$sb.Append("`n---`n`n## Skipped: could not be read ($($script:Skipped.Count) file(s))`n`n")
  [void]$sb.Append("These files exist but could not be read; treat them as *located, not accessible*. Files marked DRM-protected need a decryption request through the DRM workflow if their content matters.`n`n")
  foreach ($k in ($script:Skipped | Select-Object -First 50)) { [void]$sb.Append("- $($k.path) ($($k.type), modified $($k.date); $($k.reason))`n") }
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Resolve-Path -LiteralPath (Split-Path -Parent ([System.IO.Path]::GetFullPath($Out)))).Path + '\' + (Split-Path -Leaf $Out), $sb.ToString(), $utf8)
$size = (Get-Item $Out).Length
$extra = $(if ($script:Skipped.Count -gt 0) { " $($script:Skipped.Count) unreadable file(s) listed as skipped." } else { "" })
Write-Host "wrote $Out — $included document(s) of $($docs.Count) scanned, $size bytes.$extra Attach it to your chat with the question."
