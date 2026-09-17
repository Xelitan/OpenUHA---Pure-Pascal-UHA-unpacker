unit uha_ppm_bc1sub;

{$mode delphi}{$H+}{$Q-}{$R-}

interface

uses uha_ppm_textbook, uha_ppm_kernel, SysUtils;

const
  BC1_LVLBYTES = $400000;
  BC1_LVLOFF: array[0..7] of Cardinal =
    ($000000,$040000,$0c0000,$140000,$180000,$1c0000,$200000,$3c0000);

  BC1_WT070: array[0..15] of Cardinal =
    (1,4,8,12,17,24,33,43,53,64,76,89,103,118,144,199);
  BC1_WT0B0: array[0..15] of Cardinal =
    (1,3,6,10,16,23,32,43,53,64,76,89,103,118,144,199);
  BC1_WT0F0: array[0..15] of Cardinal =
    (0,1,3,6,13,22,32,43,53,64,76,89,103,118,144,199);

type
  TBc1Sub = record
    Lvl   : array of Byte;
    Ring  : array[0..$7F] of Byte;
    Conf  : array[0..$FF] of Byte;
    Pred  : array[0..$FF] of Byte;
    Ctx   : array[0..7] of Cardinal;
    Win   : array[0..$FFF] of Byte;
    WPos  : Cardinal;
    RingPtr : Integer;
    RingFlag: Integer;
    Best  : Integer;
    BestPred  : Byte;
    BestFlags : Byte;
    BestC0    : Byte;
    BestC1    : Byte;
    Fired393C : Boolean;
    LastBest  : Integer;
  end;

var
  Bc1: TBc1Sub;
  Bc1WpFire: Boolean;
  Bc1RingRan: Boolean;
  Bc1F154Pending: Boolean;
  Bc1F154Key: Cardinal;

  XLevelRing : Boolean;
  XOrRescale : Boolean;
  XMaskFlags : Boolean;
  XNewFlags  : Boolean;
  XNoMatchHalve : Boolean;
  XF154Bfc   : Boolean;
  XLowFlagExit : Boolean;
  LvlDbg : Boolean;
  LvlLim : Integer;
  LvlPos : Integer;
  Bc1PostArmed : Boolean;
  Bc1RecOk : Boolean;
  StrideCtx7 : Boolean;
  PostGateOff  : Boolean;

procedure Bc1Reset;
procedure Bc1BlockReset;

function Bc1PreDecode(var M: TPpmModel; R0, R1: Cardinal): Boolean;

procedure Bc1RingMasses(const W: array of Cardinal; const Y: array of Byte;
  out M0, M1: Cardinal);

function Bc1RingDecode(var R: TRangeDecoder; M0, M1: Cardinal): Boolean;

procedure Bc1PostUpdate(var M: TPpmModel; Sym: Byte);

procedure Bc1Sub2Update(CtxByte, Sym: Byte);

procedure Bc1PushWindow(Sym: Byte);

implementation

function RecBase(level: Integer; ctx: Cardinal): Cardinal; inline;
begin
  Result := BC1_LVLOFF[level] + ctx*4;
end;

procedure Bc1BlockReset;
var i: Integer;
begin
  SetLength(Bc1.Lvl, BC1_LVLBYTES);
  for i := 0 to BC1_LVLBYTES-1 do Bc1.Lvl[i] := 0;
  for i := 0 to $7F do Bc1.Ring[i] := 1;

  for i := 0 to $FF do begin Bc1.Conf[i] := 0; Bc1.Pred[i] := $FF; end;
end;

procedure Bc1Reset;
var i: Integer;
begin
  Bc1BlockReset;
  for i := 0 to $FFF do Bc1.Win[i] := 0;
  Bc1.WPos := $140;
  Bc1.RingPtr := -1; Bc1.Best := 8; Bc1.LastBest := 0;
  Bc1.BestPred := 0; Bc1.BestFlags := 0;
end;

procedure Bc1NoMatchExit(var M: TPpmModel);
begin
  if XNoMatchHalve and (M.Br18 > 1) then
    M.RankSmall[M.RankPtrSmall] := M.RankSmall[M.RankPtrSmall] shr 1;
end;

function Bc1PreDecode(var M: TPpmModel; R0, R1: Cardinal): Boolean;
var
  b0,b1,b2,b3,c3,depth: Cardinal;
  byteA, byteB, flag: Cardinal;
  level: Integer;
  rb: Cardinal;
  c0,c1,c3f,score,best: Cardinal;
  bh: Cardinal;
