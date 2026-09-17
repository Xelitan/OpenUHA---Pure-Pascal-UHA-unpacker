
function TAlzDecoder.BMGetThreshold(Total: Cardinal): Cardinal;
begin
  Rc.Range := Rc.Range div Total;
  Result := Rc.Code div Rc.Range;
end;

procedure TAlzDecoder.BMRemove(Low, Width: Cardinal);
begin
  Rc.Code := Cardinal(Rc.Code - Low * Rc.Range);
  Rc.Range := Cardinal(Rc.Range * Width);
  Rc.Normalize;
end;

procedure TAlzDecoder.BMSse(Width, Total: Cardinal);
var Idx: Cardinal;
begin
  Idx := ((Width and $FFFF) shl 14) div Total;
  BMMixer := Cardinal(BMMixer + AlzSseMap[Idx]);
end;

procedure TAlzDecoder.BMFenwickAdd(Ctx, Sym: Integer; Step: Word);
var Al: Integer;
begin
  Al := (Sym + 1) and $FF;
  while Al <> 0 do
  begin
    BMTree[Ctx, Al] := Word(BMTree[Ctx, Al] + Step);
    Al := (Al + (Al and (-Al and $FF))) and $FF;
  end;
  BMTree[Ctx, 0] := Word(BMTree[Ctx, 0] + Step);
end;

procedure TAlzDecoder.BMRebuildFenwick(Ctx: Integer);
var S, I: Integer;
begin
  for I := 0 to 255 do BMTree[Ctx, I] := 0;
  for S := 0 to 255 do
    if BMFreq[Ctx, S] <> 0 then BMFenwickAdd(Ctx, S, BMFreq[Ctx, S]);
end;

function TAlzDecoder.BMCtxTotal(C: Integer): Word;
begin
  Result := BMTree[C, 0];
  if BMFlag <> 0 then
    Result := Word(Result - BMFreq[C, BMPredB]);
end;

function TAlzDecoder.BMInContext(C: Integer; Bx, Threshold, SseTotal: Cardinal): Integer;
var
  Rem, Step, NodeVal, High, Low, FSym, PredFreq: Cardinal;
  BaseIdx, Sym, EbpIdx: Integer;
  PredActive: Boolean;
begin
  Rem := (Bx - Threshold) and $FFFF;
  BaseIdx := 0; Step := $80;
  PredActive := BMFlag <> 0;
  EbpIdx := 0; PredFreq := 0;
  if PredActive then
  begin
    EbpIdx := BMPredB;
    PredFreq := BMFreq[C, BMPredB];
  end;
  while Step <> 0 do
  begin
    if PredActive and ((BaseIdx + Step) > Cardinal(EbpIdx)) then
    begin
      NodeVal := BMTree[C, BaseIdx + Step];
      if NodeVal < ((Rem + PredFreq) and $FFFFFFFF) then
      begin
        BaseIdx := BaseIdx + Step;
        Rem := (Rem - ((NodeVal - PredFreq) and $FFFF)) and $FFFF;
        PredActive := False;
      end;
    end
    else
    begin
      NodeVal := BMTree[C, BaseIdx + Step];
      if Rem > NodeVal then
      begin
        BaseIdx := BaseIdx + Step;
        Rem := (Rem - NodeVal) and $FFFF;
      end;
    end;
    Step := Step shr 1;
  end;
  Sym := BaseIdx;
  High := (Rem + Threshold) and $FFFF;
  FSym := BMFreq[C, Sym];
  Low := (High - FSym) and $FFFFFFFF;
  BMSse((High - Low) and $FFFFFFFF, SseTotal);
  BMRemove(Low, (High - Low) and $FFFFFFFF);
  Result := Sym;
end;

function TAlzDecoder.BMDecodeFromContexts(Ctx, Ctx2: Integer): Integer;
var
  Bx, Combined, Threshold, EscTotal, Th2, Acc, Stp, Bx2: Cardinal;
  S: Integer;
  ExclSum: Cardinal;
  Known: array[0..255] of Boolean;
