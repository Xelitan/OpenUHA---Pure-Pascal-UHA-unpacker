unit uhadec;
{$mode delphi}{$H+}

interface

uses Classes, SysUtils, uha_lzp_textbook, uha_ppm_m4, uha_alz_textbook, uha_meta, uha_mm_filter;

const
  UHA_OK              =  0;
  UHA_ERR_SIGNATURE   = -1;
  UHA_ERR_TRUNCATED   = -2;
  UHA_ERR_METHOD      = -3;
  UHA_ERR_DECODE      = -4;

type

  TUhaBlob = record
    Name: string;
    Data: TBytes;
  end;
  TUhaBlobArray = array of TUhaBlob;

function UnUHA(InStr, OutStr: TStream): Integer;

function UnUHA_ExtractAll(InStr: TStream; out Blobs: TUhaBlobArray): Integer;

implementation

{$Q-}{$R-}

type
  TByteArr = array of Byte;

type
  THeader = record
    family : Byte;
    order  : Byte;
    usize  : Cardinal;
    psize  : Cardinal;
    dataOfs: Integer;
  end;

function ParseHeader(const raw: TByteArr; out h: THeader): Integer;
var
  dec: array[0..38] of Byte;
  seed: Byte; i: Integer;
begin
  if Length(raw) < 39 then Exit(UHA_ERR_TRUNCATED);
  if (raw[0] <> Ord('U')) or (raw[1] <> Ord('H')) or (raw[2] <> Ord('A')) then
    Exit(UHA_ERR_SIGNATURE);
  for i := 0 to 38 do dec[i] := raw[i];
  seed := raw[$25];
  for i := 0 to 30 do
    dec[4+i] := raw[4+i] xor Byte((seed + Cardinal(i)*Cardinal(i)) and $FF);
  h.family  := dec[9];
  h.order   := dec[10];
  h.usize   := dec[13] or (dec[14] shl 8) or (dec[15] shl 16) or (Cardinal(dec[16]) shl 24);
  h.psize   := dec[17] or (dec[18] shl 8) or (dec[19] shl 16) or (Cardinal(dec[20]) shl 24);
  h.dataOfs := 39;
  Result := UHA_OK;
end;

type
  TRangeDecoder = class
  private
    FData: TByteArr;
    FPos : Integer;
  public
    Code, Range: Cardinal;
    constructor Create(const data: TByteArr; startOfs: Integer);
    function ReadByte: Byte;
    procedure Init;
    function GetFreq(total: Cardinal): Cardinal;
    procedure Decode(low, freq: Cardinal);
  end;

const RENORM = $01000000;

constructor TRangeDecoder.Create(const data: TByteArr; startOfs: Integer);
begin
  FData := data; FPos := startOfs;
end;

function TRangeDecoder.ReadByte: Byte;
begin
  if FPos < Length(FData) then begin Result := FData[FPos]; Inc(FPos); end
  else Result := 0;
end;

procedure TRangeDecoder.Init;
var i: Integer;
begin
  Code := 0; Range := $FFFFFFFF;
  for i := 0 to 4 do Code := (Code shl 8) or ReadByte;
end;

function TRangeDecoder.GetFreq(total: Cardinal): Cardinal;
begin
  Range := Range div total;
  Result := Code div Range;
end;

procedure TRangeDecoder.Decode(low, freq: Cardinal);
begin
  Code := Code - low * Range;
  Range := Range * freq;
  while Range < RENORM do
  begin
    Code := (Code shl 8) or ReadByte;
    Range := Range shl 8;
  end;
end;

function DecodeStore(const raw: TByteArr; const h: THeader; OutStr: TStream): Integer;
begin
  if Cardinal(Length(raw) - h.dataOfs) < h.usize then Exit(UHA_ERR_TRUNCATED);
  OutStr.WriteBuffer(raw[h.dataOfs], h.usize);
  Result := UHA_OK;
end;

function DecodeRawBuffer(const raw: TByteArr; const h: THeader; out ob: TByteArr): Integer;
var fd: TByteArr; i, rc: Integer;
  Members: TUhaEntries; Ends: array of Cardinal; Total: Cardinal;
