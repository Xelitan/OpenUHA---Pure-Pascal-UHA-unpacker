unit uha_ppm_textbook;

{$mode delphi}{$H+}{$Q-}{$R-}

interface

uses SysUtils;

const
  PPM_OK            =  0;
  PPM_ERR_ORDER     = -1;
  PPM_ERR_CORRUPT   = -2;
  PPM_ERR_OUTSPACE  = -3;

  RANGE_RENORM = $01000000;
  SSE_TOTAL    = $2000;

type

  TRangeDecoder = record
    Code  : Cardinal;
    Range : Cardinal;
    Data  : PByte;
    Pos   : Integer;
    Size  : Integer;
  end;

procedure RD_Init(var R: TRangeDecoder; AData: PByte; ASize: Integer);
function  RD_ReadByte(var R: TRangeDecoder): Byte;
var RdSite: Integer;
var RdTrace: Boolean;

procedure RD_Renorm(var R: TRangeDecoder);

procedure RD_Decode(var R: TRangeDecoder; Low, Width: Cardinal);

function  RD_GetFreq(var R: TRangeDecoder; Total: Cardinal): Cardinal;

function  SSE_DecodeBit(var R: TRangeDecoder; Prob: Cardinal): Boolean;

function  SSE_AdaptHit(Prob: Cardinal): Cardinal;

function  SSE_AdaptEscape(Prob: Cardinal): Cardinal;

type

  TDetransform = record
    Flag : Byte;
    Arg  : Byte;
  end;

type

  TFenwickRow = array[0..255] of Word;
  PFenwickRow = ^TFenwickRow;

function Fenwick_BSearch(const Row: TFenwickRow; Total, Freq: Cardinal;
  out Rem: Cardinal): Integer;

function Fenwick_MixSearch(const Row, FreqRow: TFenwickRow; Total, Freq: Cardinal;
  const Excl: array of Byte; NExcl: Integer; out Rem: Cardinal): Integer;

type

  TOrder1Record = array[0..31] of Byte;

function Record_DecodeWalk(var R: TRangeDecoder; const Rec: TOrder1Record;
  Total: Cardinal; Excl: PByte; var NExcl: Integer; out FoundSym: Integer): Boolean;

procedure Detr_Init(var D: TDetransform);

procedure Detr_Emit(var D: TDetransform; Sym: Byte; Count, Thr1, Thr2: Cardinal;
  Outp: PByte; var OutLen: Integer);

implementation

{$I ppm_detr_tables.inc}

procedure RD_Init(var R: TRangeDecoder; AData: PByte; ASize: Integer);
begin
  R.Data := AData;
  R.Size := ASize;
  R.Pos  := 0;
  R.Code := 0;
  R.Range := $FFFFFFFF;
end;

function RD_ReadByte(var R: TRangeDecoder): Byte;
begin
  if R.Pos < R.Size then
  begin
    Result := R.Data[R.Pos];
    Inc(R.Pos);
  end
  else
    Result := 0;
end;

procedure RD_Renorm(var R: TRangeDecoder);
begin
  if (R.Range = 0) and (GetEnvironmentVariable('PPM_RNGGUARD') <> '') then
  begin
    writeln(ErrOutput, 'RNG0 Range became 0 (RD_Renorm would spin) Code=', IntToHex(R.Code,8),
      ' Pos=', R.Pos);
    Halt(9);
  end;
  while R.Range < RANGE_RENORM do
  begin
    R.Code  := (R.Code shl 8) or RD_ReadByte(R);
    R.Range := R.Range shl 8;
  end;
end;

procedure RD_Decode(var R: TRangeDecoder; Low, Width: Cardinal);
begin
  if (Width = 0) and (GetEnvironmentVariable('PPM_RNGGUARD') <> '') then
    writeln(ErrOutput, 'RNG0-SITE RD_Decode Width=0 Low=', Low, ' Range=', IntToHex(R.Range,8), ' site=', RdSite);
  R.Code  := R.Code - Low * R.Range;
  R.Range := R.Range * Width;
  RD_Renorm(R);

  if RdTrace then
    writeln(ErrOutput, '  rd site=', RdSite, ' low=', Low, ' width=', Width,
      ' code=', IntToHex(R.Code,8), ' rng=', IntToHex(R.Range,8));
end;

function RD_GetFreq(var R: TRangeDecoder; Total: Cardinal): Cardinal;
begin
  R.Range := R.Range div Total;
  Result  := R.Code div R.Range;
end;

function SSE_DecodeBit(var R: TRangeDecoder; Prob: Cardinal): Boolean;
var
  Freq: Cardinal;
begin
  R.Range := R.Range div SSE_TOTAL;
  Freq := (R.Code div R.Range) and $FFFF;
  if Freq < Prob then
  begin

    R.Code  := R.Code;
    R.Range := R.Range * Prob;
    RD_Renorm(R);
    if RdTrace then
      writeln(ErrOutput, '  sse site=', RdSite, ' prob=', Prob, ' HIT  code=',
        IntToHex(R.Code,8), ' rng=', IntToHex(R.Range,8));
    Result := True;
  end
  else
  begin

    R.Code  := R.Code - Prob * R.Range;
    R.Range := R.Range * (SSE_TOTAL - Prob);
    RD_Renorm(R);
    if RdTrace then
      writeln(ErrOutput, '  sse site=', RdSite, ' prob=', Prob, ' ESC  code=',
        IntToHex(R.Code,8), ' rng=', IntToHex(R.Range,8));
    Result := False;
  end;
end;

function SSE_AdaptHit(Prob: Cardinal): Cardinal;
begin
  Result := Prob + ((SSE_TOTAL - Prob) shr 6);
