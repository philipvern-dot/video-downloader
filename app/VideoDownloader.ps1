# Video Downloader
# Open "Video Downloader" in the parent folder. This file is the program window.

param(
    [switch]$SmokeTest,
    [switch]$TestDownload
)

$ErrorActionPreference = 'Stop'
$script:SmokeTest = [bool]$SmokeTest

if (-not ('VideoDownloader.Native' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Globalization;
using System.Text.RegularExpressions;
using System.Runtime.InteropServices;
namespace VideoDownloader {
  public static class Native {
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
  }

  public static class YtLinePump {
    static readonly Regex Ansi = new Regex("\x1b\\[[0-9;]*[A-Za-z]", RegexOptions.Compiled);
    static readonly Regex Percent = new Regex(@"\[download\]\s+([\d.]+)%", RegexOptions.Compiled);
    static readonly ConcurrentQueue<string> Lines = new ConcurrentQueue<string>();
    public static volatile bool Exited;
    public static int Generation;
    public static int ExitCode;
    public static double LivePercent = -1;
    public static string LiveDetail;

    public static void BeginJob() {
      Generation++;
      string discard;
      while (Lines.TryDequeue(out discard)) {}
      LivePercent = -1;
      LiveDetail = null;
      ExitCode = 0;
      Exited = false;
    }

    public static void ClearPercent() {
      LivePercent = -1;
      LiveDetail = null;
    }

    public static void Accept(string line) {
      if (string.IsNullOrEmpty(line)) return;
      line = Ansi.Replace(line, string.Empty).TrimEnd('\r');
      if (line.Length == 0) return;
      Match match = Percent.Match(line);
      if (match.Success) {
        double pct;
        if (double.TryParse(match.Groups[1].Value, NumberStyles.Float, CultureInfo.InvariantCulture, out pct)) {
          LivePercent = pct;
          LiveDetail = line;
        }
        return;
      }
      Lines.Enqueue(line);
    }

    public static void OnData(object sender, DataReceivedEventArgs e) {
      Accept(e.Data);
    }

    public static void OnExit(object sender, EventArgs e) {
      int gen = Generation;
      int code = -1;
      try {
        Process process = sender as Process;
        if (process != null) code = process.ExitCode;
      } catch {}
      if (gen != Generation) return;
      ExitCode = code;
      Exited = true;
    }

    public static string[] Drain() {
      List<string> batch = new List<string>();
      string line;
      while (Lines.TryDequeue(out line)) {
        if (!string.IsNullOrEmpty(line)) batch.Add(line);
      }
      return batch.ToArray();
    }
  }
}
'@
}

function Hide-OwnConsole {
    try {
        $hwnd = [VideoDownloader.Native]::GetConsoleWindow()
        if ($hwnd -eq [IntPtr]::Zero) { return }
        $owner = [uint32]0
        [void][VideoDownloader.Native]::GetWindowThreadProcessId($hwnd, [ref]$owner)
        if ($owner -eq [uint32]$PID) {
            [void][VideoDownloader.Native]::ShowWindow($hwnd, 0)
        }
    } catch {
    }
}

if (-not $SmokeTest -and -not $TestDownload) {
    Hide-OwnConsole
}

if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA' -and -not $TestDownload) {
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $argList = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    if ($SmokeTest) {
        $argList += '-SmokeTest'
        $child = Start-Process -FilePath $ps -ArgumentList $argList -Wait -PassThru
        exit $child.ExitCode
    }
    Start-Process -FilePath $ps -ArgumentList $argList | Out-Null
    exit 0
}

$script:AppDir = $PSScriptRoot
if (-not $script:AppDir) { $script:AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$script:Root = Split-Path -Parent $script:AppDir
$script:ToolsDir = Join-Path $script:Root 'tools'
$script:DefaultDownloadsDir = Join-Path $script:Root 'downloads'
$script:DownloadsDir = $script:DefaultDownloadsDir
$script:ListsDir = Join-Path $script:Root 'saved-lists'
$script:YtDlp = Join-Path $script:ToolsDir 'yt-dlp.exe'
$script:Ffmpeg = Join-Path $script:ToolsDir 'ffmpeg.exe'
$script:Ffprobe = Join-Path $script:ToolsDir 'ffprobe.exe'
$script:Deno = Join-Path $script:ToolsDir 'deno.exe'
$script:SettingsPath = Join-Path $script:AppDir 'settings.json'
$script:ArchiveFile = Join-Path $script:AppDir 'download-history.txt'
$script:AudioArchiveFile = Join-Path $script:AppDir 'audio-history.txt'

foreach ($dir in @($script:DownloadsDir, $script:ListsDir, $script:ToolsDir)) {
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
}

Add-Type -AssemblyName System.Drawing

$script:ColorPage = [Drawing.Color]::FromArgb(238, 241, 244)
$script:ColorInk = [Drawing.Color]::FromArgb(17, 24, 39)
$script:ColorBody = [Drawing.Color]::FromArgb(55, 65, 81)
$script:ColorMuted = [Drawing.Color]::FromArgb(75, 85, 99)
$script:ColorLine = [Drawing.Color]::FromArgb(214, 218, 225)
$script:ColorHeader = [Drawing.Color]::FromArgb(28, 36, 48)
$script:ColorHeaderMuted = [Drawing.Color]::FromArgb(209, 213, 219)
$script:ColorPrimary = [Drawing.Color]::FromArgb(29, 78, 216)
$script:ColorPrimaryHover = [Drawing.Color]::FromArgb(30, 64, 175)
$script:ColorDanger = [Drawing.Color]::FromArgb(185, 28, 28)
$script:ColorLogBg = [Drawing.Color]::FromArgb(28, 36, 48)
$script:ColorLogText = [Drawing.Color]::FromArgb(229, 231, 235)
$script:ColorLogOk = [Drawing.Color]::FromArgb(134, 239, 172)
$script:ColorLogWarn = [Drawing.Color]::FromArgb(252, 211, 77)
$script:ColorLogErr = [Drawing.Color]::FromArgb(252, 165, 165)
$script:ColorLogMuted = [Drawing.Color]::FromArgb(156, 163, 175)
$script:ColorOkText = [Drawing.Color]::FromArgb(22, 101, 52)
$script:ColorErrText = [Drawing.Color]::FromArgb(153, 27, 27)

function ConvertTo-Arg([string]$value) {
    if ($null -eq $value) { return '""' }
    if ($value -notmatch '[\s"]') { return $value }
    return '"' + ($value -replace '"', '\"') + '"'
}

function ConvertTo-CommandLine([string[]]$parts) {
    return (($parts | ForEach-Object { ConvertTo-Arg $_ }) -join ' ')
}

function Test-YouTubeHost([string]$Url) {
    try {
        $uri = [Uri]$Url
    } catch {
        return $false
    }
    if ($uri.Scheme -ne 'http' -and $uri.Scheme -ne 'https') { return $false }
    $hostName = $uri.Host.ToLowerInvariant()
    if ($hostName -eq 'youtu.be' -or $hostName -eq 'youtube.com') { return $true }
    if ($hostName.EndsWith('.youtube.com') -or $hostName.EndsWith('.youtu.be')) { return $true }
    return $false
}

function Get-LinkKind([string]$Url, [bool]$ExpandAttached) {
    if (-not (Test-YouTubeHost $Url)) { return 'open' }

    $hasVideoId = (
        $Url -match '(?i)youtu\.be/[^/?#]+' -or
        $Url -match '(?i)[?&]v=[^&#]+' -or
        $Url -match '(?i)/shorts/[^/?#]+' -or
        $Url -match '(?i)/embed/[^/?#]+' -or
        $Url -match '(?i)/live/[^/?#]+'
    )
    $isPlaylist = $Url -match '(?i)/playlist(\?|/|$)' -or (($Url -match '(?i)[?&]list=[^&#]+') -and -not $hasVideoId)
    if ($hasVideoId -and $ExpandAttached -and ($Url -match '(?i)[?&]list=')) { return 'playlist' }
    if ($isPlaylist) { return 'playlist' }

    $path = $Url
    try { $path = ([Uri]$Url).AbsolutePath } catch { }
    $path = $path -replace '%40', '@'
    if (-not $hasVideoId -and $path -match '(?i)^/(@[^/]+|channel/[^/]+|c/[^/]+|user/[^/]+)(/|$)') {
        return 'channel'
    }
    return 'video'
}

function Trim-UrlTail([string]$url) {
    $trim = @(
        [char]')', [char]']', [char]'}', [char]'>',
        [char]'"', [char]"'", [char]'.', [char]',', [char]';'
    )
    return $url.TrimEnd($trim)
}

function Resolve-Line([string]$line) {
    $t = $line.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) {
        return [pscustomobject]@{ Status = 'skip' }
    }
    $t = $t.Trim(@([char]'"', [char]"'", [char]'<', [char]'>'))
    $url = $null
    if ($t -match '(?i)https?://\S+') {
        $url = Trim-UrlTail $Matches[0]
    } elseif ($t -match '(?i)^((?:www\.)?youtube\.com/\S+|youtu\.be/\S+)') {
        $url = Trim-UrlTail ('https://' + $Matches[1])
    }
    if (-not $url) {
        return [pscustomobject]@{ Status = 'invalid'; Text = $line.Trim() }
    }
    return [pscustomobject]@{ Status = 'ok'; Url = $url }
}

function Get-LinksFromText([string]$Text, [bool]$ExpandAttached) {
    $items = New-Object System.Collections.Generic.List[object]
    $invalid = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    $dupes = 0
    foreach ($line in ($Text -split "`r?`n")) {
        $parsed = Resolve-Line $line
        if ($parsed.Status -eq 'skip') { continue }
        if ($parsed.Status -eq 'invalid') {
            $invalid.Add([string]$parsed.Text)
            continue
        }
        $url = [string]$parsed.Url
        if ($seen.ContainsKey($url)) {
            $dupes++
            continue
        }
        $seen[$url] = $true
        $items.Add([pscustomobject]@{
            Url = $url
            Kind = (Get-LinkKind $url $ExpandAttached)
        })
    }
    return [pscustomobject]@{
        Items = $items
        Invalid = $invalid
        DuplicateCount = $dupes
    }
}

function Get-JobKey([string]$kind) {
    if ($kind -eq 'video') { return 'video' }
    if ($kind -eq 'open') { return 'open' }
    return 'collection'
}

function Build-Jobs($items) {
    $jobs = New-Object System.Collections.Generic.List[object]
    foreach ($item in $items) {
        $key = Get-JobKey $item.Kind
        $last = $null
        if ($jobs.Count -gt 0) { $last = $jobs[$jobs.Count - 1] }
        if ($null -eq $last -or $last.Key -ne $key) {
            $last = [pscustomobject]@{
                Key = $key
                Urls = (New-Object System.Collections.Generic.List[string])
                Channels = 0
            }
            $jobs.Add($last)
        }
        $last.Urls.Add([string]$item.Url)
        if ($item.Kind -eq 'channel') { $last.Channels++ }
    }
    # A bare list would collapse into one object, and one playlist would never start.
    return ,@($jobs.ToArray())
}

function Get-HeightFormat([string]$resolution) {
    $known = @(360, 480, 720, 1080, 1440, 2160)
    $height = 0
    if (-not [int]::TryParse($resolution, [ref]$height)) { return $null }
    if ($known -notcontains $height) { return $null }
    $selectors = New-Object System.Collections.Generic.List[string]
    foreach ($cap in @($known | Where-Object { $_ -ge $height })) {
        $selectors.Add("bv*[height<=$cap]+ba/b[height<=$cap]")
    }
    $selectors.Add('bv*+ba/b')
    return ($selectors -join '/')
}

function Get-YtArguments {
    param(
        [string]$Key,
        [bool]$PlaylistFolders,
        [bool]$SkipExisting,
        [string]$Destination,
        [string]$ArchiveFile,
        [string]$BatchFile,
        [string]$Resolution = 'best',
        [bool]$AudioOnly = $false
    )
    $template = '%(title).80s [%(id)s].%(ext)s'
    if ($Key -eq 'collection') {
        if ($PlaylistFolders) {
            $template = '%(playlist).70s/%(playlist_index)s - %(title).70s [%(id)s].%(ext)s'
        } else {
            $template = '%(playlist_index)s - %(title).80s [%(id)s].%(ext)s'
        }
    } elseif ($Key -eq 'open') {
        $template = '%(playlist_index&{} - |)s%(title).80s [%(id)s].%(ext)s'
    }

    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add('--ignore-config')
    if ($AudioOnly) {
        $parts.Add('-t')
        $parts.Add('mp3')
        $parts.Add('--audio-quality')
        $parts.Add('0')
    } else {
        $parts.Add('-t')
        $parts.Add('mp4')
        $heightFormat = Get-HeightFormat $Resolution
        if ($heightFormat) {
            $parts.Add('-f')
            $parts.Add($heightFormat)
        }
    }
    if ($script:Deno -and (Test-Path -LiteralPath $script:Deno)) {
        $parts.Add('--js-runtimes')
        $parts.Add('deno:' + $script:Deno)
    }
    foreach ($part in @(
        '--ffmpeg-location', $script:ToolsDir,
        '--paths', $Destination,
        '-o', $template,
        '--windows-filenames',
        '--trim-filenames', '150',
        '--newline',
        '--progress',
        '--color', 'no_color',
        '--ignore-errors',
        '--embed-metadata',
        '--no-embed-info-json',
        '--retries', '10',
        '--fragment-retries', '10',
        '--socket-timeout', '30',
        '--print', 'after_move:YD_SAVED:%(filepath)s'
    )) {
        $parts.Add([string]$part)
    }
    if ($Key -eq 'video') {
        $parts.Add('--no-playlist')
    } elseif ($Key -eq 'collection') {
        $parts.Add('--yes-playlist')
    }
    if ($SkipExisting) {
        $parts.Add('--download-archive')
        $parts.Add($ArchiveFile)
        $parts.Add('--no-overwrites')
    } else {
        $parts.Add('--force-overwrites')
    }
    $parts.Add('-a')
    $parts.Add($BatchFile)
    return $parts.ToArray()
}

