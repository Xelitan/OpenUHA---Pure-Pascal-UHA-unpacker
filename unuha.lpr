program uhaunpack;

{$mode delphi}{$H+}

uses
  Classes, SysUtils, uhadec, uha_meta;

function DefaultOutputName(const ArcName: string): string;
begin
  if SameText(ExtractFileExt(ArcName), '.uha') then
    Result := ChangeFileExt(ArcName, '')
  else
    Result := ArcName + '.out';
end;

function ErrText(rc: Integer): string;
begin
  case rc of
    UHA_OK:             Result := 'ok';
    UHA_ERR_SIGNATURE:  Result := 'not a UHA archive (bad signature)';
    UHA_ERR_TRUNCATED:  Result := 'archive truncated';
    UHA_ERR_METHOD:     Result := 'unsupported compression method';
    UHA_ERR_DECODE:     Result := 'decode error';
  else
    Result := 'error ' + IntToStr(rc);
  end;
end;

function LoadBytes(const fn: string): TBytes;
var fs: TFileStream;
begin
  fs := TFileStream.Create(fn, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, fs.Size);
    if fs.Size > 0 then fs.ReadBuffer(Result[0], fs.Size);
  finally
    fs.Free;
  end;
end;

procedure ListEntries(const fn: string);
var raw: TBytes; entries: TUhaEntries; n, i: Integer;
begin
  raw := LoadBytes(fn);
  n := UHA_ReadEntries(raw, entries);
  if n < 0 then begin WriteLn('error: ', ErrText(n)); Halt(1); end;
  WriteLn(ExtractFileName(fn), '  -  ', n, ' file(s):');
  for i := 0 to High(entries) do
    WriteLn(Format('  %-40s %12u', [entries[i].Name, entries[i].Size]));
end;

procedure WriteSlice(const fn: string; const buf: TBytes; ofs, count: Integer);
var fs: TFileStream;
begin
  fs := TFileStream.Create(fn, fmCreate);
  try
    if count > 0 then fs.WriteBuffer(buf[ofs], count);
  finally
    fs.Free;
  end;
end;

function SafeName(const s: string): string;
begin
  Result := ExtractFileName(StringReplace(s, '\', '/', [rfReplaceAll]));
  if Result = '' then Result := 'file';
end;

var
  ArcName, OutName, TargetDir, fn: string;
  InStr : TFileStream;
  OutBuf: TMemoryStream;
  data  : TBytes;
  raw   : TBytes;
  entries: TUhaEntries;
  rc, nFiles, i, ofs: Integer;

begin
  if (ParamCount < 1) or (ParamStr(1) = '-h') or (ParamStr(1) = '--help') then
  begin
    WriteLn('UHARC (.uha) unpacker  -  PPM / ALZ / LZP / STORE');
    WriteLn('usage: unuha <archive.uha> [output]   unpack (file, or dir for multi-file)');
    WriteLn('       unuha -l <archive.uha>          list stored file names + sizes');
    Halt(2);
  end;

  if (ParamStr(1) = '-l') or (ParamStr(1) = '--list') then
  begin
    if ParamCount < 2 then begin WriteLn('error: -l needs an archive'); Halt(2); end;
    if not FileExists(ParamStr(2)) then
      begin WriteLn('error: cannot open "', ParamStr(2), '"'); Halt(1); end;
    ListEntries(ParamStr(2));
    Halt(0);
  end;

  ArcName := ParamStr(1);
  if not FileExists(ArcName) then
  begin
    WriteLn('error: cannot open "', ArcName, '"');
    Halt(1);
  end;

  InStr  := TFileStream.Create(ArcName, fmOpenRead or fmShareDenyNone);
  OutBuf := TMemoryStream.Create;
  try
    rc := UnUHA(InStr, OutBuf);
    if rc <> UHA_OK then begin WriteLn('error: ', ErrText(rc)); Halt(1); end;
    SetLength(data, OutBuf.Size);
    if OutBuf.Size > 0 then begin OutBuf.Position := 0; OutBuf.ReadBuffer(data[0], OutBuf.Size); end;
  finally
    OutBuf.Free;
    InStr.Free;
  end;

  raw := LoadBytes(ArcName);
  nFiles := UHA_ReadEntries(raw, entries);

  if nFiles > 1 then
  begin

    if ParamCount >= 2 then TargetDir := ParamStr(2) else TargetDir := '';
    if TargetDir <> '' then ForceDirectories(TargetDir);

    WriteLn('unpacked ', ExtractFileName(ArcName), '  (', nFiles, ' files, ',
            Length(data), ' bytes):');
    ofs := 0;
    for i := 0 to High(entries) do
    begin
      if TargetDir <> '' then
        fn := IncludeTrailingPathDelimiter(TargetDir) + SafeName(entries[i].Name)
      else
        fn := SafeName(entries[i].Name);
      if ofs + Integer(entries[i].Size) > Length(data) then
      begin
        WriteLn('error: size table exceeds decompressed data'); Halt(1);
      end;
      WriteSlice(fn, data, ofs, entries[i].Size);
      WriteLn(Format('  %-40s %12u  -> %s', [entries[i].Name, entries[i].Size, fn]));
      Inc(ofs, entries[i].Size);
    end;
  end
  else
  begin

    if ParamCount >= 2 then OutName := ParamStr(2)
    else OutName := DefaultOutputName(ArcName);
    WriteSlice(OutName, data, 0, Length(data));
    WriteLn('unpacked ', ExtractFileName(ArcName), ' -> ', OutName,
            '  (', Length(data), ' bytes)');
    if nFiles = 1 then WriteLn('  stored name: ', entries[0].Name);
  end;
end.