begin
  b0 := R0 and $FF; b1 := (R0 shr 8) and $FF;
  b2 := (R0 shr 16) and $FF; b3 := (R0 shr 24) and $FF;
  c3 := (R1 shr 24) and $FF;

  if (R0 and $FFFF0000) = $FFFF0000 then depth := $10000
  else if (R0 and $FFFF) = $FFFF then depth := $20000
  else if (R0 and $FF000000) = $FF000000 then depth := $30000
  else if (R0 and $FF0000) = $FF0000 then depth := $40000
  else if (R0 and $FF00) = $FF00 then depth := $50000
  else if (R0 and $FF) = $FF then depth := $60000
  else depth := 0;

  Bc1.Ctx[0] := (b3 shl 8) + c3;
  Bc1.Ctx[1] := (R0 shr 8) and $FFFF;
  Bc1.Ctx[2] := (R0 shr 16) and $FFFF;
  Bc1.Ctx[3] := (b2 shl 8) + b0;
  Bc1.Ctx[4] := (b3 shl 8) + b1;
  Bc1.Ctx[5] := (b3 shl 8) + b0;
  Bc1.Ctx[6] := (R1 and $FFFF) + depth;

  if StrideCtx7 and (M.Brf0 <> 0) and (M.Flag3939 <> M.Brf0) then
  begin
    flag := ((M.LastCtx mod M.Brf0) shl 8) and $FFFF;
    byteA := M.Window[(M.WinPos - M.Brf0) and M.WinMask];
    byteB := M.Window[(M.WinPos - 2 * M.Brf0) and M.WinMask];
  end
  else
  begin
    byteA := Bc1.Win[(Bc1.WPos - 1) and $FFF];
    byteB := Bc1.Win[(Bc1.WPos - 2) and $FFF];
    if ((R0 shr 16) and $FFFF) = $F6FF then flag := $100 else flag := 0;
  end;
  Bc1.Ctx[7] := (flag + ((byteA - byteB) and $FF)) and $FFFF;
  Bc1F154Pending := False;
  Bc1.Lvl[RecBase(7, Bc1.Ctx[7]) + 2] := (2*byteA - byteB) and $FF;

  if b0 = $FF then
  begin
    Bc1.Ctx[1] := Bc1.Ctx[1] + $10000;
    Bc1.Ctx[2] := Bc1.Ctx[2] + $10000;
  end;

  Bc1.RingPtr := -1;
  Bc1RecOk := False;
  Bc1.Fired393C := False;
  best := 0; bh := 8;
  for level := 0 to 7 do
  begin
    rb := RecBase(level, Bc1.Ctx[level]);
    c0 := Bc1.Lvl[rb]; c1 := Bc1.Lvl[rb+1]; c3f := Bc1.Lvl[rb+3];
    if c0 = 0 then Continue;
    if c3f >= $80 then Continue;
    score := ((c1 shl 8) * c3f) div c0;
    if score > best then begin best := score; bh := level; end;
  end;
  if LvlDbg and (LvlPos <= LvlLim) then
  begin
    Write(ErrOutput, 'PRE ol=', LvlPos, ' bh=', bh, ' ctx=[');
    for level := 0 to 7 do
    begin
      Write(ErrOutput, IntToHex(Bc1.Ctx[level],1));
      if level < 7 then Write(ErrOutput, ',');
    end;
    Write(ErrOutput, ']  ');
    for level := 0 to 7 do
    begin
      rb := RecBase(level, Bc1.Ctx[level]);
      Write(ErrOutput, level, ':', Bc1.Lvl[rb], '/', Bc1.Lvl[rb+1], '/',
        Bc1.Lvl[rb+2], '/', IntToHex(Bc1.Lvl[rb+3],2));
      if level < 7 then Write(ErrOutput, ' ');
    end;
    Writeln(ErrOutput);
  end;
  Bc1.Best := Integer(bh);
  if bh >= 8 then
  begin
    Bc1NoMatchExit(M);
    Bc1.RingFlag := 1; Result := False; Exit;
  end;

  rb := RecBase(Integer(bh), Bc1.Ctx[bh]);
  Bc1.BestPred := Bc1.Lvl[rb+2];
  Bc1.BestFlags := Bc1.Lvl[rb+3];
  c0 := Bc1.Lvl[rb]; c1 := Bc1.Lvl[rb+1];
  Bc1.BestC0 := c0 and $FF; Bc1.BestC1 := c1 and $FF;

  if (c1 <= c0) and ((not XLowFlagExit) or ((Bc1.BestFlags and $7F) <= 1)) then
  begin
    Bc1NoMatchExit(M);
    Bc1.RingFlag := 1; Result := False; Exit;
  end;

  Bc1.Fired393C := (M.Brf0 > 1) and (bh = 7);

  Bc1.LastBest := Integer(bh);
  Bc1RecOk := True;

  if (c0 * 5 <= c1 * 3) or ((Bc1.BestFlags and $7F) > 2) then
    Bc1.RingFlag := 0
  else
    Bc1.RingFlag := 1;
  if c0 = 2 then
  begin
    if (c1 >= 3) and (c1 <= 6) then
      Bc1.RingPtr := Integer(((c1 shl 3) - $18 + bh) * 2);
  end
  else if c0 = 3 then
  begin
    if (c1 >= 4) and (c1 <= 7) then
      Bc1.RingPtr := Integer(((c1 shl 3) - $20 + bh) * 2 + $40);
  end;

  Result := Bc1WpFire or (Bc1.RingPtr >= 0);
