unit uha_ppm_records;

{$mode delphi}{$H+}{$Q-}{$R-}

interface

uses uha_ppm_kernel, uha_ppm_statics, uha_ppm_bc1sub, SysUtils;

procedure Rec1_ApplyRecord(var M: TPpmModel; Sym: Integer; C38: Cardinal;
  S47Hint: Integer);

procedure Rec2_ApplyHeavy(var M: TPpmModel; Sym: Integer);
procedure Rec2_ApplyLight(var M: TPpmModel; Sym: Integer);

var Rec2NewCount: Int64; Rec2FoundCount: Int64;

implementation

var Rec1Bfc: Boolean;
var R2Watch: Boolean; R2WatchIdx: Cardinal = $FFFFFFFF;

const M32 = $FFFFFFFF;

procedure RecGlobals(var M: TPpmModel);
var edx: Cardinal;
begin
  edx := (M.DCG + 2) and M32;
  M.DCG := edx;
  if edx > $800 then
  begin
    M.DCG := edx shr 1;
    M.C4G := M.C4G shr 1;
    M.A8G := M.A8G shr 1;
  end;
end;

function Rec1Sort(var R: TRec1Rec; Cl: Integer): Integer;
var t: Byte;
begin
  while (Cl > 0) and (R[1 + Cl] >= R[Cl]) do
  begin
    t := R[1 + Cl];  R[1 + Cl]  := R[Cl];      R[Cl]      := t;
    t := R[$D + Cl]; R[$D + Cl] := R[$C + Cl]; R[$C + Cl] := t;
    R[$1A] := (R[$1A] - 1) and $FF;
    Dec(Cl);
  end;
  Result := Cl;
end;

procedure Rec1Special(var M: TPpmModel; Sym: Integer; C38: Cardinal);
var
  ctx, best, edx, cur: Cardinal;
  curCntPlus, bestScore, curRun: Cardinal;
  idx: Cardinal;
  i: Integer;
begin
  ctx := C38 and $7FFF;
  edx := 0;
  best := 0;
  if M.Rec1s[ctx][0] <> 0 then
  begin
    cur := ctx;
    while True do
    begin
      curCntPlus := (M.Rec1s[cur][1] + 1) and M32;
      bestScore := M.Rec1s[ctx + best][$19] and $3F;
      if M.Rec1s[ctx + best][1] > curCntPlus then
        Inc(bestScore);
      curRun := M.Rec1s[cur][$19] and $3F;
      if bestScore > curRun then
        best := edx;
      Inc(edx, $8000);
      Inc(cur, $8000);
      if edx >= $40000 then Break;
      if M.Rec1s[cur][0] = 0 then
      begin
        best := edx;
        Break;
      end;
    end;
  end;

  if edx < $38000 then
    M.Rec1s[ctx + edx + $8000][0] := 0;

  idx := ctx + best;
  for i := 0 to $1F do M.Rec1s[idx][i] := 0;
  M.Rec1s[idx][0]   := 1;
  M.Rec1s[idx][$1A] := $20;
  M.Rec1s[idx][1]   := (M.S48 + 1) and $FF;
  M.Rec1s[idx][$D]  := Sym and $FF;
  M.Rec1s[idx][$1C] := M.C48 and $FF;
  M.Rec1s[idx][$1D] := (M.C48 shr 8) and $FF;
  M.Rec1s[idx][$1E] := (M.C48 shr 16) and $FF;
  M.Rec1s[idx][$1F] := (M.C48 shr 24) and $FF;
  M.C38 := ctx;
  M.LinkTab[M.LinkPtr] := M.Rec1s[idx][$1A];
end;

function Rec1Main(var M: TPpmModel; var R: TRec1Rec; Sym, S47Hint: Integer;
  out BumpC4: Boolean): Integer;
var
  cl, fcl, i: Integer;
  ah, runCond: Boolean;
  flags, low6, newcnt: Cardinal;
