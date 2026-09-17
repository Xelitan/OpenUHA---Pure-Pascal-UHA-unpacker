unit uha_ppm_rw2;

{$mode delphi}{$H+}{$Q-}{$R-}

interface

uses uha_ppm_textbook, uha_ppm_kernel, uha_ppm_statics, uha_ppm_bc1sub;

type
  TRec2Flags = array[0..7] of Byte;

procedure Rec2TotalAndFlags(var M: TPpmModel; Rec2Idx: Cardinal;
  out Rec: TRec2Rec; out ActiveCount: Integer; out Flags: TRec2Flags;
  out Total: Cardinal);

function Rec2Reweight_Decode(var M: TPpmModel; var R: TRangeDecoder;
  Rec2Idx: Cardinal; SelHint: Integer; out Sym: Integer): Boolean;

implementation

uses SysUtils;

var NativeTotal: Boolean;
var BlkA40: Boolean;

const
  M32 = $FFFFFFFF;
  TAB_A = 1; TAB_B = 2; TAB_E = 3; TAB_ESC = 4;

type
  TAdaptEntry = record
    Tab : Integer;
    Idx : Cardinal;
    Slot: Integer;
  end;

procedure Rec2TotalAndFlags(var M: TPpmModel; Rec2Idx: Cardinal;
  out Rec: TRec2Rec; out ActiveCount: Integer; out Flags: TRec2Flags;
  out Total: Cardinal);
var
  slot, i: Integer;
  xs: Byte;
begin
  Rec := M.Rec2s[Rec2Idx];

  if NativeTotal then Total := Rec[$12] else Total := Rec[0];
  ActiveCount := 0;
  for slot := 0 to 7 do
  begin
    if (slot > 0) and (Rec[slot + 1] = 0) then Break;
    Inc(ActiveCount);
    if not NativeTotal then Total := (Total + Rec[slot + 1]) and M32;
  end;
  for slot := 0 to 7 do Flags[slot] := 1;
  for i := 0 to M.NExcl - 1 do
  begin
    xs := M.Excl[i];
    for slot := 0 to ActiveCount - 1 do
      if (Flags[slot] <> 0) and (Rec[9 + slot] = xs) then
      begin
        Flags[slot] := 0;
        Total := (Total - Rec[slot + 1]) and M32;
        Break;
      end;
  end;
end;

procedure AppendExcl(var M: TPpmModel; SymB: Byte);
begin
  M.Excl[M.NExcl] := SymB;
  Inc(M.NExcl);
end;

function Rec2Context(const M: TPpmModel): Integer;
begin
  Result := M.C48 and $FF;
  if (M.ByteClass = 0) and (M.Novel[(M.C48 shr 8) and $FF] <> 0) then
    Inc(Result, $100);
end;

function NewcStd(Prob, Mult, Count: Cardinal; out Nc: Cardinal): Boolean;
var den: Cardinal;
begin
  den := ($2000 - Prob) and M32;
  if (den = 0) or (den > $2000) then
  begin
    Nc := $FF;
    Exit(True);
  end;
  Nc := (Prob * Mult) div den + 1;
  if Nc <= Count then Exit(False);
  if Nc >= $100 then Nc := $FF;
  Result := True;
end;

function Rec2Reweight_Decode(var M: TPpmModel; var R: TRangeDecoder;
  Rec2Idx: Cardinal; SelHint: Integer; out Sym: Integer): Boolean;
var
  rec: TRec2Rec;
  recw: array[0..$13] of Byte;
  flags: TRec2Flags;
  adapt: array[0..3] of TAdaptEntry;
  nAdapt, activeCount: Integer;
  baseTotal, total, diff, idx, p, nc: Cardinal;
  a0, sel, s, slot: Integer;
  ctx: Integer;
  w30, w34, b38, count, mult, ecx, q: Cardinal;
  localB8, localD0, symB: Byte;
  runit, freq, cum, nxt, lowc, highc, cnt: Cardinal;
  escaped, hit: Boolean;
  i: Integer;

  procedure AdaptByEntry(const E: TAdaptEntry; Up: Boolean);
  var v: Cardinal;
  begin
    case E.Tab of
      TAB_A:   v := M.R2A[E.Idx];
      TAB_B:   v := M.R2B[E.Idx];
      TAB_E:   v := M.R2E[E.Idx];
    else       v := M.R2Esc[E.Idx];
    end;
    if Up then
      v := (v + (($2000 - v) shr 6)) and M32
    else
      v := (v - (v shr 6)) and M32;
    case E.Tab of
      TAB_A:   M.R2A[E.Idx] := v;
      TAB_B:   M.R2B[E.Idx] := v;
      TAB_E:   M.R2E[E.Idx] := v;
    else       M.R2Esc[E.Idx] := v;
    end;
  end;

