unit uha_ppm_post;

{$mode delphi}{$H+}{$Q-}{$R-}

interface

uses uha_ppm_textbook, uha_ppm_kernel, uha_ppm_maint, uha_ppm_update,
  uha_ppm_records, uha_ppm_fenwick, uha_ppm_d390, SysUtils;

function PpmCtxResolution(const M: TPpmModel): Integer;
procedure PpmUpdateHeadRankPtrs(var M: TPpmModel);
function PpmPredbyteGate(const M: TPpmModel): Boolean;
function PpmWindowPredictorGate(const M: TPpmModel): Boolean;
procedure PpmLiteralDecayC54(var M: TPpmModel);

procedure PpmPostSymbolMaintenance(var M: TPpmModel; Sym: Integer; Dl: Boolean);

procedure PpmMatchMaintain(var M: TPpmModel; Sym: Integer; Dl: Boolean;
  Outp: PByte; var OutLen: Integer);

procedure PpmEmitAndMaintain(var M: TPpmModel; Sym: Integer;
  Outp: PByte; var OutLen: Integer;
  PbGate, Light, ClearS47, DecayC54: Boolean;
  RecordS47: Integer; Rec2Update, Rec2BeforeRecord: Boolean;
  RunRec1: Boolean = True);

procedure PpmRec2ReweightPost(var M: TPpmModel; Sym: Integer;
  Outp: PByte; var OutLen: Integer; PbGate: Boolean);

procedure PpmC550Post(var M: TPpmModel; Ctx, Sym, KCtx: Integer;
  Outp: PByte; var OutLen: Integer; PbGate: Boolean; AgeIdx: Integer;
  Sse2Idx: Integer; KernelWeight: Cardinal; Sse2UpIdx: Integer;
  ExactOrderLoop: Boolean; WpCtx: Integer; WpDelta: Integer; WpFired: Boolean;
  WpBase: Integer; WpWork: Integer = $304; WpMirror: Boolean = False;
  WpArmed: Boolean = False; NfDecCtx: Integer = -1);

implementation

const M32 = $FFFFFFFF;

var Bc1WpFireO: Boolean;
var MMDbg: Boolean; MMLo, MMHi: Integer;

function PpmCtxResolution(const M: TPpmModel): Integer;
var b: Integer;
begin
  b := M.C48 and $FF;
  if (M.ByteClass = 0) and (M.Novel[(M.C48 shr 8) and $FF] <> 0) then
    Inc(b, $100);
  Result := b;
end;

procedure PpmUpdateHeadRankPtrs(var M: TPpmModel);
var k, k0: Cardinal;
begin
  if M.Br18 <= 1 then
  begin
    k0 := M.Brf0 and $FF;
    if (k0 < 2) or (k0 > 4) then Exit;
  end;

  k := M.Brf0;
  if k = 0 then Exit;

  M.RankPtrSmall := k;
  M.RankPtrLarge := k;
  if k <= 4 then
    M.RankPtrSmall := (M.RankSmallBase[k] + (M.LastCtx mod k)) and M32;
  if k <= $10 then
    M.RankPtrLarge := (M.RankLargeBase[k] + (M.LastCtx mod k)) and M32;
end;

function PpmWindowPredictorGate(const M: TPpmModel): Boolean;
begin
  if M.ClsFlag31 <> 0 then
    Result := Cardinal(M.RecA[0] * 31) < Cardinal(M.RecA[1] * 32)
  else
    Result := M.RecA[0] < M.RecA[1];
end;

function PpmPredbyteGate(const M: TPpmModel): Boolean;
begin
  Result := False;
  if M.ByteClass = 0 then Exit;
  if M.Br18 <= 1 then Exit;
  if M.RankPtrSmall > Cardinal(High(M.RankSmall)) then Exit;
  Result := M.RankSmall[M.RankPtrSmall] <> 0;
end;

procedure PpmLiteralDecayC54(var M: TPpmModel);
begin
  M.C54 := M.C54 shr 3;
