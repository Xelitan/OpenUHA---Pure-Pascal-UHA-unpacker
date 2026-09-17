unit uha_ppm_d390;

{$mode delphi}{$H+}{$Q-}{$R-}

interface

uses uha_ppm_kernel;

type
  TD390Result = record
    AccAdd : Cardinal;
    SseIdx : Integer;
    SseVal : Cardinal;
    Excl   : Integer;
  end;

function D390_Update(var M: TPpmModel; Ctx, Sym: Integer): TD390Result;

implementation

uses SysUtils;

var D390Dbg: Boolean; D390Lo: Integer = 15271; D390Hi: Integer = 15277;

function F154w(const M: TPpmModel; key: Cardinal): Cardinal; inline;
begin Result := M.F154[(key * 2) and $FFFFFFFF] and $FFFF; end;

function F154i2(const M: TPpmModel; key: Cardinal): Cardinal; inline;
begin

  if key > $3FFF then key := $3FFF;
  Result := M.F154[key] and $FFFF;
end;

function InExclL(const Excl: array of Byte; N: Integer; sym: Byte): Boolean;
var i: Integer;
begin
  for i := 0 to N - 1 do if Excl[i] = sym then Exit(True);
  Result := False;
end;

function RemAfterExcl(const M: TPpmModel; CtxId: Integer;
  const Excl: array of Byte; N: Integer): Cardinal;
var i: Integer;
begin
  Result := M.Cum[CtxId][0];
  for i := 0 to N - 1 do
    Result := (Result - M.Freq[CtxId][Excl[i]]) and $FFFF;
end;

function TotalFromRem(const M: TPpmModel; CtxId: Integer; Rem: Cardinal): Cardinal;
var c, idx, sse2, t: Cardinal;
begin
  if CtxId >= $301 then Exit(Rem and $FFFFFFFF);
  c := M.EntWt[CtxId];
  if (CtxId >= $200) or (Rem >= $2000) then Exit((Rem + c) and $FFFFFFFF);
  if ((Rem + c) and $FFFFFFFF) = 0 then Exit(Rem and $FFFFFFFF);
  idx  := ((c shl 5) div ((Rem + c) and $FFFFFFFF)) and $FFFFFFFF;
  if (idx > $1F) and (GetEnvironmentVariable('PPM_IDXDBG') <> '') then
    writeln(ErrOutput, 'IDXOOR ctx=', IntToHex(CtxId,3), ' Rem=', Rem, ' c=', c, ' idx=', idx);
  if idx > $1F then idx := $1F;
  sse2 := M.Sse2[idx];
  if sse2 = 0 then Exit(Rem and $FFFFFFFF);
  t := ((Rem shl 13) div sse2) + 1;
  if t >= $4000 then t := $3FFF;
  Result := t;
end;

function PresentContribution(const M: TPpmModel; CtxId, Sym: Integer;
  const Excl: array of Byte; N: Integer): Cardinal;
var rem, total, freq: Cardinal;
begin
  rem := RemAfterExcl(M, CtxId, Excl, N);
  total := TotalFromRem(M, CtxId, rem);
  if total = 0 then Exit(0);
  freq := M.Freq[CtxId][Sym];
  Result := F154i2(M, (freq shl 14) div total);
end;

function NovelWorkctxContribution(const M: TPpmModel; Ctx, WorkCtx, Sym: Integer;
  const Excl: array of Byte; N: Integer): Cardinal;
var b: Integer; rem, total, freq: Cardinal;
  function Ineligible(bb: Integer): Boolean; inline;
  begin Result := (M.Freq[Ctx][bb] <> 0) or InExclL(Excl, N, bb); end;
begin
  rem := M.Cum[WorkCtx][0];
  for b := 0 to 255 do
    if Ineligible(b) then rem := (rem - M.Freq[WorkCtx][b]) and $FFFF;
  total := TotalFromRem(M, WorkCtx, rem);
  if total = 0 then Exit(0);
  freq := M.Freq[WorkCtx][Sym];
  Result := F154i2(M, (freq shl 14) div total);
