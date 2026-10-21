# Generates the cheer voice clips voice/<group>-<index>.mp3 with Azure text-to-speech.
# The lines come from the VOICE table between "// VOICE-BEGIN" and "// VOICE-END" in index.html;
# after editing a line, rerun with -Force (or delete that mp3) so it is regenerated.
# The key file is never committed: line 1 = key, line 2 = region (e.g. eastasia).
param(
  [string]$KeyFile = "$env:USERPROFILE\.secrets\azure-key.txt",
  [string]$Voice = 'zh-CN-XiaoyiNeural',
  [string]$Style = 'cheerful',
  [switch]$Force
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$html = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'index.html')
if ($html -notmatch '(?s)// VOICE-BEGIN\s*const VOICE = (\{.*?\});\s*// VOICE-END') { throw 'VOICE table not found in index.html' }
$table = $Matches[1] | ConvertFrom-Json

$lines = Get-Content $KeyFile | Where-Object { $_.Trim() -ne '' }
$key = $lines[0].Trim()
$region = $lines[1].Trim().ToLower().Replace(' ', '')
$url = "https://$region.tts.speech.microsoft.com/cognitiveservices/v1"
$headers = @{
  'Ocp-Apim-Subscription-Key' = $key
  'X-Microsoft-OutputFormat'  = 'audio-24khz-48kbitrate-mono-mp3'
  'User-Agent'                = 'cutie-pop'
}
$outDir = Join-Path $root 'voice'
New-Item -ItemType Directory -Force $outDir | Out-Null

$made = 0
foreach ($p in $table.PSObject.Properties) {
  $i = 0
  foreach ($text in $p.Value) {
    $file = Join-Path $outDir ('{0}-{1}.mp3' -f $p.Name, $i)
    $i++
    if ((Test-Path $file) -and -not $Force) { continue }
    $t = [Security.SecurityElement]::Escape($text)
    $ssml = "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xmlns:mstts='https://www.w3.org/2001/mstts' xml:lang='zh-CN'>" +
      "<voice name='$Voice'><mstts:express-as style='$Style' styledegree='2'><prosody rate='+6%' pitch='+8%'>$t</prosody></mstts:express-as></voice></speak>"
    for ($try = 1; $try -le 6; $try++) {
      try {
        Invoke-WebRequest -UseBasicParsing -Method Post -Uri $url -Headers $headers -ContentType 'application/ssml+xml' `
          -Body ([Text.Encoding]::UTF8.GetBytes($ssml)) -OutFile $file -TimeoutSec 30
        $made++
        Write-Host ('  {0}' -f (Split-Path -Leaf $file))
        break
      } catch {
        $code = 0; if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
        if ($code -eq 429 -or $code -ge 500 -or $code -eq 0) { Start-Sleep -Seconds (5 * $try); continue }
        Write-Host "  failed ($code): $($p.Name)-$($i - 1)" -ForegroundColor Red
        break
      }
    }
  }
}
Write-Host "Done, $made new clip(s)."