end;

procedure PutWindow(var M: TPpmModel; Sym: Integer);
var wp: Cardinal;
begin
  wp := M.WinPos;
  M.Window[wp] := Sym and $FF;
  if wp < $100 then
    M.Window[wp + M.WinWrap] := Sym and $FF;
end;

procedure AdvanceWin(var M: TPpmModel);
begin
  M.WinPos := (M.WinPos + 1) and M.WinMask;
end;

procedure EmitDetransformed(var M: TPpmModel; Sym: Integer;
  Outp: PByte; var OutLen: Integer);
begin
  if (GetEnvironmentVariable('PPM_EMITDBG') <> '') and (OutLen >= 138) and (OutLen <= 144) then
    writeln(ErrOutput, 'EMIT outLen=', OutLen, ' rawSym=', Sym and $FF);
  M.OutCount := OutLen;
  Detr_Emit(M.Detr, Sym and $FF, Cardinal(OutLen), M.DetrThr1, M.DetrThr2,
    Outp, OutLen);
  M.OutCount := OutLen;
end;

const

  CLS_T7DC: array[0..255] of Byte = (
    0,1,2,3,4,5,6,7,7,8,8,9,9,10,10,10,
    11,11,11,11,11,12,12,12,12,12,12,12,12,13,13,13,
    13,13,13,13,13,13,13,13,13,13,14,14,14,14,14,14,
    14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,15,
    15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,
    15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,
    15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,
    15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,
    17,17,17,17,17,17,17,17,17,17,17,17,17,17,17,17,
    17,17,17,17,17,17,17,17,17,17,17,17,17,17,17,17,
    17,17,17,17,17,17,17,17,17,17,17,17,17,17,17,17,
    17,17,17,17,17,17,17,17,17,17,17,17,17,17,17,17,
    17,17,18,18,18,18,18,18,18,18,18,18,18,18,18,18,
    18,18,18,18,18,18,18,19,19,19,19,19,19,19,19,19,
    19,19,19,19,20,20,20,20,20,20,20,20,21,21,21,21,
    21,22,22,22,23,23,24,24,25,25,26,27,28,29,30,31);
  CLS_T6CC: array[0..15] of Byte = (0,0,0,0,1,1,1,1,1,1,1,1,1,0,0,0);

var RecFreeze: Boolean;
var EntryDecFlag: Boolean;
var EmptyEntry: Boolean;
var RecBKern: Boolean;
var RecABr: Boolean;
var PostDbg: Boolean; PostLo: Integer = 0; PostHi: Integer = -1;
  CLS_T6DC: array[0..255] of Byte = (
     0, 1, 1, 2, 2, 2, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4,
     4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,
     6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
     6, 6, 6, 6, 6, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
     7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
     7, 7, 7, 7, 7, 7, 7, 8, 8, 8, 8, 8, 8, 8, 8, 8,
     8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,
     8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,
     8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,
     8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,
     8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 9, 9, 9, 9, 9, 9,
     9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9,
     9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9,10,10,10,10,
    10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,
    10,11,11,11,11,11,11,11,11,11,11,11,11,11,12,12,
    12,12,12,12,12,12,13,13,13,13,13,14,14,14,15,15);

