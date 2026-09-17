unit uha_ppm_cascade;

{$mode delphi}{$H+}{$Q-}{$R-}

interface

uses uha_ppm_textbook, uha_ppm_kernel, uha_ppm_statics, uha_ppm_maint,
  uha_ppm_post, uha_ppm_predict, uha_ppm_rw1, uha_ppm_rw2, uha_ppm_c550,
  uha_ppm_bc1sub;

type
  TCascadeRoute = (crOrder1Hit, crPredictedHit, crRec2Hit, crEntryHit, crC550);

function DecodeLiteralCascade(var M: TPpmModel; var R: TRangeDecoder;
  Outp: PByte; var OutLen: Integer;
  out Route: TCascadeRoute; out Sym: Integer): Boolean;

implementation

uses SysUtils;

const M32 = $FFFFFFFF;

const PPMS_43B2CC: array[0..255] of Cardinal = (
  0,1,1,1,2,2,2,2,2,2,2,2,2,3,3,3,
  3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,
  4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,
  4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,
  4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,
  4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,
  4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,
  4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,
  4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,
  4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,
  4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,
  4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,
  4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,
  4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,
  4,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,
  5,5,5,5,6,6,6,6,6,6,6,6,6,7,7,7);

var BC1Dbg, C50Trace: Boolean;
var RTrace: Boolean; RTraceLim: Integer;
var RingSuppressWp: Boolean;
var RingAfterEntryMiss: Boolean;
var RingAfterRewMiss: Boolean;
var EarlyExcl: Boolean;
var EarlyCtx: Boolean;
var EarlyRank: Boolean;
var EarlyS41: Boolean;
var RingInCore: Boolean;
var RingWantedFlag, RingRecheckChain: Boolean;
var EarlyRec: Boolean;
var RingRec1: Boolean;
var RingS48: Boolean;
var RingFlags: Boolean;
var RingRec2S41: Boolean;
var RingEscHalve: Boolean;
var F393CExact: Boolean;
var C550WinCtx: Boolean;
var SkipRec2Flag: Boolean;
var StaleBest: Boolean;
var RingEscAppend: Boolean;
var PostCtx: Boolean;
var EarlyRecDone: Boolean; EarlyRecIdx: Cardinal; EarlyRecPred: Boolean;

var PredDbg: Boolean; PredLo: Integer = 0; PredHi: Integer = -1;
var RtdLo: Integer = 24666; RtdHi: Integer = 24674;
var KeepC4C: Boolean;

var LastWpFired, LastPathA: Boolean; LastKCtx, LastWorkCtx: Integer;
var WprDbg: Boolean;
var WpcDbg: Boolean;

var RingEligible: Boolean;
var RingTried: Boolean;
var RingRec1Weight: Cardinal;
var RingRec1Pred: Byte;
var PreRankBefore, PreRankAfter: Cardinal;

function Excluded(const M: TPpmModel; SymB: Byte): Boolean;
var i: Integer;
begin
  for i := 0 to M.NExcl - 1 do
    if M.Excl[i] = SymB then Exit(True);
  Result := False;
end;

procedure AppendExcl(var M: TPpmModel; SymB: Byte);
begin
  M.Excl[M.NExcl] := SymB;
  Inc(M.NExcl);
end;

function RecordTotal(const M: TPpmModel; RecIdx: Cardinal): Cardinal;
var k: Integer;
begin
  Result := M.Rec1s[RecIdx][0];
  k := 0;
  while (k < $C) and (M.Rec1s[RecIdx][1 + k] <> 0) do
  begin
    Result := (Result + M.Rec1s[RecIdx][1 + k]) and M32;
    Inc(k);
  end;
end;

function Rec0At(const M: TPpmModel; RecIdx: Cardinal): Byte;
begin

  if RecIdx >= REC1_COUNT then Exit(0);
  Result := M.Rec1s[RecIdx][0];
end;

function TagMatches(const M: TPpmModel; RecIdx, C48: Cardinal): Boolean;
var tag: Cardinal;
begin
  if RecIdx >= REC1_COUNT then Exit(False);
  tag := Cardinal(M.Rec1s[RecIdx][$1C]) or
         (Cardinal(M.Rec1s[RecIdx][$1D]) shl 8) or
         (Cardinal(M.Rec1s[RecIdx][$1E]) shl 16) or
         (Cardinal(M.Rec1s[RecIdx][$1F]) shl 24);
  Result := tag = C48;
end;

function SelectPredictedRecord(var M: TPpmModel; var RecIdx: Cardinal): Boolean;
var
  c48, c38: Cardinal;
begin
  c48 := M.C48;
  c38 := M.C38;
  if Rec0At(M, RecIdx) = 0 then
  begin
    if c38 < $40000 then
      M.C38 := (c38 + $40000) and M32;
    Exit(False);
  end;
  while (Rec0At(M, RecIdx) <> 0) and (not TagMatches(M, RecIdx, c48)) do
  begin
    c38 := (c38 + $8000) and M32;
    RecIdx := RecIdx + $8000;
    M.C38 := c38;
    if c38 >= $40000 then Break;
  end;
  if (Rec0At(M, RecIdx) = 0) and (M.C38 < $40000) then
    M.C38 := (M.C38 + $40000) and M32;
  Result := (Rec0At(M, RecIdx) <> 0) and TagMatches(M, RecIdx, c48);
end;

function PredictedInlineGate(const M: TPpmModel; RecIdx: Cardinal): Boolean;
var
  high, scale: Cardinal;
begin
  if M.C44 <> 0 then Exit(True);
  if M.Br18 <= 1 then Exit(True);
  if M.A8G > M.DCG then Exit(True);
  if M.RankSmall[M.RankPtrSmall] <= $3FE then Exit(True);
  high := M.Rec1s[RecIdx][$1A] shr 4;
  scale := Cardinal(M.Rec1s[RecIdx][$1B]) shl 6;
  Result := (high * scale) >= M.RankLarge[M.RankPtrLarge];
end;

function PredictedLateGate(const M: TPpmModel; RecIdx, Rec2Idx: Cardinal): Boolean;
var
  ratio1Enabled: Boolean;
  left, right, r13: Cardinal;
