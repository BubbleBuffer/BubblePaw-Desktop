#ifndef MyAppVersion
  #error MyAppVersion must be supplied with /DMyAppVersion=<version>
#endif
#ifndef SourceDir
  #error SourceDir must point to the Flutter Windows release bundle
#endif
#ifndef OutputDir
  #error OutputDir must point to the installer output directory
#endif

[Setup]
AppId={{71D5B5CB-715A-4E0F-9800-3D2700363AE5}
AppName=BubblePaw Desktop
AppVersion={#MyAppVersion}
AppPublisher=BubbleBuffer
DefaultDirName={localappdata}\Programs\BubblePaw
DefaultGroupName=BubblePaw
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=BubblePaw-{#MyAppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
UninstallDisplayIcon={app}\bubblepaw_desktop.exe

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\BubblePaw Desktop"; Filename: "{app}\bubblepaw_desktop.exe"