begin
  Bx := BMCtxTotal(Ctx);
  if Bx <> 0 then
  begin
    Combined := (Bx + BMEW[Ctx]) and $FFFF;
    Threshold := BMGetThreshold(Combined);
    if Threshold < Bx then
    begin
      Result := BMInContext(Ctx, Bx, Threshold, Combined);
      Exit;
    end;

    BMSse((Combined - Bx) and $FFFFFFFF, Combined);
    BMRemove(Bx, (Combined - Bx) and $FFFFFFFF);
    ExclSum := 0;
    for S := 0 to 255 do
    begin
      Known[S] := (BMFreq[Ctx, S] <> 0) or ((BMFlag <> 0) and (S = BMPredB));
      if Known[S] then ExclSum := ExclSum + BMFreq[Ctx2, S];
    end;
    EscTotal := (BMTree[Ctx2, 0] - ExclSum) and $FFFF;
    if EscTotal = 0 then begin Rc.Corrupt := True; Result := 0; Exit; end;
    Th2 := BMGetThreshold(EscTotal);
    Acc := 0;
    for S := 255 downto 0 do
    begin
      if Known[S] then Continue;
      Stp := BMFreq[Ctx2, S];
      if Th2 < Acc + Stp then
      begin
        BMSse(Stp, EscTotal);
        BMRemove(Acc, Stp);
        Result := S; Exit;
      end;
      Acc := (Acc + Stp) and $FFFF;
    end;
    Rc.Corrupt := True; Result := 0;
  end
  else
  begin
    Bx2 := BMCtxTotal(Ctx2);
    if Bx2 = 0 then begin Rc.Corrupt := True; Result := 0; Exit; end;
    Threshold := BMGetThreshold(Bx2);
    Result := BMInContext(Ctx2, Bx2, Threshold, Bx2);
  end;
end;

procedure TAlzDecoder.BMRescaleEntry(Ctx: Integer);
var S: Integer; NewEw: Word; Total: Cardinal;
begin
  for S := 0 to 255 do
    if BMFreq[Ctx, S] > $10 then BMFreq[Ctx, S] := BMFreq[Ctx, S] shr 1
    else BMFreq[Ctx, S] := 0;
  BMRebuildFenwick(Ctx);
  NewEw := (BMEW[Ctx] + 1) shr 1;
  BMEW[Ctx] := NewEw;
  Total := BMTree[Ctx, 0];
  if Ctx < $300 then BMCounter[Ctx] := (Total + NewEw) shl 6
  else BMCounter[Ctx] := (Total + NewEw) shl 8;
end;

procedure TAlzDecoder.BMRescaleCtx2(Ctx: Integer);
var S: Integer;
begin
  for S := 0 to 255 do BMFreq[Ctx, S] := (BMFreq[Ctx, S] + 1) shr 1;
  BMRebuildFenwick(Ctx);
end;

procedure TAlzDecoder.BMEscapeIncrement(InnerCtx, Sym: Integer);
var Ctx2: Integer; Step2: Word;
begin
  Ctx2 := BMEscCtx;
  Step2 := AlzEscStep[InnerCtx];
  BMFreq[Ctx2, Sym] := Word(BMFreq[Ctx2, Sym] + Step2);
  BMFenwickAdd(Ctx2, Sym, Step2);
  if BMTree[Ctx2, 0] >= $4000 then BMRescaleCtx2(Ctx2);
end;