procedure ClsDeltaUpdate(var M: TPpmModel; Sym: Integer);
var delta: Byte;
begin
  if M.Flag3934 = 0 then Exit;
  delta := Byte(Sym) - M.ClsBase;
  if M.ClsNeg <> 0 then delta := Byte(-delta);
  if delta >= $80 then
    M.ClsNeg := Ord(M.ClsNeg = 0);
  case M.Flag3934 of
    1: M.ClsCtx := $209 + Cardinal(CLS_T6CC[(M.ClsCtx - $209) and $F]) shl 4
                        + Cardinal(CLS_T6DC[delta]);
    2: M.ClsCtx := $229 + (M.ClsPhase shl 4) + Cardinal(CLS_T6DC[delta]);
    3: begin
         if M.Cls3Active <> 0 then
         begin
           delta := Byte(Sym - (M.RollCtx0 shr 16));
           M.ClsNeg := M.Cls3SavedNeg;
           if M.ClsNeg <> 0 then delta := Byte(-delta);
           if delta >= $80 then M.ClsNeg := Ord(M.ClsNeg = 0);
         end;
         if Byte(Sym) = M.Cls3Pred[M.Cls3Index] then
           Inc(M.Cls3Confidence[M.Cls3Index])
         else
           M.Cls3Confidence[M.Cls3Index] := M.Cls3Confidence[M.Cls3Index] shr 1;
         M.ClsCtx := $249 + (M.ClsPhase shl 5) + Cardinal(CLS_T7DC[delta]);
       end;
    7, 8, 9: M.MM7.Update(M.ClsPhase, Byte(Sym), delta, M.ClsNeg);
    5, 6: begin
      if M.Flag3934 = 5 then
        M.MM6.Update(Byte(Sym xor $80), Byte(delta), M.LastCtx)
      else
        M.MM6.Update(Byte(Sym), Byte(delta), M.LastCtx);
      if MMDbg and (M.OutCount >= MMLo) and (M.OutCount <= MMHi) then
        WriteLn(ErrOutput, 'MMUPDATE count=', M.LastCtx, ' sym=', Sym, ' delta=', delta, ' base=', M.ClsBase, ' neg=', M.ClsNeg);
    end;
    4: M.ClsCtx := $2A9 + (M.ClsPhase shl 4) + Cardinal(CLS_T6DC[delta]);
  end;
end;

procedure ClsPhaseUpdate(var M: TPpmModel);
var oldPhase: Cardinal; confident: Boolean;
begin
  if M.Flag3934 = 0 then Exit;
  if M.Flag3934 >= 7 then
  begin
    M.ClsPhase := M.LastCtx mod M.ClsStride;
    M.MM7.Predict(M.ClsPhase, M.ClsBase, M.ClsNeg, M.ClsCtx);
    if MMDbg and (M.OutCount >= MMLo) and (M.OutCount <= MMHi) then
      WriteLn(ErrOutput, 'MMPRED2 count=', M.LastCtx, ' base=', M.ClsBase,
        ' ctx=', M.ClsCtx, ' neg=', M.ClsNeg, ' score=', M.MM7.PrevScore);
    Exit;
  end;
  if (M.Flag3934 = 5) or (M.Flag3934 = 6) then
  begin
    M.MM6.Predict(M.LastCtx, M.ClsBase, M.ClsCtx);
    if M.Flag3934 = 5 then
    begin
      M.ClsBase := Byte(M.ClsBase + $80);
      Dec(M.ClsCtx, 4);
    end;
    if MMDbg and (M.OutCount >= MMLo) and (M.OutCount <= MMHi) then
      WriteLn(ErrOutput, 'MMPRED count=', M.LastCtx, ' base=', M.ClsBase, ' ctx=', M.ClsCtx, ' best=', M.MM6.CandBest0,
        ' scores=', M.MM6.CandScore[0], ',', M.MM6.CandScore[1], ',', M.MM6.CandScore[2], ',', M.MM6.CandScore[3], ',', M.MM6.CandScore[4], ',', M.MM6.CandScore[5]);
    Exit;
  end;
  oldPhase := M.ClsPhase;
  if M.ClsStride <> 0 then
    M.ClsPhase := M.LastCtx mod M.ClsStride;
  M.ClsBase := Byte(M.RollCtx0 shr M.ClsShift);
  if M.Flag3934 = 3 then
  begin
    M.Cls3Index := M.LastCtx mod 6;
    confident := M.Cls3Confidence[M.Cls3Index] > 8;
    M.Cls3Pred[M.Cls3Index] := Byte((M.RollCtx0 and $FF) -
      (M.RollCtx0 shr 24) + M.ClsBase);
    M.Cls3Active := Ord(confident and (M.Cls3Streak < 5));
    if M.Cls3Active <> 0 then
    begin
      M.Cls3SavedNeg := M.ClsNeg;
      M.ClsCtx := $259 + (oldPhase shl 5);
      M.ClsNeg := 0;
      M.ClsBase := M.Cls3Pred[M.Cls3Index];
    end;
    if confident then Inc(M.Cls3Streak) else M.Cls3Streak := 0;
  end;
