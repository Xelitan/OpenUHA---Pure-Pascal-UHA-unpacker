unit uha_ppm_mm6;
{$mode delphi}{$H+}{$Q-}{$R-}
interface

type
  TPpmMM6 = record
    MMHist, MMCoef: array[0..0, 0..4] of LongInt;
    MMLast, MMDelta: array[0..0] of LongInt;
    MMAcc: array[0..0, 0..10] of LongInt;
    MMCounter: array[0..0] of Cardinal;
    SlotHash, SlotHash74, SlotHash78: array[0..0] of Cardinal;
    CandAcc: array[0..123] of LongInt;
    DeltaRing: array[0..127] of LongInt;
    CandScore: array[0..5] of LongInt;
    CandBest0, CandBest1, CandBest2, CandCur, CandPrev: LongInt;
    ResBank: array[0..5, 0..256] of LongInt;
    procedure Reset;
    procedure Update(OutByte, DeltaByte: Byte; Position: Cardinal);
    procedure Predict(Position: Cardinal; out BaseByte: Byte; out Context: Cardinal);
  end;
implementation

uses uha_ppm_statics;

const
{$I ALZ_CAND.inc}
procedure TPpmMM6.Reset;
begin
  FillChar(Self, SizeOf(Self), 0);
  CandBest2 := 2;
  SlotHash[0] := $FFFFFFFF;
  SlotHash74[0] := $FFFFFFFF;
  SlotHash78[0] := $FFFFFFFF;
end;
function AlzMMW(V: LongInt): LongInt;
var i: LongInt;
begin
  i := V and $FFF;
  if i <= $800 then Result := i else Result := $1000 - i;
end;

function AlzSExt8(B: Byte): LongInt; inline;
begin
  if (B and $80) <> 0 then Result := LongInt(B) - 256 else Result := B;
end;

procedure TPpmMM6.Update(OutByte, DeltaByte: Byte; Position: Cardinal);
var
  OutS, BaseVal, RingDelta, MinV, V, Sum, D1, D2, D3, EdiMin: LongInt;
  I, K, A, Cnt, RingPos, Bv, GCnt: Integer;
  Res: array[0..5] of LongInt;
