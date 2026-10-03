; Builds video_downloader.exe, the setup program attached to a GitHub Release.
; The tool programs are not in git. This script reads them from the working copy.
; Compile with Inno Setup 6:
;   "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" VideoDownloader.iss

#define AppVersion "1.0.1"
#define Repo ".."
#define ToolExe "E:\Programming\video_downloader\tools"

[Setup]
AppId={{8F3A1C2E-6B47-4D19-9E5A-7C0D4B8E2F61}
AppName=Video Downloader
AppVersion={#AppVersion}
AppPublisher=Video Downloader
AppCopyright=Copyright (c) 2026 Philip Miller
DefaultDirName={localappdata}\Programs\Video Downloader
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#Repo}
OutputBaseFilename=video_downloader
Compression=lzma2
SolidCompression=yes
LZMAUseSeparateProcess=yes
WizardStyle=modern
Uninstallable=yes
UninstallDisplayName=Video Downloader {#AppVersion}
UninstallDisplayIcon={sys}\imageres.dll,189
VersionInfoVersion=1.0.1.0
VersionInfoProductName=Video Downloader
VersionInfoCompany=Video Downloader
VersionInfoDescription=Installs Video Downloader and the tools it needs
CloseApplications=yes

[Files]
Source: "{#Repo}\app\VideoDownloader.ps1"; DestDir: "{app}\app"
Source: "{#Repo}\app\launch.vbs"; DestDir: "{app}\app"
Source: "{#Repo}\app\version.txt"; DestDir: "{app}\app"
Source: "{#Repo}\LICENSE"; DestDir: "{app}"
Source: "{#Repo}\tools\FFmpeg-LICENSE.txt"; DestDir: "{app}\tools"
Source: "{#ToolExe}\yt-dlp.exe"; DestDir: "{app}\tools"
Source: "{#ToolExe}\ffmpeg.exe"; DestDir: "{app}\tools"
Source: "{#ToolExe}\ffprobe.exe"; DestDir: "{app}\tools"
Source: "{#ToolExe}\deno.exe"; DestDir: "{app}\tools"

[Tasks]
Name: desktopicon; Description: "Create a desktop shortcut"

[Icons]
Name: "{autoprograms}\Video Downloader"; Filename: "{sys}\wscript.exe"; Parameters: "//nologo ""{app}\app\launch.vbs"""; WorkingDir: "{app}"; IconFilename: "{sys}\imageres.dll"; IconIndex: 189; Comment: "Download videos and playlists as MP4 or MP3 files"
Name: "{autodesktop}\Video Downloader"; Filename: "{sys}\wscript.exe"; Parameters: "//nologo ""{app}\app\launch.vbs"""; WorkingDir: "{app}"; IconFilename: "{sys}\imageres.dll"; IconIndex: 189; Comment: "Download videos and playlists as MP4 or MP3 files"; Tasks: desktopicon

[Run]
Filename: "{sys}\wscript.exe"; Parameters: "//nologo ""{app}\app\launch.vbs"""; WorkingDir: "{app}"; Description: "Open Video Downloader"; Flags: postinstall nowait skipifsilent

[UninstallDelete]
Type: files; Name: "{app}\Video Downloader.lnk"