begin
  ratio1Enabled := (M.ByteClass <> 0) or (M.Rec2s[Rec2Idx][$13] >= $30);
  if ratio1Enabled and ((M.Rec1s[RecIdx][$19] and $38) = 0) then
  begin
    left := (M.Rec1s[RecIdx][$19] and $04) + M.Rec1s[RecIdx][1] +
            (M.Rec1s[RecIdx][$1A] shr 4);
    left := left * M.Rec2s[Rec2Idx][$12];
    right := M.Rec2s[Rec2Idx][1] + (M.Rec2s[Rec2Idx][$13] shr 4);
    right := right * M.C1C;
    if left < right then Exit(False);
  end;
  r13 := M.Rec2s[Rec2Idx][$13];
  if (r13 >= $60) and ((r13 shr 2) > M.Rec1s[RecIdx][$1A]) then Exit(False);
  Result := True;
end;

function PredictedFrequencyGate(var M: TPpmModel; RecIdx: Cardinal): Boolean;
var
  total: Cardinal;
  excl: Byte;
  idx: Integer;
begin
  total := M.C1C;
  if M.NExcl <> 0 then
  begin
    excl := M.Excl[0];
    for idx := 0 to $B do
    begin
      if M.Rec1s[RecIdx][idx + $0D] = excl then
      begin
        total := (total - M.Rec1s[RecIdx][idx + 1]) and M32;
        Break;
      end;
      if M.Rec1s[RecIdx][idx + 2] = 0 then Break;
    end;
  end;
  M.C3C := total;
  Result := M.Rec1s[RecIdx][0] < total;
end;

function Rec2SelectorFromPredbyte(const M: TPpmModel; Rec2Idx: Cardinal): Integer;
var
  ctx, slot: Integer;
  pred: Byte;
begin
  ctx := M.C48 and $FF;
  if (M.ByteClass = 0) and (M.Novel[(M.C48 shr 8) and $FF] <> 0) then
    Inc(ctx, $100);
  pred := M.PredByte[ctx];

  Result := 8;
  for slot := 0 to 7 do
  begin
    if M.Rec2s[Rec2Idx][9 + slot] = pred then
    begin
      Result := slot;
      Break;
    end;
    if (slot >= 7) or (M.Rec2s[Rec2Idx][2 + slot] = 0) then Break;
  end;
end;

procedure LiteralExclReset(var M: TPpmModel);
begin
  M.NExcl := 0;
end;

procedure LiteralContExcl(var M: TPpmModel);
begin
  if M.HasCont then
  begin
    M.Excl[0] := M.Window[M.ContOfs];
    M.NExcl := 1;
    M.HasCont := False;
    M.ContOfs := 0;
  end;
end;

function LiteralContext(const M: TPpmModel): Cardinal;
begin
  if M.MarkerFl = 2 then
    Result := ((M.RollCtx0 shr 8) and $FF)
      or ((M.RollCtx0 shr 16) and $FF00)
      or ((M.RollCtx1 shl 8) and $FF0000)
      or (M.RollCtx1 and $FF000000)
  else
    Result := M.RollCtx0;
end;

procedure LiteralSetup(var M: TPpmModel; out Ctx: Integer; out PbGate: Boolean;
  out RecIdx: Cardinal);
var
  c48, rec2idx: Cardinal;
begin
  c48 := LiteralContext(M);
  M.C48 := c48;

  M.C38 := (c48 xor (c48 shr $0D)) and $7FFF;

  Ctx := PpmCtxResolution(M);

  if (not EarlyS41) or (M.ByteClass = 0) then
  begin
    M.S3E := 0;
    M.S41 := 0;
  end;

  if (not EarlyExcl) or (M.ByteClass = 0) then LiteralExclReset(M);
  M.S45 := 0;
  M.Flag3938 := 0;
  M.Flag393B := 0;
  M.Flag3943 := 0;
  M.S48 := 0;
  M.BFC := 0;

  if (not EarlyS41) or (M.ByteClass = 0) then
    M.Flag393C := 0;

  if (not EarlyExcl) or (M.ByteClass = 0) then LiteralContExcl(M);

  if M.ByteClass = 0 then
    rec2idx := c48 and $FFFF
  else
    rec2idx := c48 and $FFFF;
  if (M.ByteClass = 0) and (M.Novel[(c48 shr 16) and $FF] <> 0) then
    Inc(rec2idx, $10000);
  M.C40 := rec2idx;
  if EarlyRecDone then RecIdx := EarlyRecIdx
  else RecIdx := M.C38 and $7FFF;

  if (not EarlyRank) or (M.ByteClass = 0) then PpmUpdateHeadRankPtrs(M);
  PbGate := PpmPredbyteGate(M);
  if (not EarlyRank) or (M.ByteClass = 0) then LastsymPredict(M);
end;

function WpClassSel(const M: TPpmModel): Boolean;
begin
  if M.ByteClass <> 0 then Exit(M.WpClassSelected);
  Result := (M.Flag3934 <> 0)
        and ((M.Br18 <= 4) or (M.RankSmall[M.RankPtrSmall] <= $3FE));
end;

function RingAttempt(var M: TPpmModel; var R: TRangeDecoder;
  Outp: PByte; var OutLen: Integer; out Route: TCascadeRoute; out Sym: Integer;
  FromGateFail: Boolean = False): Integer;
var
  rec2i, ctxb, m0, m1: Cardinal;
  r2_13: Byte;
  w: array[0..2] of Cardinal;
  y: array[0..2] of Byte;