end;

procedure PpmPostSymbolMaintenance(var M: TPpmModel; Sym: Integer; Dl: Boolean);
begin
  RingStore(M, Sym);
  if Dl then
    MarkerMachine(M, Sym);
  RankMachinery(M, Sym);
  ClsDeltaUpdate(M, Sym);
  M.LastCtx := (M.LastCtx + 1) and M32;
  M.C54 := (M.C54 + 1) and M32;
  UpdateRollingCtx(M, Sym);
  ClsPhaseUpdate(M);
  RingRecompute(M);
end;

procedure PpmMatchMaintain(var M: TPpmModel; Sym: Integer; Dl: Boolean;
  Outp: PByte; var OutLen: Integer);
begin

  EmitDetransformed(M, Sym, Outp, OutLen);
  PpmPostSymbolMaintenance(M, Sym, Dl);
  PutWindow(M, Sym);
  AdvanceWin(M);
end;

procedure PrepareWpUpdate(var M: TPpmModel; Sym: Integer);
var
  delta, savedExcl, savedWork: Integer;
  d: TD390Result;
begin
  if (M.ByteClass = 0) or (not Bc1WpFireO) or (not M.WpArmed) then Exit;
  delta := (Sym - M.ClsBase) and $FF;
  if M.ClsNeg <> 0 then delta := (-delta) and $FF;
  savedExcl := M.NExcl;
  savedWork := M.WorkCtx;
  M.NExcl := 0;
  M.WorkCtx := $304 + M.Flag3934;
  d := D390_Update(M, M.ClsCtx, delta);
  if d.SseIdx >= 0 then M.SseProb[d.SseIdx] := d.SseVal;
  M.WpAccAdd := d.AccAdd;
  M.WpPend := True;
  M.NExcl := savedExcl;
  M.WorkCtx := savedWork;
end;

procedure PpmEmitAndMaintain(var M: TPpmModel; Sym: Integer;
  Outp: PByte; var OutLen: Integer;
  PbGate, Light, ClearS47, DecayC54: Boolean;
  RecordS47: Integer; Rec2Update, Rec2BeforeRecord: Boolean;
  RunRec1: Boolean = True);
var
  s47: Integer;
begin
  PutWindow(M, Sym);
  EmitDetransformed(M, Sym, Outp, OutLen);
  if PbGate then
    UpdatePredbyte(M, PpmCtxResolution(M), Sym);
  if DecayC54 then
    PpmLiteralDecayC54(M);
  if ClearS47 then
    M.S47 := 0;
  s47 := RecordS47;
  if s47 < 0 then s47 := 0;
  if Rec2Update and Rec2BeforeRecord then
  begin
    if Light then Rec2_ApplyLight(M, Sym) else Rec2_ApplyHeavy(M, Sym);
  end;
  if RunRec1 then
    Rec1_ApplyRecord(M, Sym, M.C38, s47);
  if Rec2Update and (not Rec2BeforeRecord) then
  begin
    if Light then Rec2_ApplyLight(M, Sym) else Rec2_ApplyHeavy(M, Sym);
  end;
  M.S45 := $FF;
  PrepareWpUpdate(M, Sym);
  PpmPostSymbolMaintenance(M, Sym, True);
  AdvanceWin(M);
end;

procedure PpmRec2ReweightPost(var M: TPpmModel; Sym: Integer;
  Outp: PByte; var OutLen: Integer; PbGate: Boolean);
