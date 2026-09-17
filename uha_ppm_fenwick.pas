unit uha_ppm_fenwick;

{$mode delphi}{$H+}{$Q-}{$R-}

interface

uses uha_ppm_kernel;

function  HalveAndRebuild(var M: TPpmModel; Ctx: Integer): Cardinal;
procedure ApplyFenwick(var M: TPpmModel; Sym, Order: Integer);
procedure ApplyT268(var M: TPpmModel; Sym, CtxIdx: Integer);
procedure ApplyLiteralUpdates(var M: TPpmModel; EntryCtx, NextCtx, Sym: Integer);

procedure T268_Rescale(var M: TPpmModel; CtxIdx: Integer);

implementation

uses SysUtils;

var PbWatch: Boolean; PbWatchCtx: Integer = -1;
var T268Win: Boolean; T268Lo: Integer = 0; T268Hi: Integer = -1;
var T268Ctx: Integer = -1;
var FenwickWatch: Integer = -1;

const M16 = $FFFF; M32 = $FFFFFFFF;

function LowBit(al: Cardinal): Cardinal; inline;
begin
  Result := (((0 - al) and al) and $FF);
end;

function HalveAndRebuildEx(var M: TPpmModel; Ctx: Integer; Bc1Drop: Boolean): Cardinal;
var total, hw, f: Cardinal; i, twok, fourk, a: Integer;
begin
  total := 0;
  for i := 0 to $FF do
  begin
    f := M.Freq[Ctx][i];
    if f = 0 then Continue;
    if Bc1Drop and (M.ByteClass <> 0) then
    begin
      if f > $10 then hw := f shr 1 else hw := 0;
    end
    else
      hw := (f + 1) shr 1;
    M.Freq[Ctx][i] := hw and M16;
    total := (total + hw) and M32;
  end;
  for i := 0 to $FE do M.Cum[Ctx][i + 1] := M.Freq[Ctx][i];
  M.Cum[Ctx][0] := total and M16;
  twok := 2;
  while twok <= $80 do
  begin
    fourk := 2 * twok;
    a := $200 - fourk;
    while a <> 0 do
    begin
      M.Cum[Ctx][a shr 1] := (M.Cum[Ctx][a shr 1] + M.Cum[Ctx][(a - twok) shr 1]) and M16;
      a := a - fourk;
    end;
    twok := twok * 2;
  end;
  Result := total;
end;

function HalveAndRebuild(var M: TPpmModel; Ctx: Integer): Cardinal;
begin
  Result := HalveAndRebuildEx(M, Ctx, False);
end;

procedure ApplyFenwick(var M: TPpmModel; Sym, Order: Integer);
var wc, al, step, tot: Cardinal;
begin
  wc := M.WorkCtx;
  if Integer(wc) = FenwickWatch then
    writeln(ErrOutput, 'FW ol=', M.WinPos, ' ctx=', Order, ' sym=', Sym,
      ' total=', M.Cum[wc][0], ' freq=', M.Freq[wc][Sym]);
  step := M.TStep[Order];
  M.Freq[wc][Sym] := (M.Freq[wc][Sym] + step) and M16;
  al := (Sym + 1) and $FF;
  while al <> 0 do
  begin
    M.Cum[wc][al] := (M.Cum[wc][al] + step) and M16;
    al := (al + LowBit(al)) and $FF;
  end;
  tot := (M.Cum[wc][0] + step) and M16;
  M.Cum[wc][0] := tot;
  if tot >= $4000 then HalveAndRebuild(M, wc);
end;

procedure T268_Rescale(var M: TPpmModel; CtxIdx: Integer);
var total, ht, budget: Cardinal; bc: Byte;
begin
  total := HalveAndRebuildEx(M, CtxIdx, True);
  if total = 0 then Exit;
  ht := (M.EntWt[CtxIdx] + 1) shr 1;
  M.EntWt[CtxIdx] := ht and M16;
  budget := (ht + total) and M32;
  M.Budget[CtxIdx] := budget;
  bc := M.ByteClass;
  if CtxIdx >= (Cardinal($200) shr bc) then
    M.Budget[CtxIdx] := (budget shl 8) and M32
  else
    M.Budget[CtxIdx] := ((budget * 3) shl 5) and M32;
  if M.Flag3934 = 3 then
    if total > (ht shl 3) then
      M.Budget[CtxIdx] := (M.Budget[CtxIdx] shl 4) and M32;
end;

procedure ApplyT268(var M: TPpmModel; Sym, CtxIdx: Integer);
var
  si, entry_freq, persym0, combo, sub_amt, ef, weight, rowtot, al: Cardinal;
  predbyte, bh: Integer;
  budgetSigned: Int64;
