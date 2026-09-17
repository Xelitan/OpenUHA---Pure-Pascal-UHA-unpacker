unit uha_ppm_rw1;

{$mode delphi}{$H+}{$Q-}{$R-}

interface

uses uha_ppm_textbook, uha_ppm_kernel, uha_ppm_statics;

function Order1Reweight_Decode(var M: TPpmModel; var R: TRangeDecoder;
  Rec1Idx, Rec2Idx: Cardinal; Ctx28: Integer; out Sym: Integer): Boolean;

implementation

uses SysUtils;

var WatchRec1: Integer;

const
  M32 = $FFFFFFFF;
  TAB_A = 1; TAB_B = 2; TAB_C = 3; TAB_E = 4;

type
  TAdaptEntry = record
    Tab : Integer;
    Idx : Cardinal;
    Slot: Integer;
  end;

procedure AppendExcl(var M: TPpmModel; SymB: Byte);
begin
  M.Excl[M.NExcl] := SymB;
  Inc(M.NExcl);
end;

function EscmassIndex(const M: TPpmModel; Rec0: Byte; Edx, Roll: Cardinal;
  B7, Ge6: Boolean; out Idx: Cardinal): Boolean;
var ctxbits: Cardinal;
begin
  Result := False;
  if Edx >= $80 then Exit;
  if M.ByteClass <> 0 then
  begin
    ctxbits := (Roll and $C0) shr 5;
    if (Roll and $E0) = ((Roll shr 8) and $E0) then Inc(ctxbits);
  end
  else
  begin
    ctxbits := Ord((Roll and $FF) = $DF)
             + Cardinal(M.Novel[Roll and $FF]) * 4
             + Cardinal(M.Novel[(Roll shr 8) and $FF]) * 2;
  end;
  ctxbits := ctxbits + (Cardinal(Ord(B7)) shl 3) + (Cardinal(Ord(Ge6)) shl 4);
  Idx := PPMS_43A590[Rec0] * $100 + PPMS_43A590[Edx and $FF] * $20 + ctxbits;
  Result := True;
end;

function NewcStd(Prob, Mult, Count: Cardinal; out Nc: Cardinal): Boolean;
begin
  Nc := (Prob * Mult) div ($2000 - Prob) + 1;
  if Nc <= Count then Exit(False);
  if Nc >= $100 then Nc := $FF;
  Result := True;
end;

function Order1Reweight_Decode(var M: TPpmModel; var R: TRangeDecoder;
  Rec1Idx, Rec2Idx: Cardinal; Ctx28: Integer; out Sym: Integer): Boolean;
var
  recb, recw: array[0..$1F] of Byte;
  flags: array[0..$B] of Byte;
  adapt: array[0..7] of TAdaptEntry;
  nAdapt: Integer;
  roll, c3c, total, edx: Cardinal;
  b7, ge6, escaped: Boolean;
  rec2marker, pb, d0: Byte;
  sl, ps, ds, s, slot, dslot: Integer;
  mainsym: Byte;
  base, wA, wB, b38: Cardinal;
  count, mult, ecx, q, idx, flg, nc: Cardinal;
  emIdx, runit, freq, cum, nxt, lowc, highc: Cardinal;
  cnt: Cardinal;
  hit: Boolean;
  prob: Cardinal;
  i: Integer;

  function SlotFor(SymB: Byte): Integer;
  var k: Integer;
  begin
    for k := 0 to $B do
    begin
      if (k > 0) and (recb[k + 1] = 0) then Break;
      if recb[$D + k] = SymB then Exit(k);
    end;
    Result := $C;
  end;

  procedure AdaptByEntry(const E: TAdaptEntry; Up: Boolean);
  var p: Cardinal;
  begin
    case E.Tab of
      TAB_A: p := M.RwA[E.Idx];
      TAB_B: p := M.RwB[E.Idx];
      TAB_C: p := M.RwC[E.Idx];
    else     p := M.RwE[E.Idx];
    end;
    if Up then
      p := (p + (($2000 - p) shr 6)) and M32
    else
      p := (p - (p shr 6)) and M32;
    case E.Tab of
      TAB_A: M.RwA[E.Idx] := p;
      TAB_B: M.RwB[E.Idx] := p;
      TAB_C: M.RwC[E.Idx] := p;
    else     M.RwE[E.Idx] := p;
    end;
  end;