begin
  M.S45 := $FF;
  M.S41 := 1;
  Rec1_ApplyRecord(M, Sym, M.C38, M.S47);
  Rec2_ApplyHeavy(M, Sym);

  PrepareWpUpdate(M, Sym);
  EmitDetransformed(M, Sym, Outp, OutLen);
  if PbGate then
    UpdatePredbyte(M, PpmCtxResolution(M), Sym);

  if M.ByteClass = 0 then PpmLiteralDecayC54(M);
  PpmPostSymbolMaintenance(M, Sym, True);
  PutWindow(M, Sym);
  AdvanceWin(M);
end;

procedure AdaptSse2Down(var M: TPpmModel; Sse2Idx: Integer);
var v: Cardinal;
begin
  if Sse2Idx < 0 then Exit;
  v := M.Sse2[Sse2Idx];
  M.Sse2[Sse2Idx] := (v - (v shr 6)) and M32;
end;

function C550SelectPath(const M: TPpmModel): Char;
var idx, age: Cardinal;
begin
  idx := (M.AgeCtr + 1) and $FF;
  age := (M.Age - M.AgeRing[idx]) and M32;
  if (age < $6D4250) or (age >= $FEFF01) then Exit('C');
  if age < $91ADC0 then Exit('B');
  Result := 'A';
end;

procedure ApplySseWrite(var M: TPpmModel; const D: TD390Result);
begin
  if D.SseIdx >= 0 then
    M.SseProb[D.SseIdx] := D.SseVal;
end;

procedure PpmC550Post(var M: TPpmModel; Ctx, Sym, KCtx: Integer;
  Outp: PByte; var OutLen: Integer; PbGate: Boolean; AgeIdx: Integer;
  Sse2Idx: Integer; KernelWeight: Cardinal; Sse2UpIdx: Integer;
  ExactOrderLoop: Boolean; WpCtx: Integer; WpDelta: Integer; WpFired: Boolean;
  WpBase: Integer; WpWork: Integer = $304; WpMirror: Boolean = False;
  WpArmed: Boolean = False; NfDecCtx: Integer = -1);
var
  path: Char;
  wpI: Integer;
  dEntry, dOrder0, dShadow: TD390Result;
  becEntry, becOrder0, becAge: Cardinal;
  v: Cardinal;
  oldS49: Byte;
  flag: Integer;
  takenCtx, takenSym, takenWc: Integer;
  entryDec: Integer;
  eb: Boolean;
  shadowCtx, shadowSym, shadowWc, shadowFlag: Integer;
