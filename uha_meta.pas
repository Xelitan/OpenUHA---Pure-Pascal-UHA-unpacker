unit uha_meta;

{$mode delphi}{$H+}{$Q-}{$R-}

interface

uses Classes, SysUtils, uha_lzp_textbook;

type
  TUhaEntry = record
    Name : string;
    Size : Cardinal;
  end;
  TUhaEntries = array of TUhaEntry;

function UHA_ReadEntries(const raw: array of Byte; out entries: TUhaEntries): Integer;

function UHA_ReadNames(const raw: array of Byte; out names: TStringList): Integer;

implementation

{$I uha_descramble_sbox.inc}

type TByteArr = array of Byte;

procedure Descramble(var buf: TByteArr);
var S: array[0..255] of Byte;
    i, j, k: Integer; b, t: Byte;
begin
  for k := 0 to 255 do S[k] := UHA_INIT_SBOX[k];
  i := 0; j := (0 - 2) and $FF;
  for k := 0 to High(buf) do
  begin
    j := (j + 1) and $FF;
    i := (i + 1) and $FF;
    b := S[i];
    t := Byte(S[(i - 1) and $FF] + b);
    S[i] := t;
    buf[k] := buf[k] xor t;
    S[j] := Byte(S[j] - b);
  end;
end;

function DecodeBlock(const raw: array of Byte; srcOfs, pkLen, unpacked: Integer;
  out plain: TByteArr): Boolean;
var blk: TByteArr; i: Integer;
begin
  SetLength(blk, pkLen);
  for i := 0 to pkLen-1 do blk[i] := raw[srcOfs+i];
  Descramble(blk);
  SetLength(plain, unpacked);
  Result := LZP_Decode(blk, $11, unpacked, plain) = 0;
end;

function UHA_ReadEntries(const raw: array of Byte; out entries: TUhaEntries): Integer;
var
  dec: array[0..38] of Byte;
  seed: Byte;
  i, off, fc, names_packed, names_unpacked, attrs_packed, psize: Integer;
  names, attrs: TByteArr;
  p, ln, f, base, alen: Integer;
  nm: string;
  v, prev, sz: Cardinal;
begin
  SetLength(entries, 0);
  if Length(raw) < 39 then Exit(-2);
  if (raw[0] <> Ord('U')) or (raw[1] <> Ord('H')) or (raw[2] <> Ord('A')) then
    Exit(-1);

  for i := 0 to 38 do dec[i] := raw[i];
  seed := raw[$25];
  for i := 0 to 30 do
    dec[4+i] := raw[4+i] xor Byte((seed + Cardinal(i)*Cardinal(i)) and $FF);

  psize          := dec[17] or (dec[18] shl 8) or (dec[19] shl 16) or (dec[20] shl 24);
  fc             := dec[21] or (dec[22] shl 8) or (dec[23] shl 16);
  names_unpacked := dec[24] or (dec[25] shl 8) or (dec[26] shl 16);
  names_packed   := dec[27] or (dec[28] shl 8) or (dec[29] shl 16);
  attrs_packed   := dec[30] or (dec[31] shl 8) or (dec[32] shl 16);
  if (fc <= 0) or (names_packed <= 0) then Exit(0);

  off := 39 + psize + fc*4;
  if off + names_packed + attrs_packed > Length(raw) then Exit(-2);

  if not DecodeBlock(raw, off, names_packed, names_unpacked, names) then
  begin
    if GetEnvironmentVariable('META_DBG') <> '' then
      writeln(ErrOutput, 'META: names block failed  off=', off, ' pk=', names_packed,
        ' un=', names_unpacked);
    Exit(-4);
  end;

  alen := 14*fc + 16;
  if not DecodeBlock(raw, off + names_packed, attrs_packed, alen, attrs) then
  begin
    if GetEnvironmentVariable('META_DBG') <> '' then
      writeln(ErrOutput, 'META: attrs block failed  off=', off + names_packed,
        ' pk=', attrs_packed, ' un=', alen);
    Exit(-4);
  end;

  SetLength(entries, fc);

  p := fc;
  for f := 0 to fc-1 do
  begin
    nm := '';
    if p < names_unpacked then
    begin
      ln := names[p]; Inc(p);
      for i := 0 to ln-1 do
        if p < names_unpacked then begin nm := nm + Chr(names[p]); Inc(p); end;
    end;
    entries[f].Name := nm;
  end;

  base := 6*fc;
  prev := 0;
  for f := 0 to fc-1 do
  begin
    v := Cardinal(attrs[base + f])
      or (Cardinal(attrs[base + fc + f])   shl 8)
      or (Cardinal(attrs[base + 2*fc + f]) shl 16)
      or (Cardinal(attrs[base + 3*fc + f]) shl 24);
    sz := (prev - v) and $FFFFFFFF;
    entries[f].Size := sz;
    prev := sz;
  end;

  Result := fc;
end;

function UHA_ReadNames(const raw: array of Byte; out names: TStringList): Integer;
var entries: TUhaEntries; n, i: Integer;
begin
  names := TStringList.Create;
  n := UHA_ReadEntries(raw, entries);
  if n > 0 then
    for i := 0 to High(entries) do names.Add(entries[i].Name);
  Result := n;
end;

end.