end;

procedure Bc1RingMasses(const W: array of Cardinal; const Y: array of Byte;
  out M0, M1: Cardinal);
var
  i: Integer;
  rp: Cardinal;
begin
  if Bc1.RingPtr < 0 then
  begin

    M0 := Bc1.BestC0;
    M1 := Bc1.BestC1 + BC1_WT070[(Bc1.BestFlags shr 3) and $F];
  end
  else
  begin
    rp := Cardinal(Bc1.RingPtr);
    M0 := Bc1.Ring[rp];
    M1 := Bc1.Ring[rp+1] + BC1_WT070[(Bc1.BestFlags shr 3) and $F];
  end;
  for i := 0 to 2 do
    if Bc1.BestPred = Y[i] then M1 := M1 + W[i] else M0 := M0 + W[i];
  if GetEnvironmentVariable('PPM_TRIPDBG') <> '' then
    writeln(ErrOutput, 'TRIP m0=', M0, ' m1=', M1, ' bc0=', Bc1.BestC0, ' bc1=', Bc1.BestC1,
      ' rp=', Bc1.RingPtr, ' bp=', Bc1.BestPred,
      ' y0=', Y[0], ' y1=', Y[1], ' y2=', Y[2],
      ' w0=', W[0], ' w1=', W[1], ' w2=', W[2]);
end;

function Bc1RingDecode(var R: TRangeDecoder; M0, M1: Cardinal): Boolean;
var
  total, freq, low, width: Cardinal;
begin
  total := M0 + M1;
  if total = 0 then
  begin
    if GetEnvironmentVariable('PPM_RINGDBG') <> '' then
      writeln(ErrOutput, 'RINGZERO m0=', M0, ' m1=', M1, ' rp=', Bc1.RingPtr,
        ' c0=', Bc1.BestC0, ' c1=', Bc1.BestC1);
    Result := False; Exit;
  end;
  if GetEnvironmentVariable('PPM_MASSDBG') <> '' then
    writeln(ErrOutput, 'MASS m0=', M0, ' m1=', M1, ' total=', total,
      ' code=', IntToHex(R.Code,8), ' rng=', IntToHex(R.Range,8));
  freq := RD_GetFreq(R, total);
  if freq < M0 then begin low := 0; width := M0; Result := False; end
  else begin low := M0; width := M1; Result := True; end;
  RdSite := 251; RD_Decode(R, low, width);
end;

procedure Bc1PostUpdate(var M: TPpmModel; Sym: Byte);
var
  level: Integer;
  rb, rp: Cardinal;
  c0, c1, c2, c3: Byte;
  hit: Cardinal;