function Format-Count([int]$count, [string]$word) {
    if ($count -eq 1) { return "1 $word" }
    return "$count ${word}s"
}

function Get-MissingTools {
    $missing = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path -LiteralPath $script:YtDlp)) { $missing.Add($script:YtDlp) }
    if (-not (Test-Path -LiteralPath $script:Ffmpeg)) { $missing.Add($script:Ffmpeg) }
    return $missing
}

function Update-Shortcut {
    try {
        $wsh = New-Object -ComObject WScript.Shell
        $lnkPath = Join-Path $script:Root 'Video Downloader.lnk'
        $lnk = $wsh.CreateShortcut($lnkPath)
        $lnk.TargetPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
        $vbs = Join-Path $script:AppDir 'launch.vbs'
        $lnk.Arguments = "//nologo `"$vbs`""
        $lnk.WorkingDirectory = $script:Root
        $lnk.WindowStyle = 1
        $lnk.Description = 'Download videos and playlists as MP4 files'
        $lnk.IconLocation = (Join-Path $env:SystemRoot 'System32\imageres.dll') + ',189'
        $lnk.Save()
    } catch {
    }
}

function Load-Settings {
    $defaults = @{
        PlaylistFolders = $true
        SkipExisting = $true
        ExpandAttached = $false
        Detailed = $false
        SeenWelcome = $false
        Resolution = 'best'
        AudioOnly = $false
        DownloadsFolder = ''
    }
    if (-not (Test-Path -LiteralPath $script:SettingsPath)) { return $defaults }
    try {
        $json = Get-Content -Raw -LiteralPath $script:SettingsPath -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $json.playlistFolders) { $defaults.PlaylistFolders = [bool]$json.playlistFolders }
        if ($null -ne $json.skipExisting) { $defaults.SkipExisting = [bool]$json.skipExisting }
        if ($null -ne $json.expandAttached) { $defaults.ExpandAttached = [bool]$json.expandAttached }
        if ($null -ne $json.detailed) { $defaults.Detailed = [bool]$json.detailed }
        if ($null -ne $json.seenWelcome) { $defaults.SeenWelcome = [bool]$json.seenWelcome }
        if ($json.resolution) { $defaults.Resolution = [string]$json.resolution }
        if ($null -ne $json.audioOnly) { $defaults.AudioOnly = [bool]$json.audioOnly }
        if ($json.downloadsFolder) { $defaults.DownloadsFolder = [string]$json.downloadsFolder }
    } catch {
    }
    return $defaults
}

function Resolve-DownloadsFolder([string]$saved) {
    if ([string]::IsNullOrWhiteSpace($saved)) { return $script:DefaultDownloadsDir }
    try {
        $full = [IO.Path]::GetFullPath($saved.Trim())
    } catch {
        return $script:DefaultDownloadsDir
    }
    if ([string]::IsNullOrWhiteSpace($full)) { return $script:DefaultDownloadsDir }
    if (Test-Path -LiteralPath $full -PathType Leaf) { return $script:DefaultDownloadsDir }
    $root = [IO.Path]::GetPathRoot($full)
    if ($root -and -not (Test-Path -LiteralPath $root)) { return $script:DefaultDownloadsDir }
    return $full
}

function Save-Settings {
    if ($script:SmokeTest) { return }
    if ($null -eq $script:FolderCheck) { return }
    $obj = [ordered]@{
        playlistFolders = [bool]$script:FolderCheck.Checked
        skipExisting = [bool]$script:SkipCheck.Checked
        expandAttached = [bool]$script:AttachedCheck.Checked
        detailed = [bool]$script:DetailedCheck.Checked
        seenWelcome = [bool]$script:SeenWelcome
        resolution = (Get-SelectedResolution)
        audioOnly = [bool]$script:AudioCheck.Checked
        downloadsFolder = [string]$script:DownloadsDir
    }
    $json = $obj | ConvertTo-Json
    $utf8 = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText($script:SettingsPath, $json, $utf8)
}

function Invoke-TestDownload {
    $dest = Join-Path $env:TEMP 'video-downloader-test'
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
    New-Item -ItemType Directory -Path $dest | Out-Null
    $batch = Join-Path $env:TEMP 'video-downloader-test-links.txt'
    $archive = Join-Path $env:TEMP 'video-downloader-test-history.txt'
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllLines($batch, @('https://www.youtube.com/watch?v=jNQXAC9IVRw'), $utf8)
    $parts = Get-YtArguments -Key 'video' -PlaylistFolders $true -SkipExisting $false -Destination $dest -ArchiveFile $archive -BatchFile $batch
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $script:YtDlp
    $psi.Arguments = ConvertTo-CommandLine $parts
    $psi.WorkingDirectory = $script:Root
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $proc = [Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    if ($proc.ExitCode -ne 0) {
        throw "Test download failed ($($proc.ExitCode)).`r`n$stdout`r`n$stderr"
    }
    if ($stdout -notmatch 'YD_SAVED:') {
        throw "The downloader did not report the saved file.`r`n$stdout`r`n$stderr"
    }
    if ($stderr -match '(?m)^ERROR:') {
        throw "The downloader reported a problem.`r`n$stdout`r`n$stderr"
    }
    if ($stderr -match 'No supported JavaScript runtime') {
        throw "Deno was not used.`r`n$stderr"
    }
    $file = Get-ChildItem -LiteralPath $dest -Filter '*.mp4' -Recurse | Select-Object -First 1
    if ($null -eq $file) { throw "Test download did not create an MP4.`r`n$stdout`r`n$stderr" }
    if ($file.Name -notmatch '\[jNQXAC9IVRw\]\.mp4$') { throw "Unexpected file name: $($file.Name)" }
    $probe = & $script:Ffprobe -v error -show_entries format=format_name -show_entries stream=codec_type,codec_name -of default=nw=1 $file.FullName
    $probeText = ($probe | Out-String)
    if ($probeText -notmatch 'codec_name=h264') { throw "Video codec was not h264.`r`n$probeText" }
    if ($probeText -notmatch 'codec_name=aac') { throw "Audio codec was not aac.`r`n$probeText" }
    if ($probeText -notmatch 'format_name=mov,mp4') { throw "Container was not mp4.`r`n$probeText" }

    $audioArchive = Join-Path $env:TEMP 'video-downloader-test-audio-history.txt'
    $audioParts = Get-YtArguments -Key 'video' -PlaylistFolders $false -SkipExisting $false -Destination $dest -ArchiveFile $audioArchive -BatchFile $batch -AudioOnly $true
    $audioPsi = New-Object System.Diagnostics.ProcessStartInfo
    $audioPsi.FileName = $script:YtDlp
    $audioPsi.Arguments = ConvertTo-CommandLine $audioParts
    $audioPsi.WorkingDirectory = $script:Root
    $audioPsi.UseShellExecute = $false
    $audioPsi.CreateNoWindow = $true
    $audioPsi.RedirectStandardOutput = $true
    $audioPsi.RedirectStandardError = $true
    $audioProc = [Diagnostics.Process]::Start($audioPsi)
    $audioOut = $audioProc.StandardOutput.ReadToEnd()
    $audioErr = $audioProc.StandardError.ReadToEnd()
    $audioProc.WaitForExit()
    if ($audioProc.ExitCode -ne 0 -or $audioOut -notmatch 'YD_SAVED:' -or $audioErr -match '(?m)^ERROR:') {
        throw "MP3 download failed.`r`n$audioOut`r`n$audioErr"
    }
    $audioFile = Get-ChildItem -LiteralPath $dest -Filter '*.mp3' -Recurse | Select-Object -First 1
    if ($null -eq $audioFile) { throw "MP3 download did not create an MP3.`r`n$audioOut`r`n$audioErr" }
    $audioProbe = & $script:Ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=nw=1 $audioFile.FullName
    if (($audioProbe | Out-String) -notmatch 'codec_name=mp3') { throw "Audio codec was not mp3.`r`n$audioProbe" }
    Remove-Item -LiteralPath $audioArchive -Force -ErrorAction SilentlyContinue

    $plBatch = Join-Path $env:TEMP 'video-downloader-test-playlist.txt'
    [System.IO.File]::WriteAllLines($plBatch, @('https://www.youtube.com/playlist?list=PL4cUxeGkcC9gQeDH6xYhmO-db2mhoTSrT'), $utf8)
    $plParts = @(Get-YtArguments -Key 'collection' -PlaylistFolders $true -SkipExisting $false -Destination $dest -ArchiveFile $archive -BatchFile $plBatch)
    $plParts += @('--skip-download', '--playlist-end', '1', '--print', 'filename')
    $plPsi = New-Object System.Diagnostics.ProcessStartInfo
    $plPsi.FileName = $script:YtDlp
    $plPsi.Arguments = (ConvertTo-CommandLine $plParts)
    $plPsi.WorkingDirectory = $script:Root
    $plPsi.UseShellExecute = $false
    $plPsi.CreateNoWindow = $true
    $plPsi.RedirectStandardOutput = $true
    $plPsi.RedirectStandardError = $true
    $plProc = [Diagnostics.Process]::Start($plPsi)
    $plOut = $plProc.StandardOutput.ReadToEnd()
    $plErr = $plProc.StandardError.ReadToEnd()
    $plProc.WaitForExit()
    if ($plProc.ExitCode -ne 0 -or $plOut -notmatch 'CSS Tutorials For Beginners\\1 - .+\[I9XRrlOOazo\]\.mp4') {
        throw "Playlist naming failed.`r`n$plOut`r`n$plErr"
    }
    Remove-Item -LiteralPath $plBatch -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $dest -Recurse -Force
    Remove-Item -LiteralPath $batch -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
    Write-Output 'TEST DOWNLOAD OK'
}

if ($TestDownload) {
    try {
        Invoke-TestDownload
        exit 0
    } catch {
        Write-Output ("TEST DOWNLOAD FAIL: " + $_.Exception.Message)
        exit 1
    }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

$script:FontTitle = New-Object Drawing.Font('Segoe UI', 22, [Drawing.FontStyle]::Bold)
$script:FontSubtitle = New-Object Drawing.Font('Segoe UI', 10)
$script:FontSection = New-Object Drawing.Font('Segoe UI', 11, [Drawing.FontStyle]::Bold)
$script:FontUi = New-Object Drawing.Font('Segoe UI', 10)
$script:FontHint = New-Object Drawing.Font('Segoe UI', 9)
$script:FontButton = New-Object Drawing.Font('Segoe UI', 10)
$script:FontButtonBold = New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold)
$script:FontLog = New-Object Drawing.Font('Consolas', 10)
$script:FontHelpHeading = New-Object Drawing.Font('Segoe UI', 13, [Drawing.FontStyle]::Bold)
$script:FontHelpBody = New-Object Drawing.Font('Segoe UI', 10)

function Enable-DoubleBuffer($control) {
    $prop = $control.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'Instance,NonPublic')
    if ($prop) { $prop.SetValue($control, $true, $null) }
}

function Get-AppIcon {
    try {
        if (-not ('VideoDownloader.ShellIcon' -as [type])) {
            Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
namespace VideoDownloader {
  public static class ShellIcon {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern int ExtractIconEx(string file, int index, out IntPtr large, out IntPtr small, int count);
    [DllImport("user32.dll")]
    public static extern bool DestroyIcon(IntPtr hIcon);
    public static Icon Load(string file, int index) {
      IntPtr large, small;
      ExtractIconEx(file, index, out large, out small, 1);
      if (large == IntPtr.Zero) return null;
      Icon icon = (Icon)Icon.FromHandle(large).Clone();
      DestroyIcon(large);
      if (small != IntPtr.Zero) DestroyIcon(small);
      return icon;
    }
  }
}
'@
        }
        $dll = Join-Path $env:SystemRoot 'System32\imageres.dll'
        return [VideoDownloader.ShellIcon]::Load($dll, 189)
    } catch {
        return $null
    }
}

function Update-ButtonFace($btn) {
    if ($null -eq $btn) { return }
    $role = [string]$btn.Tag
    $gray = [Drawing.Color]::FromArgb(229, 231, 235)
    $grayText = [Drawing.Color]::FromArgb(156, 163, 175)
    if (-not $btn.Enabled) {
        $btn.BackColor = $gray
        $btn.ForeColor = $grayText
        $btn.FlatAppearance.BorderColor = $gray
        $btn.FlatAppearance.MouseOverBackColor = $gray
        $btn.FlatAppearance.MouseDownBackColor = $gray
        return
    }
    if ($role -eq 'primary') {
        $btn.BackColor = $script:ColorPrimary
        $btn.ForeColor = [Drawing.Color]::White
        $btn.FlatAppearance.BorderColor = $script:ColorPrimary
        $btn.FlatAppearance.MouseOverBackColor = $script:ColorPrimaryHover
        $btn.FlatAppearance.MouseDownBackColor = $script:ColorPrimaryHover
    } elseif ($role -eq 'danger') {
        $btn.BackColor = [Drawing.Color]::White
        $btn.ForeColor = $script:ColorDanger
        $btn.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(252, 165, 165)
        $btn.FlatAppearance.MouseOverBackColor = [Drawing.Color]::FromArgb(254, 242, 242)
        $btn.FlatAppearance.MouseDownBackColor = [Drawing.Color]::FromArgb(254, 226, 226)
    } else {
        $btn.BackColor = [Drawing.Color]::White
        $btn.ForeColor = $script:ColorInk
        $btn.FlatAppearance.BorderColor = $script:ColorLine
        $btn.FlatAppearance.MouseOverBackColor = [Drawing.Color]::FromArgb(243, 244, 246)
        $btn.FlatAppearance.MouseDownBackColor = [Drawing.Color]::FromArgb(229, 231, 235)
    }
}

function New-Button([string]$text, [string]$role, [int]$width, [int]$height) {
    $btn = New-Object Windows.Forms.Button
    $btn.Text = $text
    $btn.Tag = $role
    $btn.Width = $width
    $btn.Height = $height
    $btn.FlatStyle = [Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize = 1
    $btn.Cursor = [Windows.Forms.Cursors]::Hand
    $btn.UseVisualStyleBackColor = $false
    $btn.Margin = New-Object Windows.Forms.Padding(0, 4, 8, 0)
    if ($role -eq 'primary') { $btn.Font = $script:FontButtonBold } else { $btn.Font = $script:FontButton }
    $btn.Add_EnabledChanged({ Update-ButtonFace $this })
    Update-ButtonFace $btn
    return $btn
}

function Set-Tip($control, [string]$text) {
    $script:Tips.SetToolTip($control, $text)
    $script:TipMap[$control] = $text
}

function Set-Status([string]$text, [string]$kind) {
    if ($null -eq $script:StatusLabel) { return }
    if ($script:StatusLabel.Text -eq $text -and $script:StatusKind -eq $kind) { return }
    $script:StatusKind = $kind
    $script:StatusLabel.Text = $text
    if ($kind -eq 'ok') { $script:StatusLabel.ForeColor = $script:ColorOkText }
    elseif ($kind -eq 'err') { $script:StatusLabel.ForeColor = $script:ColorErrText }
    elseif ($kind -eq 'busy') { $script:StatusLabel.ForeColor = $script:ColorInk }
    else { $script:StatusLabel.ForeColor = $script:ColorMuted }
}

function Set-Progress([double]$percent) {
    if ($percent -lt 0) { $percent = 0 }
    if ($percent -gt 100) { $percent = 100 }
    $script:ProgressValue = $percent
    if ($null -eq $script:ProgressTrack) { return }
    $width = $script:ProgressTrack.ClientSize.Width
    $fill = [int][Math]::Round($width * ($percent / 100.0))
    if ($fill -lt 0) { $fill = 0 }
    if ($percent -gt 0 -and $fill -lt 6 -and $width -gt 0) { $fill = 6 }
    if ($fill -gt $width) { $fill = $width }
    $script:ProgressFill.Width = $fill
    $script:ProgressFill.Height = $script:ProgressTrack.ClientSize.Height
}

function Test-LogPinned {
    $box = $script:Log
    if ($null -eq $box -or $box.TextLength -le 1) { return $true }
    $last = $box.GetPositionFromCharIndex($box.TextLength - 1)
    return ($last.Y -le ($box.ClientSize.Height + 8))
}

function Write-Activity([string]$message, [string]$kind) {
    $box = $script:Log
    if ($null -eq $box -or $box.IsDisposed) { return }
    $color = $script:ColorLogText
    if ($kind -eq 'ok') { $color = $script:ColorLogOk }
    elseif ($kind -eq 'warn') { $color = $script:ColorLogWarn }
    elseif ($kind -eq 'err') { $color = $script:ColorLogErr }
    elseif ($kind -eq 'dim') { $color = $script:ColorLogMuted }
    $follow = Test-LogPinned
    if ($box.TextLength -gt 180000) {
        $box.Select(0, 60000)
        $box.SelectedText = ''
    }
    $box.SelectionStart = $box.TextLength
    $box.SelectionLength = 0
    $box.SelectionColor = $color
    $box.AppendText($message + [Environment]::NewLine)
    if ($follow) {
        $box.SelectionStart = $box.TextLength
        $box.ScrollToCaret()
    }
}

function Remember-Raw([string]$line) {
    if ($null -eq $script:RecentRaw) { return }
    $script:RecentRaw.Add($line)
    if ($script:RecentRaw.Count -gt 40) { $script:RecentRaw.RemoveAt(0) }
}

function Ensure-OutputHandlers {
    if ($script:DataHandler) { return }
    $script:DataHandler = [Delegate]::CreateDelegate([System.Diagnostics.DataReceivedEventHandler], [VideoDownloader.YtLinePump].GetMethod('OnData'))
    $script:ExitHandler = [Delegate]::CreateDelegate([System.EventHandler], [VideoDownloader.YtLinePump].GetMethod('OnExit'))
}

function Add-PendingLine([string]$line) {
    [VideoDownloader.YtLinePump]::Accept($line)
    $script:LivePercent = [double][VideoDownloader.YtLinePump]::LivePercent
    $detail = [VideoDownloader.YtLinePump]::LiveDetail
    if ($null -ne $detail) { $script:LiveDetail = [string]$detail }
}

function Read-PendingLines {
    $batch = [VideoDownloader.YtLinePump]::Drain()
    if ($null -eq $batch -or $batch -is [string]) { return ,@($batch) }
    return ,$batch
}

function Receive-Line([string]$line) {
    if ([string]::IsNullOrWhiteSpace($line)) { return }
    $line = $line.TrimEnd()
    Remember-Raw $line

    if ($line.StartsWith('YD_SAVED:')) {
        $script:Saved++
        $path = $line.Substring(9).Trim().Trim('"')
        $root = $script:DownloadsDir.TrimEnd('\')
        $name = $path
        if ($path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
            $name = $path.Substring($root.Length).TrimStart('\', '/')
        } else {
            $name = [IO.Path]::GetFileName($path)
        }
        Write-Activity "Saved  $name" 'ok'
        Set-Status "Saved  $name" 'ok'
        return
    }
    if ($line -match 'has already been downloaded') {
        $script:Skipped++
        $name = 'a video already in Downloads'
        if ($line -match '\]\s*(.+?)\s+has already been downloaded') {
            $name = [IO.Path]::GetFileName($Matches[1].Trim())
        }
        Write-Activity "Skipped  $name" 'dim'
        return
    }
    if ($line -match 'already been recorded in the archive') {
        $script:Skipped++
        $name = 'a video already in the history'
        if ($line -match '\]\s*([^:\]]+):\s+has already been recorded') {
            $name = $Matches[1].Trim()
        }
        Write-Activity "Skipped  $name" 'dim'
        return
    }
    if ($line -match 'Downloading item (\d+) of (\d+)') {
        $script:ItemIndex = [int]$Matches[1]
        $script:ItemCount = [int]$Matches[2]
        Write-Activity "Video $($Matches[1]) of $($Matches[2])" 'text'
        Set-Status "Video $($Matches[1]) of $($Matches[2])" 'busy'
        return
    }
    if ($line -match '\[download\] Destination:\s*(.+)$') {
        $script:CurrentName = [IO.Path]::GetFileName($Matches[1].Trim())
        [VideoDownloader.YtLinePump]::ClearPercent()
        $script:LivePercent = -1
        $script:LiveDetail = ''
        Set-Progress 0
        Set-Status "Starting  $($script:CurrentName)" 'busy'
        if ($script:DetailedCheck.Checked) { Write-Activity $line 'dim' }
        return
    }
    if ($line -match '\[(Merger|VideoRemuxer|VideoConvertor|Metadata|Fixup)\]') {
        Set-Status 'Packaging MP4...' 'busy'
        if ($script:DetailedCheck.Checked) { Write-Activity $line 'dim' }
        return
    }
    if ($line.StartsWith('ERROR:')) {
        $script:Failed++
        $script:JobHadError = $true
        Write-Activity $line 'err'
        Set-Status 'A video failed. The rest will continue.' 'err'
        return
    }
    if ($line.StartsWith('WARNING:')) {
        if ($script:DetailedCheck.Checked) { Write-Activity $line 'warn' }
        return
    }
    if ($script:DetailedCheck.Checked) { Write-Activity $line 'dim' }
}

function Update-LiveProgress {
    if (-not $script:Running) { return }
    $pumpPercent = [double][VideoDownloader.YtLinePump]::LivePercent
    if ($pumpPercent -ge 0) {
        $script:LivePercent = $pumpPercent
        $detail = [VideoDownloader.YtLinePump]::LiveDetail
        if ($null -ne $detail) { $script:LiveDetail = [string]$detail }
    }
    if ($script:LivePercent -lt 0) { return }
    if ([string]::IsNullOrEmpty($script:LiveDetail)) { return }
    $pct = [double]$script:LivePercent
    Set-Progress $pct
    $speed = ''
    $eta = ''
    if ($script:LiveDetail -match 'at\s+(\S+)\s+ETA\s+(\S+)') {
        $speed = $Matches[1]
        $eta = $Matches[2]
    }
    $bits = New-Object System.Collections.Generic.List[string]
    if ($script:ItemCount -gt 0) { $bits.Add("Video $($script:ItemIndex) of $($script:ItemCount)") }
    $bits.Add(("{0:N0}%" -f $pct))
    if ($speed -and $speed -ne 'Unknown') { $bits.Add($speed) }
    if ($eta -and $eta -ne 'Unknown') { $bits.Add("ETA $eta") }
    if ($script:CurrentName) { $bits.Add([string]$script:CurrentName) }
    Set-Status ($bits -join '   ') 'busy'
}

function Remove-BatchFile {
    if ($script:BatchFile -and (Test-Path -LiteralPath $script:BatchFile)) {
        Remove-Item -LiteralPath $script:BatchFile -Force -ErrorAction SilentlyContinue
    }
    $script:BatchFile = $null
}

function Stop-DownloadProcess {
    $script:CancelRequested = $true
    $proc = $script:Process
    if ($proc -and -not $proc.HasExited) {
        $taskkill = Join-Path $env:SystemRoot 'System32\taskkill.exe'
        & $taskkill /PID $proc.Id /T /F | Out-Null
    }
}

function Get-JobLabel($job) {
    $n = $job.Urls.Count
    if ($job.Key -eq 'video') {
        if ($n -eq 1) { return 'Downloading 1 video...' }
        return "Downloading $n videos..."
    }
    if ($job.Key -eq 'collection') {
        if ($job.Channels -eq $n) {
            if ($n -eq 1) { return 'Downloading 1 channel...' }
            return "Downloading $n channels..."
        }
        if ($n -eq 1) { return 'Downloading 1 playlist...' }
        return "Downloading $n playlists..."
    }
    if ($n -eq 1) { return 'Downloading 1 link...' }
    return "Downloading $n links..."
}

function Complete-Run([bool]$cancelled) {
    Remove-BatchFile
    if ($script:Process) {
        try { $script:Process.Dispose() } catch { }
        $script:Process = $null
    }
    $script:Running = $false
    $script:LivePercent = -1
    $script:LiveDetail = ''
    Set-Busy $false
    if ($cancelled) {
        Set-Progress 0
        if ($script:Saved -eq 0) { $text = 'Cancelled. Nothing was saved.' }
        else { $text = "Cancelled. $(Format-Count $script:Saved 'file') saved before the stop." }
        Set-Status $text 'err'
        Write-Activity $text 'warn'
        return
    }
    $bits = New-Object System.Collections.Generic.List[string]
    $bits.Add("$(Format-Count $script:Saved 'file') saved")
    if ($script:Skipped -gt 0) { $bits.Add("$(Format-Count $script:Skipped 'video') skipped") }
    if ($script:Failed -gt 0) { $bits.Add("$(Format-Count $script:Failed 'video') failed") }
    $text = 'Finished. ' + ($bits -join ', ') + '.'
    if ($script:Failed -gt 0) {
        Set-Status $text 'err'
        Write-Activity $text 'warn'
    } else {
        Set-Progress 100
        Set-Status $text 'ok'
        Write-Activity $text 'ok'
    }
}

function Start-JobProcess($job) {
    $script:BatchFile = Join-Path $env:TEMP ("video-downloader-" + [guid]::NewGuid().ToString('n') + '.txt')
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllLines($script:BatchFile, $job.Urls.ToArray(), $utf8)
    $archive = $script:ArchiveFile
    $audioOnly = $false
    if ($script:AudioCheck -and $script:AudioCheck.Checked) {
        $archive = $script:AudioArchiveFile
        $audioOnly = $true
    }
    $argParts = Get-YtArguments -Key $job.Key -PlaylistFolders $script:FolderCheck.Checked -SkipExisting $script:SkipCheck.Checked -Destination $script:DownloadsDir -ArchiveFile $archive -BatchFile $script:BatchFile -Resolution (Get-SelectedResolution) -AudioOnly $audioOnly
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $script:YtDlp
    $psi.Arguments = ConvertTo-CommandLine $argParts
    $psi.WorkingDirectory = $script:Root
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $utf8out = New-Object System.Text.UTF8Encoding $false
    $psi.StandardOutputEncoding = $utf8out
    $psi.StandardErrorEncoding = $utf8out
    $psi.EnvironmentVariables['PATH'] = $script:ToolsDir + ';' + $psi.EnvironmentVariables['PATH']
    $psi.EnvironmentVariables['PYTHONIOENCODING'] = 'utf-8'
    if ($script:DetailedCheck.Checked) {
        Write-Activity ('Command  ' + $psi.FileName + ' ' + $psi.Arguments) 'dim'
    }

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $proc.EnableRaisingEvents = $true
    $script:Process = $proc
    $script:ExitSeen = $false
    $script:ExitGraceDone = $false
    $script:JobCleaned = $false
    $script:ExitCode = 0
    $script:JobHadError = $false
    $script:LivePercent = -1
    $script:LiveDetail = ''
    $script:CurrentName = ''
    $script:ItemIndex = 0
    $script:ItemCount = 0
    $script:RecentRaw = New-Object System.Collections.Generic.List[string]
    Ensure-OutputHandlers
    [VideoDownloader.YtLinePump]::BeginJob()
    $proc.add_OutputDataReceived($script:DataHandler)
    $proc.add_ErrorDataReceived($script:DataHandler)
    $proc.add_Exited($script:ExitHandler)
    [void]$proc.Start()
    $proc.BeginOutputReadLine()
    $proc.BeginErrorReadLine()
}

function Start-NextJob {
    if ($script:CancelRequested) {
        Complete-Run $true
        return
    }
    $jobs = @($script:Jobs)
    if ($null -eq $script:Jobs -or $script:JobPos -ge $jobs.Count) {
        Complete-Run $false
        return
    }
    $job = $jobs[$script:JobPos]
    $script:JobPos++
    Write-Activity (Get-JobLabel $job) 'text'
    Set-Status 'Looking up the videos...' 'busy'
    Set-Progress 0
    try {
        Start-JobProcess $job
    } catch {
        Write-Activity ('Could not start the downloader. ' + $_.Exception.Message) 'err'
        $script:Failed++
        $script:JobHadError = $true
        Remove-BatchFile
        Start-NextJob
    }
}

function Finish-CurrentJob {
    $code = 0
    if ($null -ne $script:ExitCode) { $code = [int]$script:ExitCode }
    if ($script:Process) {
        try { $script:Process.Dispose() } catch { }
        $script:Process = $null
    }
    Remove-BatchFile
    if ($script:CancelRequested) {
        Complete-Run $true
        return
    }
    if ($code -ne 0 -and -not $script:JobHadError) {
        $script:Failed++
        Write-Activity "The downloader stopped with an error (code $code)." 'err'
        if ($script:RecentRaw -and $script:RecentRaw.Count -gt 0) {
            $start = [Math]::Max(0, $script:RecentRaw.Count - 12)
            for ($i = $start; $i -lt $script:RecentRaw.Count; $i++) {
                Write-Activity $script:RecentRaw[$i] 'dim'
            }
        }
    }
    Start-NextJob
}

function Invoke-DownloadTick {
    if ($script:InTick) { return }
    $script:InTick = $true
    try {
        if (-not $script:Running) { return }
        if ([VideoDownloader.YtLinePump]::Exited) {
            $script:ExitSeen = $true
            $script:ExitCode = [int][VideoDownloader.YtLinePump]::ExitCode
        }
        $pending = Read-PendingLines
        if ($null -ne $pending) {
            for ($i = 0; $i -lt $pending.Count; $i++) {
                $line = [string]$pending[$i]
                if (-not [string]::IsNullOrWhiteSpace($line)) { Receive-Line $line }
            }
        }
        Update-LiveProgress
        if ($script:ExitSeen) {
            $late = Read-PendingLines
            if ($null -ne $late) {
                for ($i = 0; $i -lt $late.Count; $i++) {
                    $line = [string]$late[$i]
                    if (-not [string]::IsNullOrWhiteSpace($line)) { Receive-Line $line }
                }
            }
            if (-not $script:ExitGraceDone) {
                $script:ExitGraceDone = $true
                return
            }
            if (-not $script:JobCleaned) {
                $script:JobCleaned = $true
                Finish-CurrentJob
            }
        } elseif ($script:CancelRequested -and $null -eq $script:Process) {
            Complete-Run $true
        }
    } catch {
        try { Write-Activity ('The window hit a problem. ' + $_.Exception.Message) 'err' } catch { }
    } finally {
        $script:InTick = $false
    }
}

function Set-Busy([bool]$busy) {
    $script:Running = $busy
    $canEdit = -not $busy
    $script:LinkBox.ReadOnly = $busy
    $script:PasteButton.Enabled = $canEdit
    $script:ClearButton.Enabled = $canEdit
    $script:LoadButton.Enabled = $canEdit
    $script:SaveButton.Enabled = $canEdit
    $script:FolderCheck.Enabled = $canEdit
    $script:SkipCheck.Enabled = $canEdit
    $script:AttachedCheck.Enabled = $canEdit
    $script:DownloadButton.Enabled = $canEdit -and $script:ToolsOk
    $script:CancelButton.Enabled = $busy
    if ($script:AudioCheck) { $script:AudioCheck.Enabled = $canEdit }
    if ($script:ChangeFolderButton) { $script:ChangeFolderButton.Enabled = $canEdit }
    Update-DownloadMode
    if ($busy) {
        $script:LinkBox.BackColor = [Drawing.Color]::FromArgb(249, 250, 251)
        $script:Form.Text = 'Video Downloader - Downloading'
    } else {
        $script:LinkBox.BackColor = [Drawing.Color]::White
        $script:Form.Text = 'Video Downloader'
    }
}

function Get-SelectedResolution {
    if (-not $script:ResolutionBox -or -not $script:ResolutionValues) { return 'best' }
    $index = [int]$script:ResolutionBox.SelectedIndex
    if ($index -lt 0 -or $index -ge @($script:ResolutionValues).Count) { return 'best' }
    return [string]$script:ResolutionValues[$index]
}

function Update-DownloadMode {
    $audio = $false
    if ($script:AudioCheck) { $audio = [bool]$script:AudioCheck.Checked }
    $editable = -not $script:Running
    if ($script:ResolutionBox) { $script:ResolutionBox.Enabled = $editable -and -not $audio }
    if ($script:ResolutionLabel) { $script:ResolutionLabel.Enabled = $editable -and -not $audio }
    if ($script:SubtitleLabel) {
        if ($audio) {
            $script:SubtitleLabel.Text = 'Paste a video or playlist link. Each download is saved as an MP3 in the Downloads folder.'
        } else {
            $script:SubtitleLabel.Text = 'Paste a video or playlist link. Each download is saved as an MP4 in the Downloads folder.'
        }
    }
}

function Add-LinkText([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return }
    $text = $text.Trim()
    if ([string]::IsNullOrWhiteSpace($script:LinkBox.Text)) {
        $script:LinkBox.Text = $text
    } else {
        $script:LinkBox.Text = $script:LinkBox.Text.TrimEnd() + [Environment]::NewLine + $text
    }
}

function Read-DroppedFile([string]$path) {
    $item = Get-Item -LiteralPath $path
    if ($item.Length -gt 2MB) {
        Write-Activity "Skipped a dropped file larger than 2 MB: $($item.Name)" 'warn'
        return
    }
    $ext = $item.Extension.ToLowerInvariant()
    if ($ext -ne '.txt' -and $ext -ne '.url') {
        Write-Activity "Skipped $($item.Name). Drop a link or a .txt list." 'warn'
        return
    }
    $text = [IO.File]::ReadAllText($path)
    if ($ext -eq '.url' -and $text -match '(?m)^URL=(.+)$') {
        Add-LinkText $Matches[1].Trim()
        return
    }
    Add-LinkText $text
}

function Add-DroppedData($data) {
    if ($script:Running) { return }
    if ($data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) {
        $files = @($data.GetData([Windows.Forms.DataFormats]::FileDrop))
        foreach ($file in $files) { Read-DroppedFile $file }
        return
    }
    $payload = $null
    if ($data.GetDataPresent([Windows.Forms.DataFormats]::UnicodeText)) {
        $payload = [string]$data.GetData([Windows.Forms.DataFormats]::UnicodeText)
    } elseif ($data.GetDataPresent([Windows.Forms.DataFormats]::Text)) {
        $payload = [string]$data.GetData([Windows.Forms.DataFormats]::Text)
    }
    if ($payload) { Add-LinkText $payload }
}

function Request-Cancel {
    if (-not $script:Running) { return }
    $script:CancelRequested = $true
    Set-Status 'Stopping...' 'busy'
    Stop-DownloadProcess
}

function Start-Download {
    if ($script:Running) { return }
    $missing = @(Get-MissingTools)
    if ($missing.Count -gt 0) {
        $text = "The downloader tools are missing:`r`n`r`n" + ($missing -join "`r`n")
        [Windows.Forms.MessageBox]::Show($text, 'Video Downloader', 'OK', 'Error') | Out-Null
        return
    }
    if ([string]::IsNullOrWhiteSpace($script:LinkBox.Text)) {
        [Windows.Forms.MessageBox]::Show("Add at least one link.`r`n`r`nA video:`r`nhttps://www.youtube.com/watch?v=...`r`n`r`nA playlist:`r`nhttps://www.youtube.com/playlist?list=...", 'Video Downloader', 'OK', 'Information') | Out-Null
        return
    }
    $parsed = Get-LinksFromText $script:LinkBox.Text $script:AttachedCheck.Checked
    $items = $parsed.Items
    if ($parsed.Invalid.Count -gt 0 -and $items.Count -eq 0) {
        [Windows.Forms.MessageBox]::Show("None of these lines are web links.`r`n`r`nPaste a full link, one per line.", 'Video Downloader', 'OK', 'Information') | Out-Null
        return
    }
    if ($parsed.Invalid.Count -gt 0) {
        $shown = @($parsed.Invalid | Select-Object -First 6)
        $extra = ''
        if ($parsed.Invalid.Count -gt 6) { $extra = "`r`n...and $($parsed.Invalid.Count - 6) more" }
        $ask = "Some lines are not web links:`r`n`r`n" + ($shown -join "`r`n") + $extra + "`r`n`r`nDownload the links that are ready?"
        $answer = [Windows.Forms.MessageBox]::Show($ask, 'Video Downloader', 'YesNo', 'Question')
        if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return }
    }
    $channels = @($items | Where-Object { $_.Kind -eq 'channel' })
    if ($channels.Count -gt 0) {
        $shown = @($channels | Select-Object -First 6 | ForEach-Object { $_.Url })
        $extra = ''
        if ($channels.Count -gt 6) { $extra = "`r`nand $($channels.Count - 6) more" }
        $ask = "These links look like channels. A channel can contain a large number of videos.`r`n`r`n" + ($shown -join "`r`n") + $extra + "`r`n`r`nDownload the channels along with any other links?"
        $answer = [Windows.Forms.MessageBox]::Show($ask, 'Video Downloader', 'YesNoCancel', 'Question')
        if ($answer -eq [Windows.Forms.DialogResult]::Cancel) { return }
        if ($answer -eq [Windows.Forms.DialogResult]::No) {
            $kept = New-Object System.Collections.Generic.List[object]
            foreach ($item in $items) {
                if ($item.Kind -ne 'channel') { $kept.Add($item) }
            }
            $items = $kept
        }
    }
    if ($null -eq $items -or $items.Count -eq 0) {
        [Windows.Forms.MessageBox]::Show('No links left to download.', 'Video Downloader', 'OK', 'Information') | Out-Null
        return
    }
    if (-not (Test-Path -LiteralPath $script:DownloadsDir)) {
        New-Item -ItemType Directory -Path $script:DownloadsDir | Out-Null
    }
    $script:Jobs = Build-Jobs $items
    $script:JobPos = 0
    $script:Saved = 0
    $script:Skipped = 0
    $script:Failed = 0
    $script:CancelRequested = $false
    $script:LivePercent = -1
    $script:Process = $null
    Set-Busy $true
    Set-Progress 0
    Write-Activity '--------' 'dim'
    Write-Activity 'Starting download.' 'text'
    if ($parsed.DuplicateCount -gt 0) {
        Write-Activity ("Left out $(Format-Count $parsed.DuplicateCount 'duplicate link').") 'dim'
    }
    Start-NextJob
}

function Choose-DownloadsFolder {
    $dlg = New-Object Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Choose where new videos and MP3s are saved'
    $dlg.ShowNewFolderButton = $true
    if (Test-Path -LiteralPath $script:DownloadsDir) {
        $dlg.SelectedPath = $script:DownloadsDir
    } else {
        $dlg.SelectedPath = $script:DefaultDownloadsDir
    }
    if ($dlg.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { return }
    $chosen = Resolve-DownloadsFolder $dlg.SelectedPath
    if ($chosen -ne $dlg.SelectedPath -and $chosen -eq $script:DefaultDownloadsDir) {
        [Windows.Forms.MessageBox]::Show('That folder cannot be used. New files will stay in the current folder.', 'Video Downloader', 'OK', 'Information') | Out-Null
        return
    }
    $script:DownloadsDir = $chosen
    if ($script:DownloadsPathBox) { $script:DownloadsPathBox.Text = $chosen }
    Save-Settings
    Write-Activity ("New downloads will be saved to $chosen") 'text'
}

function Open-DownloadsFolder {
    if (-not (Test-Path -LiteralPath $script:DownloadsDir)) {
        New-Item -ItemType Directory -Path $script:DownloadsDir | Out-Null
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'explorer.exe'
    $psi.Arguments = '/e,"' + $script:DownloadsDir + '"'
    $psi.UseShellExecute = $true
    [void][Diagnostics.Process]::Start($psi)
}

function Paste-Links {
    if (-not [Windows.Forms.Clipboard]::ContainsText()) {
        [Windows.Forms.MessageBox]::Show('The clipboard does not have any text to paste.', 'Video Downloader', 'OK', 'Information') | Out-Null
        return
    }
    Add-LinkText ([Windows.Forms.Clipboard]::GetText())
}

function Load-ListFile {
    $dlg = New-Object Windows.Forms.OpenFileDialog
    $dlg.Title = 'Open a list of links'
    $dlg.Filter = 'Text files (*.txt)|*.txt|All files (*.*)|*.*'
    $dlg.InitialDirectory = $script:ListsDir
    if ($dlg.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { return }
    $text = [IO.File]::ReadAllText($dlg.FileName)
    if (-not [string]::IsNullOrWhiteSpace($script:LinkBox.Text)) {
        $answer = [Windows.Forms.MessageBox]::Show("Add these links below the ones already in the box?`r`n`r`nYes adds them. No replaces the box.", 'Video Downloader', 'YesNoCancel', 'Question')
        if ($answer -eq [Windows.Forms.DialogResult]::Cancel) { return }
        if ($answer -eq [Windows.Forms.DialogResult]::No) { $script:LinkBox.Clear() }
    }
    Add-LinkText $text
}

function Save-ListFile {
    if ([string]::IsNullOrWhiteSpace($script:LinkBox.Text)) {
        [Windows.Forms.MessageBox]::Show('There are no links to save.', 'Video Downloader', 'OK', 'Information') | Out-Null
        return
    }
    $dlg = New-Object Windows.Forms.SaveFileDialog
    $dlg.Title = 'Save this list'
    $dlg.Filter = 'Text files (*.txt)|*.txt'
    $dlg.InitialDirectory = $script:ListsDir
    $dlg.FileName = 'my-links.txt'
    $dlg.OverwritePrompt = $true
    if ($dlg.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { return }
    $utf8 = New-Object System.Text.UTF8Encoding $true
    [IO.File]::WriteAllText($dlg.FileName, $script:LinkBox.Text.Trim() + [Environment]::NewLine, $utf8)
    Write-Activity ("Saved the list to " + [IO.Path]::GetFileName($dlg.FileName)) 'ok'
}

function Get-HelpSections {
    $downloads = $script:DownloadsDir
    $history = $script:ArchiveFile
    $audioHistory = $script:AudioArchiveFile
    $license = Join-Path $script:ToolsDir 'FFmpeg-LICENSE.txt'
    return @(
        @{
            Title = 'Opening the program'
            Body = "Double-click Video Downloader in this folder. The window that opens is the whole program.`r`n`r`nIf you move this folder and that shortcut stops opening, open app\launch.vbs. That starts the program and repairs the shortcut."
        },
        @{
            Title = 'Adding links'
            Body = "Paste one or more links into the box, one per line. You can mix video links and playlist links. Blank lines are ignored.`r`n`r`nLoad a list reads a text file of links. Save this list writes the box to a text file you can open later. You can also drop a link, or a .txt file, onto the box.`r`n`r`nCtrl+Enter starts the download."
        },
        @{
            Title = 'Videos, playlists, and channels'
            Body = "A link to one video downloads that video. A link to a playlist downloads every video in the playlist, in playlist order.`r`n`r`nYouTube often adds a playlist to the end of a video link. Those links still download as a single video. Turn on `"Download the playlist attached to a video link`" only when you want every video in that attached playlist.`r`n`r`nA channel link can contain a large number of videos. The program asks before downloading one.`r`n`r`nLinks from other sites work too, when the downloader supports that site."
        },
        @{
            Title = 'Where the files go'
            Body = "Videos are saved as MP4 files in:`r`n`r`n$downloads`r`n`r`nChange, next to that folder path, picks a different place. The choice is remembered the next time you open the program. Files already saved stay where they are.`r`n`r`nTurn on `"Audio only, save as MP3`" to save the soundtrack instead, in that same folder. Turn on `"Save each playlist into its own folder`" to put a playlist's files in a folder named after the playlist. Single videos stay directly in the chosen folder.`r`n`r`nOpen Downloads shows this folder in File Explorer."
        },
        @{
            Title = 'Picture size and audio only'
            Body = "Resolution is used when a video offers more than one picture size. Best available keeps the usual choice: the best MP4 that plays in ordinary video players. Pick a size such as 1080p or 720p to prefer that size. If the video does not offer it, the closest size that does exist is used. A video with only one size is downloaded as it is.`r`n`r`nAudio only, save as MP3 keeps the soundtrack and does not save a picture. The file is a high-quality MP3. Videos you already saved are not replaced."
        },
        @{
            Title = 'What is inside the MP4'
            Body = "The video and the audio are saved together in one file. The program prefers a format that plays in ordinary video players, and repackages other formats into MP4 when it needs to.`r`n`r`nThe file name is the video title plus a short id, so two videos with the same title do not overwrite each other. When the site provides a post date, that date is used as the file date."
        },
        @{
            Title = 'Skipping videos you already have'
            Body = "Turn on `"Skip videos you have already downloaded`" to remember each finished video in:`r`n`r`n$history`r`n`r`nMP3 downloads are remembered separately, in:`r`n`r`n$audioHistory`r`n`r`nSaving an MP3 does not skip the video, and saving a video does not skip the MP3. Uncheck the option to download something again. The history keeps an item even after you delete the file. Delete the matching history file as well when you want that item downloaded again."
        },
        @{
            Title = 'Progress, problems, and stopping'
            Body = "The line under the buttons names the current video. The bar shows how much of that file has downloaded. The activity box lists saved files, skipped videos, and problems.`r`n`r`nShow detailed activity adds the downloader's own technical messages. Turn it on when a video will not download and you want the full reason.`r`n`r`nCancel, or the Esc key, stops the download. Videos that already finished stay in Downloads. A half-finished video continues the next time you download that link.`r`n`r`nPrivate, deleted, region-locked, or age-restricted videos are reported in the activity box, and the rest of the list continues. This program downloads publicly available videos. A video that asks for a login will usually fail."
        },
        @{
            Title = 'What is in this folder'
            Body = "Video Downloader: double-click this to open the program.`r`napp: the program, your settings, and the download history.`r`ntools: yt-dlp, which fetches the videos, FFmpeg, which packages them as MP4 or MP3, and Deno, which lets YouTube offer its full list of sizes. FFmpeg is free software. Its license is $license.`r`ndownloads: your files.`r`nsaved-lists: link lists you save. links.txt is the list that was already in this folder."
        }
    )
}

function Add-HelpHeading($box, [string]$text) {
    if ($box.TextLength -gt 0) {
        $box.SelectionStart = $box.TextLength
        $box.SelectionLength = 0
        $box.SelectionFont = $script:FontHelpBody
        $box.SelectionColor = $script:ColorBody
        $box.AppendText([Environment]::NewLine)
    }
    $box.SelectionStart = $box.TextLength
    $box.SelectionLength = 0
    $box.SelectionFont = $script:FontHelpHeading
    $box.SelectionColor = $script:ColorInk
    $box.AppendText($text + [Environment]::NewLine)
}

function Add-HelpBody($box, [string]$text) {
    $box.SelectionStart = $box.TextLength
    $box.SelectionLength = 0
    $box.SelectionFont = $script:FontHelpBody
    $box.SelectionColor = $script:ColorBody
    $box.AppendText($text.Trim() + [Environment]::NewLine)
}

function New-HelpForm {
    $help = New-Object Windows.Forms.Form
    $help.Text = 'How this works'
    $help.StartPosition = 'CenterParent'
    $help.Font = $script:FontUi
    $help.BackColor = [Drawing.Color]::White
    $help.AutoScaleMode = [Windows.Forms.AutoScaleMode]::None
    $help.MinimizeBox = $false
    $help.MaximizeBox = $true
    $help.ShowInTaskbar = $false
    $help.KeyPreview = $true
    $area = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $w = [Math]::Min(760, $area.Width - 40)
    $h = [Math]::Min(820, $area.Height - 40)
    $help.ClientSize = New-Object Drawing.Size($w, $h)
    $help.MinimumSize = New-Object Drawing.Size([Math]::Min(640, $area.Width), [Math]::Min(480, $area.Height))
    $icon = Get-AppIcon
    if ($icon) { $help.Icon = $icon }
    Enable-DoubleBuffer $help

    $header = New-Object Windows.Forms.Panel
    $header.Dock = 'Top'
    $header.Height = 92
    $header.BackColor = $script:ColorHeader
    $title = New-Object Windows.Forms.Label
    $title.Text = 'How this works'
    $title.Font = $script:FontTitle
    $title.ForeColor = [Drawing.Color]::White
    $title.BackColor = $script:ColorHeader
    $title.AutoSize = $false
    $sub = New-Object Windows.Forms.Label
    $sub.Text = 'Links, folders, skipping, and what is in this folder.'
    $sub.Font = $script:FontSubtitle
    $sub.ForeColor = $script:ColorHeaderMuted
    $sub.BackColor = $script:ColorHeader
    $sub.AutoSize = $false
    $header.Controls.Add($title)
    $header.Controls.Add($sub)
    $header.Tag = @{ Title = $title; Sub = $sub }
    $header.Add_Resize({
        $this.Tag.Title.SetBounds(28, 16, ($this.ClientSize.Width - 56), 36)
        $this.Tag.Sub.SetBounds(28, 54, ($this.ClientSize.Width - 56), 24)
    })

    $footer = New-Object Windows.Forms.Panel
    $footer.Dock = 'Bottom'
    $footer.Height = 64
    $footer.BackColor = $script:ColorPage
    $close = New-Button 'Close' 'secondary' 110 34
    $footer.Controls.Add($close)
    $footer.Tag = $close
    $footer.Add_Resize({
        $button = $this.Tag
        $button.Location = New-Object Drawing.Point(($this.ClientSize.Width - $button.Width - 24), 14)
    })
    $footer.Add_Paint({
        $pen = New-Object Drawing.Pen $script:ColorLine
        $_.Graphics.DrawLine($pen, 0, 0, $this.Width, 0)
        $pen.Dispose()
    })
    $close.Add_Click({ $script:HelpForm.Close() })
    Set-Tip $close 'Close this guide. Esc does this too.'

    $bodyHost = New-Object Windows.Forms.Panel
    $bodyHost.Dock = 'Fill'
    $bodyHost.BackColor = [Drawing.Color]::White
    $bodyHost.Padding = New-Object Windows.Forms.Padding(24, 12, 12, 8)
    $box = New-Object Windows.Forms.RichTextBox
    $box.Dock = 'Fill'
    $box.BorderStyle = 'None'
    $box.ReadOnly = $true
    $box.BackColor = [Drawing.Color]::White
    $box.Font = $script:FontHelpBody
    $box.DetectUrls = $false
    $box.ScrollBars = 'Vertical'
    $box.ShortcutsEnabled = $true
    $bodyHost.Controls.Add($box)
    foreach ($section in (Get-HelpSections)) {
        Add-HelpHeading $box $section.Title
        Add-HelpBody $box $section.Body
    }
    $box.SelectionStart = 0
    $box.SelectionLength = 0
    $script:HelpBox = $box

    $help.Controls.Add($bodyHost)
    $help.Controls.Add($footer)
    $help.Controls.Add($header)
    $help.Add_KeyDown({
        if ($_.KeyCode -eq [Windows.Forms.Keys]::Escape) {
            $script:HelpForm.Close()
            $_.SuppressKeyPress = $true
        }
    })
    $help.Add_FormClosed({ $script:HelpForm = $null })
    $header.PerformLayout()
    return $help
}

function Show-Help {
    if ($script:HelpForm -and -not $script:HelpForm.IsDisposed) {
        $script:HelpForm.Activate()
        return
    }
    $script:HelpForm = New-HelpForm
    [void]$script:HelpForm.Show($script:Form)
}

function Write-Welcome {
    Write-Activity 'Ready. Paste a video or playlist link, then click Download.' 'text'
    Write-Activity 'A playlist link downloads every video in the playlist. A video link downloads only that video.' 'text'
    $oldList = Join-Path $script:ListsDir 'links.txt'
    if ((Test-Path -LiteralPath $oldList) -and -not $script:SeenWelcome) {
        Write-Activity 'An older link list is saved at saved-lists\links.txt. Use Load a list to open it.' 'dim'
        $script:SeenWelcome = $true
        Save-Settings
    }
}

function Warn-MissingTools {
    $missing = @(Get-MissingTools)
    if ($missing.Count -eq 0) {
        $script:ToolsOk = $true
        return
    }
    $script:ToolsOk = $false
    $text = "The downloader tools are missing:`r`n" + ($missing -join "`r`n")
    Write-Activity $text 'err'
    if (-not $script:SmokeTest) {
        [Windows.Forms.MessageBox]::Show($text, 'Video Downloader', 'OK', 'Error') | Out-Null
    }
}

function Layout-Actions {
    $panel = $script:ActionPanel
    if ($null -eq $panel -or $panel.ClientSize.Width -lt 20) { return }
    $y = [Math]::Max(0, [int](($panel.ClientSize.Height - $script:DownloadButton.Height) / 2))
    $script:DownloadButton.Location = New-Object Drawing.Point(0, $y)
    $script:CancelButton.Location = New-Object Drawing.Point(($script:DownloadButton.Right + 8), ($y + 2))
    $script:HelpButton.Location = New-Object Drawing.Point(($panel.ClientSize.Width - $script:HelpButton.Width), ($y + 2))
    $script:OpenButton.Location = New-Object Drawing.Point(($script:HelpButton.Left - 8 - $script:OpenButton.Width), ($y + 2))
}

function Layout-Options {
    $card = $script:OptionsCard
    if ($null -eq $card -or $card.ClientSize.Width -lt 20) { return }
    $script:OptionsTitle.SetBounds(16, 12, ($card.ClientSize.Width - 32), 22)
    $y = 40
    foreach ($chk in @($script:FolderCheck, $script:SkipCheck, $script:AttachedCheck, $script:DetailedCheck)) {
        $chk.Location = New-Object Drawing.Point(16, $y)
        $y += 28
    }
    if ($script:ModeRow) {
        $script:ModeRow.SetBounds(16, ($y + 2), ($card.ClientSize.Width - 32), 32)
        $script:ResolutionLabel.Location = New-Object Drawing.Point(0, 6)
        $script:ResolutionBox.Location = New-Object Drawing.Point(84, 2)
        $script:AudioCheck.Location = New-Object Drawing.Point(276, 4)
        $y += 36
    }
    if ($script:FolderRow) {
        $rowWidth = $card.ClientSize.Width - 32
        $script:FolderRow.SetBounds(16, $y, $rowWidth, 32)
        $script:ChangeFolderButton.Location = New-Object Drawing.Point(($rowWidth - 88), 0)
        $script:DownloadsPathBox.SetBounds(64, 4, ([Math]::Max(40, $rowWidth - 64 - 96)), 24)
    }
}

function Update-ChromeLayout {
    $header = $script:Header
    if ($header -and $header.ClientSize.Width -gt 0) {
        $script:TitleLabel.SetBounds(28, 18, ($header.ClientSize.Width - 56), 36)
        $script:SubtitleLabel.SetBounds(28, 56, ($header.ClientSize.Width - 56), 40)
    }
    $status = $script:StatusPanel
    if ($status -and $status.ClientSize.Width -gt 0) {
        $script:StatusLabel.SetBounds(24, 8, ($status.ClientSize.Width - 48), 22)
        $script:ProgressTrack.SetBounds(24, 36, ([Math]::Max(0, $status.ClientSize.Width - 48)), 8)
        Set-Progress $script:ProgressValue
    }
    Layout-Actions
    Layout-Options
}

function New-Check([string]$text) {
    $chk = New-Object Windows.Forms.CheckBox
    $chk.Text = $text
    $chk.AutoSize = $true
    $chk.Font = $script:FontUi
    $chk.ForeColor = $script:ColorInk
    $chk.BackColor = [Drawing.Color]::White
    $chk.UseVisualStyleBackColor = $false
    return $chk
}

# Window
$script:ToolsOk = $false
$script:Running = $false
$script:SeenWelcome = $false
$script:ProgressValue = 0
$script:LivePercent = -1
$script:Saved = 0
$script:Skipped = 0
$script:Failed = 0
$script:CancelRequested = $false
$script:PendingLines = New-Object System.Collections.ArrayList
$script:QueueLock = New-Object Object
$script:RecentRaw = New-Object System.Collections.Generic.List[string]
$script:TipMap = @{}
$script:Tips = New-Object Windows.Forms.ToolTip
$script:Tips.InitialDelay = 400
$script:Tips.ReshowDelay = 200
$script:Tips.AutoPopDelay = 20000
$script:Tips.ShowAlways = $true

$settings = Load-Settings
$script:DownloadsDir = Resolve-DownloadsFolder $settings.DownloadsFolder
$script:SeenWelcome = [bool]$settings.SeenWelcome

$script:Form = New-Object Windows.Forms.Form
$script:Form.Text = 'Video Downloader'
$script:Form.Font = $script:FontUi
$script:Form.BackColor = $script:ColorPage
$script:Form.StartPosition = 'CenterScreen'
$script:Form.AutoScaleMode = [Windows.Forms.AutoScaleMode]::None
$script:Form.KeyPreview = $true
$area = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$wantW = 1040
$wantH = 900
if ($wantW -gt ($area.Width - 24)) { $wantW = [Math]::Max(760, $area.Width - 24) }
if ($wantH -gt ($area.Height - 24)) { $wantH = [Math]::Max(640, $area.Height - 24) }
$script:Form.ClientSize = New-Object Drawing.Size($wantW, $wantH)
$script:Form.MinimumSize = New-Object Drawing.Size([Math]::Min(880, $area.Width), [Math]::Min(840, $area.Height))
$appIcon = Get-AppIcon
if ($appIcon) { $script:Form.Icon = $appIcon }
Enable-DoubleBuffer $script:Form

$script:Header = New-Object Windows.Forms.Panel
$script:Header.Dock = 'Top'
$script:Header.Height = 108
$script:Header.BackColor = $script:ColorHeader
$script:TitleLabel = New-Object Windows.Forms.Label
$script:TitleLabel.Text = 'Video Downloader'
$script:TitleLabel.Font = $script:FontTitle
$script:TitleLabel.ForeColor = [Drawing.Color]::White
$script:TitleLabel.BackColor = $script:ColorHeader
$script:SubtitleLabel = New-Object Windows.Forms.Label
$script:SubtitleLabel.Text = "Paste a video or playlist link. Each download is saved as an MP4 in the Downloads folder."
$script:SubtitleLabel.Font = $script:FontSubtitle
$script:SubtitleLabel.ForeColor = $script:ColorHeaderMuted
$script:SubtitleLabel.BackColor = $script:ColorHeader
$script:Header.Controls.Add($script:TitleLabel)
$script:Header.Controls.Add($script:SubtitleLabel)

$script:StatusPanel = New-Object Windows.Forms.Panel
$script:StatusPanel.Dock = 'Bottom'
$script:StatusPanel.Height = 58
$script:StatusPanel.BackColor = [Drawing.Color]::White
$script:StatusLabel = New-Object Windows.Forms.Label
$script:StatusLabel.Text = 'Ready'
$script:StatusLabel.Font = $script:FontUi
$script:StatusLabel.ForeColor = $script:ColorMuted
$script:StatusLabel.AutoEllipsis = $true
$script:StatusLabel.BackColor = [Drawing.Color]::White
$script:ProgressTrack = New-Object Windows.Forms.Panel
$script:ProgressTrack.BackColor = [Drawing.Color]::FromArgb(229, 231, 235)
$script:ProgressTrack.Height = 8
$script:ProgressFill = New-Object Windows.Forms.Panel
$script:ProgressFill.BackColor = $script:ColorPrimary
$script:ProgressFill.Height = 8
$script:ProgressFill.Width = 0
$script:ProgressTrack.Controls.Add($script:ProgressFill)
$script:StatusPanel.Controls.Add($script:StatusLabel)
$script:StatusPanel.Controls.Add($script:ProgressTrack)
$script:StatusPanel.Add_Paint({
    $pen = New-Object Drawing.Pen $script:ColorLine
    $_.Graphics.DrawLine($pen, 0, 0, $script:StatusPanel.Width, 0)
    $pen.Dispose()
})

$table = New-Object Windows.Forms.TableLayoutPanel
$table.Dock = 'Fill'
$table.BackColor = $script:ColorPage
$table.ColumnCount = 1
$table.RowCount = 8
$table.Padding = New-Object Windows.Forms.Padding(24, 16, 24, 8)
$table.Margin = New-Object Windows.Forms.Padding(0)
$table.GrowStyle = 'FixedSize'
[void]$table.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent, 100)))
[void]$table.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute, 26)))
[void]$table.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent, 36)))
[void]$table.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute, 48)))
[void]$table.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute, 42)))
[void]$table.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute, 240)))
[void]$table.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute, 52)))
[void]$table.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute, 28)))
[void]$table.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent, 64)))

$linksLabel = New-Object Windows.Forms.Label
$linksLabel.Text = 'Links'
$linksLabel.Font = $script:FontSection
$linksLabel.ForeColor = $script:ColorInk
$linksLabel.BackColor = $script:ColorPage
$linksLabel.Dock = 'Fill'
$linksLabel.TextAlign = 'BottomLeft'

$script:LinkHost = New-Object Windows.Forms.Panel
$script:LinkHost.Dock = 'Fill'
$script:LinkHost.BackColor = [Drawing.Color]::White
$script:LinkHost.Padding = New-Object Windows.Forms.Padding(8, 6, 8, 6)
$script:LinkHost.Margin = New-Object Windows.Forms.Padding(0, 4, 0, 4)
$script:LinkBox = New-Object Windows.Forms.TextBox
$script:LinkBox.Multiline = $true
$script:LinkBox.ScrollBars = 'Vertical'
$script:LinkBox.BorderStyle = 'None'
$script:LinkBox.Font = $script:FontUi
$script:LinkBox.BackColor = [Drawing.Color]::White
$script:LinkBox.ForeColor = $script:ColorInk
$script:LinkBox.Dock = 'Fill'
$script:LinkBox.AcceptsReturn = $true
$script:LinkBox.AcceptsTab = $false
$script:LinkBox.HideSelection = $false
$script:LinkBox.WordWrap = $true
$script:LinkHost.Controls.Add($script:LinkBox)
$script:LinkHost.Add_Paint({
    $color = $script:ColorLine
    if ($script:LinkFocused) { $color = $script:ColorPrimary }
    $pen = New-Object Drawing.Pen $color
    $_.Graphics.DrawRectangle($pen, 0, 0, ($script:LinkHost.Width - 1), ($script:LinkHost.Height - 1))
    $pen.Dispose()
})
$script:LinkBox.Add_Enter({ $script:LinkFocused = $true; $script:LinkHost.Invalidate() })
$script:LinkBox.Add_Leave({ $script:LinkFocused = $false; $script:LinkHost.Invalidate() })
$script:LinkBox.AllowDrop = $true
$script:LinkBox.Add_DragEnter({
    if ($script:Running) { $_.Effect = 'None'; return }
    $data = $_.Data
    if ($data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop) -or $data.GetDataPresent([Windows.Forms.DataFormats]::UnicodeText) -or $data.GetDataPresent([Windows.Forms.DataFormats]::Text)) {
        $_.Effect = 'Copy'
    } else {
        $_.Effect = 'None'
    }
})
$script:LinkBox.Add_DragDrop({ Add-DroppedData $_.Data })

$hint = New-Object Windows.Forms.Label
$hint.Text = 'One link per line. A playlist link downloads every video in the playlist. A video link downloads only that video.'
$hint.Font = $script:FontHint
$hint.ForeColor = $script:ColorMuted
$hint.BackColor = $script:ColorPage
$hint.Dock = 'Fill'
$hint.TextAlign = 'TopLeft'

$linkButtons = New-Object Windows.Forms.FlowLayoutPanel
$linkButtons.Dock = 'Fill'
$linkButtons.FlowDirection = 'LeftToRight'
$linkButtons.WrapContents = $false
$linkButtons.BackColor = $script:ColorPage
$linkButtons.Margin = New-Object Windows.Forms.Padding(0)
$script:PasteButton = New-Button 'Paste' 'secondary' 84 32
$script:ClearButton = New-Button 'Clear' 'secondary' 84 32
$script:LoadButton = New-Button 'Load a list' 'secondary' 118 32
$script:SaveButton = New-Button 'Save this list' 'secondary' 128 32
$linkButtons.Controls.Add($script:PasteButton)
$linkButtons.Controls.Add($script:ClearButton)
$linkButtons.Controls.Add($script:LoadButton)
$linkButtons.Controls.Add($script:SaveButton)

$script:OptionsCard = New-Object Windows.Forms.Panel
$script:OptionsCard.Dock = 'Fill'
$script:OptionsCard.BackColor = [Drawing.Color]::White
$script:OptionsCard.Margin = New-Object Windows.Forms.Padding(0, 6, 0, 6)
$script:OptionsTitle = New-Object Windows.Forms.Label
$script:OptionsTitle.Text = 'Options'
$script:OptionsTitle.Font = $script:FontSection
$script:OptionsTitle.ForeColor = $script:ColorInk
$script:OptionsTitle.BackColor = [Drawing.Color]::White
$script:FolderCheck = New-Check 'Save each playlist into its own folder'
$script:SkipCheck = New-Check 'Skip videos you have already downloaded'
$script:AttachedCheck = New-Check 'Download the playlist attached to a video link'
$script:DetailedCheck = New-Check 'Show detailed activity'
$script:FolderCheck.Checked = [bool]$settings.PlaylistFolders
$script:SkipCheck.Checked = [bool]$settings.SkipExisting
$script:AttachedCheck.Checked = [bool]$settings.ExpandAttached
$script:DetailedCheck.Checked = [bool]$settings.Detailed
$script:ResolutionValues = @('best', '2160', '1440', '1080', '720', '480', '360')
$script:ResolutionLabel = New-Object Windows.Forms.Label
$script:ResolutionLabel.Text = 'Resolution'
$script:ResolutionLabel.AutoSize = $true
$script:ResolutionLabel.Font = $script:FontUi
$script:ResolutionLabel.ForeColor = $script:ColorInk
$script:ResolutionLabel.BackColor = [Drawing.Color]::White
$script:ResolutionBox = New-Object Windows.Forms.ComboBox
$script:ResolutionBox.DropDownStyle = [Windows.Forms.ComboBoxStyle]::DropDownList
$script:ResolutionBox.Font = $script:FontUi
$script:ResolutionBox.Width = 160
$script:ResolutionBox.IntegralHeight = $true
foreach ($label in @('Best available', '2160p (4K)', '1440p', '1080p', '720p', '480p', '360p')) {
    [void]$script:ResolutionBox.Items.Add($label)
}
$resolutionIndex = [array]::IndexOf($script:ResolutionValues, [string]$settings.Resolution)
if ($resolutionIndex -lt 0) { $resolutionIndex = 0 }
$script:ResolutionBox.SelectedIndex = $resolutionIndex
$script:AudioCheck = New-Check 'Audio only, save as MP3'
$script:AudioCheck.Checked = [bool]$settings.AudioOnly
$script:ModeRow = New-Object Windows.Forms.Panel
$script:ModeRow.BackColor = [Drawing.Color]::White
$script:ModeRow.Height = 32
$script:ModeRow.Controls.Add($script:ResolutionLabel)
$script:ModeRow.Controls.Add($script:ResolutionBox)
$script:ModeRow.Controls.Add($script:AudioCheck)
$script:OptionsCard.Controls.Add($script:OptionsTitle)
$script:OptionsCard.Controls.Add($script:FolderCheck)
$script:OptionsCard.Controls.Add($script:SkipCheck)
$script:OptionsCard.Controls.Add($script:AttachedCheck)
$script:OptionsCard.Controls.Add($script:DetailedCheck)
$script:OptionsCard.Controls.Add($script:ModeRow)
$script:DownloadsLabel = New-Object Windows.Forms.Label
$script:DownloadsLabel.Text = 'Save to'
$script:DownloadsLabel.AutoSize = $true
$script:DownloadsLabel.Font = $script:FontUi
$script:DownloadsLabel.ForeColor = $script:ColorInk
$script:DownloadsLabel.BackColor = [Drawing.Color]::White
$script:DownloadsLabel.Location = New-Object Drawing.Point(0, 6)
$script:DownloadsPathBox = New-Object Windows.Forms.TextBox
$script:DownloadsPathBox.ReadOnly = $true
$script:DownloadsPathBox.Font = $script:FontUi
$script:DownloadsPathBox.BackColor = [Drawing.Color]::White
$script:DownloadsPathBox.ForeColor = $script:ColorInk
$script:DownloadsPathBox.BorderStyle = [Windows.Forms.BorderStyle]::FixedSingle
$script:DownloadsPathBox.Text = $script:DownloadsDir
$script:ChangeFolderButton = New-Button 'Change' 'secondary' 88 28
$script:ChangeFolderButton.Margin = New-Object Windows.Forms.Padding(0)
$script:FolderRow = New-Object Windows.Forms.Panel
$script:FolderRow.BackColor = [Drawing.Color]::White
$script:FolderRow.Height = 32
$script:FolderRow.Controls.Add($script:DownloadsLabel)
$script:FolderRow.Controls.Add($script:DownloadsPathBox)
$script:FolderRow.Controls.Add($script:ChangeFolderButton)
$script:OptionsCard.Controls.Add($script:FolderRow)
$script:ChangeFolderButton.Add_Click({ Choose-DownloadsFolder })
$script:OptionsCard.Add_Paint({
    $pen = New-Object Drawing.Pen $script:ColorLine
    $_.Graphics.DrawRectangle($pen, 0, 0, ($script:OptionsCard.Width - 1), ($script:OptionsCard.Height - 1))
    $pen.Dispose()
})
foreach ($chk in @($script:FolderCheck, $script:SkipCheck, $script:AttachedCheck, $script:DetailedCheck, $script:AudioCheck)) {
    $chk.Add_CheckedChanged({
        try {
            Update-DownloadMode
            if (-not $script:LoadingSettings) { Save-Settings }
        } catch {
            Write-Activity ('Could not save that option. ' + $_.Exception.Message) 'warn'
        }
    })
}
$script:ResolutionBox.Add_SelectedIndexChanged({
    try {
        if (-not $script:LoadingSettings) { Save-Settings }
    } catch {
        Write-Activity ('Could not save that option. ' + $_.Exception.Message) 'warn'
    }
})

$script:ActionPanel = New-Object Windows.Forms.Panel
$script:ActionPanel.Dock = 'Fill'
$script:ActionPanel.BackColor = $script:ColorPage
$script:ActionPanel.Margin = New-Object Windows.Forms.Padding(0, 4, 0, 0)
$script:DownloadButton = New-Button 'Download' 'primary' 156 38
$script:CancelButton = New-Button 'Cancel' 'danger' 108 34
$script:OpenButton = New-Button 'Open Downloads' 'secondary' 160 34
$script:HelpButton = New-Button 'How this works' 'secondary' 148 34
$script:CancelButton.Enabled = $false
$script:ActionPanel.Controls.Add($script:DownloadButton)
$script:ActionPanel.Controls.Add($script:CancelButton)
$script:ActionPanel.Controls.Add($script:OpenButton)
$script:ActionPanel.Controls.Add($script:HelpButton)

$activityLabel = New-Object Windows.Forms.Label
$activityLabel.Text = 'Activity'
$activityLabel.Font = $script:FontSection
$activityLabel.ForeColor = $script:ColorInk
$activityLabel.BackColor = $script:ColorPage
$activityLabel.Dock = 'Fill'
$activityLabel.TextAlign = 'BottomLeft'

$logHost = New-Object Windows.Forms.Panel
$logHost.Dock = 'Fill'
$logHost.BackColor = $script:ColorLogBg
$logHost.Padding = New-Object Windows.Forms.Padding(10, 8, 10, 8)
$logHost.Margin = New-Object Windows.Forms.Padding(0, 4, 0, 0)
$script:Log = New-Object Windows.Forms.RichTextBox
$script:Log.Dock = 'Fill'
$script:Log.BorderStyle = 'None'
$script:Log.ReadOnly = $true
$script:Log.BackColor = $script:ColorLogBg
$script:Log.ForeColor = $script:ColorLogText
$script:Log.Font = $script:FontLog
$script:Log.DetectUrls = $false
$script:Log.ScrollBars = 'Vertical'
$script:Log.WordWrap = $true
$script:Log.ShortcutsEnabled = $true
$logHost.Controls.Add($script:Log)
$logHost.Add_Paint({
    $pen = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(55, 65, 81))
    $_.Graphics.DrawRectangle($pen, 0, 0, ($this.Width - 1), ($this.Height - 1))
    $pen.Dispose()
})

[void]$table.Controls.Add($linksLabel, 0, 0)
[void]$table.Controls.Add($script:LinkHost, 0, 1)
[void]$table.Controls.Add($hint, 0, 2)
[void]$table.Controls.Add($linkButtons, 0, 3)
[void]$table.Controls.Add($script:OptionsCard, 0, 4)
[void]$table.Controls.Add($script:ActionPanel, 0, 5)
[void]$table.Controls.Add($activityLabel, 0, 6)
[void]$table.Controls.Add($logHost, 0, 7)

$script:Form.Controls.Add($table)
$script:Form.Controls.Add($script:StatusPanel)
$script:Form.Controls.Add($script:Header)

Set-Tip $script:LinkBox 'One web link per line. Each line can be a single video or a whole playlist. You can also drop a link or a .txt file here.'
Set-Tip $script:PasteButton 'Paste links from the clipboard onto the end of the list.'
Set-Tip $script:ClearButton 'Empty the links box. Downloaded files stay in the Downloads folder.'
Set-Tip $script:LoadButton 'Add links from a text file. Lines that are not links are left out.'
Set-Tip $script:SaveButton 'Save the links in the box to a text file you can open later.'
Set-Tip $script:FolderCheck "Put each playlist's videos in a folder named after the playlist, inside Downloads. Single videos stay directly in Downloads."
Set-Tip $script:SkipCheck 'Remember finished videos and skip them next time. Uncheck this to download them again. The memory is the download history file in the app folder.'
Set-Tip $script:AttachedCheck "YouTube often adds a playlist to a video's address. Leave this off to download only the video. Turn it on to download every video in that attached playlist."
Set-Tip $script:DetailedCheck "Show the downloader's own technical messages in the activity box. Useful when a video will not download."
Set-Tip $script:ResolutionBox 'Pick a picture size when a video offers more than one. If that size is missing, the closest available size is used. Best available keeps the best MP4 that plays in ordinary players.'
Set-Tip $script:ResolutionLabel 'Pick a picture size when a video offers more than one. If that size is missing, the closest available size is used.'
Set-Tip $script:AudioCheck 'Save only the soundtrack, as a high-quality MP3. MP4 files already in Downloads stay there. MP3s are remembered separately from videos.'
Set-Tip $script:DownloadButton 'Download every link in the box. Videos are saved as MP4. With Audio only turned on, the soundtrack is saved as an MP3. Ctrl+Enter does this too.'
Set-Tip $script:CancelButton 'Stop the download. Videos that already finished stay in Downloads. Esc does this too.'
Set-Tip $script:DownloadsPathBox 'New videos and MP3s are saved in this folder. The choice is remembered the next time you open the program.'
Set-Tip $script:DownloadsLabel 'New videos and MP3s are saved in this folder.'
Set-Tip $script:ChangeFolderButton 'Choose a different folder for new downloads. Files already saved stay where they are.'
Set-Tip $script:OpenButton 'Open the current save folder in File Explorer.'
Set-Tip $script:HelpButton 'Open a short guide to links, folders, skipping, and what each part of this folder is for.'
Set-Tip $script:Log 'Saved files, skipped videos, and problems are listed here.'
Set-Tip $script:ProgressTrack 'How much of the current file has been downloaded.'
Set-Tip $script:StatusLabel 'What the program is doing right now.'

$script:PasteButton.Add_Click({ Paste-Links })
$script:ClearButton.Add_Click({ $script:LinkBox.Clear() })
$script:LoadButton.Add_Click({ Load-ListFile })
$script:SaveButton.Add_Click({ Save-ListFile })
$script:DownloadButton.Add_Click({ Start-Download })
$script:CancelButton.Add_Click({ Request-Cancel })
$script:OpenButton.Add_Click({ Open-DownloadsFolder })
$script:HelpButton.Add_Click({ Show-Help })

$script:Form.Add_KeyDown({
    if ($_.Control -and $_.KeyCode -eq [Windows.Forms.Keys]::Enter) {
        $_.SuppressKeyPress = $true
        if (-not $script:Running) { Start-Download }
    } elseif ($_.KeyCode -eq [Windows.Forms.Keys]::Escape -and $script:Running) {
        $_.SuppressKeyPress = $true
        Request-Cancel
    }
})
$script:Form.Add_FormClosing({
    if ($script:SmokeTest) { return }
    if ($script:Running) {
        $answer = [Windows.Forms.MessageBox]::Show('A download is still running. Stop it and close?', 'Video Downloader', 'YesNo', 'Question')
        if ($answer -ne [Windows.Forms.DialogResult]::Yes) {
            $_.Cancel = $true
            return
        }
        $script:Closing = $true
        Stop-DownloadProcess
        $deadline = [DateTime]::UtcNow.AddSeconds(4)
        while ($script:Process -and -not $script:Process.HasExited -and [DateTime]::UtcNow -lt $deadline) {
            [Threading.Thread]::Sleep(100)
        }
    }
    Save-Settings
})
$script:Form.Add_FormClosed({
    if ($script:Timer) { $script:Timer.Stop(); $script:Timer.Dispose() }
    if ($script:HelpForm -and -not $script:HelpForm.IsDisposed) { $script:HelpForm.Close() }
})
$script:Header.Add_Resize({ Update-ChromeLayout })
$script:StatusPanel.Add_Resize({ Update-ChromeLayout })
$script:ActionPanel.Add_Resize({ Layout-Actions })
$script:OptionsCard.Add_Resize({ Layout-Options })
$script:Form.Add_Shown({
    Update-ChromeLayout
    if (-not $script:SmokeTest) {
        try {
            $script:Form.WindowState = [Windows.Forms.FormWindowState]::Normal
            $script:Form.Visible = $true
            [void][VideoDownloader.Native]::ShowWindow($script:Form.Handle, 9)
            [void][VideoDownloader.Native]::SetForegroundWindow($script:Form.Handle)
        } catch {
        }
        $script:LinkBox.Focus() | Out-Null
    }
})

$script:Timer = New-Object Windows.Forms.Timer
$script:Timer.Interval = 100
$script:Timer.Add_Tick({ Invoke-DownloadTick })
$script:Timer.Start()

Write-Welcome
Warn-MissingTools
Set-Busy $false
Set-Status 'Ready' 'idle'
Update-Shortcut
Update-ChromeLayout

function Assert-True([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

function Invoke-SelfCheck {
    $missing = @(Get-MissingTools)
    Assert-True ($missing.Count -eq 0) ("Missing tools: " + ($missing -join ', '))

    $cases = @(
        @('https://www.youtube.com/watch?v=abc', $false, 'video'),
        @('https://youtu.be/abc', $false, 'video'),
        @('https://www.youtube.com/watch?v=abc&list=PL0123456789', $false, 'video'),
        @('https://www.youtube.com/watch?v=abc&list=PL0123456789', $true, 'playlist'),
        @('https://www.youtube.com/playlist?list=PL0123456789', $false, 'playlist'),
        @('https://www.youtube.com/@SomeChannel', $false, 'channel'),
        @('https://www.youtube.com/@SomeChannel/videos', $false, 'channel'),
        @('https://www.youtube.com/shorts/abc123', $false, 'video'),
        @('https://www.youtube.com/@SomeChannel/shorts', $false, 'channel'),
        @('https://www.youtube.com/channel/UCxxxxxxxx', $false, 'channel'),
        @('https://vimeo.com/123456', $false, 'open'),
        @('https://m.youtube.com/watch?v=abc', $false, 'video'),
        @('https://notyoutube.com/watch?v=abc', $false, 'open')
    )
    foreach ($case in $cases) {
        $got = Get-LinkKind $case[0] ([bool]$case[1])
        Assert-True ($got -eq $case[2]) ("Kind for $($case[0]) expand=$($case[1]) was $got, expected $($case[2])")
    }

    $quoted = ConvertTo-Arg 'E:\Youtube Downloads\tools'
    Assert-True ($quoted -eq '"E:\Youtube Downloads\tools"') "Bad quote: $quoted"
    Assert-True ((ConvertTo-Arg '--newline') -eq '--newline') 'Simple arg was quoted'

    $videoArgs = Get-YtArguments -Key 'video' -PlaylistFolders $true -SkipExisting $true -Destination 'E:\Youtube Downloads\downloads' -ArchiveFile 'E:\Youtube Downloads\app\download-history.txt' -BatchFile 'C:\temp\list.txt'
    Assert-True ($videoArgs -contains '--no-playlist') 'Video args missing --no-playlist'
    Assert-True ($videoArgs -contains '--ignore-config') 'Missing --ignore-config'
    Assert-True ($videoArgs -contains '-t') 'Missing mp4 preset'
    Assert-True (-not ($videoArgs -contains '--yes-playlist')) 'Video args forced a playlist'
    $videoLine = ConvertTo-CommandLine $videoArgs
    Assert-True ($videoLine.Contains('"E:\Youtube Downloads\downloads"')) "Path was not quoted: $videoLine"
    Assert-True (-not ($videoArgs -contains '-f')) 'Best resolution should not add a format filter'
    Assert-True ($videoLine.Contains('deno:' + $script:Deno)) "Deno was not added: $videoLine"

    $capped = Get-YtArguments -Key 'video' -PlaylistFolders $true -SkipExisting $true -Destination 'E:\Youtube Downloads\downloads' -ArchiveFile 'E:\Youtube Downloads\app\download-history.txt' -BatchFile 'C:\temp\list.txt' -Resolution '720'
    $formatIndex = [array]::IndexOf($capped, '-f')
    Assert-True ($formatIndex -ge 0 -and $capped[$formatIndex + 1] -match 'height<=720') '720p did not cap the picture size'
    $audioArgs = Get-YtArguments -Key 'video' -PlaylistFolders $true -SkipExisting $true -Destination 'E:\Youtube Downloads\downloads' -ArchiveFile 'E:\Youtube Downloads\app\audio-history.txt' -BatchFile 'C:\temp\list.txt' -AudioOnly $true
    Assert-True ($audioArgs -contains 'mp3') 'Audio mode missing mp3'
    Assert-True (-not ($audioArgs -contains 'mp4')) 'Audio mode still requested an MP4'
    Assert-True ($audioArgs -contains '--audio-quality') 'Audio mode missing quality'
    Assert-True ((Resolve-DownloadsFolder '') -eq $script:DefaultDownloadsDir) 'Empty save folder should stay the default'
    Assert-True ((Resolve-DownloadsFolder 'D:\Video Downloader') -eq 'D:\Video Downloader') 'A chosen folder was not kept'
    Assert-True ((Resolve-DownloadsFolder $script:YtDlp) -eq $script:DefaultDownloadsDir) 'A file was accepted as a save folder'

    $collectionArgs = Get-YtArguments -Key 'collection' -PlaylistFolders $true -SkipExisting $true -Destination 'E:\Youtube Downloads\downloads' -ArchiveFile 'E:\Youtube Downloads\app\download-history.txt' -BatchFile 'C:\temp\list.txt'
    Assert-True ($collectionArgs -contains '--yes-playlist') 'Playlist args missing --yes-playlist'
    Assert-True (-not ($collectionArgs -contains '--no-playlist')) 'Playlist args blocked the playlist'
    $templateIndex = [array]::IndexOf($collectionArgs, '-o')
    Assert-True ($collectionArgs[$templateIndex + 1] -match 'playlist') 'Playlist template missing folder'

    $sample = "https://www.youtube.com/watch?v=abc`r`n`r`n# comment`r`nhttps://www.youtube.com/playlist?list=PLabcdefghij`r`nnot a link`r`nhttps://www.youtube.com/watch?v=abc`r`nhttps://youtu.be/zzz`r`nwww.youtube.com/watch?v=bare`r`nhttps://www.youtube.com/watch?v=abc&list=PLzzzzzzzzz`r`nhttps://www.youtube.com/@ExampleChannel"
    $parsed = Get-LinksFromText $sample $false
    $videos = @($parsed.Items | Where-Object { $_.Kind -eq 'video' })
    $playlists = @($parsed.Items | Where-Object { $_.Kind -eq 'playlist' })
    $channels = @($parsed.Items | Where-Object { $_.Kind -eq 'channel' })
    Assert-True ($videos.Count -eq 4) "Expected 4 videos, got $($videos.Count)"
    Assert-True ($playlists.Count -eq 1) "Expected 1 playlist, got $($playlists.Count)"
    Assert-True ($channels.Count -eq 1) "Expected 1 channel, got $($channels.Count)"
    Assert-True ($parsed.Invalid.Count -eq 1) "Expected 1 invalid line, got $($parsed.Invalid.Count)"
    Assert-True ($parsed.DuplicateCount -eq 1) "Expected 1 duplicate, got $($parsed.DuplicateCount)"
    $expanded = Get-LinksFromText 'https://www.youtube.com/watch?v=abc&list=PLzzzzzzzzz' $true
    Assert-True ($expanded.Items[0].Kind -eq 'playlist') 'Attached playlist was not expanded'

    foreach ($entry in $script:TipMap.GetEnumerator()) {
        $gotTip = $script:Tips.GetToolTip($entry.Key)
        Assert-True (-not [string]::IsNullOrWhiteSpace($gotTip)) 'A control is missing its tooltip'
    }
    Assert-True ($script:TipMap.Count -ge 14) "Expected tooltips on the main controls, found $($script:TipMap.Count)"

    Add-PendingLine 'queue-one'
    Add-PendingLine 'queue-two'
    $drained = Read-PendingLines
    $onePlaylist = New-Object 'System.Collections.Generic.List[object]'
    $onePlaylist.Add([pscustomobject]@{ Url = 'https://www.youtube.com/playlist?list=PLtest'; Kind = 'playlist' })
    $built = Build-Jobs $onePlaylist
    Assert-True (@($built).Count -eq 1) 'One playlist did not produce one download job'
    Assert-True ($built[0].Key -eq 'collection') 'Playlist job was not a collection'
    Assert-True ($built[0].Urls.Count -eq 1) 'Playlist job lost its link'
    Assert-True ($drained.Count -eq 2) ("Drained $($drained.Count) lines: " + ($drained -join ' | '))
    Assert-True ([string]$drained[0] -eq 'queue-one') "First queued line was $($drained[0])"
    Assert-True ([string]$drained[1] -eq 'queue-two') "Second queued line was $($drained[1])"

    Ensure-OutputHandlers
    [VideoDownloader.YtLinePump]::BeginJob()
    $pumpCmd = Join-Path $env:TEMP 'vd-pump-test.cmd'
    $pumpText = "@echo off`r`necho [download]  12.5%% of 1MiB at 1MiB/s ETA 00:01`r`necho WARNING: sample`r`necho YD_SAVED:C:\temp\clip.mp4`r`n"
    [System.IO.File]::WriteAllText($pumpCmd, $pumpText)
    $pumpPsi = New-Object System.Diagnostics.ProcessStartInfo
    $pumpPsi.FileName = Join-Path $env:SystemRoot 'System32\cmd.exe'
    $pumpPsi.Arguments = '/c "' + $pumpCmd + '"'
    $pumpPsi.UseShellExecute = $false
    $pumpPsi.CreateNoWindow = $true
    $pumpPsi.RedirectStandardOutput = $true
    $pumpPsi.RedirectStandardError = $true
    $pumpProc = New-Object System.Diagnostics.Process
    $pumpProc.StartInfo = $pumpPsi
    $pumpProc.EnableRaisingEvents = $true
    $pumpProc.add_OutputDataReceived($script:DataHandler)
    $pumpProc.add_ErrorDataReceived($script:DataHandler)
    $pumpProc.add_Exited($script:ExitHandler)
    [void]$pumpProc.Start()
    $pumpProc.BeginOutputReadLine()
    $pumpProc.BeginErrorReadLine()
    $pumpDeadline = [DateTime]::UtcNow.AddSeconds(8)
    while (-not [VideoDownloader.YtLinePump]::Exited -and [DateTime]::UtcNow -lt $pumpDeadline) {
        Start-Sleep -Milliseconds 50
    }
    $pumpProc.Dispose()
    Remove-Item -LiteralPath $pumpCmd -Force -ErrorAction SilentlyContinue
    Assert-True ([bool][VideoDownloader.YtLinePump]::Exited) 'The download listener did not see the process finish'
    $pumped = Read-PendingLines
    $pumpedText = $pumped -join "`n"
    Assert-True ($pumpedText -match 'YD_SAVED:') "Listener missed the saved file line: $pumpedText"
    Assert-True ($pumpedText -match 'WARNING:') "Listener missed the warning: $pumpedText"
    Assert-True ([math]::Abs([double][VideoDownloader.YtLinePump]::LivePercent - 12.5) -lt 0.01) 'Listener missed the progress percent'
}

function Save-FormImage($targetForm, [string]$path) {
    $wasTop = $targetForm.TopMost
    $targetForm.TopMost = $true
    $targetForm.BringToFront()
    $targetForm.Activate()
    [Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 250
    [Windows.Forms.Application]::DoEvents()
    $bounds = $targetForm.Bounds
    $bmp = New-Object Drawing.Bitmap $bounds.Width, $bounds.Height
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($bounds.Location, [Drawing.Point]::Empty, $bounds.Size)
    $g.Dispose()
    $bmp.Save($path, [Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $targetForm.TopMost = $wasTop
}

function Invoke-SmokeTest {
    Invoke-SelfCheck
    $script:Form.Show()
    Update-ChromeLayout
    [Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 200
    [Windows.Forms.Application]::DoEvents()
    Save-FormImage $script:Form (Join-Path $env:TEMP 'vd-main.png')
    $script:Form.ClientSize = New-Object Drawing.Size(860, 680)
    Update-ChromeLayout
    [Windows.Forms.Application]::DoEvents()
    Save-FormImage $script:Form (Join-Path $env:TEMP 'vd-main-narrow.png')
    $script:Form.ClientSize = New-Object Drawing.Size($wantW, $wantH)
    Show-Help
    [Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 200
    Save-FormImage $script:HelpForm (Join-Path $env:TEMP 'vd-help.png')
    if ($script:HelpBox) {
        [IO.File]::WriteAllText((Join-Path $env:TEMP 'vd-help.txt'), $script:HelpBox.Text)
    }
    [IO.File]::WriteAllText((Join-Path $env:TEMP 'vd-log.txt'), $script:Log.Text)
    Assert-True ($script:Log.Text -match 'Paste a video or playlist link') 'Startup instructions were not in the activity box'
    Assert-True ($script:HelpBox.Text -match 'Where the files go') 'The guide was missing its folder section'
    $script:Saved = 0
    $script:Skipped = 0
    $script:Failed = 0
    $script:DetailedCheck.Checked = $false
    Receive-Line '[download] Destination: E:\Youtube Downloads\downloads\Me at the zoo [jNQXAC9IVRw].mp4'
    Receive-Line 'YD_SAVED:E:\Youtube Downloads\downloads\Me at the zoo [jNQXAC9IVRw].mp4'
    Receive-Line '[youtube] abc123: has already been recorded in the archive'
    Receive-Line 'ERROR: [youtube] xyz: Video unavailable'
    Receive-Line '[download] Downloading item 2 of 10'
    Add-PendingLine '[download]  45.2% of  10.00MiB at  1.50MiB/s ETA 00:03'
    Assert-True ($script:Saved -eq 1) "Parser saved $($script:Saved)"
    Assert-True ($script:Skipped -eq 1) "Parser skipped $($script:Skipped)"
    Assert-True ($script:Failed -eq 1) "Parser failed $($script:Failed)"
    Assert-True ($script:ItemIndex -eq 2 -and $script:ItemCount -eq 10) 'Parser item counter'
    Assert-True ([math]::Abs($script:LivePercent - 45.2) -lt 0.01) "Parser percent $($script:LivePercent)"
    if ($script:HelpForm) { $script:HelpForm.Close() }
    $script:Form.Close()
    Write-Output 'SMOKE OK'
}

try {
    if ($script:SmokeTest) {
        Invoke-SmokeTest
        exit 0
    }
    [void][System.Windows.Forms.Application]::Run($script:Form)
} catch {
    $msg = $_.Exception.ToString()
    if ($script:SmokeTest) {
        Write-Output ("SMOKE FAIL: " + $msg)
        Write-Output $_.ScriptStackTrace
        Write-Output $_.InvocationInfo.PositionMessage
        exit 1
    }
    try {
        [Windows.Forms.MessageBox]::Show($msg, 'Video Downloader', 'OK', 'Error') | Out-Null
    } catch { }
    exit 1
}
