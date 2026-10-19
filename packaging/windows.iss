; SPDX-License-Identifier: GPL-3.0-only
#ifndef AppVersion
  #error AppVersion must be supplied by package-windows.ps1
#endif
#define RepoRoot SourcePath + ".."

[Setup]
AppId={{6C6E15ED-6C58-4D26-A86F-92F129CD7044}
AppName=码住
AppVersion={#AppVersion}
AppPublisher=码住 contributors
AppPublisherURL=https://github.com/wzuivcsyuiopas-cmd/mazhu
DefaultDirName={localappdata}\Programs\Mazhu
DefaultGroupName=码住
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.22000
OutputDir={#RepoRoot}\release
OutputBaseFilename=Mazhu-{#AppVersion}-windows-x64
SetupIconFile={#RepoRoot}\windows\Mazhu\Assets\AppIcon.ico
UninstallDisplayIcon={app}\Mazhu.exe
LicenseFile={#RepoRoot}\LICENSE
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Files]
Source: "{#RepoRoot}\windows\dist\x64\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#RepoRoot}\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#RepoRoot}\NOTICE.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\码住"; Filename: "{app}\Mazhu.exe"

[Run]
Filename: "{app}\Mazhu.exe"; Description: "Launch 码住"; Flags: nowait postinstall skipifsilent