end;

function SseIndex(const M: TPpmModel; Ctx, pb: Integer; FreqPred, Rem: Cardinal): Cardinal;
var w, c, sse: Cardinal;
begin
  w := M.WTab[M.ClsIdx[Ctx]];
  c := M.EntWt[Ctx];
  sse := (((w + FreqPred) and $FFFFFFFF) shl 4) div ((w + c + Rem) and $FFFFFFFF);
  if      FreqPred > $600 then
  else if FreqPred > $100 then sse := sse or $30
  else if FreqPred > $40  then sse := sse or $20
  else                         sse := sse or $10;
  if (Ctx and $C0) = $C0 then sse := sse or $40;
  if (pb and $C0) = $C0 then
  begin if pb = $FF then sse := sse or $100 else sse := sse or $80; end;
  if M.ByteClass <> 0 then
  begin if ((M.WinPos - M.Recency[pb]) and $FFFFFFFF) <= $40 then sse := sse or $200; end
  else
    if M.Novel[pb] <> 0 then sse := sse or $200;
  if M.LastCtx = M.LastSym[pb] then sse := sse or $400;
  Result := sse;
end;

function D390_Update(var M: TPpmModel; Ctx, Sym: Integer): TD390Result;
var
  e268, wt, tot, freqPred, rem, total: Cardinal;
  idx, old: Cardinal;
  noMps: Boolean;
  pb, i, n: Integer;
  excl: array[0..MAX_EXCL-1] of Byte;