begin
  Result := 0;
  if RingTried or (M.ByteClass = 0) then Exit;

  if RTrace and (OutLen <= RTraceLim) then
    writeln(ErrOutput, 'RA ', OutLen, ' eligible=', RingEligible,
      ' bestPred=', Bc1.BestPred, ' excluded=', Excluded(M, Bc1.BestPred),
      ' nexcl=', M.NExcl, ' bestC0=', Bc1.BestC0, ' bestC1=', Bc1.BestC1,
      ' best=', Bc1.Best, ' ringptr=', Bc1.RingPtr,
      ' flags=', IntToHex(Bc1.BestFlags,2), ' recOk=', Bc1RecOk, ' S41=', M.S41);
  Bc1PostArmed := True;
  if not RingEligible then
  begin
    RingTried := True;
    Exit;
  end;
  RingTried := True;
  M.C44 := M.C44 shr 2;
  if Excluded(M, Bc1.BestPred) then
  begin

    if (Bc1.BestC0 > 3) or ((Bc1.BestC1 shr 6) > Bc1.BestC0) then
      Bc1PostArmed := False;
    Exit;
  end;

  Bc1RingRan := Bc1WpFire and (M.ByteClass <> 0) and PpmWindowPredictorGate(M)
                and WpClassSel(M);

  if RingSuppressWp and Bc1RingRan and (M.WpA < M.WpB) then Exit;

  rec2i := M.C40;
  ctxb  := M.C48 and $FF;
  w[0] := RingRec1Weight; y[0] := RingRec1Pred;
  r2_13 := M.Rec2s[rec2i][$13];
  w[1] := BC1_WT0B0[(r2_13 shr 4) and $F];
  y[1] := M.Rec2s[rec2i][9 + (r2_13 and $F)];
  w[2] := BC1_WT070[Bc1.Conf[ctxb] and $F];
  y[2] := Bc1.Pred[ctxb];
  if RTrace and (OutLen <= RTraceLim) then
    writeln(ErrOutput, 'TRP ', OutLen, ' rec2i=', IntToHex(rec2i,5), ' r0=', IntToHex(M.RollCtx0,8),
      ' r2_13=', IntToHex(r2_13,2), ' y1=', y[1], ' y2=', y[2], ' ctxb=', ctxb,
      ' conf=', Bc1.Conf[ctxb], ' pred=', Bc1.Pred[ctxb]);
  Bc1RingMasses(w, y, m0, m1);
  if PredDbg and (OutLen >= PredLo) and (OutLen <= PredHi) then
    writeln(ErrOutput, 'MASS outLen=', OutLen, ' m0=', m0, ' m1=', m1,
      ' RingPtr=', Bc1.RingPtr, ' BestPred=', Bc1.BestPred,
      ' BestC0=', Bc1.BestC0, ' BestC1=', Bc1.BestC1, ' BestFlags=', Bc1.BestFlags,
      ' w=[', w[0], ',', w[1], ',', w[2], '] y=[', y[0], ',', y[1], ',', y[2], ']',
      ' code=', IntToHex(R.Code,8), ' rng=', IntToHex(R.Range,8));

  if Bc1RingDecode(R, m0, m1) then
  begin

    if M.Flag393C <> 0 then
    begin
      M.RankSmall[M.RankPtrSmall] := (M.RankSmall[M.RankPtrSmall] + M.C58) and $FFFFFFFF;
      M.RankLarge[M.RankPtrLarge] := (M.RankLarge[M.RankPtrLarge] + M.C58) and $FFFFFFFF;
      M.C58 := M.C58 * 2;
      if M.C58 > $FFFF then M.C58 := $FFFF;
    end;
    Sym := Bc1.BestPred;
    M.C40 := rec2i;

    M.NExcl := 0; M.S45 := 0;
    M.Flag3943 := 0;

    if not RingS48 then M.S48 := 1;
    if not RingFlags then begin M.S49 := 0; M.S41 := 1; end;

    if RingRec2S41 then
      PpmEmitAndMaintain(M, Sym, Outp, OutLen, True, False, False, False, M.S47,
        M.S41 <> 0, False, RingRec1)
    else
      PpmEmitAndMaintain(M, Sym, Outp, OutLen, True, False, False, False, M.S47,
        (M.Rec2s[rec2i][0] = 0) or FromGateFail, False, RingRec1);
    Route := crEntryHit;
    Result := 1;
  end
  else
  begin
    if BC1Dbg then writeln(ErrOutput, Format('BC1 RING-ESCAPE m0=%d m1=%d', [m0, m1]));

    if RingEscHalve and (M.Flag393C <> 0) then
    begin
      if GetEnvironmentVariable('PPM_ESCH') <> '' then
        writeln(ErrOutput, 'ESCH ol=', OutLen);
      M.RankSmall[M.RankPtrSmall] := M.RankSmall[M.RankPtrSmall] shr 1;
      M.RankLarge[M.RankPtrLarge] := M.RankLarge[M.RankPtrLarge] shr 1;
      M.C58 := ((M.C58 shr 1) + $FF) and $FFFFFFFF;
    end;

    if RingEscAppend then
    begin
      if M.NExcl < MAX_EXCL then AppendExcl(M, Bc1.BestPred);
    end
    else
    begin
      M.Excl[0] := Bc1.BestPred;
      M.NExcl := 1;
    end;
    Result := 2;
  end;
end;

function PostCtxOf(C550Ctx, Ctx: Integer): Integer; inline;
begin
  if PostCtx then Result := C550Ctx else Result := Ctx;
end;

function DecodeLiteralCascadeCore(var M: TPpmModel; var R: TRangeDecoder;
  Outp: PByte; var OutLen: Integer;
  out Route: TCascadeRoute; out Sym: Integer;
  Bc1NoRing: Boolean = False; PreExcl: Integer = -1): Boolean;
var
  ctx: Integer;
  pbGate, predicted, found, hit, entryExcluded, rec2Gate: Boolean;
  recIdx: Cardinal;
  rsym, psym, s47, sel, slot: Integer;
  rec2Copy: TRec2Rec;
  rec2Flags: TRec2Flags;
  rec2Active: Integer;
  rec2Total, total, pe, ageIdx: Cardinal;
  rec2UpdateFlag: Boolean;
  ringStat: Integer;
  skipRec2, ringE123: Boolean;
  entrySym: Integer;
  Res: TC550Result;
  c550Ctx, c550Next, wpA, wpB: Integer;
  wpCtxVal, wpDeltaVal, wpBase, wpI, wpWork: Integer;
  wpMirror: Boolean;
  wpFired, wpOk: Boolean;
  rec2GateFailed: Boolean;
