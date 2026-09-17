unit uha_ppm_mm7;
{$mode delphi}{$H+}{$Q-}{$R-}

interface

type
  TPpmMM7 = record
    Hist, Coef: array[0..3, 0..4] of LongInt;
    Last, Delta: array[0..3] of LongInt;
    Acc: array[0..3, 0..10] of Cardinal;
    Cost, LastCost, PriorCost, PriorLastCost, Counter: array[0..3] of Cardinal;
    Hash, Hash74, Hash78: array[0..3] of Cardinal;
    Direction: array[0..3] of Byte;
    GlobalDelta, DelayedDelta, PrevScore: LongInt;
    SampleClass: Byte;
    procedure Reset(Cls: Byte);
    procedure Update(Slot: Cardinal; OutByte, DeltaByte, Neg: Byte);
    procedure Predict(Slot: Cardinal; out BaseByte, Neg: Byte; out Context: Cardinal);
  end;

implementation

uses uha_ppm_statics;

function SignedByte(B: Byte): LongInt; inline;
begin
  Result := B;
  if B >= $80 then Dec(Result, $100);
end;

function Distance(V: LongInt): Cardinal; inline;
begin
  Result := V and $FFF;
  if Result > $800 then Result := $1000 - Result;
end;

procedure TPpmMM7.Reset(Cls: Byte);
var S: Integer;
begin
  FillChar(Self, SizeOf(Self), 0);
  SampleClass := Cls;
  for S := 0 to 3 do
  begin
    Hash[S] := $FFFFFFFF;
    Hash74[S] := $FFFFFFFF;
    Hash78[S] := $FFFFFFFF;
  end;
end;

procedure TPpmMM7.Update(Slot: Cardinal; OutByte, DeltaByte, Neg: Byte);
var S, I, K, C, Bound: Integer; OutS, BaseVal, H: LongInt; MinV: Cardinal;
begin
  S := Slot and 3;
  Direction[S] := Neg;
  if SampleClass = 7 then OutS := Integer(OutByte) - $80
  else OutS := SignedByte(OutByte);
  BaseVal := SignedByte(Byte(PrevScore - OutS)) shl 4;
  Inc(Acc[S, 0], Distance(BaseVal));
  for I := 0 to 4 do
  begin
    if I = 4 then H := GlobalDelta else H := Hist[S, I];
    Inc(Acc[S, I * 2 + 1], Distance(BaseVal - H));
    Inc(Acc[S, I * 2 + 2], Distance(BaseVal + H));
  end;
  Inc(Cost[S], AlzMMCost[Byte(PrevScore - OutS)]);
  Inc(LastCost[S], AlzMMCost[Byte(Last[S] - OutS)]);
  Delta[S] := SignedByte(Byte(OutS - Last[S]));
  GlobalDelta := Delta[S];
  Inc(Counter[S]);
  Last[S] := OutS;
  if (Counter[S] and $F) = 0 then
  begin
    MinV := Acc[S, 0]; K := 0; Acc[S, 0] := 0;
    for I := 1 to 10 do
    begin
      if MinV > Acc[S, I] then begin MinV := Acc[S, I]; K := I; end;
      Acc[S, I] := 0;
    end;
    if K <> 0 then
    begin
      C := (K - 1) div 2;
      Bound := C;
      if C = 4 then Bound := 3;
      if (K and 1) <> 0 then
      begin
        if Coef[S, Bound] > -$20 then Dec(Coef[S, C]);
      end
      else if Coef[S, Bound] < $20 then Inc(Coef[S, C]);
    end;
    if (Counter[S] and $FF) = 0 then
    begin
      Dec(Cost[S], PriorCost[S]); PriorCost[S] := Cost[S];
      Dec(LastCost[S], PriorLastCost[S]); PriorLastCost[S] := LastCost[S];
    end;
  end;
  if SampleClass = 9 then
  begin
    GlobalDelta := DelayedDelta;
    DelayedDelta := Delta[S];
  end;
  Hash[S] := (Hash[S] shl 8) + DeltaByte;
  if SampleClass = 7 then
  begin
    Hash74[S] := (Hash74[S] shl 8) + Cardinal(AlzS7BankC[DeltaByte]);
    Hash78[S] := (Hash78[S] shl 8) + Cardinal(AlzS7BankD[DeltaByte]);
  end;
end;

procedure TPpmMM7.Predict(Slot: Cardinal; out BaseByte, Neg: Byte; out Context: Cardinal);
var S: Integer; H1, H2, NewH1, Score: LongInt;
begin
  S := Slot and 3;
  H1 := Hist[S, 1]; H2 := Hist[S, 2];
  NewH1 := Delta[S] - Hist[S, 0];
  Score := (Last[S] shl 4) + Coef[S, 0] * Delta[S]
    + Coef[S, 1] * NewH1 + Coef[S, 2] * H1 + Coef[S, 3] * H2
    + Coef[S, 4] * GlobalDelta;
  Hist[S, 3] := H2; Hist[S, 2] := H1;
  Hist[S, 1] := NewH1; Hist[S, 0] := Delta[S];
  PrevScore := Score div 16;
  if Cost[S] > LastCost[S] then BaseByte := Byte(Last[S])
  else BaseByte := Byte(PrevScore);
  if SampleClass = 7 then
  begin
    BaseByte := Byte(BaseByte + $80);
    Context := $2F1 + Cardinal(S);
    if Hash[S] = 0 then Inc(Context, 2)
    else if Hash74[S] = 0 then Inc(Context, 4)
    else if Hash78[S] = 0 then Inc(Context, 6);
  end
  else if SampleClass = 8 then
  begin
    Context := $2F9 + Cardinal(S);
    if Hash[S] = 0 then Context := $2FB;
  end
  else
  begin
    Context := $2FC + Cardinal(S);
    if Hash[S] = 0 then Context := $300;
  end;
  Neg := Direction[S];
end;

end.