begin

  GCnt := Integer(Position);
  OutS := AlzSExt8(OutByte);
  RingDelta := OutS - CandCur;
  BaseVal := AlzSExt8(Byte(CandScore[3] - OutS)) shl 4;

  MMAcc[0,0]  := MMAcc[0,0]  + AlzMMW(BaseVal);
  MMAcc[0,1]  := MMAcc[0,1]  + AlzMMW(BaseVal - MMHist[0,0]);
  MMAcc[0,2]  := MMAcc[0,2]  + AlzMMW(BaseVal + MMHist[0,0]);
  MMAcc[0,3]  := MMAcc[0,3]  + AlzMMW(BaseVal - MMHist[0,1]);
  MMAcc[0,4]  := MMAcc[0,4]  + AlzMMW(BaseVal + MMHist[0,1]);
  MMAcc[0,5]  := MMAcc[0,5]  + AlzMMW(BaseVal - MMHist[0,2]);
  MMAcc[0,6]  := MMAcc[0,6]  + AlzMMW(BaseVal + MMHist[0,2]);
  MMAcc[0,7]  := MMAcc[0,7]  + AlzMMW(BaseVal - MMHist[0,3]);
  MMAcc[0,8]  := MMAcc[0,8]  + AlzMMW(BaseVal + MMHist[0,3]);
  MMAcc[0,9]  := MMAcc[0,9]  + AlzMMW(BaseVal - MMHist[0,4]);
  MMAcc[0,10] := MMAcc[0,10] + AlzMMW(BaseVal + MMHist[0,4]);

  Inc(MMCounter[0]);
  MMDelta[0] := AlzSExt8(Byte(OutS - MMLast[0]));
  MMLast[0] := OutS;

  if (MMCounter[0] and $F) = 0 then
  begin
    MinV := MMAcc[0,0]; K := 0; MMAcc[0,0] := 0;
    for I := 1 to 10 do
    begin
      V := MMAcc[0,I];
      if MinV > V then begin MinV := V; K := I; end;
      MMAcc[0,I] := 0;
    end;
    Dec(K);
    case K of
      0: if MMCoef[0,0] > -$20 then Dec(MMCoef[0,0]);
      1: if MMCoef[0,0] <  $20 then Inc(MMCoef[0,0]);
      2: if MMCoef[0,1] > -$20 then Dec(MMCoef[0,1]);
      3: if MMCoef[0,1] <  $20 then Inc(MMCoef[0,1]);
      4: if MMCoef[0,2] > -$20 then Dec(MMCoef[0,2]);
      5: if MMCoef[0,2] <  $20 then Inc(MMCoef[0,2]);
      6: if MMCoef[0,3] > -$20 then Dec(MMCoef[0,3]);
      7: if MMCoef[0,3] <  $20 then Inc(MMCoef[0,3]);
      8: if MMCoef[0,3] > -$20 then Dec(MMCoef[0,4]);
      9: if MMCoef[0,3] <  $20 then Inc(MMCoef[0,4]);
    end;
  end;

  DeltaRing[GCnt and $7F] := RingDelta;

  if (AlzCandMask[CandBest0] and LongInt(GCnt)) = 0 then
  begin
    CandBest1 := 2; CandBest2 := 2; EdiMin := $FFFF;
    Cnt := GCnt;
    for A := 2 to 123 do
    begin
      D1 := (DeltaRing[(Cnt-1) and $7F]   - DeltaRing[(Cnt-1-A) and $7F]) and $FFF;
      D2 := (DeltaRing[Cnt and $7F]       - DeltaRing[(Cnt-A) and $7F])   and $FFF;
      D3 := (DeltaRing[(Cnt-2) and $7F]   - DeltaRing[(Cnt-2-A) and $7F]) and $FFF;
      Sum := AlzMMW(D1) + AlzMMW(D2) + AlzMMW(D3);
      CandAcc[A] := ((CandAcc[A] * 13) shr 4) + Sum;
      if CandAcc[A] < CandAcc[CandBest1] then CandBest1 := A;
      if Sum < EdiMin then begin EdiMin := Sum; CandBest2 := A; end;
    end;
  end;

  Res[0] := OutS - CandScore[0];
  Res[1] := OutS - CandScore[1];
  Res[2] := OutS - CandScore[2];
  Res[3] := OutS - CandScore[3];
  Res[4] := RingDelta - CandScore[4];
  Res[5] := RingDelta - CandScore[5];
  CandBest0 := 0;
  RingPos := GCnt and $FF;
  for K := 0 to 5 do
  begin
    ResBank[K,256] := ResBank[K,256] - ResBank[K,RingPos];
    Bv := AlzCandBucket9[Res[K] and $1FF];
    ResBank[K,RingPos] := Bv;
    ResBank[K,256] := ResBank[K,256] + Bv;
    if ResBank[K,256] < ResBank[CandBest0,256] then CandBest0 := K;
  end;

  CandPrev := CandCur;
  CandCur := OutS;

  SlotHash[0]   := (SlotHash[0]   shl 8) + DeltaByte;
  SlotHash74[0] := (SlotHash74[0] shl 8) + Cardinal(AlzCandByteA[DeltaByte]);
  SlotHash78[0] := (SlotHash78[0] shl 8) + Cardinal(AlzCandByteB[DeltaByte]);
end;

procedure TPpmMM6.Predict(Position: Cardinal; out BaseByte: Byte; out Context: Cardinal);
var
  RingIdx1, RingIdx2, Base: Integer;
  RingV, OldH1, OldH2, NewH1, Score: LongInt;
  SB: Byte;
begin
  CandScore[0] := 0;
  CandScore[1] := CandCur;
  CandScore[2] := (CandCur + CandCur) - CandPrev;

  RingIdx1 := (Integer(Position) - CandBest1) and $7F;
  RingV := DeltaRing[RingIdx1];

  OldH1 := MMHist[0,1]; OldH2 := MMHist[0,2];
  NewH1 := MMDelta[0] - MMHist[0,0];
  MMHist[0,4] := RingV;
  MMHist[0,3] := OldH2;
  MMHist[0,2] := OldH1;
  MMHist[0,1] := NewH1;
  MMHist[0,0] := MMDelta[0];

  Score := (MMLast[0] shl 4)
         + MMCoef[0,0] * MMDelta[0]
         + MMCoef[0,1] * NewH1
         + MMCoef[0,2] * OldH1
         + MMCoef[0,3] * OldH2
         + MMCoef[0,4] * RingV;
  Score := Score div 16;
  CandScore[3] := Score;
  CandScore[4] := RingV;
  RingIdx2 := (Integer(Position) - CandBest2) and $7F;
  CandScore[5] := DeltaRing[RingIdx2];

  SB := Byte(CandScore[CandBest0]);
  if CandBest0 >= 4 then SB := Byte(SB + Byte(CandCur));
  BaseByte := SB;

  Base := $2ED;
  if SlotHash[0] = 0 then Inc(Base)
  else if SlotHash74[0] = 0 then Base := Base + 2
  else if SlotHash78[0] = 0 then Base := Base + 3;
  Context := Cardinal(Base);
end;

end.