begin
  Result := False; Sym := -1;
  Rec2TotalAndFlags(M, Rec2Idx, rec, activeCount, flags, baseTotal);
  M.C4C := baseTotal;
  if activeCount = 0 then Exit;

  if M.A8G >= M.DCG then a0 := 8 else a0 := rec[$13] and $0F;
  for i := 0 to $13 do recw[i] := rec[i];
  total := baseTotal;
  nAdapt := 0;

  ctx := Rec2Context(M);
  localB8 := M.PredByte[ctx];
  if (M.C48 and $C0) = $C0 then b38 := $10 else b38 := 0;
  w30 := PPMS_43E0B0[rec[$13] shr 4];
  w34 := PPMS_43E070[M.ClsIdx[ctx]];

  diff := (baseTotal - rec[0]) and M32;
  if (activeCount < 8) and (diff < $10) then
  begin
    idx := PPMS_43A570[activeCount] + (diff and $0C) + Cardinal(Ord(rec[$12] = baseTotal));
    p := M.R2Esc[idx];
    if RdTrace then
      writeln(ErrOutput, '  escm idx=', idx, ' R2Esc=', p, ' diff=', diff,
        ' active=', activeCount, ' rec0=', rec[0], ' rec12=', rec[$12],
        ' baseTotal=', baseTotal);
    if p <> 0 then
    begin
      adapt[nAdapt].Tab := TAB_ESC; adapt[nAdapt].Idx := idx;
      adapt[nAdapt].Slot := 8; Inc(nAdapt);
      total := (((diff shl 13) div p) + 1 + (rec[0] div 2)) and M32;
    end;
  end;

  if (a0 < 8) and (flags[a0] <> 0) and (recw[a0 + 1] <> 0) then
  begin
    count := recw[a0 + 1];
    symB := recw[a0 + 9];
    localD0 := symB;
    mult := (baseTotal - count) and M32;
    ecx := count + w30;
    q := 0;
    if localD0 = localB8 then
    begin
      ecx := ecx + w34;
      q := $80;
    end;
    idx := q;
    q := ecx shl 4;
    if (mult + ecx) <> 0 then q := q div (mult + ecx) else q := 0;
    idx := idx or q;
    if a0 <> 0 then idx := idx or $100;
    if (symB and $C0) = $C0 then idx := idx or $20;

    if BlkA40 and Bc1RecOk and (symB = Bc1.BestPred) then idx := idx or $40;
    if M.WinPos <= M.T46A[symB] then idx := idx or $200;
    if M.LastCtx = M.LastSym[symB] then idx := idx or $400;
    idx := idx or b38;
    adapt[nAdapt].Tab := TAB_A; adapt[nAdapt].Idx := idx;
    adapt[nAdapt].Slot := a0; Inc(nAdapt);
    if (M.ByteClass <> 0) and (baseTotal = 42) and (a0 = 0) and (count = 11)
       and (GetEnvironmentVariable('PPM_TADBG') <> '') then
    begin
      NewcStd(M.R2A[idx], mult, count, nc);
      writeln(ErrOutput, 'TA-A slot0: idx=', idx, ' R2A[idx]=', M.R2A[idx],
        ' mult=', mult, ' count=', count, ' w30=', w30, ' w34=', w34,
        ' symB=', symB, ' localB8=', localB8, ' b38=', b38, ' nc=', nc,
        ' WinPos=', M.WinPos, ' T46A[symB]=', M.T46A[symB],
        ' bit200=', M.WinPos <= M.T46A[symB]);
    end;
    if NewcStd(M.R2A[idx], mult, count, nc) then
    begin
      total := (total + nc - count) and M32; recw[a0 + 1] := nc;
      if RdTrace then writeln(ErrOutput, '  blkA slot=', a0, ' idx=', idx,
        ' R2A=', M.R2A[idx], ' count=', count, ' nc=', nc, ' total=', total,
        ' symB=', symB, ' localB8=', localB8, ' ctx=', IntToHex(ctx,3),
        ' w30=', w30, ' w34=', w34, ' b38=', b38, ' mult=', mult);
    end;
  end;

  sel := SelHint;

  if (sel < 8) and (flags[sel] <> 0) and (sel <> a0) and (recw[sel + 1] <> 0) then
  begin
    count := recw[sel + 1];
    symB := recw[sel + 9];
    mult := (baseTotal - count) and M32;
    ecx := count + w34;
    if (mult + ecx) <> 0 then q := (ecx shl 4) div (mult + ecx) else q := 0;
    idx := q;
    if (symB and $C0) = $C0 then idx := idx or $20;
    if M.WinPos <= M.T46A[symB] then idx := idx or $40;
    if M.LastCtx = M.LastSym[symB] then idx := idx or $80;
    idx := idx or b38;
    adapt[nAdapt].Tab := TAB_B; adapt[nAdapt].Idx := idx;
    adapt[nAdapt].Slot := sel; Inc(nAdapt);
    if NewcStd(M.R2B[idx], mult, count, nc) then
    begin
      total := (total + nc - count) and M32; recw[sel + 1] := nc;
      if RdTrace then writeln(ErrOutput, '  blkB slot=', sel, ' idx=', idx,
        ' R2B=', M.R2B[idx], ' count=', count, ' nc=', nc, ' total=', total);
    end;
  end;

  if (flags[0] <> 0) and (a0 <> 0) and (sel <> 0) and (recw[1] <> 0) then
  begin
    count := recw[1];
    symB := recw[9];
    if baseTotal <> 0 then q := (count shl 4) div baseTotal else q := 0;
    idx := q;
    if (symB and $C0) = $C0 then idx := idx or $20;
    if Bc1RecOk and (symB = Bc1.BestPred) then idx := idx or $40;
    if M.WinPos <= M.T46A[symB] then idx := idx or $80;
    if M.LastCtx = M.LastSym[symB] then idx := idx or $100;
    idx := idx or b38;
    adapt[nAdapt].Tab := TAB_E; adapt[nAdapt].Idx := idx;
    adapt[nAdapt].Slot := 0; Inc(nAdapt);
    nc := ((baseTotal * M.R2E[idx]) shr 13) + 1;
    if nc >= $100 then nc := $FF;
    total := (total + nc - count) and M32;
    if RdTrace then writeln(ErrOutput, '  blkE slot=0 idx=', idx,
      ' count=', count, ' nc=', nc, ' total=', total);
    recw[1] := nc;
  end;

  escaped := True; slot := 8; lowc := M32; highc := 0;
  if (M.ByteClass <> 0) and (GetEnvironmentVariable('PPM_R2DBG') <> '') then
    writeln(ErrOutput, 'R2 a0=', a0, ' A8G=', M.A8G, ' DCG=', M.DCG, ' f13=', rec[$13],
      ' base=', baseTotal, ' total=', total, ' nexcl=', M.NExcl,
      ' rec0=', M.Rec2s[Rec2Idx][0], ' slots=', M.Rec2s[Rec2Idx][1], ',',
      M.Rec2s[Rec2Idx][2], ',', M.Rec2s[Rec2Idx][3], ',', M.Rec2s[Rec2Idx][4],
      ' code=', IntToHex(R.Code, 8));
  if total <> 0 then
  begin
    runit := R.Range div total;
    if runit <> 0 then
    begin
      freq := (R.Code div runit) and $FFFF;
      cum := 0;
      escaped := False;
      lowc := M32;
      for s := 0 to 7 do
      begin
        if flags[s] = 0 then Continue;
        cnt := recw[s + 1];
        if cnt = 0 then
        begin
          escaped := True; lowc := cum; highc := total;
          Break;
        end;
        nxt := cum + cnt;
        if freq < nxt then
        begin
          slot := s; Sym := recw[s + 9];
          lowc := cum; highc := nxt;
          Break;
        end;
        AppendExcl(M, recw[s + 9]);
        cum := nxt;
      end;
      if lowc = M32 then
      begin
        escaped := True; lowc := cum; highc := total;
      end;

      M.C20 := total;
      M.C24 := lowc and M32;
      M.C28 := highc and M32;
      if escaped then M.S49 := 8 else M.S49 := slot and $FF;

      R.Code := (R.Code - lowc * runit) and M32;
      R.Range := ((highc - lowc) * runit) and M32;
      RD_Renorm(R);
      if RdTrace then
        writeln(ErrOutput, '  rew total=', total, ' runit=', IntToHex(runit,8),
          ' lowc=', lowc, ' highc=', highc, ' code=', IntToHex(R.Code,8),
          ' rng=', IntToHex(R.Range,8));
      Result := not escaped;
    end;
  end;

  for i := 0 to nAdapt - 1 do
  begin
    if adapt[i].Slot = 8 then
      hit := Result
    else
      hit := Result and (adapt[i].Slot = slot) and (not escaped);
    AdaptByEntry(adapt[i], hit);
  end;
end;

initialization
  NativeTotal := GetEnvironmentVariable('X_R2TOTAL_OFF') = '';
  BlkA40 := GetEnvironmentVariable('X_BLKA40_OFF') = '';

end.