begin

  for level := 0 to 7 do
  begin
    rb := RecBase(level, Bc1.Ctx[level]);
    c0 := Bc1.Lvl[rb];
    if c0 = 0 then
    begin
      Bc1.Lvl[rb]   := 2;
      Bc1.Lvl[rb+1] := 2;
      Bc1.Lvl[rb+2] := Sym;
      if XNewFlags then Bc1.Lvl[rb+3] := 0;
      Continue;
    end;

    if level = Bc1.LastBest then
    begin
      c1 := Bc1.Lvl[rb+1];
      c2 := Bc1.Lvl[rb+2];
      if Bc1RingRan and ((Cardinal(c0) + Cardinal(c1)) <> 0) then
      begin

        if Sym = c2 then
        begin
          M.Flag3943 := 0;
          Bc1F154Key := (Cardinal(c1) shl 14) div (Cardinal(c0) + Cardinal(c1))
        end
        else
          Bc1F154Key := (Cardinal(c0) shl 14) div (Cardinal(c0) + Cardinal(c1));
        Bc1F154Pending := True;
        if XF154Bfc and (Bc1F154Key < $4000) then
          M.BFC := (M.BFC + (M.F154[Bc1F154Key] and $FFFF)) and $FFFFFFFF;
      end;
      if XLevelRing and (Bc1.RingPtr >= 0) then
      begin
        rp := Cardinal(Bc1.RingPtr);
        hit := Ord(Sym = c2);
        Inc(Bc1.Ring[rp + hit]);
        if (Bc1.Ring[rp+1] >= $FE) or (XOrRescale and (Bc1.Ring[rp] >= $FE)) then
        begin
          Bc1.Ring[rp]   := (Bc1.Ring[rp]   + 1) shr 1;
          Bc1.Ring[rp+1] := (Bc1.Ring[rp+1] + 1) shr 1;
        end;
      end;
    end;

    if XMaskFlags then c3 := Bc1.Lvl[rb+3] and $7F
    else c3 := Bc1.Lvl[rb+3];
    c2 := Bc1.Lvl[rb+2];
    if XMaskFlags then Bc1.Lvl[rb+3] := c3;
    c0 := Bc1.Lvl[rb]; c1 := Bc1.Lvl[rb+1];
    if Sym = c2 then
    begin
      if c1 >= $FE then
      begin
        c0 := Byte(c0 + 1) shr 1;
        c1 := Byte(c1 + 1) shr 1;
      end;
      Inc(c1);
      Bc1.Lvl[rb] := c0; Bc1.Lvl[rb+1] := c1;
      if c3 < $7F then Bc1.Lvl[rb+3] := c3 + 1;
    end
    else
    begin
      if c0 >= $FE then
      begin
        c0 := Byte(c0 + 1) shr 1;
        c1 := Byte(c1 + 1) shr 1;
      end;
      Inc(c0);
      Bc1.Lvl[rb] := c0; Bc1.Lvl[rb+1] := c1;
      if c3 < 2 then
      begin
        Bc1.Lvl[rb+2] := Sym;
        Bc1.Lvl[rb+3] := $80;
      end
      else
        Bc1.Lvl[rb+3] := (c3 shr 1) + $80;
    end;
  end;
  if (not XLevelRing) and (Bc1.RingPtr >= 0) and Bc1RingRan then
  begin
    rb := Cardinal(Bc1.RingPtr);
    hit := Ord(Sym = Bc1.BestPred);
    Inc(Bc1.Ring[rb + hit]);
    if (Bc1.Ring[rb+1] >= $FE) or (XOrRescale and (Bc1.Ring[rb] >= $FE)) then
    begin
      Bc1.Ring[rb]   := (Bc1.Ring[rb] + 1) shr 1;
      Bc1.Ring[rb+1] := (Bc1.Ring[rb+1] + 1) shr 1;
    end;
  end;
end;

procedure Bc1Sub2Update(CtxByte, Sym: Byte);
begin
  if Sym = Bc1.Pred[CtxByte] then
  begin
    if Bc1.Conf[CtxByte] < $F then Inc(Bc1.Conf[CtxByte]);
  end
  else
  begin
    Bc1.Pred[CtxByte] := Sym;
    Bc1.Conf[CtxByte] := 0;
  end;
end;

procedure Bc1PushWindow(Sym: Byte);
begin
  Bc1.Win[Bc1.WPos and $FFF] := Sym;
  Inc(Bc1.WPos);
end;

initialization
  Bc1WpFire := GetEnvironmentVariable('PPM_WPFIRE') <> '0';
  StrideCtx7 := GetEnvironmentVariable('X_STRIDECTX7_OFF') = '';

  XOrRescale := GetEnvironmentVariable('X_ORRESCALE_OFF') = '';
  XMaskFlags := GetEnvironmentVariable('X_MASKFLAGS_OFF') = '';
  XNewFlags  := GetEnvironmentVariable('X_NEWFLAGS_OFF') = '';
  XNoMatchHalve := GetEnvironmentVariable('X_HALVE_OFF') = '';
  XF154Bfc   := GetEnvironmentVariable('X_F154_OFF') = '';
  XLowFlagExit := GetEnvironmentVariable('X_LOWFLAG_OFF') = '';

  XLevelRing := GetEnvironmentVariable('X_LEVELRING_OFF') = '';
  PostGateOff := GetEnvironmentVariable('X_POSTGATE_OFF') <> '';
  LvlDbg := GetEnvironmentVariable('PPM_LVLDBG') <> '';
  LvlLim := StrToIntDef(GetEnvironmentVariable('PPM_LVLDBG'), 16);

end.