begin
  Result := False; Sym := -1;
  roll := M.C48;
  for i := 0 to $1F do recb[i] := M.Rec1s[Rec1Idx][i];

  rec2marker := M.Rec2s[Rec2Idx][$13];
  pb := M.PredByte[Ctx28];
  d0 := M.Rec2s[Rec2Idx][(rec2marker and $F) + 9];
  sl := recb[$1A] and $F;
  if M.DCG <= M.A8G then sl := $C;
  ps := SlotFor(pb);
  ds := SlotFor(d0);
  if sl < $C then mainsym := recb[$D + sl] else mainsym := 0;

  for s := 0 to $B do flags[s] := 1;
  c3c := M.C1C;
  if M.NExcl <> 0 then
    for s := 0 to $B do
    begin
      if (s > 0) and (recb[s + 1] = 0) then Break;
      if recb[$D + s] = M.Excl[0] then
      begin
        flags[s] := 0;
        c3c := (c3c - recb[s + 1]) and M32;
        Break;
      end;
    end;

  edx := (c3c - recb[0]) and M32;
  b7 := M.Rec2s[Rec2Idx][7] <> 0;
  ge6 := M.C54 >= 6;

  if EscmassIndex(M, recb[0], edx, roll, b7, ge6, emIdx) then
    total := ((edx shl $D) div M.EscMass[emIdx]) + 1
  else
    total := c3c and M32;

  base := PPMS_43E0F0[recb[$1A] shr 4];
  wA := PPMS_43E0B0[rec2marker shr 4];
  wB := PPMS_43E070[M.ClsIdx[Ctx28]];
  if (roll and $C0) = $C0 then b38 := $10 else b38 := 0;

  M.C3C := c3c;

  for i := 0 to $1F do recw[i] := recb[i];
  nAdapt := 0;

  if (sl < $C) and (flags[sl] <> 0) then
  begin
    count := recw[sl + 1]; mult := (c3c - count) and M32;
    ecx := base + (count - Cardinal(Ord(count = 2))) + (recw[$1B] shr 4);
    flg := 0;
    if mainsym = d0 then begin ecx := ecx + wA; flg := $40; end;
    if mainsym = pb then begin ecx := ecx + wB; flg := flg or $80; end;
    if (mult + ecx) <> 0 then q := (ecx shl 4) div (mult + ecx) else q := 0;
    idx := q;
    if sl <> 0 then idx := idx or $100;
    if (mainsym and $C0) = $C0 then idx := idx or $20;
    if M.WinPos <= M.T46A[mainsym] then idx := idx or $200;
    if M.LastCtx = M.LastSym[mainsym] then idx := idx or $400;
    idx := idx or flg or b38;
    adapt[nAdapt].Tab := TAB_A; adapt[nAdapt].Idx := idx;
    adapt[nAdapt].Slot := sl; Inc(nAdapt);
    if NewcStd(M.RwA[idx], mult, count, nc) then
    begin total := (total + nc - count) and M32; recw[sl + 1] := nc; end;
  end;

  if (ps < $C) and (flags[ps] <> 0) and (sl <> ps) then
  begin
    count := recw[ps + 1]; mult := (c3c - count) and M32; ecx := count + wB;
    if (mult + ecx) <> 0 then q := (ecx shl 4) div (mult + ecx) else q := 0;
    idx := q;
    if (pb and $C0) = $C0 then idx := idx or $20;
    if pb = d0 then idx := idx or $40;
    if M.WinPos <= M.T46A[pb] then idx := idx or $80;
    if M.LastCtx = M.LastSym[pb] then idx := idx or $100;
    idx := idx or b38;
    adapt[nAdapt].Tab := TAB_B; adapt[nAdapt].Idx := idx;
    adapt[nAdapt].Slot := ps; Inc(nAdapt);
    if NewcStd(M.RwB[idx], mult, count, nc) then
    begin total := (total + nc - count) and M32; recw[ps + 1] := nc; end;
  end;

  if (ds < $C) and (flags[ds] <> 0) and (sl <> ds) and (ds <> ps) then
  begin
    count := recw[ds + 1]; mult := (c3c - count) and M32; ecx := count + wA;
    if (mult + ecx) <> 0 then q := (ecx shl 4) div (mult + ecx) else q := 0;
    idx := q;
    if (d0 and $C0) = $C0 then idx := idx or $20;
    if M.WinPos <= M.T46A[d0] then idx := idx or $40;
    if M.LastCtx = M.LastSym[d0] then idx := idx or $80;
    idx := idx or b38;
    adapt[nAdapt].Tab := TAB_C; adapt[nAdapt].Idx := idx;
    adapt[nAdapt].Slot := ds; Inc(nAdapt);
    if NewcStd(M.RwC[idx], mult, count, nc) then
    begin total := (total + nc - count) and M32; recw[ds + 1] := nc; end;
  end;

  if (sl <> 0) and (ps <> 0) and (ds <> 0) and (flags[0] <> 0) and (recw[1] <> 0) then
  begin
    count := recw[1];
    if c3c <> 0 then q := (count shl 4) div c3c else q := 0;
    idx := q;
    if (recw[$D] and $C0) = $C0 then idx := idx or $20;
    if M.WinPos <= M.T46A[recw[$D]] then idx := idx or $80;
    if M.LastCtx = M.LastSym[recw[$D]] then idx := idx or $100;
    idx := idx or b38;
    adapt[nAdapt].Tab := TAB_E; adapt[nAdapt].Idx := idx;
    adapt[nAdapt].Slot := 0; Inc(nAdapt);
    nc := ((c3c * M.RwE[idx]) shr $D) + 1;
    if nc >= $100 then nc := $FF;
    total := (total + nc - count) and M32;
    recw[1] := nc;
  end;

  M.C20 := total and M32;
  if WatchRec1 = Integer(Rec1Idx) then
  begin
    Write(ErrOutput, 'RW1 rec=', Rec1Idx, ' code=', IntToHex(R.Code, 8),
      ' c3c=', c3c, ' total=', total, ' sl=', sl, ' ps=', ps, ' ds=', ds,
      ' c54=', M.C54, ' wA=', wA, ' wB=', wB, ' base=', base);
    if edx < $80 then Write(ErrOutput, ' emIdx=', emIdx, ' emProb=', M.EscMass[emIdx]);
    Write(ErrOutput, ' recw=');
    for i := 0 to $1F do Write(ErrOutput, IntToHex(recw[i], 2));
    for i := 0 to nAdapt - 1 do
      Write(ErrOutput, ' adapt=', adapt[i].Tab, '/', adapt[i].Idx, '/', adapt[i].Slot);
    Writeln(ErrOutput);
  end;

  escaped := True; slot := -1; dslot := -1; lowc := M32; highc := 0;
  if (total <> 0) then
  begin
    runit := R.Range div total;
    if runit <> 0 then
    begin
      freq := (R.Code div runit) and $FFFF;
      cum := 0;
      escaped := False;
      lowc := M32;
      for s := 0 to $B do
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
          Sym := recw[$D + s]; dslot := s; slot := s;
          lowc := cum; highc := nxt;
          Break;
        end;
        AppendExcl(M, recw[$D + s]);
        cum := nxt;
      end;
      if lowc = M32 then
      begin
        escaped := True; lowc := cum; highc := total;
      end;

      if escaped then M.S47 := $0C
      else M.S47 := dslot and $FF;
      M.C24 := lowc and M32;
      M.C28 := highc and M32;

      R.Code := (R.Code - lowc * runit) and M32;
      R.Range := ((highc - lowc) * runit) and M32;
      RD_Renorm(R);
      Result := not escaped;
    end;
  end;

  for i := 0 to nAdapt - 1 do
  begin
    hit := (not escaped) and (adapt[i].Slot = dslot) and (dslot >= 0);
    AdaptByEntry(adapt[i], hit);
  end;
  if EscmassIndex(M, recb[0], edx, roll, b7, ge6, emIdx) then
  begin
    prob := M.EscMass[emIdx];
    if escaped then
      prob := (prob - (prob shr 6)) and M32
    else
      prob := (prob + (($2000 - prob) shr 6)) and M32;
    M.EscMass[emIdx] := prob;
  end;
  if slot >= 0 then ;
end;

initialization
  WatchRec1 := StrToIntDef(GetEnvironmentVariable('PPM_RW1WATCH'), -1);

end.