begin
  Result := True;
  Sym := -1;
  rec2GateFailed := False;
  skipRec2 := False;

  if (M.ByteClass <> 0) and RingInCore and EarlyRank and (not Bc1NoRing) then
    M.RankSmall[M.RankPtrSmall] := PreRankBefore;
  LiteralSetup(M, ctx, pbGate, recIdx);

  if PreExcl >= 0 then
  begin
    M.Excl[0] := Byte(PreExcl);
    M.NExcl := 1;
  end;

  if Bc1NoRing then

    SelectPredictedRecord(M, recIdx);

  if not Bc1NoRing then
  begin

  if EarlyRecDone then
  begin
    EarlyRecDone := False;
    predicted := EarlyRecPred and ((M.ByteClass = 0) or Bc1WpFire);
  end
  else if (M.ByteClass = 0) or Bc1WpFire then
    predicted := SelectPredictedRecord(M, recIdx)
  else
    predicted := False;

  if PredDbg and (OutLen >= PredLo) and (OutLen <= PredHi) then
    writeln(ErrOutput, 'LITHEAD outLen=', OutLen, ' code=', IntToHex(R.Code,8),
      ' rng=', IntToHex(R.Range,8), ' NExcl=', M.NExcl, ' S47=', M.S47, ' S49=', M.S49);
  if PredDbg and (OutLen >= PredLo) and (OutLen <= PredHi) then
    writeln(ErrOutput, 'PRED outLen=', OutLen, ' recIdx=', recIdx, ' C38=', IntToHex(M.C38,8),
      ' predicted=', predicted, ' rec1_0=', Rec0At(M, recIdx),
      ' rec1_1=', M.Rec1s[recIdx][1], ' rec1_2=', M.Rec1s[recIdx][2],
      ' pb=', M.Rec1s[recIdx][$0D], ' pb2=', M.Rec1s[recIdx][$0E],
      ' tag=', TagMatches(M, recIdx, M.C48), ' C48=', IntToHex(M.C48,8));
  if predicted then
  begin
    RingRec1Weight := BC1_WT0F0[M.Rec1s[recIdx][$1A] shr 4];
    RingRec1Pred := M.Rec1s[recIdx][$0D + (M.Rec1s[recIdx][$1A] and $F)];
    M.S47 := $FF;
    M.C1C := RecordTotal(M, recIdx);
    if PredDbg and (OutLen >= PredLo) and (OutLen <= PredHi) then
      writeln(ErrOutput, '  PGATES inline=', PredictedInlineGate(M, recIdx),
        ' late=', PredictedLateGate(M, recIdx, M.C40), ' C1C=', M.C1C);
    if not PredictedInlineGate(M, recIdx) then
      predicted := False
    else if not PredictedLateGate(M, recIdx, M.C40) then
      predicted := False
    else
    begin
      M.C54 := (M.C54 + 1) and M32;
      if not PredictedFrequencyGate(M, recIdx) then
        predicted := False
      else
        M.Flag3938 := 1;
    end;
  end;

  if predicted and (M.ByteClass <> 0) then
  begin
    M.Flag393B := Ord(M.WpArmed);
    predicted := not M.WpEngaged;
  end;
  if predicted and (M.Rec1s[recIdx][2] <> 0) then
  begin
    if RTrace and (OutLen <= RTraceLim) then
      writeln(ErrOutput, 'O1R ', OutLen, ' recIdx=', recIdx, ' C40=', IntToHex(M.C40,5),
        ' ctx=', IntToHex(ctx,3), ' code=', IntToHex(R.Code,8), ' rng=', IntToHex(R.Range,8),
        ' r1_0=', M.Rec1s[recIdx][0], ' r1_1=', M.Rec1s[recIdx][1],
        ' r1_2=', M.Rec1s[recIdx][2], ' pb=', M.Rec1s[recIdx][$0D],
        ' S47=', M.S47, ' C1C=', M.C1C);
    found := Order1Reweight_Decode(M, R, recIdx, M.C40, ctx, rsym);
    if found then
    begin
      s47 := M.S47;
      rec2UpdateFlag := (s47 < $0C) and (M.Rec1s[recIdx][s47 + 1] < 7);
      PpmEmitAndMaintain(M, rsym, Outp, OutLen,
        True, True, False, False, s47, rec2UpdateFlag, True);

      Bc1PostArmed := False;
      Route := crOrder1Hit; Sym := rsym;
      Exit;
    end;
    M.S47 := $0C;
    if M.ByteClass = 0 then M.S41 := 1;
    M.S49 := $FF;
    predicted := False;
  end;

  if predicted then
  begin
    hit := Predicted_Decode(M, R, recIdx, psym);
    if PredDbg and (OutLen >= PredLo) and (OutLen <= PredHi) then
      writeln(ErrOutput, '  AFTERPRED outLen=', OutLen, ' hit=', hit, ' psym=', psym,
        ' code=', IntToHex(R.Code,8), ' rng=', IntToHex(R.Range,8));
    if hit then
    begin
      PpmEmitAndMaintain(M, psym, Outp, OutLen,
        True, True, True, False, 0, M.Rec1s[recIdx][1] < 7, True);
      Bc1PostArmed := False;
      Route := crPredictedHit; Sym := psym;
      Exit;
    end;

    M.C1C := RecordTotal(M, recIdx);
    M.S47 := $0C;
    M.S49 := $FF;
    AppendExcl(M, M.Rec1s[recIdx][$0D]);
    M.C4C := M.Rec2s[M.C40][0];
  end;

  if (M.ByteClass <> 0) and RingInCore and EarlyRank and (not Bc1NoRing) then
  begin
    M.RankSmall[M.RankPtrSmall] := PreRankAfter;
    pbGate := PpmPredbyteGate(M);
  end;
  if (M.ByteClass <> 0) and (not Bc1NoRing) then
    PpmLiteralDecayC54(M);
  if (M.ByteClass <> 0) and (not Bc1NoRing) and Bc1RecOk then
    M.C44 := M.C44 + 2;
  ringE123 := False; ringStat := 0;
  if RingInCore and RingWantedFlag and (not Bc1NoRing) and (M.ByteClass <> 0) then
  begin
    ringE123 := True;
    ringStat := RingAttempt(M, R, Outp, OutLen, Route, Sym);
    if ringStat = 1 then begin Result := True; Exit; end;
    if (ringStat = 2) and (not RingEscAppend) then
    begin

      M.Excl[0] := Bc1.BestPred;
      M.NExcl := 1;
    end;
  end;

  skipRec2 := SkipRec2Flag and ringE123
              and (ringStat = 0) and (not RingEligible);
  if SkipRec2Flag and ringE123 and RingEligible and (not RingRecheckChain) then
    skipRec2 := True;
  if SkipRec2Flag and ringE123 and RingEligible and RingRecheckChain then
  begin

    if (M.C50 = 0) or (M.Rec2s[M.C40][$11] = 0) then
      M.S41 := 1
    else
      M.S41 := Ord((M.C58 < $FFFF) and
                   (M.RankSmall[M.RankPtrSmall] <= $3FE));
    skipRec2 := (M.S41 = 0) or (M.Rec2s[M.C40][0] = 0);
  end;
  if skipRec2 and (GetEnvironmentVariable('PPM_SKIPDBG') <> '') then
    writeln(ErrOutput, 'SKIP ol=', OutLen, ' ringStat=', ringStat,
      ' elig=', RingEligible, ' rec2_0=', M.Rec2s[M.C40][0], ' C40=', IntToHex(M.C40,5),
      ' NExcl=', M.NExcl);

  if not skipRec2 then
  begin
  if PredDbg and (OutLen >= PredLo) and (OutLen <= PredHi) then
  begin
    Write(ErrOutput, 'REC2 outLen=', OutLen, ' r0=', IntToHex(M.RollCtx0,8),
      ' C40=', IntToHex(M.C40,5), ' NExcl=', M.NExcl, ' Excl=');
    for slot := 0 to M.NExcl - 1 do Write(ErrOutput, M.Excl[slot], ',');
    Write(ErrOutput, ' rec2=[');
    for slot := 0 to $13 do
    begin
      Write(ErrOutput, M.Rec2s[M.C40][slot]);
      if slot < $13 then Write(ErrOutput, ', ');
    end;
    Writeln(ErrOutput, ']');
  end;
  if M.Rec2s[M.C40][0] <> 0 then
  begin
    entryExcluded := False;
    if M.Rec2s[M.C40][2] = 0 then
      entryExcluded := Excluded(M, M.Rec2s[M.C40][9]);
    if PredDbg and (OutLen >= PredLo) and (OutLen <= PredHi) then
    begin
      Rec2TotalAndFlags(M, M.C40, rec2Copy, rec2Active, rec2Flags, rec2Total);
      writeln(ErrOutput, '  GATE outLen=', OutLen, ' total=', rec2Total,
        ' rec2_0=', rec2Copy[0], ' t*4=', rec2Total shl 2, ' r0*5=', Cardinal(rec2Copy[0])*5,
        ' g1=', (rec2Total shl 2) > (Cardinal(rec2Copy[0]) * 5),
        ' r11=', rec2Copy[$11], ' C50=', M.C50,
        ' g2=', ((Cardinal(rec2Copy[$11]) shl 2) + M.C50) < $10,
        ' rec2_2=', M.Rec2s[M.C40][2], ' entryExcl=', entryExcluded);
    end;

    Rec2TotalAndFlags(M, M.C40, rec2Copy, rec2Active, rec2Flags, rec2Total);
    M.C4C := rec2Total;
    M.S49 := $FF;
    rec2Gate := ((rec2Total shl 2) > (Cardinal(rec2Copy[0]) * 5)) and
                (((Cardinal(rec2Copy[$11]) shl 2) + M.C50) < $10);
    if rec2Gate and (M.ByteClass <> 0) then
    begin
      M.S3E := Ord(M.WpArmed);
      rec2Gate := not M.WpEngaged;
    end;
    rec2GateFailed := not rec2Gate;

    if M.Rec2s[M.C40][2] <> 0 then
    begin
      if rec2Gate then
      begin
        sel := Rec2SelectorFromPredbyte(M, M.C40);
        if RTrace and (OutLen <= RTraceLim) then
          writeln(ErrOutput, 'REW ', OutLen, ' C40=', IntToHex(M.C40,5), ' C4C=', M.C4C, ' active=', rec2Active,
            ' sel=', sel, ' code=', IntToHex(R.Code,8), ' rng=', IntToHex(R.Range,8),
            ' rec2_0=', M.Rec2s[M.C40][0], ' rec2_12=', M.Rec2s[M.C40][$12],
            ' rec2_13=', M.Rec2s[M.C40][$13]);
        found := Rec2Reweight_Decode(M, R, M.C40, sel, rsym);
        if found then
        begin
          slot := M.S49;
          total := M.C4C;
          if (slot < 8) and ((Cardinal(M.Rec2s[M.C40][slot + 1]) shl 2) >= total) then
          begin
            if total > $10 then M.S48 := 2 else M.S48 := 1;
          end;
          PpmRec2ReweightPost(M, rsym, Outp, OutLen, True);

          if not RingTried then Bc1PostArmed := False;
          Route := crRec2Hit; Sym := rsym;
          Exit;
        end;
        if M.ByteClass <> 0 then
        begin

          slot := 0;
          while (slot < 8) and (M.Rec2s[M.C40][slot + 1] <> 0) do
          begin
            if (M.NExcl < MAX_EXCL) and (not Excluded(M, M.Rec2s[M.C40][9 + slot])) then
              AppendExcl(M, M.Rec2s[M.C40][9 + slot]);
            Inc(slot);
          end;
        end;
        M.S41 := 1;

        if RingAfterRewMiss and (not Bc1NoRing) then
          if RingAttempt(M, R, Outp, OutLen, Route, Sym, True) = 1 then
          begin
            Result := True;
            Exit;
          end;
      end;

    end
    else if not entryExcluded then
    begin

      if rec2Gate then
      begin
        hit := Entry_Decode(M, R, M.C40, pe);
        if hit then
        begin
          M.S48 := 1;
          M.S49 := 0;
          M.S41 := 1;
          entrySym := M.Rec2s[M.C40][9];

          PpmEmitAndMaintain(M, entrySym, Outp, OutLen,
            True, False, False, M.ByteClass = 0, M.S47, True, False);
          if not RingTried then Bc1PostArmed := False;
          Route := crEntryHit; Sym := entrySym;
          Exit;
        end;
        AppendExcl(M, M.Rec2s[M.C40][9]);
        M.S49 := 8;
        M.C28 := $2000;

        M.C24 := pe;
        if not KeepC4C then M.C4C := M.Rec2s[M.C40][0];

        if RingAfterEntryMiss and (not Bc1NoRing) then
          if RingAttempt(M, R, Outp, OutLen, Route, Sym, True) = 1 then
          begin
            Result := True;
            Exit;
          end;
      end;
    end
    else
    begin
      M.S41 := 1;

      M.S49 := $FF;
      if not KeepC4C then M.C4C := M.Rec2s[M.C40][0];
    end;
  end;
  end;

  if RTrace and (OutLen <= RTraceLim) then
    writeln(ErrOutput, 'GF ', OutLen, ' rec2GateFailed=', rec2GateFailed,
      ' Bc1NoRing=', Bc1NoRing, ' RingTried=', RingTried, ' RingEligible=', RingEligible);
  if rec2GateFailed and (not Bc1NoRing) then
    if RingAttempt(M, R, Outp, OutLen, Route, Sym, True) = 1 then
    begin
      Result := True;
      Exit;
    end;

  end;

  ageIdx := (M.AgeCtr + 1) and $FF;
  if M.ByteClass <> 0 then M.Flag3943 := Ord(M.WpArmed);

  if M.ByteClass <> 0 then pbGate := PpmPredbyteGate(M);

  if C550WinCtx and pbGate then
    c550Ctx := $100 + M.Window[(M.WinPos - M.Br18) and M.WinMask]
  else
    c550Ctx := ctx;
  if (GetEnvironmentVariable('PPM_WPDBG') <> '') and (OutLen <= 12) then
    writeln(ErrOutput, 'WP outLen=', OutLen, ' RecA0=', M.RecA[0], ' RecA1=', M.RecA[1],
      ' (RecA0<RecA1)=', M.RecA[0] < M.RecA[1]);
  if M.ByteClass = 0 then PpmLiteralDecayC54(M);
  M.Bec := 0;
  if (M.ByteClass = 0) or (not skipRec2) then M.S41 := 1;

  if WpClassSel(M) then
  begin
    wpCtxVal := Integer(M.ClsCtx);
    wpWork   := $304 + Integer(M.Flag3934);
  end
  else
  begin
    wpDeltaVal := (Integer(M.Window[(M.WinPos - M.Br18) and M.WinMask]) -
      Integer(M.Window[(M.WinPos - 2 * M.Br18) and M.WinMask])) and $FF;
    wpCtxVal := Integer(PPMS_43B2CC[wpDeltaVal]) + $201;
    wpWork   := $304;
  end;

  wpFired := Bc1WpFire and (M.ByteClass <> 0) and PpmWindowPredictorGate(M);
  if (GetEnvironmentVariable('PPM_CLSTRACE') <> '') and (OutLen <= 12) then
    writeln(ErrOutput, 'CLST outLen=', OutLen, ' cls=', M.Flag3934,
      ' ClsCtx=', IntToHex(M.ClsCtx,3), ' ClsBase=', M.ClsBase, ' ClsNeg=', M.ClsNeg,
      ' ClsPhase=', M.ClsPhase, ' wpCtx=', IntToHex(wpCtxVal,3), ' wpWork=', IntToHex(wpWork,3),
      ' fired=', wpFired, ' r0=', IntToHex(M.RollCtx0,8));
  if (M.ByteClass <> 0) and WprDbg and (OutLen >= 77632) and (OutLen <= 81780) then
    writeln(ErrOutput, 'WPR outLen=', OutLen, ' wpos=', M.WinPos, ' fired=', wpFired,
      ' base=', Integer(Bc1.Win[(Bc1.WPos - 1) and $FFF]), ' WPos=', Bc1.WPos,
      ' wpCtx=', IntToHex(wpCtxVal,3), ' Ctx7=', IntToHex(Bc1.Ctx[7],5),
      ' RecA0=', M.RecA[0], ' RecA1=', M.RecA[1]);

  if WpClassSel(M) then
    wpBase := Integer(M.ClsBase)
  else
    wpBase := Integer(M.Window[(M.WinPos - M.Br18) and M.WinMask]);

  wpMirror := WpClassSel(M) and (M.ClsNeg <> 0);
  if wpFired then
  begin

    for wpI := 0 to M.NExcl - 1 do
      if wpMirror then M.Excl[wpI] := Byte((wpBase - M.Excl[wpI]) and $FF)
      else M.Excl[wpI] := Byte((M.Excl[wpI] - wpBase) and $FF);
    wpOk := C550_Decode(M, R, wpCtxVal, wpWork, Res);

    if not wpOk then
    begin
      for wpI := 0 to M.NExcl - 1 do
        if wpMirror then M.Excl[wpI] := Byte((wpBase - M.Excl[wpI]) and $FF)
        else M.Excl[wpI] := Byte((M.Excl[wpI] + wpBase) and $FF);
      Result := False; Exit;
    end;
  end
  else
  begin

    if C550WinCtx and pbGate then
      c550Ctx := $100 + M.Window[(M.WinPos - M.Br18) and M.WinMask]
    else
      c550Ctx := ctx;
    if RTrace and (OutLen <= RTraceLim) then
    begin
      Write(ErrOutput, 'C5 ', OutLen, ' ctx=', IntToHex(c550Ctx,3), ' wc=301',
        ' code=', IntToHex(R.Code,8), ' rng=', IntToHex(R.Range,8),
        ' nexcl=', M.NExcl, ' excl=[');
      for wpI := 0 to M.NExcl - 1 do
      begin
        Write(ErrOutput, M.Excl[wpI]);
        if wpI < M.NExcl - 1 then Write(ErrOutput, ',');
      end;
      Writeln(ErrOutput, '] S41=', M.S41, ' S47=', M.S47, ' S49=', M.S49, ' C4C=', M.C4C,
        ' pbGate=', pbGate, ' Br18=', M.Br18, ' RankS=', M.RankSmall[M.RankPtrSmall],
        ' RankPtr=', M.RankPtrSmall);
    end;
    if not C550_Decode(M, R, c550Ctx, $301, Res) then
    begin Result := False; Exit; end;
  end;

  if wpFired then
    if wpMirror then Res.Sym := (wpBase - Res.Sym) and $FF
    else Res.Sym := (Res.Sym + wpBase) and $FF;

  if wpMirror then wpDeltaVal := (wpBase - Res.Sym) and $FF
  else wpDeltaVal := (Res.Sym - wpBase) and $FF;

  PpmC550Post(M, PostCtxOf(c550Ctx, ctx), Res.Sym, Res.KCtx, Outp, OutLen, pbGate,
    Integer(ageIdx), Res.Sse2Idx, Res.Weight, Res.Sse2UpIdx, M.S41 <> 0, wpCtxVal, wpDeltaVal, wpFired,
    wpBase, wpWork, wpMirror, wpFired and WpClassSel(M), c550Ctx);
  LastWpFired := wpFired; LastPathA := Res.PathA;
  LastKCtx := Res.KCtx; LastWorkCtx := Res.WorkCtx;
  Route := crC550; Sym := Res.Sym;