end;

function SSE_AdaptEscape(Prob: Cardinal): Cardinal;
begin
  Result := Prob - (Prob shr 6);
end;

function Fenwick_BSearch(const Row: TFenwickRow; Total, Freq: Cardinal;
  out Rem: Cardinal): Integer;
var
  budget, node: Cardinal;
  base, s: Integer;
begin
  budget := Total - Freq;
  base   := 0;
  s      := $80;
  while s <> 0 do
  begin
    node := Row[base + s];
    if node < budget then
    begin
      base   := base + s;
      budget := budget - node;
    end;
    s := s shr 1;
  end;
  Rem    := budget;
  Result := base;
end;

function Fenwick_MixSearch(const Row, FreqRow: TFenwickRow; Total, Freq: Cardinal;
  const Excl: array of Byte; NExcl: Integer; out Rem: Cardinal): Integer;
var
  baseNode, step, esiNode, i: Integer;
  budget, s, cumat: Cardinal;
  alive: array[0..31] of Boolean;
begin
  budget := (Total - Freq) and $FFFF;
  baseNode := 0;
  step := $80;
  for i := 0 to NExcl - 1 do alive[i] := True;
  while step <> 0 do
  begin
    esiNode := baseNode + step;
    s := 0;
    for i := 0 to NExcl - 1 do
      if alive[i] and (esiNode > Excl[i]) then
        s := (s + FreqRow[Excl[i]]) and $FFFF;
    cumat := Row[esiNode];
    if cumat < ((s + budget) and $FFFFFFFF) then
    begin
      for i := 0 to NExcl - 1 do
        if alive[i] and (esiNode > Excl[i]) then alive[i] := False;
      budget := (budget - ((cumat - s) and $FFFFFFFF)) and $FFFF;
      baseNode := esiNode;
    end;
    step := step shr 1;
  end;
  Rem := budget;
  Result := baseNode;
end;

function Record_DecodeWalk(var R: TRangeDecoder; const Rec: TOrder1Record;
  Total: Cardinal; Excl: PByte; var NExcl: Integer; out FoundSym: Integer): Boolean;
var
  threshold, cum, nxt, cnt, low, high: Cardinal;
  slot: Integer;
  found: Boolean;
begin
  threshold := RD_GetFreq(R, Total) and $FFFF;
  cum   := 0;
  found := False;
  FoundSym := -1;
  low   := 0;
  high  := Total and $FFFF;
  for slot := 0 to 11 do
  begin
    cnt := Rec[1 + slot];
    if cnt = 0 then Break;
    nxt := (cum + cnt) and $FFFF;
    if threshold < nxt then
    begin
      FoundSym := Rec[$D + slot];
      low := cum; high := nxt;
      found := True;
      Break;
    end;
    Excl[NExcl] := Rec[$D + slot];
    Inc(NExcl);
    cum := nxt;
  end;
  if not found then low := cum;
  RD_Decode(R, low, high - low);
  Result := found;
end;

procedure Detr_Init(var D: TDetransform);
begin
  D.Flag := 0;
  D.Arg  := 0;
end;

procedure Detr_Put(b: Byte; Outp: PByte; var OutLen: Integer); inline;
begin
  Outp[OutLen] := b;
  Inc(OutLen);
end;

procedure Detr_Emit(var D: TDetransform; Sym: Byte; Count, Thr1, Thr2: Cardinal;
  Outp: PByte; var OutLen: Integer);
var
  dl, flag, cls, strlen, i: Cardinal;
  off, term: Cardinal;
begin
  dl   := (not Sym) and $FF;
  flag := D.Flag;

  if flag = 1 then
  begin
    D.Flag := 0;
    if Count < Thr1 then
    begin
      term := (D.Arg - $A6) and $FFFFFFFF;
      Detr_Put(DetrEsc[(term * 11 + dl) and $FFFFFFFF], Outp, OutLen);
    end
    else if dl = $FE then
      Detr_Put($FE, Outp, OutLen)
    else
    begin
      Detr_Put(0, Outp, OutLen); Detr_Put(0, Outp, OutLen);
      Detr_Put(3, Outp, OutLen); Detr_Put(3, Outp, OutLen);
      Detr_Put(dl, Outp, OutLen);
    end;
    Exit;
  end;

  if (Count >= Thr1) and (dl = $FE) then
  begin
    D.Flag := 1;
    Exit;
  end;
  if Count >= Thr2 then
  begin
    Detr_Put(dl, Outp, OutLen); Exit;
  end;
  if (dl < $80) and (flag = 0) then
  begin
    Detr_Put(dl, Outp, OutLen); Exit;
  end;

  cls := DetrClass[dl];
  if cls >= $C8 then
  begin
    Detr_Put((dl - flag) and $FF, Outp, OutLen);
    D.Flag := 0;
    Exit;
  end;
  if cls = $64 then
  begin
    D.Arg := dl; D.Flag := 1; Exit;
  end;
  if cls = $63 then
  begin
    D.Flag := $20; Exit;
  end;

  strlen := DetrStrLen[cls];
  off    := DetrStrOff[cls];
  if flag <> 0 then
  begin
    Detr_Put((((not DetrStrData[off]) and $FF) - $20) and $FF, Outp, OutLen);
    Inc(off); Dec(strlen);
    D.Flag := 0;
  end;
  for i := 1 to strlen do
  begin
    Detr_Put((not DetrStrData[off]) and $FF, Outp, OutLen);
    Inc(off);
  end;
end;

initialization
  RdTrace := GetEnvironmentVariable('PPM_RDTRACE') <> '';

end.