begin
  BumpC4 := False;
  if S47Hint <> $FF then cl := S47Hint
  else
  begin
    cl := 0;
    while (cl < $C) and (R[$D + cl] <> (Sym and $FF)) do Inc(cl);
  end;

  if cl >= $C then
  begin
    ah := PPMS_REC1THR[R[0]] < M.C1C;
    if ah then
      for i := 0 to $C do R[i] := ((R[i] + 1) shr 1) and $FF;
    R[0]   := (R[0] + 2) and $FF;
    R[$1B] := R[$1B] shr 1;
    fcl := 1;
    while (fcl < $B) and (R[1 + fcl] <> 0) do Inc(fcl);
    newcnt := (M.S48 + 2) and $FF;
    R[1 + fcl]  := newcnt;
    R[$D + fcl] := Sym and $FF;
    R[$1A] := fcl;
    low6 := R[$19] and $3F;
    R[$19] := (R[$19] and $C0) or (low6 shr 1);
    Result := Rec1Sort(R, fcl);
    Exit;
  end;

  BumpC4 := True;
  ah := PPMS_REC1THR[R[0]] < M.C1C;
  flags := R[$19] and $C0;
  if (Cardinal(R[1 + cl]) + 1) < (Cardinal(R[1]) shr 1) then
  begin
    if flags = $C0 then ah := True;
    flags := (flags + $40) and $FF;
  end
  else
    flags := (flags shr 1) and $C0;
  R[$19] := (R[$19] and $3F) or flags;
  runCond := (cl <> 0) and ((R[$1A] shr 4) >= 4) and ((R[$1A] and $F) = Cardinal(cl));
  if runCond or ah then
    for i := 0 to $C do R[i] := ((R[i] + 1) shr 1) and $FF;
  R[1 + cl] := (R[1 + cl] + 2) and $FF;
  low6 := R[$19] and $3F;
  if low6 < $3F then R[$19] := (R[$19] and $C0) or (low6 + 1);
  if (R[$1A] and $F) = Cardinal(cl) then
  begin
    if R[$1A] < $F0 then R[$1A] := (R[$1A] + $10) and $FF;
    if R[$1B] < $F8 then R[$1B] := (R[$1B] + 8) and $FF;
  end
  else
  begin
    R[$1A] := cl;
    R[$1B] := R[$1B] shr 1;
  end;
  Result := Rec1Sort(R, cl);
end;

procedure Rec1_ApplyRecord(var M: TPpmModel; Sym: Integer; C38: Cardinal;
  S47Hint: Integer);
var
  slot, aslot: Integer;
  bumpC4: Boolean;
  linkFrom, q, baseCnt: Cardinal;
begin
  if C38 >= $40000 then
  begin
    Rec1Special(M, Sym, C38);
    Exit;
  end;

  if M.Flag3938 <> 0 then
  begin
    aslot := S47Hint;
    if aslot = $FF then
    begin
      aslot := 0;
      while (aslot < $C) and (M.Rec1s[C38][$D + aslot] <> (Sym and $FF)) do Inc(aslot);
    end;
    if (aslot < $C) and ((M.Rec1s[C38][aslot + 1] shr 6) > M.Rec1s[C38][0]) then
      M.A8G := (M.A8G + 4) and M32;
  end;

  if Rec1Bfc and (M.Flag393B <> 0) then
  begin
    slot := S47Hint;
    if slot = $FF then
    begin
      slot := 0;
      while (slot < $C) and (M.Rec1s[C38][$D + slot] <> (Sym and $FF)) do Inc(slot);
    end;
    if (slot >= 0) and (slot < $C) then
    begin
      baseCnt := M.Rec1s[C38][slot + 1];
      M.S3E := 0;
      Bc1RingRan := False;
      M.Flag3943 := 0;
    end
    else
      baseCnt := M.Rec1s[C38][0];
    if M.C3C <> 0 then
    begin
      q := (baseCnt shl $E) div M.C3C;
      if q < $4000 then
        M.BFC := (M.BFC + (M.F154[q] and $FFFF)) and M32;
    end;
  end;
  slot := Rec1Main(M, M.Rec1s[C38], Sym, S47Hint, bumpC4);
  if bumpC4 then
    M.C4G := (M.C4G + 5) and M32;
  M.S47 := slot and $FF;
  RecGlobals(M);
  linkFrom := C38;
  M.LinkTab[M.LinkPtr] := M.Rec1s[linkFrom][$1A];
end;

function Rec2Sort(var R: TRec2Rec; Cl: Integer): Integer;
var cnt, prev, s8, s9: Byte;
begin
  while Cl > 0 do
  begin
    cnt := R[Cl + 1]; prev := R[Cl];
    if cnt < prev then Break;
    R[Cl + 1] := prev; R[Cl] := cnt;
    s8 := R[Cl + 8]; s9 := R[Cl + 9];
    R[Cl + 8] := s9; R[Cl + 9] := s8;
    R[$13] := (R[$13] - 1) and $FF;
    Dec(Cl);
  end;
  Result := Cl;