end;

function DecodeLiteralCascade(var M: TPpmModel; var R: TRangeDecoder;
  Outp: PByte; var OutLen: Integer;
  out Route: TCascadeRoute; out Sym: Integer): Boolean;
var
  r0, r1, rec2i, ctxb: Cardinal;
  r2_13: Byte;
  w: array[0..2] of Cardinal;
  y: array[0..2] of Byte;
  m0, m1: Cardinal;
  ringPtrSet, ringWanted: Boolean;
  chainAl, ringStat: Integer;
begin
  if M.ByteClass = 0 then
  begin
    Result := DecodeLiteralCascadeCore(M, R, Outp, OutLen, Route, Sym);
    Exit;
  end;

  if EarlyExcl then
  begin
    LiteralExclReset(M);
    LiteralContExcl(M);
  end;
  if EarlyS41 then
  begin
    M.S3E := 0;
    M.S41 := 0;
    M.Flag393C := 0;
  end;

  if EarlyCtx then
  begin
    M.C48 := LiteralContext(M);
    M.C38 := (M.C48 xor (M.C48 shr $0D)) and $7FFF;
    M.C40 := M.C48 and $FFFF;
  end;

  if EarlyRank then
  begin
    PpmUpdateHeadRankPtrs(M);
    LastsymPredict(M);
  end;

  M.WpClassSelected := (M.Flag3934 <> 0)
    and ((M.Br18 <= 4) or (M.RankSmall[M.RankPtrSmall] <= $3FE));
  M.WpArmed := M.WpClassSelected and PpmWindowPredictorGate(M);
  M.WpEngaged := M.WpArmed and (M.WpA < M.WpB);
  M.WpKernelWeight := 0;

  RingRec1Weight := 0;
  RingRec1Pred := 0;
  if EarlyRec then
  begin
    EarlyRecIdx := M.C38 and $7FFF;
    EarlyRecPred := SelectPredictedRecord(M, EarlyRecIdx);
    EarlyRecDone := True;
    if EarlyRecPred then
    begin

      RingRec1Weight := BC1_WT0F0[M.Rec1s[EarlyRecIdx][$1A] shr 4];
      RingRec1Pred := M.Rec1s[EarlyRecIdx][$0D + (M.Rec1s[EarlyRecIdx][$1A] and $F)];
    end;
  end;

  r0 := M.RollCtx0; r1 := M.RollCtx1; ctxb := M.C48 and $FF;
  if C50Trace then
    Writeln(ErrOutput, 'C50 ol=', OutLen, ' value=', M.C50);

  rec2i := M.C48 and $FFFF;
  LvlPos := OutLen;
  PreRankBefore := M.RankSmall[M.RankPtrSmall];
  if PredDbg and (OutLen >= PredLo) and (OutLen <= PredHi) then
    writeln(ErrOutput, 'RANKPRE ol=', OutLen, ' rank=', M.RankSmall[M.RankPtrSmall],
      ' ptr=', M.RankPtrSmall, ' br18=', M.Br18);
  ringPtrSet := Bc1PreDecode(M, r0, r1);
  PreRankAfter := M.RankSmall[M.RankPtrSmall];
  if PredDbg and (OutLen >= PredLo) and (OutLen <= PredHi) then
    writeln(ErrOutput, 'RANKPOST ol=', OutLen, ' rank=', M.RankSmall[M.RankPtrSmall],
      ' best=', Bc1.Best, ' c0=', Bc1.BestC0, ' c1=', Bc1.BestC1,
      ' flags=', Bc1.BestFlags);
  if F393CExact then
    M.Flag393C := Ord(Bc1.Fired393C)
  else
    if (M.Brf0 > 1) and (Bc1.Best = 7) then M.Flag393C := 1 else M.Flag393C := 0;
  if (GetEnvironmentVariable('PPM_RTDBG') <> '') and (OutLen >= RtdLo) and (OutLen <= RtdHi) then
    writeln(ErrOutput, 'RT outLen=', OutLen, ' set=', ringPtrSet,
      ' r2_13=', M.Rec2s[rec2i][$13], ' c0=', Bc1.BestC0, ' c1=', Bc1.BestC1,
      ' fl=', Bc1.BestFlags, ' Best=', Bc1.Best,
      ' C50=', M.C50, ' r2_11=', M.Rec2s[rec2i][$11], ' C58=', M.C58,
      ' RankSmall=', M.RankSmall[M.RankPtrSmall], ' r2_0=', M.Rec2s[rec2i][0],
      ' BestPred=', Bc1.BestPred, ' NExcl=', M.NExcl, ' excl=', Excluded(M, Bc1.BestPred));

  if M.Rec2s[rec2i][$13] < $90 then
  begin

    if StaleBest then
    begin
      if Bc1.RingFlag = 0 then M.S41 := 0 else M.S41 := 1;
    end
    else if (Bc1.BestC0 * 5 <= Bc1.BestC1 * 3) or ((Bc1.BestFlags and $7F) > 2) then
      M.S41 := 0
    else
      M.S41 := 1;
  end
  else
    M.S41 := 1;

  ringWanted := M.S41 = 0;

  RingRecheckChain := ringWanted;
  if not ringWanted then
  begin
    if (M.C50 = 0) or (M.Rec2s[rec2i][$11] = 0) then
      chainAl := 1
    else if M.C58 < $FFFF then
    begin
      if M.RankSmall[M.RankPtrSmall] > $3FE then chainAl := 0 else chainAl := 1;
    end
    else
      chainAl := 0;
    M.S41 := chainAl;
    ringWanted := chainAl = 0;
  end;
  if not ringWanted then
    ringWanted := M.Rec2s[rec2i][0] = 0;

  RingEligible := ringPtrSet;
  RingTried := False;
  Bc1RingRan := False;
  Bc1PostArmed := False;

  RingWantedFlag := ringWanted;
  if ringWanted and (not RingInCore) then
    ringStat := RingAttempt(M, R, Outp, OutLen, Route, Sym)
  else
    ringStat := 0;

  if ringStat = 1 then
    Result := True
  else if ringStat = 2 then
  begin

    Result := DecodeLiteralCascadeCore(M, R, Outp, OutLen, Route, Sym, True,
      Integer(Bc1.BestPred));
    if not Result then Exit;
  end
  else
  begin
    Result := DecodeLiteralCascadeCore(M, R, Outp, OutLen, Route, Sym, False);
    if not Result then
    begin
      if BC1Dbg then writeln(ErrOutput, Format('BC1 CORE-FALSE (c550 path-A) r0=%.8x', [r0]));
      Exit;
    end;
  end;

  LvlPos := OutLen;

  if Bc1PostArmed or PostGateOff then
  begin
    if WpcDbg then
      writeln(ErrOutput, 'WPC level ol=', OutLen-1, ' bfc=', M.BFC,
        ' c0c=', M.WpKernelWeight, ' f43=', M.Flag3943,
        ' f3d=', Ord(Bc1RingRan), ' s3e=', M.S3E, ' best=', Bc1.LastBest);
    Bc1PostUpdate(M, Byte(Sym));
  end;

  if M.WpPend then
  begin
    if WpcDbg then
      writeln(ErrOutput, 'WPC commit ol=', OutLen-1, ' bfc=', M.BFC,
        ' c0c=', M.WpKernelWeight, ' f43=', M.Flag3943,
        ' f3d=', Ord(Bc1RingRan), ' s3e=', M.S3E);

    if M.Flag3943 <> 0 then M.BFC := M.BFC + M.WpKernelWeight;
    M.WpA := ((M.WpA * 31) shr 5) + M.WpAccAdd;
    M.WpB := ((M.WpB * 31) shr 5) + M.BFC;
    M.WpPend := False;
  end;

  if RTrace and (OutLen <= RTraceLim) then
    writeln(ErrOutput, 'RT ', OutLen - 1, ' pre=', Ord(ringPtrSet),
      ' ring=', Ord(ringWanted), ' hit=', ringStat,
      ' route=', Ord(Route), ' post=', Ord(Bc1PostArmed or PostGateOff),
      ' sym=', Sym, ' wpf=', Ord(LastWpFired), ' patha=', Ord(LastPathA),
      ' kctx=', IntToHex(LastKCtx,3), ' wc=', IntToHex(LastWorkCtx,3),
      ' wpA=', M.WpA, ' wpB=', M.WpB, ' recA=', M.RecA[0], '/', M.RecA[1]);
  Bc1Sub2Update(Byte(ctxb), Byte(Sym));
  Bc1PushWindow(Byte(Sym));