begin

  if WpFired then
  begin
    flag := 0;
    takenCtx := WpCtx; takenSym := WpDelta; takenWc := WpWork;
    shadowCtx := Ctx;
    if EntryDecFlag and (NfDecCtx >= 0) then shadowCtx := NfDecCtx;
    shadowSym := Sym; shadowWc := $301; shadowFlag := 1;
  end
  else
  begin
    flag := 1;
    takenCtx := Ctx; takenSym := Sym; takenWc := $301;
    shadowCtx := WpCtx; shadowSym := WpDelta; shadowWc := WpWork; shadowFlag := 0;
  end;

  if EntryDecFlag and (not WpFired) and (NfDecCtx >= 0) then entryDec := NfDecCtx
  else entryDec := takenCtx;

  if RecABr then eb := (M.RecA[flag] <= M.RecB[flag])
  else eb := (KCtx = takenCtx);

  if Sse2UpIdx >= 0 then
  begin
    v := M.Sse2[Sse2UpIdx];
    M.Sse2[Sse2UpIdx] := (v + (($2000 - v) shr 6)) and M32;
  end;

  path := C550SelectPath(M);

  if M.Flag3943 <> 0 then
    if path = 'A' then M.WpKernelWeight := M.WpKernelWeight + $9240
    else M.WpKernelWeight := M.WpKernelWeight + KernelWeight;

  if path = 'A' then
  begin
    M.WorkCtx := takenWc;
    dEntry := D390_Update(M, entryDec, takenSym);
    ApplySseWrite(M, dEntry);
    M.Bec := dEntry.AccAdd;

    if not (RecFreeze and WpFired) then
    begin
      Recency_Update(M.RecB, flag, dEntry.AccAdd);
      Recency_Update(M.RecA, flag, dEntry.AccAdd);
    end;

    becAge := dEntry.AccAdd;
  end
  else if path = 'C' then
  begin
    M.WorkCtx := takenWc;
    dEntry := D390_Update(M, entryDec, takenSym);
    AdaptSse2Down(M, Sse2Idx);
    M.Bec := dEntry.AccAdd;
    ApplySseWrite(M, dEntry);
    M.Bec := KernelWeight;

    if not (RecFreeze and WpFired) then
    begin
      Recency_Update(M.RecB, flag, KernelWeight);
      Recency_Update(M.RecA, flag, KernelWeight);
    end;
    becAge := KernelWeight;
  end
  else if KCtx = takenCtx then
  begin
    M.WorkCtx := takenWc;
    dEntry := D390_Update(M, entryDec, takenSym);
    AdaptSse2Down(M, Sse2Idx);
    M.WorkCtx := $302 + flag;
    dOrder0 := D390_Update(M, $200, takenSym);
    becEntry := KernelWeight;
    becOrder0 := dOrder0.AccAdd;
  end
  else
  begin
    M.WorkCtx := $302 + flag;
    dOrder0 := D390_Update(M, $200, takenSym);
    AdaptSse2Down(M, Sse2Idx);
    M.WorkCtx := takenWc;
    dEntry := D390_Update(M, entryDec, takenSym);

    if RecABr and (M.RecA[flag] <= M.RecB[flag]) then
    begin

      becEntry := KernelWeight;
      becOrder0 := dOrder0.AccAdd;
    end
    else
    begin
      becEntry := dEntry.AccAdd;
      becOrder0 := KernelWeight;
    end;
  end;

  if ExactOrderLoop then
    M.S45 := 2;

  if (path <> 'C') and (path <> 'A') then
  begin

    if KCtx = takenCtx then
    begin
      M.Bec := dOrder0.AccAdd;
      ApplySseWrite(M, dOrder0);
      ApplySseWrite(M, dEntry);
    end
    else
    begin
      M.Bec := dEntry.AccAdd;
      ApplySseWrite(M, dEntry);
      ApplySseWrite(M, dOrder0);
    end;
    if ExactOrderLoop and (KCtx = takenCtx) then
      M.Bec := KernelWeight;

    if not (RecFreeze and WpFired) then
    begin
      Recency_Update(M.RecA, flag, becEntry);
      Recency_Update(M.RecB, flag, becOrder0);
    end;
    becAge := KernelWeight;
  end;

  AgeRing_Commit(M, AgeIdx, becAge);

  if WpFired then
    for wpI := 0 to M.NExcl - 1 do
      if WpMirror then M.Excl[wpI] := Byte((WpBase - M.Excl[wpI]) and $FF)
      else M.Excl[wpI] := Byte((M.Excl[wpI] + WpBase) and $FF);

  if (M.ByteClass <> 0) and Bc1WpFireO then
  begin

    if not WpFired then
      for wpI := 0 to M.NExcl - 1 do
        if WpMirror then M.Excl[wpI] := Byte((WpBase - M.Excl[wpI]) and $FF)
        else M.Excl[wpI] := Byte((M.Excl[wpI] - WpBase) and $FF);
    M.WorkCtx := shadowWc;
    dShadow := D390_Update(M, shadowCtx, shadowSym);
    if PostDbg and (OutLen >= PostLo) and (OutLen <= PostHi) then
      writeln(ErrOutput, 'SH outLen=', OutLen, ' fired=', WpFired, ' path=', path,
        ' takenCtx=', IntToHex(takenCtx,3), ' takenSym=', takenSym,
        ' takenWc=', IntToHex(takenWc,3), ' flag=', flag,
        ' | shadowCtx=', IntToHex(shadowCtx,3), ' shadowSym=', shadowSym,
        ' shadowWc=', IntToHex(shadowWc,3), ' shadowFlag=', shadowFlag,
        ' acc=', dShadow.AccAdd, ' nexcl=', M.NExcl,
        ' excl0=', M.Excl[0], ' wpBase=', WpBase, ' wpMirror=', WpMirror, ' wpFired=', WpFired);
    ApplySseWrite(M, dShadow);

    PrepareWpUpdate(M, Sym);

    M.WpPend := WpArmed;

    if not (RecFreeze and WpFired) then
    begin
      Recency_Update(M.RecA, shadowFlag, dShadow.AccAdd);
      Recency_Update(M.RecB, shadowFlag, dShadow.AccAdd);
    end;

    M.WorkCtx := shadowWc;
    ApplyT268(M, shadowSym, shadowCtx);
    if not WpFired then
      for wpI := 0 to M.NExcl - 1 do
        if WpMirror then M.Excl[wpI] := Byte((WpBase - M.Excl[wpI]) and $FF)
        else M.Excl[wpI] := Byte((M.Excl[wpI] + WpBase) and $FF);
  end;

  Rec1_ApplyRecord(M, Sym, M.C38, M.S47);

  if ((M.ByteClass = 0) and (not ExactOrderLoop)) or (M.S41 <> 0) then
  begin
    oldS49 := M.S49;
    Rec2_ApplyHeavy(M, Sym);
    if oldS49 = 0 then
      M.S49 := oldS49;
  end;

  if (path = 'C') or (path = 'A') then
  begin
    M.WorkCtx := takenWc;
    ApplyT268(M, takenSym, entryDec);
  end
  else
    ApplyLiteralUpdates(M, entryDec, takenWc, takenSym);
  if ExactOrderLoop then
    M.S45 := $FF;

  PutWindow(M, Sym);
  EmitDetransformed(M, Sym, Outp, OutLen);
  if PbGate then

    UpdatePredbyte(M, Ctx, Sym);
  PpmPostSymbolMaintenance(M, Sym, True);
  AdvanceWin(M);
