; Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
;
; The OpenMila installer for Windows, for Inno Setup 6.
;
; It installs the payload that packaging\windows\package.ps1 already staged for
; the portable zip: one build, two artifacts. Compile it through
; packaging\windows\build-installer.ps1, which resolves the stage, the version
; and ISCC.exe - this file is not meant to be compiled by hand, because every
; path it needs comes in as a preprocessor define:
;
;   StageDir    the staged payload (dist\OpenMila-<version>-win64)
;   SourceRoot  the repository root, for the icon and the licence
;   OutputDir   where the installer is written (dist)
;   OutputBase  the installer's file name without .exe
;   AppVersion  the full version string, e.g. 1.9.5-beta.2+port.0
;   VersionInfo the same version as four numbers, for the VERSIONINFO resource
;
; Deliberate properties, each of which is a requirement rather than a taste:
;
;   * Per user, under %LOCALAPPDATA%, with PrivilegesRequired=lowest. Installing
;     OpenMila never shows a UAC prompt and never needs an administrator, so it
;     works on a managed machine where the user is not one. Everything it writes
;     is under the user's own profile: no HKLM, no Program Files, no services.
;   * An AppUserModelID on both shortcuts, so Windows groups the taskbar button
;     with the window instead of showing a second, unnamed icon.
;   * A .milaconfig association under HKCU\Software\Classes, so a team
;     configuration file opens OpenMila with one click, as upstream intends.
;   * Uninstall removes the app, the shortcuts, the association and the
;     autostart entry, and KEEPS recordings, transcripts, models and settings.
;     They live outside the application directory and are only removed when the
;     user explicitly asks, which is what the purge prompt (and /PURGEDATA=yes)
;     is for. The MCP registration is the one part this cannot reach: it lives
;     in the AI client's own configuration, so docs/port/INSTALL.md names the
;     command (claude mcp remove openmila) instead.

#ifndef StageDir
  #error StageDir is not defined: compile through packaging\windows\build-installer.ps1
#endif
#ifndef SourceRoot
  #error SourceRoot is not defined: compile through packaging\windows\build-installer.ps1
#endif
#ifndef AppVersion
  #error AppVersion is not defined: compile through packaging\windows\build-installer.ps1
#endif
#ifndef VersionInfo
  #error VersionInfo is not defined: compile through packaging\windows\build-installer.ps1
#endif
#ifndef OutputDir
  #define OutputDir StageDir + "\.."
#endif
#ifndef OutputBase
  #define OutputBase "OpenMila-" + AppVersion + "-win64-setup"
#endif

#define MyAppName "OpenMila"
#define MyPublisher "NX1X"
#define MyURL "https://openmila.nx1xlab.dev"
#define MyExe "openmila.exe"
; The taskbar identity. Windows groups a window under the shortcut's
; AppUserModelID; the app sets the same string at runtime, and the two must
; match exactly or the pinned icon and the running window stay separate.
#define MyAumid "NX1X.OpenMila"
; The ProgID that owns .milaconfig. Versionless on purpose: an upgrade keeps the
; association the user already has instead of orphaning it.
#define MyProgId "OpenMila.milaconfig"