end;

initialization
  C50Trace := GetEnvironmentVariable('PPM_C50TRACE') <> '';
  WpcDbg := GetEnvironmentVariable('PPM_WPCDBG') <> '';
  BC1Dbg := GetEnvironmentVariable('PPM_BC1DBG') <> '';
  RingSuppressWp := GetEnvironmentVariable('X_RINGWP_OFF') = '';
  RingAfterEntryMiss := GetEnvironmentVariable('X_RINGENTRY_OFF') = '';
  RingAfterRewMiss := GetEnvironmentVariable('X_RINGREW_OFF') = '';
  EarlyExcl := GetEnvironmentVariable('X_EARLYEXCL_OFF') = '';
  EarlyCtx := GetEnvironmentVariable('X_EARLYCTX_OFF') = '';
  EarlyRank := GetEnvironmentVariable('X_EARLYRANK_OFF') = '';
  EarlyS41 := GetEnvironmentVariable('X_EARLYS41_OFF') = '';
  RingInCore := GetEnvironmentVariable('X_RINGINCORE_OFF') = '';
  EarlyRec := GetEnvironmentVariable('X_EARLYREC') <> '';
  RingRec1 := GetEnvironmentVariable('X_RINGREC1_OFF') = '';
  RingS48 := GetEnvironmentVariable('X_RINGS48_OFF') = '';
  RingFlags := GetEnvironmentVariable('X_RINGFLAGS_OFF') = '';
  RingRec2S41 := GetEnvironmentVariable('X_RINGREC2_OFF') = '';
  RingEscHalve := GetEnvironmentVariable('X_RINGESCHALVE_OFF') = '';
  F393CExact := GetEnvironmentVariable('X_F393C_OFF') = '';
  C550WinCtx := GetEnvironmentVariable('X_C550CTX_OFF') = '';
  SkipRec2Flag := GetEnvironmentVariable('X_SKIPREC2_OFF') = '';
  StaleBest := GetEnvironmentVariable('X_STALEBEST_OFF') = '';
  RingEscAppend := GetEnvironmentVariable('X_RINGESCAPP_OFF') = '';
  PostCtx := GetEnvironmentVariable('X_POSTCTX') <> '';
  PredDbg := GetEnvironmentVariable('PPM_PREDDBG') <> '';
  if PredDbg then
  begin
    PredLo := StrToIntDef(Copy(GetEnvironmentVariable('PPM_PREDDBG'), 1,
                Pos(':', GetEnvironmentVariable('PPM_PREDDBG')) - 1), 0);
    PredHi := StrToIntDef(Copy(GetEnvironmentVariable('PPM_PREDDBG'),
                Pos(':', GetEnvironmentVariable('PPM_PREDDBG')) + 1, 20), 0);
  end;
  if Pos(':', GetEnvironmentVariable('PPM_RTDBG')) > 0 then
  begin
    RtdLo := StrToIntDef(Copy(GetEnvironmentVariable('PPM_RTDBG'), 1,
               Pos(':', GetEnvironmentVariable('PPM_RTDBG')) - 1), 24666);
    RtdHi := StrToIntDef(Copy(GetEnvironmentVariable('PPM_RTDBG'),
               Pos(':', GetEnvironmentVariable('PPM_RTDBG')) + 1, 20), 24674);
  end;
  KeepC4C := GetEnvironmentVariable('X_KEEPC4C_OFF') = '';
  RTrace := GetEnvironmentVariable('PPM_RTRACE') <> '';
  RTraceLim := StrToIntDef(GetEnvironmentVariable('PPM_RTRACE'), 64);
  WprDbg := GetEnvironmentVariable('PPM_WPRDBG') <> '';

end.