procedure TAlzDecoder.BMUpdate(Ctx, Sym: Integer);
var Step1, Step2: Word; NewCtr: Cardinal; NewSym: Boolean; Ctx2: Integer;
begin
  Ctx2 := BMEscCtx;
  Step1 := AlzEntryStep[Ctx];
  Step2 := AlzEscStep[Ctx];
  NewCtr := Cardinal(BMCounter[Ctx] - (BMFreq[Ctx, Sym] + BMEW[Ctx]));
  NewSym := BMFreq[Ctx, Sym] = 0;
  if NewSym then
  begin
    BMFreq[Ctx2, Sym] := Word(BMFreq[Ctx2, Sym] + Step2);
    BMFenwickAdd(Ctx2, Sym, Step2);
    if BMTree[Ctx2, 0] >= $4000 then BMRescaleCtx2(Ctx2);
    BMEW[Ctx] := Word(BMEW[Ctx] + Step1);
  end;
  BMFreq[Ctx, Sym] := Word(BMFreq[Ctx, Sym] + Step1);
  BMFenwickAdd(Ctx, Sym, Step1);
  BMCounter[Ctx] := NewCtr;
  if ((BMEW[Ctx] + BMTree[Ctx, 0]) >= $4000) or ((NewCtr and $80000000) <> 0) then
    BMRescaleEntry(Ctx);
end;

function TAlzDecoder.BMTotalOfFor(C: Integer): Cardinal;
begin
  Result := BMTree[C, 0];
  if C < $3F9 then Result := (Result + BMEW[C]) and $FFFF;
  if BMFlag <> 0 then Result := (Result - BMFreq[C, BMPredB]) and $FFFF;
end;

function TAlzDecoder.BMKnownMap(C, Sym: Integer; ExcludeCtx: Integer): Cardinal;
var T: Cardinal; S: Integer;
begin
  T := BMTree[C, 0];
  if C < $3F9 then T := (T + BMEW[C]) and $FFFF;
  if ExcludeCtx >= 0 then
    for S := 0 to 255 do
      if BMFreq[ExcludeCtx, S] <> 0 then T := (T - BMFreq[C, S]) and $FFFF;

  if (BMFlag <> 0) and
     ((ExcludeCtx < 0) or (BMFreq[ExcludeCtx, BMPredB] = 0)) then
    T := (T - BMFreq[C, BMPredB]) and $FFFF;
  if T = 0 then begin Result := 0; Exit; end;
  Result := AlzSseMap[(Cardinal(BMFreq[C, Sym]) shl 14) div T];
end;

function TAlzDecoder.BMSseEval(Ctx, Sym: Integer): Cardinal;
var Tot0, TAdj, Ewc: Cardinal; Ctx2: Integer;
begin
  if BMFreq[Ctx, Sym] <> 0 then
  begin
    Result := BMKnownMap(Ctx, Sym, -1); Exit;
  end;
  Tot0 := BMTree[Ctx, 0]; TAdj := Tot0;
  if BMFlag <> 0 then TAdj := (TAdj - BMFreq[Ctx, BMPredB]) and $FFFF;
  Ctx2 := BMEscCtx;
  if TAdj <> 0 then
  begin
    Ewc := BMEW[Ctx];
    Result := Cardinal(AlzSseMap[(Ewc shl 14) div ((Ewc + TAdj) and $FFFFFFFF)]
                       + BMKnownMap(Ctx2, Sym, Ctx));
  end
  else
    Result := BMKnownMap(Ctx2, Sym, -1);
end;

procedure TAlzDecoder.BMPredTail(Mixer: Cardinal; DoAcc80, DoAcc90: Boolean);
begin
  if DoAcc80 then
  begin
    BMTable[BMPCounter] := Mixer;
    BMAcc80 := Cardinal(BMAcc80 + Mixer);
  end;
  if DoAcc90 then
    BMAcc90 := Cardinal(((BMAcc90 * 31) shr 5) + Mixer);
  BMAcc8c := Cardinal(((BMAcc8c * 31) shr 5) + Mixer);
end;

function TAlzDecoder.BMDecodeLiteral(Ctx, Ctx2: Integer): Integer;
var Acc, DecodeMix, Sec: Cardinal; Sym, SavedFlag, SseSym: Integer;

  function SsePredSym(RawSym: Integer): Integer;
  begin
    if State.BMSideActive then
    begin
      if State.SideDir = 0 then Result := Byte(State.SideBias + RawSym)
      else Result := Byte(State.SideBias - RawSym);
    end
    else
      Result := RawSym;
  end;