begin
  Result.AccAdd := 0; Result.SseIdx := -1; Result.SseVal := 0; Result.Excl := -1;
  n := M.NExcl;
  for i := 0 to n - 1 do excl[i] := M.Excl[i];
  e268 := M.EntWt[Ctx];
  wt   := (e268 * M.Order0Wt[Ctx]) and $FFFFFFFF;
  tot  := M.Cum[Ctx][0];
  if tot <= wt then
  begin
    Result.AccAdd := PresentContribution(M, M.WorkCtx, Sym, excl, n);
    if D390Dbg and (Integer(M.WinPos) >= D390Lo) and (Integer(M.WinPos) <= D390Hi) then
      writeln(ErrOutput, 'D390 wpos=', M.WinPos, ' ctx=', IntToHex(Ctx,3), ' sym=', Sym,
        ' wc=', IntToHex(M.WorkCtx,3), ' HIGHCOUNT tot=', tot, ' wt=', wt,
        ' -> AccAdd=', Result.AccAdd);
    Exit;
  end;

  noMps := Ctx >= (Cardinal($200) shr M.ByteClass);
  pb := M.PredByte[Ctx];
  if (not noMps) and InExclL(excl, n, pb) then noMps := True;
  if not noMps then
  begin
    freqPred := M.Freq[Ctx][pb];
    rem := RemAfterExcl(M, Ctx, excl, n);
    idx := SseIndex(M, Ctx, pb, freqPred, rem);
    old := M.SseProb[idx];
    if pb = Sym then
    begin
      Result.AccAdd := F154w(M, old);
      if D390Dbg and (Integer(M.WinPos) >= D390Lo) and (Integer(M.WinPos) <= D390Hi) then
        writeln(ErrOutput, 'D390 wpos=', M.WinPos, ' ctx=', IntToHex(Ctx,3), ' sym=', Sym,
          ' wc=', IntToHex(M.WorkCtx,3), ' MPSHIT pb=', pb, ' sseidx=', idx, ' old=', old,
          ' -> AccAdd=', Result.AccAdd);
      Result.SseIdx := idx; Result.SseVal := (old + (($2000 - old) shr 6)) and $FFFFFFFF;
      Exit;
    end;

    Result.AccAdd := F154w(M, ($2000 - old) and $FFFFFFFF);
    Result.SseIdx := idx; Result.SseVal := (old - (old shr 6)) and $FFFFFFFF;
    excl[n] := pb; Inc(n);
  end;

  if M.Freq[Ctx][Sym] <> 0 then
  begin
    if D390Dbg and (Integer(M.WinPos) >= D390Lo) and (Integer(M.WinPos) <= D390Hi) then
      writeln(ErrOutput, 'D390 wpos=', M.WinPos, ' ctx=', IntToHex(Ctx,3), ' sym=', Sym,
        ' wc=', IntToHex(M.WorkCtx,3), ' PRESENT freq=', M.Freq[Ctx][Sym],
        ' rem=', RemAfterExcl(M, Ctx, excl, n),
        ' total=', TotalFromRem(M, Ctx, RemAfterExcl(M, Ctx, excl, n)),
        ' contrib=', PresentContribution(M, Ctx, Sym, excl, n),
        ' preAcc=', Result.AccAdd, ' nexcl=', n, ' pb=', pb, ' noMps=', noMps);
    Result.AccAdd := (Result.AccAdd + PresentContribution(M, Ctx, Sym, excl, n)) and $FFFFFFFF;
    Exit;
  end;

  rem := RemAfterExcl(M, Ctx, excl, n);
  if rem <> 0 then
  begin
    total := TotalFromRem(M, Ctx, rem);
    if D390Dbg and (Integer(M.WinPos) >= D390Lo) and (Integer(M.WinPos) <= D390Hi) then
      writeln(ErrOutput, 'D390 wpos=', M.WinPos, ' ctx=', IntToHex(Ctx,3), ' sym=', Sym,
        ' wc=', IntToHex(M.WorkCtx,3), ' rem=', rem, ' total=', total,
        ' key=', ((total - rem) shl 14) div total,
        ' escW=', F154i2(M, ((total - rem) shl 14) div total),
        ' preAcc=', Result.AccAdd, ' nexcl=', n,
        ' | Cum=', M.Cum[Ctx][0], ' EntWt=', M.EntWt[Ctx], ' Order0Wt=', M.Order0Wt[Ctx],
        ' wt=', (Cardinal(M.EntWt[Ctx]) * M.Order0Wt[Ctx]));
    Result.AccAdd := (Result.AccAdd + F154i2(M, ((total - rem) shl 14) div total)) and $FFFFFFFF;
  end
  else if D390Dbg and (Integer(M.WinPos) >= D390Lo) and (Integer(M.WinPos) <= D390Hi) then
    writeln(ErrOutput, 'D390 wpos=', M.WinPos, ' ctx=', IntToHex(Ctx,3), ' sym=', Sym,
      ' rem=0 preAcc=', Result.AccAdd, ' nexcl=', n);
  total := NovelWorkctxContribution(M, Ctx, M.WorkCtx, Sym, excl, n);
  if D390Dbg and (Integer(M.WinPos) >= D390Lo) and (Integer(M.WinPos) <= D390Hi) then
    writeln(ErrOutput, '     novelWc=', total, ' -> AccAdd=', Result.AccAdd + total);
  Result.AccAdd := (Result.AccAdd + total) and $FFFFFFFF;
end;

initialization
  D390Dbg := GetEnvironmentVariable('PPM_D390DBG') <> '';
  if D390Dbg and (Pos(':', GetEnvironmentVariable('PPM_D390DBG')) > 0) then
  begin
    D390Lo := StrToIntDef(Copy(GetEnvironmentVariable('PPM_D390DBG'), 1,
                Pos(':', GetEnvironmentVariable('PPM_D390DBG')) - 1), 0);
    D390Hi := StrToIntDef(Copy(GetEnvironmentVariable('PPM_D390DBG'),
                Pos(':', GetEnvironmentVariable('PPM_D390DBG')) + 1, 20), MaxInt);
  end;

end.