end;

initialization
  RecFreeze := GetEnvironmentVariable('X_RECFREEZE') <> '';
  EntryDecFlag := GetEnvironmentVariable('X_ENTRYDEC_OFF') = '';
  EmptyEntry := GetEnvironmentVariable('X_EMPTYENTRY') <> '';
  RecBKern := GetEnvironmentVariable('X_RECBKERN') <> '';
  RecABr := GetEnvironmentVariable('X_RECABR_OFF') = '';

  PostDbg := GetEnvironmentVariable('PPM_POSTDBG') <> '';
  if PostDbg then
  begin
    PostLo := StrToIntDef(Copy(GetEnvironmentVariable('PPM_POSTDBG'), 1,
                Pos(':', GetEnvironmentVariable('PPM_POSTDBG')) - 1), 0);
    PostHi := StrToIntDef(Copy(GetEnvironmentVariable('PPM_POSTDBG'),
                Pos(':', GetEnvironmentVariable('PPM_POSTDBG')) + 1, 20), MaxInt);
  end;
  Bc1WpFireO := GetEnvironmentVariable('PPM_WPFIRE') <> '0';
  MMDbg := GetEnvironmentVariable('PPM_MMDBG') <> '';
  MMLo := StrToIntDef(Copy(GetEnvironmentVariable('PPM_MMDBG'), 1,
    Pos(':', GetEnvironmentVariable('PPM_MMDBG')) - 1), 81770);
  MMHi := StrToIntDef(Copy(GetEnvironmentVariable('PPM_MMDBG'),
    Pos(':', GetEnvironmentVariable('PPM_MMDBG')) + 1, 20), 81790);

end.