end;

procedure Rec2_ApplyHeavy(var M: TPpmModel; Sym: Integer);
var
  ch, cl, ci, i, a: Integer;
  baseCnt, q, dh: Cardinal;
begin
  if R2Watch and (M.C40 = R2WatchIdx) then
    writeln(ErrOutput, 'R2W heavy C40=', IntToHex(M.C40,5), ' sym=', Sym,
      ' slot0=', M.Rec2s[M.C40][9], ' rec0=', M.Rec2s[M.C40][0], ' wpos=', M.WinPos);
  ch := Sym and $FF;
  if (M.WinPos >= 16462) and (M.WinPos <= 16468) and (GetEnvironmentVariable('PPM_R2DBG') <> '') then
    writeln(ErrOutput, 'R2H wpos=', M.WinPos, ' sym=', ch, ' C40=', IntToHex(M.C40,5),
      ' rec2_0=', M.Rec2s[M.C40][0], ' S49=', M.S49, ' C50=', M.C50);
  if M.Rec2s[M.C40][0] = 0 then
  begin
    for i := 0 to $13 do M.Rec2s[M.C40][i] := 0;
    M.Rec2s[M.C40][0] := 3; M.Rec2s[M.C40][1] := 3;
    M.Rec2s[M.C40][$12] := 6; M.Rec2s[M.C40][9] := ch;
    Exit;
  end;

  cl := M.S49;
  if cl = $FF then
  begin
    cl := 0;
    while (cl < 8) and (ch <> M.Rec2s[M.C40][cl + 9]) do Inc(cl);
  end;
  if M.S3E <> 0 then
  begin
    if cl < 8 then
    begin
      Bc1RingRan := False;
      M.Flag3943 := 0;
    end;
    if cl >= 8 then baseCnt := M.Rec2s[M.C40][0]
    else baseCnt := M.Rec2s[M.C40][cl + 1];
    if M.C4C <> 0 then q := ((baseCnt shl $E) div M.C4C) and M32 else q := 0;
    q := q and $1FFFF;
    if q < $4000 then
      M.BFC := (M.BFC + (M.F154[q] and $FFFF)) and M32;
  end;
  if M.Rec2s[M.C40][$12] > PPMS_REC2THR[M.Rec2s[M.C40][0]] then
  begin
    M.Rec2s[M.C40][$12] := 0;
    for a := 8 downto 0 do
    begin
      dh := ((M.Rec2s[M.C40][a] + 1) and $FF) shr 1;
      M.Rec2s[M.C40][a] := dh;
      M.Rec2s[M.C40][$12] := (M.Rec2s[M.C40][$12] + dh) and $FF;
    end;
  end;
  M.Rec2s[M.C40][$12] := (M.Rec2s[M.C40][$12] + 4) and $FF;

  if cl < 8 then
  begin
    M.C50 := ((M.C50 * 4 - M.C50) shr 2) and M32;
    Inc(Rec2FoundCount);
    M.Rec2s[M.C40][$11] := (M.Rec2s[M.C40][$11] shr 1) and $FF;
    M.Rec2s[M.C40][cl + 1] := (M.Rec2s[M.C40][cl + 1] + 4) and $FF;
    if (M.Rec2s[M.C40][$13] and $F) = Cardinal(cl) then
    begin
      if M.Rec2s[M.C40][$13] < $F0 then
        M.Rec2s[M.C40][$13] := (M.Rec2s[M.C40][$13] + $10) and $FF;
      M.C4G := (M.C4G + 5) and M32;
    end
    else
    begin
      M.Rec2s[M.C40][$13] := cl;
      M.C4G := (M.C4G + 5) and M32;
    end;
    cl := Rec2Sort(M.Rec2s[M.C40], cl);
  end
  else
  begin
    M.C50 := (M.C50 + 1) and M32;
    Inc(Rec2NewCount);
    M.Rec2s[M.C40][$11] := (M.Rec2s[M.C40][$11] + 1) and $FF;
    M.Rec2s[M.C40][0] := (M.Rec2s[M.C40][0] + 4) and $FF;
    ci := 1;
    while (ci < 7) and (M.Rec2s[M.C40][ci + 1] <> 0) do Inc(ci);
    if M.Rec2s[M.C40][ci + 1] < $C then
    begin
      dh := M.Rec2s[M.C40][ci + 1];
      M.Rec2s[M.C40][$12] := (M.Rec2s[M.C40][$12] + ((4 - dh) and $FF)) and $FF;
      M.Rec2s[M.C40][ci + 1] := 4; M.Rec2s[M.C40][ci + 9] := ch;
      M.Rec2s[M.C40][$13] := ci;
      cl := Rec2Sort(M.Rec2s[M.C40], ci);
    end
    else
    begin
      M.Rec2s[M.C40][ci + 1] := 4; M.Rec2s[M.C40][ci + 9] := ch;
      M.Rec2s[M.C40][$13] := ci;
      cl := Rec2Sort(M.Rec2s[M.C40], 0);
    end;
  end;
  M.S49 := cl and $FF;
  RecGlobals(M);