begin
  BMEscCtx := Ctx2;
  BMPCounter := (BMPCounter + 1) and $FF;
  Acc := Cardinal(BMAcc80 - BMTable[BMPCounter]);
  BMAcc80 := Acc; BMMixer := 0;
  SavedFlag := BMFlag;
  if (Acc < $6D4250) or (Acc >= $FEFF01) then
  begin

    Sym := BMDecodeFromContexts(Ctx, Ctx2);
    DecodeMix := BMMixer;
    BMUpdate(Ctx, Sym);
    BMPredTail(DecodeMix, True, True);
  end
  else if Acc < $91ADC0 then
  begin
    if BMAcc90 >= BMAcc8c then
    begin

      Sym := BMDecodeFromContexts(Ctx, Ctx2);
      DecodeMix := BMMixer;
      BMMixer := 0; BMEscCtx := $402; BMFlag := 0;
      SseSym := SsePredSym(Sym);
      Sec := BMSseEval($300, SseSym);
      BMEscapeIncrement($300, SseSym);
      BMAcc90 := Cardinal(((BMAcc90 * 31) shr 5) + Sec);
      BMEscCtx := Ctx2;
      BMUpdate(Ctx, Sym);
      BMPredTail(DecodeMix, True, False);
    end
    else
    begin

      BMFlag := 0; BMEscCtx := $402;
      Sym := BMDecodeFromContexts($300, $402);
      DecodeMix := BMMixer;
      BMTable[BMPCounter] := DecodeMix;
      BMAcc80 := Cardinal(BMAcc80 + DecodeMix);
      BMFlag := SavedFlag;
      BMEscCtx := Ctx2;
      BMMixer := 0;
      if State.BMSideActive then
      begin
        if State.SideDir = 0 then SseSym := Byte(Sym - State.SideBias)
        else SseSym := Byte(State.SideBias - Sym);
      end
      else
        SseSym := Sym;
      Sec := BMSseEval(Ctx, SseSym);
      BMEscCtx := $402;
      BMEscapeIncrement($300, Sym);
      BMAcc90 := Cardinal(((BMAcc90 * 31) shr 5) + DecodeMix);
      BMEscCtx := Ctx2;
      BMUpdate(Ctx, SseSym);
      BMPredTail(Sec, False, False);
      Sym := SseSym;
    end;
  end
  else
  begin

    Sym := BMGetThreshold($100) and $FF;
    BMRemove(Sym, 1);
    BMMixer := 0;
    DecodeMix := BMSseEval(Ctx, Sym);
    BMUpdate(Ctx, Sym);
    BMPredTail(DecodeMix, True, True);
  end;
  Result := Sym;
end;

procedure TAlzDecoder.ResetByteModel;
var C, S: Integer;
begin
  for C := 0 to BM_NCTX-1 do
  begin
    for S := 0 to 255 do begin BMTree[C, S] := 0; BMFreq[C, S] := 0; end;
    BMEW[C] := 1;
    BMCounter[C] := 16384;
  end;

  for C := $301 to $3F8 do BMCounter[C] := 256;
  for C := $3F9 to $400 do
  begin
    for S := 0 to 255 do BMFreq[C, S] := 2;
    BMRebuildFenwick(C); BMEW[C] := 0;
  end;
  for C := $401 to BM_NCTX-1 do
  begin
    for S := 0 to 255 do BMFreq[C, S] := 4;
    BMRebuildFenwick(C); BMEW[C] := 0;
  end;
  BMMixer := 0; BMAcc80 := $91ADC0; BMAcc8c := 0; BMAcc90 := 0;
  for C := 0 to 255 do BMTable[C] := 37440;
  BMPCounter := 255; BMFlag := 0; BMPredB := 0; BMEscCtx := 0;
end;