begin
  if CtxIdx = T268Ctx then
    writeln(ErrOutput, 'CTX ol=', M.WinPos, ' sym=', Sym,
      ' cum=', M.Cum[CtxIdx][0], ' ent=', M.EntWt[CtxIdx],
      ' ord=', M.Order0Wt[CtxIdx], ' freq=', M.Freq[CtxIdx][Sym],
      ' budget=', M.Budget[CtxIdx]);
  if (PbWatch and (CtxIdx = PbWatchCtx))
     or (T268Win and (Integer(M.WinPos) >= T268Lo) and (Integer(M.WinPos) <= T268Hi)) then
    writeln(ErrOutput, 'T268 ctx=', IntToHex(CtxIdx,3), ' sym=', Sym,
      ' pb=', M.PredByte[CtxIdx], ' wpos=', M.WinPos);
  si := M.TStep2[CtxIdx];
  entry_freq := M.EntWt[CtxIdx];
  persym0 := M.Freq[CtxIdx][Sym];
  predbyte := M.PredByte[CtxIdx];
  combo := (entry_freq + persym0) and M32;
  if Sym = predbyte then
  begin
    bh := M.ClsIdx[CtxIdx];
    if bh < $F then M.ClsIdx[CtxIdx] := bh + 1;
    sub_amt := (combo shl 5) and M32;
  end
  else
  begin
    if PbWatch and (CtxIdx = PbWatchCtx) then
      writeln(ErrOutput, 'PBW fenwick ctx=', IntToHex(CtxIdx,3), ' old=', predbyte,
        ' new=', Sym and $FF, ' wpos=', M.WinPos);
    M.PredByte[CtxIdx] := Sym and $FF;
    M.ClsIdx[CtxIdx] := 0;
    sub_amt := combo;
  end;
  M.Budget[CtxIdx] := (M.Budget[CtxIdx] - sub_amt) and M32;

  if persym0 <> 0 then
  begin
    ef := M.EntWt[CtxIdx];
    weight := (M.Order0Wt[CtxIdx] * ef) and M32;
    rowtot := M.Cum[CtxIdx][0];
    if rowtot <= weight then ApplyFenwick(M, Sym, CtxIdx);
    M.Order0Wt[CtxIdx] := M.Order0Wt[CtxIdx] shr 4;
  end
  else
  begin
    ApplyFenwick(M, Sym, CtxIdx);
    M.EntWt[CtxIdx] := (M.EntWt[CtxIdx] + si) and M16;
    M.Order0Wt[CtxIdx] := (M.Order0Wt[CtxIdx] + M.ByteClass) and M32;
  end;

  M.Freq[CtxIdx][Sym] := (M.Freq[CtxIdx][Sym] + si) and M16;
  al := (Sym + 1) and $FF;
  while al <> 0 do
  begin
    M.Cum[CtxIdx][al] := (M.Cum[CtxIdx][al] + si) and M16;
    al := (al + LowBit(al)) and $FF;
  end;
  rowtot := (M.Cum[CtxIdx][0] + si) and M16;
  M.Cum[CtxIdx][0] := rowtot;

  ef := M.EntWt[CtxIdx];
  budgetSigned := Integer(M.Budget[CtxIdx]);
  if ((ef + rowtot) >= $4000) or (budgetSigned < 0) then
    T268_Rescale(M, CtxIdx);
end;

procedure ApplyLiteralUpdates(var M: TPpmModel; EntryCtx, NextCtx, Sym: Integer);
var flag: Integer;
begin
  if NextCtx = $301 then flag := 1 else flag := 0;
  M.WorkCtx := NextCtx;
  ApplyT268(M, Sym, EntryCtx);
  M.WorkCtx := $302 + flag;
  ApplyFenwick(M, Sym, $200);
end;

initialization
  FenwickWatch := StrToIntDef(GetEnvironmentVariable('PPM_FWWATCH'), -1);
  T268Ctx := StrToIntDef(GetEnvironmentVariable('PPM_T268CTX'), -1);
  PbWatch := GetEnvironmentVariable('PPM_PBWATCH') <> '';
  PbWatchCtx := StrToIntDef(GetEnvironmentVariable('PPM_PBWATCH'), -1);
  T268Win := GetEnvironmentVariable('PPM_T268WIN') <> '';
  if T268Win then
  begin
    T268Lo := StrToIntDef(Copy(GetEnvironmentVariable('PPM_T268WIN'), 1,
                Pos(':', GetEnvironmentVariable('PPM_T268WIN')) - 1), 0);
    T268Hi := StrToIntDef(Copy(GetEnvironmentVariable('PPM_T268WIN'),
                Pos(':', GetEnvironmentVariable('PPM_T268WIN')) + 1, 20), 0);
  end;

end.