end;

procedure Rec2_ApplyLight(var M: TPpmModel; Sym: Integer);
var
  ch, cl, ci, a: Integer;
  v, dh: Cardinal;
  i: Integer;
begin
  if R2Watch and (M.C40 = R2WatchIdx) then
    writeln(ErrOutput, 'R2W light C40=', IntToHex(M.C40,5), ' sym=', Sym,
      ' slot0=', M.Rec2s[M.C40][9], ' rec0=', M.Rec2s[M.C40][0], ' wpos=', M.WinPos);
  ch := Sym and $FF;
  if M.Rec2s[M.C40][0] = 0 then
  begin
    for i := 0 to $13 do M.Rec2s[M.C40][i] := 0;
    M.Rec2s[M.C40][0] := 2; M.Rec2s[M.C40][1] := 2;
    M.Rec2s[M.C40][$12] := 4; M.Rec2s[M.C40][9] := ch;
    Exit;
  end;
  M.S49 := 0;
  cl := 0;
  while (cl < 8) and (ch <> M.Rec2s[M.C40][cl + 9]) do Inc(cl);
  if M.Rec2s[M.C40][$12] > PPMS_REC2THR[M.Rec2s[M.C40][0]] then
  begin
    M.Rec2s[M.C40][$12] := 0;
    for a := 8 downto 0 do
    begin
      v := ((M.Rec2s[M.C40][a] + 1) and $FF) shr 1;
      M.Rec2s[M.C40][a] := v;
      M.Rec2s[M.C40][$12] := (M.Rec2s[M.C40][$12] + v) and $FF;
    end;
  end;
  M.Rec2s[M.C40][$12] := (M.Rec2s[M.C40][$12] + 1) and $FF;
  if cl < 8 then
  begin
    M.Rec2s[M.C40][cl + 1] := (M.Rec2s[M.C40][cl + 1] + 1) and $FF;
    if (M.Rec2s[M.C40][$13] and $F) = Cardinal(cl) then
    begin
      if M.Rec2s[M.C40][$13] < $40 then
        M.Rec2s[M.C40][$13] := (M.Rec2s[M.C40][$13] + $10) and $FF;
    end
    else
      M.Rec2s[M.C40][$13] := cl;
    M.S49 := Rec2Sort(M.Rec2s[M.C40], cl) and $FF;
  end
  else
  begin
    M.Rec2s[M.C40][$11] := (M.Rec2s[M.C40][$11] + 1) and $FF;
    M.Rec2s[M.C40][0] := (M.Rec2s[M.C40][0] + 1) and $FF;
    ci := 1;
    while (ci < 7) and (M.Rec2s[M.C40][ci + 1] <> 0) do Inc(ci);
    dh := M.Rec2s[M.C40][ci + 1];
    if dh < $C then
      M.Rec2s[M.C40][$12] := (M.Rec2s[M.C40][$12] + ((1 - dh) and $FF)) and $FF;
    M.Rec2s[M.C40][ci + 1] := 1; M.Rec2s[M.C40][ci + 9] := ch;
    M.Rec2s[M.C40][$13] := ci;
    M.S49 := Rec2Sort(M.Rec2s[M.C40], ci) and $FF;
  end;
end;

initialization
  Rec1Bfc := GetEnvironmentVariable('X_REC1BFC_OFF') = '';
  R2Watch := GetEnvironmentVariable('PPM_R2WATCH') <> '';
  R2WatchIdx := Cardinal(StrToIntDef(GetEnvironmentVariable('PPM_R2WATCH'), -1));

end.
