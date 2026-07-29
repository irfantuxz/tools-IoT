program CP210xInstaller;

{$mode objfpc}{$H+}

uses
  Windows, ShellApi, Classes, SysUtils, Process;

const
  APP_TITLE = 'Instalasi Driver CP210x Universal (ESP32 / IoT)';
  AUTHOR = '@irfan_tuxz';

function IsUserAnAdmin: BOOL; stdcall; external 'shell32.dll' name 'IsUserAnAdmin';

function IsRunAsAdmin: Boolean;
begin
  try
    Result := IsUserAnAdmin();
  except
    Result := False;
  end;
end;

{ Fungsi Disable File System Redirection untuk OS 64-bit }
function DisableFsRedirection(var OldValue: Pointer): Boolean;
type
  TSWow64DisableWow64FsRedirection = function(var OldValue: Pointer): BOOL; stdcall;
var
  KernelHandle: THandle;
  Wow64DisableFsRedirection: TSWow64DisableWow64FsRedirection;
begin
  Result := False;
  KernelHandle := GetModuleHandle('kernel32.dll');
  if KernelHandle <> 0 then
  begin
    Wow64DisableFsRedirection := TSWow64DisableWow64FsRedirection(GetProcAddress(KernelHandle, 'Wow64DisableWow64FsRedirection'));
    if Assigned(Wow64DisableFsRedirection) then
      Result := Wow64DisableFsRedirection(OldValue);
  end;
end;

{ Fungsi Restore File System Redirection }
procedure RevertFsRedirection(OldValue: Pointer);
type
  TSWow64RevertWow64FsRedirection = function(OldValue: Pointer): BOOL; stdcall;
var
  KernelHandle: THandle;
  Wow64RevertFsRedirection: TSWow64RevertWow64FsRedirection;
begin
  KernelHandle := GetModuleHandle('kernel32.dll');
  if KernelHandle <> 0 then
  begin
    Wow64RevertFsRedirection := TSWow64RevertWow64FsRedirection(GetProcAddress(KernelHandle, 'Wow64RevertWow64FsRedirection'));
    if Assigned(Wow64RevertFsRedirection) then
      Wow64RevertFsRedirection(OldValue);
  end;
end;

{ RunCommandSilent Menggunakan ShellExecuteExW (Unicode / Multi-byte Safe) }
function RunCommandSilent(const Executable, CmdArgs: string): Integer;
var
  SEInfo: TShellExecuteInfoW;
  ExitCode: DWORD;
  WExec, WArgs: UnicodeString;
begin
  Result := -1;
  WExec := UnicodeString(Executable);
  WArgs := UnicodeString(CmdArgs);

  FillChar(SEInfo, SizeOf(SEInfo), 0);
  SEInfo.cbSize := SizeOf(TShellExecuteInfoW);
  SEInfo.fMask := SEE_MASK_NOCLOSEPROCESS or SEE_MASK_FLAG_NO_UI;
  SEInfo.lpFile := PWideChar(WExec);
  SEInfo.lpParameters := PWideChar(WArgs);
  SEInfo.nShow := SW_HIDE;

  if ShellExecuteExW(@SEInfo) then
  begin
    WaitForSingleObject(SEInfo.hProcess, INFINITE);
    GetExitCodeProcess(SEInfo.hProcess, ExitCode);
    CloseHandle(SEInfo.hProcess);
    Result := ExitCode;
  end;
end;

procedure LaunchApplicationAsync(const Executable, CmdArgs: string);
var
  WExec, WArgs: UnicodeString;
begin
  WExec := UnicodeString(Executable);
  WArgs := UnicodeString(CmdArgs);
  ShellExecuteW(0, PWideChar('open'), PWideChar(WExec), PWideChar(WArgs), nil, SW_SHOWNORMAL);
end;

var
  ExePath, InfPath, RegPath: string;
  ExitCode: Integer;
  OldRedirValue: Pointer;
  IsRedirDisabled: Boolean;
begin
  SetConsoleTitle(PChar(APP_TITLE));

  { 1. AUTO-ELEVATION VIA SHELL EXECUTE JIKA BELUM ADMIN }
  if not IsRunAsAdmin then
  begin
    WriteLn('[INFO] Meminta hak akses Administrator...');
    ShellExecute(0, 'runas', PChar(ParamStr(0)), nil, nil, SW_SHOWNORMAL);
    HAlt(0);
  end;

  { Disable System32 Redirection untuk OS 64-bit }
  IsRedirDisabled := DisableFsRedirection(OldRedirValue);

  try
    { Header Tampilan }
    WriteLn('===================================================');
    WriteLn(' ', APP_TITLE);
    WriteLn(' Script by ', AUTHOR);
    WriteLn('===================================================');
    WriteLn;

    ExePath := ExtractFilePath(ParamStr(0));
    InfPath := ExePath + 'silabser.inf';
    RegPath := ExePath + 'UpdateParameters.reg';

    { 2. EKSEKUSI INSTALASI DRIVER (.INF) }
    if FileExists(InfPath) then
    begin
      WriteLn('[1/2] Menginstall driver ke Windows Driver Store...');
      WriteLn('Path: "', InfPath, '"');

      ExitCode := RunCommandSilent('pnputil.exe', '/add-driver "' + InfPath + '" /install');

      if (ExitCode = 0) or (ExitCode = 3010) then
        WriteLn('Driver berhasil terinstall.')
      else if ExitCode = 259 then
        WriteLn('Driver versi sama / lebih baru sudah terinstall.')
      else
        WriteLn('Proses pnputil selesai dengan kode status: ', ExitCode);
    end
    else
    begin
      WriteLn('[ERROR] File driver "', InfPath, '" tidak ditemukan!');
      WriteLn('Pastikan file executable berada dalam satu folder dengan "silabser.inf".');
      WriteLn;
      Write('Tekan Enter untuk keluar...');
      ReadLn;
      HAlt(1);
    end;

    WriteLn;

    { 3. IMPORT PARAMETER REGISTRY }
    if FileExists(RegPath) then
    begin
      WriteLn('[2/2] Memperbarui konfigurasi Registry...');

      ExitCode := RunCommandSilent('regedit.exe', '/s "' + RegPath + '"');

      if ExitCode = 0 then
        WriteLn('Konfigurasi Registry berhasil diterapkan.')
      else
        WriteLn('Proses regedit selesai dengan kode status: ', ExitCode);
    end
    else
    begin
      WriteLn('[INFO] File "UpdateParameters.reg" tidak ditemukan. Melewati tahap ini.');
    end;

    WriteLn;
    WriteLn('===================================================');
    WriteLn(' Instalasi selesai! Silakan pasang/reconnect ESP32.');
    WriteLn('===================================================');
    WriteLn;

    { 4. PELUNCURAN DEVICE MANAGER (DENGAN MMC.EXE) }
    WriteLn('Membuka Device Manager...');
    LaunchApplicationAsync('mmc.exe', 'devmgmt.msc');

    WriteLn;
    Write('Tekan Enter untuk keluar...');
    ReadLn;

  finally
    if IsRedirDisabled then
      RevertFsRedirection(OldRedirValue);
  end;
end.