[Setup]
; Never change AppId: it is what makes an upgrade replace this install rather
; than sit beside it, and what ties the Installed Apps entry to the uninstaller.
AppId={{11D68DC9-0188-4F11-A005-275219B1DEEA}
AppName={#MyAppName}
AppVersion={#AppVersion}
AppVerName={#MyAppName} {#AppVersion}
AppPublisher={#MyPublisher}
AppPublisherURL={#MyURL}
AppSupportURL=https://github.com/NX1X/OpenMila/issues
AppUpdatesURL=https://github.com/NX1X/OpenMila/releases
VersionInfoVersion={#VersionInfo}
VersionInfoProductTextVersion={#AppVersion}
VersionInfoCompany={#MyPublisher}
VersionInfoDescription={#MyAppName} {#AppVersion} installer
; Per user, no elevation. With PrivilegesRequired=lowest the {auto*} constants
; all resolve to the user's own locations, and {localappdata}\Programs is what
; {autopf} means here; it is written out so a reader does not have to know that.
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
UsePreviousAppDir=yes
LicenseFile={#SourceRoot}\LICENSE
SetupIconFile={#SourceRoot}\brand\icons\openmila.ico
UninstallDisplayName={#MyAppName} {#AppVersion}
UninstallDisplayIcon={app}\openmila.ico
; x64 only, matching the payload: the Swift runtime and whisper.cpp DLLs in the
; stage are 64-bit, so a 32-bit install would produce an app that cannot start.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
ChangesAssociations=yes
; The payload is large (the Swift runtime, whisper.cpp's backends, the
; diarization models and, when it was built, a Python runtime), so compression
; is worth the build time: this is what a user downloads. The block threads keep
; that build time on a four-core runner within its step budget.
Compression=lzma2/max
SolidCompression=yes
LZMANumBlockThreads=4
LZMAUseSeparateProcess=yes
WizardStyle=modern
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBase}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; An upgrade ships a different set of DLLs and a different Python runtime, and
; Inno only replaces files it is installing. Clearing these two first keeps a
; stale ggml backend or a half-replaced runtime out of the new install. Both are
; app payload; no user data lives under {app}.
Type: files; Name: "{app}\*.dll"
Type: filesandordirs; Name: "{app}\PythonRuntime"

[Files]
; The staged payload, exactly as the zip ships it.
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Start menu and (optional) desktop. Both carry the AppUserModelID so a window
; started from either one groups under the same taskbar button.
; IconFilename is explicit rather than left to the .exe's own resource: the
; packaging script only embeds an icon in openmila.exe when rc.exe is available,
; and a shortcut with a blank icon is not an acceptable failure mode. The .ico
; is always in the payload.
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyExe}"; WorkingDir: "{app}"; IconFilename: "{app}\openmila.ico"; Comment: "Local transcription, dictation and meeting notes"; AppUserModelID: "{#MyAumid}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyExe}"; WorkingDir: "{app}"; IconFilename: "{app}\openmila.ico"; Comment: "Local transcription, dictation and meeting notes"; AppUserModelID: "{#MyAumid}"; Tasks: desktopicon

[Registry]
; The .milaconfig association, per user. HKA is HKCU here, because the install
; is unprivileged; the uninsdelete* flags are what make the association go away
; with the app, and uninsdeletekeyifempty leaves an extension key alone if some
; other program also claimed it.
Root: HKA; Subkey: "Software\Classes\.milaconfig"; ValueType: string; ValueName: ""; ValueData: "{#MyProgId}"; Flags: uninsdeletevalue uninsdeletekeyifempty
Root: HKA; Subkey: "Software\Classes\.milaconfig"; ValueType: string; ValueName: "Content Type"; ValueData: "application/json"; Flags: uninsdeletevalue uninsdeletekeyifempty
Root: HKA; Subkey: "Software\Classes\.milaconfig\OpenWithProgids"; ValueType: string; ValueName: "{#MyProgId}"; ValueData: ""; Flags: uninsdeletevalue uninsdeletekeyifempty
Root: HKA; Subkey: "Software\Classes\{#MyProgId}"; ValueType: string; ValueName: ""; ValueData: "Mila team configuration"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\{#MyProgId}\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\openmila.ico"
Root: HKA; Subkey: "Software\Classes\{#MyProgId}\shell\open"; ValueType: string; ValueName: "FriendlyAppName"; ValueData: "{#MyAppName}"
; %1 is the file the user double-clicked. The app reads it from argv: a single
; quoted argument, so a path with spaces arrives in one piece.
Root: HKA; Subkey: "Software\Classes\{#MyProgId}\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyExe}"" ""%1"""

[UninstallDelete]
; The regenerable cache, and a Startup shortcut if one was ever made. Logs are
; left behind on purpose: they are what a bug report attaches, and a user who
; uninstalls after a crash should still be able to send them. cache\local-ai
; is left too: it is the model server and the language models the user chose
; to download from inside the app, several gigabytes, and a plain uninstall
; must not throw those away unasked. The purge (which removes the whole
; {localappdata}\OpenMila tree) takes them.
Type: filesandordirs; Name: "{localappdata}\{#MyAppName}\cache\*"; Excludes: "local-ai"
Type: files; Name: "{userstartup}\{#MyAppName}.lnk"
; Runtime-generated bytecode inside the installed Python runtime; the directory
; itself was installed by [Files], so this only clears what running it produced.
Type: filesandordirs; Name: "{app}\PythonRuntime"

[Run]
; The Windows App Runtime, before anything can be launched.
;
; The user interface is WinUI, and WinUI needs Microsoft's Windows App Runtime
; on the machine. The application carries the bootstrap DLL that LOOKS for that
; runtime, which is not the same thing as having it: without this step
; openmila.exe starts and exits again immediately, which is exactly what the
; first installed build did. The redistributable ships in the payload, is
; verified by digest at packaging time, and installs for the current user, so
; this step never raises an administrator prompt. It is idempotent: on a
; machine that already has the runtime it returns at once.
Filename: "{app}\WindowsAppRuntimeInstall-x64.exe"; Parameters: "--quiet"; StatusMsg: "Installing the Windows App Runtime..."; Flags: waituntilterminated runascurrentuser; Check: NeedsAppRuntime

Filename: "{app}\{#MyExe}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
// Whether the Windows App Runtime redistributable has to run.
//
// Always true today: asking Windows whether a framework package is registered
// from an unprivileged Inno script means PackageManager through COM, which is
// more moving parts than running an installer that already exits immediately
// when there is nothing to do. This function exists so the decision has one
// place to live if that ever changes.
function NeedsAppRuntime(): Boolean;
begin
  Result := FileExists(ExpandConstant('{app}\WindowsAppRuntimeInstall-x64.exe'));
end;

// Uninstall is deliberately conservative: it takes the application away and
// leaves everything the user made. Two things need code rather than a section.
//
// 1. The autostart entry. OpenMila does not create one today, but a build that
//    did would write it here, and an uninstaller that leaves an autostart value
//    pointing at a deleted exe is a broken login for the user. Deleting a value
//    that is not there costs nothing, so this runs either way.
//
// 2. The purge. Recordings, transcripts, models and settings live in
//    %APPDATA%\Mila and %LOCALAPPDATA%\OpenMila, outside the application
//    directory, and are kept unless the user explicitly asks for them to go.
//    Asking is a Yes/No box that defaults to No and names what is about to be
//    destroyed. An unattended uninstall never prompts, so it always keeps the
//    data; to purge without a prompt, pass /PURGEDATA=yes on the uninstaller's
//    command line.
//
// Line comments only in this section, on purpose: a Pascal { } comment ends at
// the first closing brace, so a constant like the one for the app directory
// inside one would end the comment early and leave the rest as code.

function CmdLineFlagSet(const Name: String): Boolean;
var
  I: Integer;
  Param: String;
begin
  Result := False;
  for I := 1 to ParamCount do
  begin
    Param := Uppercase(ParamStr(I));
    if (Param = Uppercase(Name) + '=YES') or (Param = Uppercase(Name)) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

procedure RemoveAutostartEntry;
begin
  // HKEY_CURRENT_USER explicitly, not HKA: an autostart entry for one user is
  // the only kind an unprivileged install could have written.
  RegDeleteValue(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\Run', '{#MyAppName}');
end;

function UserWantsPurge: Boolean;
begin
  if CmdLineFlagSet('/PURGEDATA') then
  begin
    Result := True;
    Exit;
  end;
  if UninstallSilent then
  begin
    Result := False;
    Exit;
  end;
  // SuppressibleMsgBox, not MsgBox: with /SUPPRESSMSGBOXES it answers with the
  // default instead of waiting for nobody, and the default here is to keep the
  // data. A prompt that cannot be seen must never be able to delete anything.
  Result := SuppressibleMsgBox('Also delete your OpenMila data?' + #13#10#13#10 +
      'This permanently deletes your recordings, transcripts, downloaded models, the local AI server and its models, and app data from' + #13#10 +
      ExpandConstant('{userappdata}\Mila') + #13#10 +
      ExpandConstant('{localappdata}\OpenMila') + #13#10#13#10 +
      'Choose No to keep them. Nothing here can be undone, and reinstalling OpenMila will not bring them back.',
      mbConfirmation, MB_YESNO or MB_DEFBUTTON2, IDNO) = IDYES;
end;

procedure PurgeUserData;
begin
  DelTree(ExpandConstant('{userappdata}\Mila'), True, True, True);
  DelTree(ExpandConstant('{localappdata}\OpenMila'), True, True, True);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
  begin
    RemoveAutostartEntry;
    if UserWantsPurge then
      PurgeUserData;
  end;
end;