begin
  SetLength(ob, h.usize);

  if h.usize = 0 then Exit(UHA_OK);
  if h.family = 0 then
  begin
    if Cardinal(Length(raw) - h.dataOfs) < h.usize then Exit(UHA_ERR_TRUNCATED);
    for i := 0 to Integer(h.usize) - 1 do ob[i] := raw[h.dataOfs + i];
    Exit(UHA_OK);
  end;
  if Cardinal(Length(raw) - h.dataOfs) < h.psize then Exit(UHA_ERR_TRUNCATED);
  SetLength(fd, h.psize);
  for i := 0 to Integer(h.psize) - 1 do fd[i] := raw[h.dataOfs + i];

  rc := UHA_ERR_METHOD;
  if (h.family = 1) or (h.family = 3) then
  begin
    if UHA_ReadEntries(raw, Members) > 0 then
    begin
      SetLength(Ends, Length(Members));
      Total := 0;
      for i := 0 to High(Members) do
      begin
        Inc(Total, Members[i].Size);
        Ends[i] := Total;
      end;
      if Total <> h.usize then SetLength(Ends, 0);
    end;
    if (h.order >= $08) and (h.order <= $17) then rc := LZP_DecodeMembers(fd, h.order, h.usize, Ends, ob)
    else if (h.order >= $18) and (h.order <= $27) then rc := PPM_DecodeMembers(fd, h.order, h.usize, Ends, ob)
    else if (h.order >= $28) and (h.order <= $57) then
    begin
      rc := ALZ_DecodeMembers(fd, h.order, h.usize, Ends, ob);
    end;
  end;
  if GetEnvironmentVariable('UHA_DBG') <> '' then
    writeln(ErrOutput, 'BLOCK family=', h.family, ' order=$', IntToHex(h.order,2),
      ' psize=', h.psize, ' usize=', h.usize, ' rc=', rc);
  if rc <> 0 then Exit(UHA_ERR_DECODE);
  Result := UHA_OK;
end;

function UnUHA_ExtractAll(InStr: TStream; out Blobs: TUhaBlobArray): Integer;
var
  raw, ob: TByteArr;
  n: Int64;
  h: THeader;
  entries: TUhaEntries;
  rc, nf, f: Integer;
  ofs, total: Cardinal;
begin
  SetLength(Blobs, 0);
  n := InStr.Size - InStr.Position;
  if n < 39 then Exit(UHA_ERR_TRUNCATED);
  SetLength(raw, n);
  InStr.ReadBuffer(raw[0], n);

  rc := ParseHeader(raw, h);
  if rc <> UHA_OK then Exit(rc);
  if (h.family <> 0) and (h.family <> 1) and (h.family <> 3) then Exit(UHA_ERR_METHOD);

  rc := DecodeRawBuffer(raw, h, ob);
  if rc <> UHA_OK then Exit(rc);

  nf := UHA_ReadEntries(raw, entries);
  total := 0;
  if nf > 0 then
    for f := 0 to nf - 1 do total := total + entries[f].Size;
  if (nf <= 0) or (total <> h.usize) then
  begin
    SetLength(entries, 1);
    entries[0].Name := ''; entries[0].Size := h.usize;
    nf := 1;
  end;

  SetLength(Blobs, nf);
  ofs := 0;
  for f := 0 to nf - 1 do
  begin
    Blobs[f].Name := entries[f].Name;
    SetLength(Blobs[f].Data, entries[f].Size);
    if entries[f].Size > 0 then
      Move(ob[ofs], Blobs[f].Data[0], entries[f].Size);

    if (h.family <> 0) and (entries[f].Size > 0) then
      RestoreFilter(Blobs[f].Data, entries[f].Size,
        (h.order >= $18) and (h.order <= $27));
    if h.family = 3 then
      RestoreMultimediaFilter(Blobs[f].Data, entries[f].Size);
    ofs := ofs + entries[f].Size;
  end;
  Result := nf;
end;

function UnUHA(InStr, OutStr: TStream): Integer;
var
  blobs: TUhaBlobArray;
  rc, f: Integer;
begin
  rc := UnUHA_ExtractAll(InStr, blobs);
  if rc < 0 then Exit(rc);
  for f := 0 to High(blobs) do
    if Length(blobs[f].Data) > 0 then
      OutStr.WriteBuffer(blobs[f].Data[0], Length(blobs[f].Data));
  Result := UHA_OK;
end;

end.
