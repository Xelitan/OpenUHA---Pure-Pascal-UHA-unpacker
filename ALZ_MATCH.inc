
procedure TAlzDecoder.ResetMatchModel;
var I: Integer;
begin
  for I := 0 to High(MSlotShort) do MSlotShort[I] := InitProb;
  for I := 0 to High(MSlotLong) do MSlotLong[I] := InitProb;
  MLowBit := InitProb;
  for I := 0 to High(MLength) do MLength[I] := InitProb;
  FillChar(MLenPred, SizeOf(MLenPred), 0);
end;

function TAlzDecoder.MDistSlot(var ProbArr: array of Word; const Trans: array of Byte;
  InitState, Fallback: Integer): Integer;
var State, Slot, Branch: Integer;
begin
  State := InitState; Slot := Fallback;
  while State <> 0 do
  begin
    if Rc.DecodeBitFast12Shift(ProbArr[State], 6) = 0 then Slot := State;
    if Slot > State then Branch := 1 else Branch := 0;
    State := Trans[2*State + Branch];
  end;
  Result := Slot;
end;

function TAlzDecoder.MUniform(Total: Cardinal): Cardinal;
begin
  if Total = 0 then begin Result := 0; Exit; end;
  Result := Rc.DecodeUniform(Total);
end;

function TAlzDecoder.MClass1Dist: Cardinal;
var
  Slot, K, LowBit, NBlocks: Integer;
  Base, Span, Limit, Extra, V: Cardinal;
begin
  Slot := MDistSlot(MSlotLong, AlzFullDistanceNext, $10, $2C);
  K := Slot - 1;
  Base := AlzDistanceBase[K];
  if K = 0 then begin Result := Base; Exit; end;
  Span := AlzDistanceSpan[K];
  Limit := State.OutputPos;
  if Base + Span - 1 > Limit then Span := Limit - Base + 1;
  LowBit := -1; Extra := 0;
  if Span >= 4 then
  begin
    LowBit := Rc.DecodeBitFast12Shift(MLowBit, 6);
    Span := Span shr 1;
  end;
  if Span > $800 then
  begin
    NBlocks := ((Span - 1) shr 11) + 1;
    V := MUniform(NBlocks);
    Extra := Extra + (V shl 11);
    if NBlocks <> Integer(V) + 1 then Span := $800 else Span := Span - (V shl 11);
  end;
  if Span >= 2 then Extra := Extra + MUniform(Span);
  if LowBit <> -1 then Extra := Extra * 2 + Cardinal(LowBit);
  Result := Base + Extra;
end;

function TAlzDecoder.MLengthDecode(Cls: Integer; Dist: Cardinal): Integer;
var
  EdiState, M, Eax, Esi, Last, B, PredByte, Sec: Integer;
  Rep, Mask, Pos, Ctx, PredPtr, Addr, B0, B1: Cardinal;
  HasPred: Boolean;
begin
  EdiState := 2; PredByte := 0; Sec := 0; PredPtr := 0; HasPred := False;
  if Cls = 1 then
  begin
    if Dist < $100 then M := 0
    else if Dist < $1000 then M := 1
    else if Dist < $10000 then M := 2
    else if Dist < $100000 then M := 3
    else M := 4;
    EdiState := M + 3; Eax := M;
  end
  else
  begin
    Rep := State.RepeatRun; Eax := 5;
    if Rep <> 0 then
      if Rep > 2 then Eax := 7 else Eax := 6;
  end;
  if (Eax <= 5) and (Dist > 1) then
  begin
    Mask := Mode.DictionaryMask; Pos := State.WindowPos;
    B0 := Window[(Pos - Dist) and Mask];
    B1 := Window[(Pos - Dist + 1) and Mask];
    Ctx := (B0 shl 8) or B1;
    if Eax = 5 then Ctx := Ctx + $10000;
    PredPtr := Ctx; HasPred := True;
    PredByte := MLenPred[PredPtr];
    Sec := MLenPred[PredPtr + $20000];
    MLenPred[PredPtr + $20000] := Byte(PredByte);
  end;
  Esi := 10; Last := Esi + 1;
  while True do
  begin
    Last := Esi + 1;
    if EdiState < Esi + 1 then
    begin
      Addr := Cardinal(Eax) * 1024;
      if Esi >= PredByte then Addr := Addr + 256;
      if Sec <= Esi then Addr := Addr + 512;
      Addr := Addr + Cardinal(Esi);
      if Rc.DecodeBitFast12Shift(MLength[Addr], 5) = 0 then Last := Esi;
    end;
    if Esi < Last then B := 1 else B := 0;
    Esi := AlzLengthNext[2*Esi + B];
    if Esi = 0 then Break;
  end;
  Result := Last and $FF;
  if HasPred then MLenPred[PredPtr] := Byte(Result);
end;

function TAlzDecoder.MDecodeMatch(Token: Integer; var Dist, Count: Cardinal): Boolean;
var
  SlotMark, Slot, Idx, I: Integer;
  Rep: Cardinal;
begin
  if Token = 1 then
  begin
    Dist := MClass1Dist; SlotMark := $FF;
  end
  else if Token = 2 then
  begin
    Dist := State.RecentDistance[0]; SlotMark := 0;
  end
  else
  begin
    Slot := MDistSlot(MSlotShort, AlzShortDistanceNext, 1, $B);
    Dist := State.RecentDistance[Slot]; SlotMark := Slot;
  end;
  Count := Cardinal(MLengthDecode(Token, Dist));

  Rep := State.RepeatRun;
  if (Dist > 1) or (Rep > 1) then
    if SlotMark <> 0 then
    begin
      if SlotMark = $FF then Idx := 11 else Idx := SlotMark;
      for I := Idx downto 1 do State.RecentDistance[I] := State.RecentDistance[I-1];
      State.RecentDistance[0] := Dist;
    end;

  Result := not Rc.Corrupt;
end;
