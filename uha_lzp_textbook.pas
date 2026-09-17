unit uha_lzp_textbook;
{$mode delphi}{$H+}{$Q-}{$R-}

interface

type
  TLzpStatus = (
    lzpsOk,
    lzpsBadOrder,
    lzpsOutputTooSmall,
    lzpsCorruptInput
  );

function LZP_Decode(const Compressed: array of Byte; Order: Integer;
  UnpackedSize: Cardinal; var Output: array of Byte): Integer;
function LZP_DecodeMembers(const Compressed: array of Byte; Order: Integer;
  UnpackedSize: Cardinal; const MemberEnds: array of Cardinal;
  var Output: array of Byte): Integer;

implementation

uses SysUtils, Math;

const
  MinOrder = 8;
  MaxOrder = 23;

  RangeTop = Cardinal($01000000);
  RangeInit = Cardinal($FFFFFFFF);

  SymbolCount = 319;
  ByteCount = 256;
  EscapeContext = 318;
  ModelRescaleLimit = 16384;

  LiteralCtxAllFF = 314;
  LiteralCtxD1DF = 315;
  LiteralCtxD3DF = 316;
  LiteralCtxHighDF = 317;

  NoPos = Cardinal($FFFFFFFF);

type
  TSeedBinaryProb = record
    Split: Word;
    Total: Word;
  end;

const

  SeedLzpDecisionProbs: array[0..49] of TSeedBinaryProb = (
    (Split:11; Total:99),
    (Split:12; Total:99),
    (Split:13; Total:99),
    (Split:14; Total:99),
    (Split:14; Total:99),
    (Split:14; Total:99),
    (Split:14; Total:99),
    (Split:14; Total:99),
    (Split:11; Total:99),
    (Split:12; Total:99),
    (Split:13; Total:99),
    (Split:14; Total:99),
    (Split:14; Total:99),
    (Split:14; Total:99),
    (Split:14; Total:99),
    (Split:14; Total:99),
    (Split:11; Total:99),
    (Split:12; Total:99),
    (Split:13; Total:99),
    (Split:14; Total:99),
    (Split:14; Total:99),
    (Split:14; Total:99),
    (Split:14; Total:99),
    (Split:14; Total:99),
    (Split:6; Total:99),
    (Split:7; Total:99),
    (Split:8; Total:99),
    (Split:9; Total:99),
    (Split:9; Total:99),
    (Split:9; Total:99),
    (Split:9; Total:99),
    (Split:9; Total:99),
    (Split:6; Total:99),
    (Split:7; Total:99),
    (Split:8; Total:99),
    (Split:9; Total:99),
    (Split:9; Total:99),
    (Split:9; Total:99),
    (Split:9; Total:99),
    (Split:9; Total:99),
    (Split:6; Total:99),
    (Split:7; Total:99),
    (Split:8; Total:99),
    (Split:9; Total:99),
    (Split:9; Total:99),
    (Split:9; Total:99),
    (Split:9; Total:99),
    (Split:9; Total:99),
    (Split:49; Total:99),
    (Split:79; Total:99)
  );

  LastAdjustmentTransition: array[0..15] of Byte = (
    6, 0, 6, 0, 6, 1, 6, 2, 6, 3, 6, 3, 7, 4, 7, 5
  );

  RankNextState: array[0..511] of Byte = (
    0, 0, 0, 0, 0, 4, 0, 0, 3, 5, 0, 0, 2, 14, 0, 0,
    7, 9, 0, 0, 8, 12, 0, 0, 11, 13, 0, 0, 10, 30, 0, 0,
    15, 17, 0, 0, 16, 20, 0, 0, 19, 21, 0, 0, 18, 26, 0, 0,
    23, 25, 0, 0, 24, 28, 0, 0, 27, 29, 0, 0, 22, 62, 0, 0,
    31, 33, 0, 0, 32, 36, 0, 0, 35, 37, 0, 0, 34, 42, 0, 0,
    39, 41, 0, 0, 40, 44, 0, 0, 43, 45, 0, 0, 38, 54, 0, 0,
    47, 49, 0, 0, 48, 52, 0, 0, 51, 53, 0, 0, 50, 58, 0, 0,
    55, 57, 0, 0, 56, 60, 0, 0, 59, 61, 0, 0, 46, 254, 0, 0,
    63, 65, 0, 0, 64, 68, 0, 0, 67, 69, 0, 0, 66, 74, 0, 0,
    71, 73, 0, 0, 72, 76, 0, 0, 75, 77, 0, 0, 70, 86, 0, 0,
    79, 81, 0, 0, 80, 84, 0, 0, 83, 85, 0, 0, 82, 90, 0, 0,
    87, 89, 0, 0, 88, 92, 0, 0, 91, 93, 0, 0, 78, 110, 0, 0,
    95, 97, 0, 0, 96, 100, 0, 0, 99, 101, 0, 0, 98, 106, 0, 0,
    103, 105, 0, 0, 104, 108, 0, 0, 107, 109, 0, 0, 102, 118, 0, 0,
    111, 113, 0, 0, 112, 116, 0, 0, 115, 117, 0, 0, 114, 122, 0, 0,
    119, 121, 0, 0, 120, 124, 0, 0, 123, 125, 0, 0, 94, 190, 0, 0,
    127, 129, 0, 0, 128, 132, 0, 0, 131, 133, 0, 0, 130, 138, 0, 0,
    135, 137, 0, 0, 136, 140, 0, 0, 139, 141, 0, 0, 134, 150, 0, 0,
    143, 145, 0, 0, 144, 148, 0, 0, 147, 149, 0, 0, 146, 154, 0, 0,
    151, 153, 0, 0, 152, 156, 0, 0, 155, 157, 0, 0, 142, 174, 0, 0,
    159, 161, 0, 0, 160, 164, 0, 0, 163, 165, 0, 0, 162, 170, 0, 0,
    167, 169, 0, 0, 168, 172, 0, 0, 171, 173, 0, 0, 166, 182, 0, 0,
    175, 177, 0, 0, 176, 180, 0, 0, 179, 181, 0, 0, 178, 186, 0, 0,
    183, 185, 0, 0, 184, 188, 0, 0, 187, 189, 0, 0, 158, 222, 0, 0,
    191, 193, 0, 0, 192, 196, 0, 0, 195, 197, 0, 0, 194, 202, 0, 0,
    199, 201, 0, 0, 200, 204, 0, 0, 203, 205, 0, 0, 198, 214, 0, 0,
    207, 209, 0, 0, 208, 212, 0, 0, 211, 213, 0, 0, 210, 218, 0, 0,
    215, 217, 0, 0, 216, 220, 0, 0, 219, 221, 0, 0, 206, 238, 0, 0,
    223, 225, 0, 0, 224, 228, 0, 0, 227, 229, 0, 0, 226, 234, 0, 0,
    231, 233, 0, 0, 232, 236, 0, 0, 235, 237, 0, 0, 230, 246, 0, 0,
    239, 241, 0, 0, 240, 244, 0, 0, 243, 245, 0, 0, 242, 250, 0, 0,
    247, 249, 0, 0, 248, 252, 0, 0, 251, 253, 0, 0, 126, 0, 0, 0
  );

  SeenToTreeGroup: array[0..255] of Cardinal = (
    0, 0, 1, 2, 3, 4, 5, 5, 6, 6, 6, 6, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7
  );

  TextClassMap: array[0..255] of Byte = (
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
    1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
  );

type
  TByteReader = record
    Data: PByte;
    Size: NativeInt;
    Pos: NativeInt;
    Exhausted: Boolean;
    procedure Init(const Source: array of Byte);
    function ReadByte: Byte;
  end;

  TRangeDecoder = record
    Reader: TByteReader;
    Code: Cardinal;
    Range: Cardinal;
    Corrupt: Boolean;
    procedure Init(const Source: array of Byte);
    procedure Normalize;
    function GetThreshold(Total: Cardinal): Cardinal;
    function GetFixed12Threshold: Cardinal;
    procedure Remove(Low, High: Cardinal);
  end;

  TBinaryProb = record

    Low0: Word;
    Split: Word;
    Total: Word;
    procedure Init(ASplit, ATotal: Word);
    procedure UpdateAfterSyntheticOne;
    function DecodeBit(var Rc: TRangeDecoder): Integer;
  end;

  TBitTreeProb = record
    Value: Word;
    procedure Init(AValue: Word);
    function DecodeBit(var Rc: TRangeDecoder): Integer;
  end;

  TContextModel = record

    Freq: array[0..SymbolCount - 1, 0..ByteCount - 1] of Word;
    Tree: array[0..SymbolCount - 1, 0..ByteCount - 1] of Word;
    EscapeWeight: array[0..SymbolCount - 1] of Word;
    procedure Init;
    function TotalOf(Context: Integer; PreviousLiteral: Integer): Cardinal;
    function PrefixSum(Context, SymbolExclusive: Integer): Cardinal;
    function SelectByCumulative(Context, PreviousLiteral: Integer;
      Threshold: Cardinal; var Symbol: Integer; var Low, High: Cardinal): Boolean;
    function DecodeFromContext(var Rc: TRangeDecoder; Context: Integer;
      PreviousLiteral: Integer; Total: Cardinal): Integer;
    function DecodeExcludedEscape(var Rc: TRangeDecoder; Context: Integer;
      PreviousLiteral: Integer): Integer;
    function DecodeSymbol(var Rc: TRangeDecoder; Context: Integer;
      PreviousLiteral: Integer): Integer;
    procedure SeedEscapeContext;
    procedure AddToContext(Context, Symbol, Delta: Integer);
    procedure UpdateSymbol(Context, Symbol: Integer);
    procedure RescaleContext(Context: Integer);
    class function RescaledFrequency(F: Word): Word; static;
    procedure RebuildTree(Context: Integer);
  end;

  TLzpHashEntry = record
    Position: Cardinal;
    Signature: Cardinal;
  end;

  TUhaLzpDecoder = record
    Rc: TRangeDecoder;
    Model: TContextModel;

    Order: Integer;
    RingMask: Cardinal;
    RingSize: Cardinal;

    Ring: array of Byte;
    Hash: array[0..262143] of TLzpHashEntry;
    HashSeen: array[0..262143] of Byte;
    PairSeen: array[0..65535] of Byte;
    LastPosByPair: array[0..65535] of Cardinal;

    DecisionProb: array[0..49] of TBinaryProb;
    RankProb: array[0..9, 0..511] of TBitTreeProb;

    OutPos: Cardinal;
    MatchRunCount: Cardinal;
    LastPredictedPos: Cardinal;
    PreviousLiteralPtr: Integer;
    LastWord: Cardinal;
    RingWritePos: Cardinal;
    LastMatchDistance: Cardinal;
    LastAdjustment: Byte;

    procedure Reset(AOrder: Integer; const Source: array of Byte;
      UnpackedSize: Cardinal);
    function DecodeTo(var Output: array of Byte; UnpackedSize: Cardinal;
      const MemberEnds: array of Cardinal): TLzpStatus;

    function LiteralContextFromHistory: Integer;
    function DecodeOneLiteral: Byte;
    function TryLzpOrMatch(var Output: array of Byte; UnpackedSize: Cardinal): Boolean;

    function HashOfHistory: Cardinal;
    function CurrentPair: Word;
    procedure RememberCurrentPosition;
    procedure PutByte(var Output: array of Byte; B: Byte);
    procedure CopyPredictedBytes(var Output: array of Byte; FromPos, Count,
      UnpackedSize: Cardinal);
    function DecodeRankSymbol(TreeGroup: Integer; SeenCount: Byte): Byte;
    function CandidatePairAt(SourcePos: Cardinal): Word;
    function HasRecentFourByteEvidence(SourcePos: Cardinal): Boolean;
  end;

procedure TByteReader.Init(const Source: array of Byte);
begin
  if Length(Source) = 0 then Data := nil else Data := @Source[0];
  Size := Length(Source);
  Pos := 0;
  Exhausted := False;
end;

function TByteReader.ReadByte: Byte;
begin
  if Pos < Size then
  begin
    Result := PByte(NativeUInt(Data) + NativeUInt(Pos))^;
    Inc(Pos);
  end
  else
  begin
    Exhausted := True;
    Result := 0;
  end;
end;

procedure TRangeDecoder.Init(const Source: array of Byte);
var
  I: Integer;
begin
  Reader.Init(Source);
  Code := 0;
  Range := RangeInit;
  Corrupt := False;
  for I := 0 to 4 do
    Code := (Code shl 8) or Reader.ReadByte;
  Corrupt := Reader.Exhausted;
end;

procedure TRangeDecoder.Normalize;
begin
  while Range < RangeTop do
  begin
    Code := (Code shl 8) or Reader.ReadByte;
    Range := Range shl 8;
  end;
end;

function TRangeDecoder.GetThreshold(Total: Cardinal): Cardinal;
begin
  if Total = 0 then
  begin
    Corrupt := True;
    Exit(0);
  end;
  Range := Range div Total;
  if Range = 0 then
  begin
    Corrupt := True;
    Exit(0);
  end;
  Result := Code div Range;
  if Result >= Total then
  begin
    Corrupt := True;
    Result := Total - 1;
  end;
end;

function TRangeDecoder.GetFixed12Threshold: Cardinal;
begin

  Range := Range shr 12;
  if Range = 0 then
  begin
    Corrupt := True;
    Exit(0);
  end;
  Result := Code div Range;
  if Result >= 4096 then
  begin
    Corrupt := True;
    Result := 4095;
  end;
end;

procedure TRangeDecoder.Remove(Low, High: Cardinal);
begin
  if (High <= Low) then
  begin
    Corrupt := True;
    Exit;
  end;
  Dec(Code, Range * Low);
  Range := Range * (High - Low);
  Normalize;

end;

procedure TBinaryProb.Init(ASplit, ATotal: Word);
begin
  Low0 := 0;
  Split := ASplit;
  Total := ATotal;
  if Split = 0 then Split := 1;
  if Total <= Split then Total := Split + 1;
end;

procedure TBinaryProb.UpdateAfterSyntheticOne;
begin

  Inc(Total, 64);
  if Total >= ModelRescaleLimit then
  begin
    Split := Word((Cardinal(Split) + 1) shr 1);
    Total := Word((Cardinal(Total) + 2) shr 1);
    if Split = 0 then Split := 1;
    if Total <= Split then Total := Split + 1;
  end;
end;

function TBinaryProb.DecodeBit(var Rc: TRangeDecoder): Integer;
var
  T: Cardinal;
begin
  T := Rc.GetThreshold(Total);
  if T < Split then
  begin
    Rc.Remove(Low0, Split);
    Result := 0;
    Inc(Split, 64);
  end
  else
  begin
    Rc.Remove(Split, Total);
    Result := 1;
  end;

  Inc(Total, 64);
  if Total >= ModelRescaleLimit then
  begin
    Split := Word((Cardinal(Split) + 1) shr 1);
    Total := Word((Cardinal(Total) + 2) shr 1);
    if Split = 0 then Split := 1;
    if Total <= Split then Total := Split + 1;
  end;
end;

procedure TBitTreeProb.Init(AValue: Word);
begin
  Value := AValue;
  if Value = 0 then Value := 2048;
  if Value >= 4096 then Value := 4095;
end;

function TBitTreeProb.DecodeBit(var Rc: TRangeDecoder): Integer;
var
  T: Cardinal;
begin

  T := Rc.GetFixed12Threshold;
  if T < Value then
  begin
    Rc.Remove(0, Value);
    Value := Word(Value + ((4096 - Value) shr 6));
    Result := 0;
  end
  else
  begin
    Rc.Remove(Value, 4096);
    Value := Word(Value - (Value shr 6));
    Result := 1;
  end;
end;

procedure TContextModel.Init;
var
  C, S: Integer;
begin
  FillChar(Freq, SizeOf(Freq), 0);
  FillChar(Tree, SizeOf(Tree), 0);
  FillChar(EscapeWeight, SizeOf(EscapeWeight), 0);

  SeedEscapeContext;

  for C := 0 to SymbolCount - 2 do
    EscapeWeight[C] := 1;
end;

procedure TContextModel.SeedEscapeContext;
var
  S, I, LowBit: Integer;
begin

  for S := 0 to ByteCount - 1 do
    Freq[EscapeContext, S] := 8;

  Tree[EscapeContext, 0] := ByteCount * 8;
  for I := 1 to ByteCount - 1 do
  begin
    LowBit := I and -I;
    Tree[EscapeContext, I] := Word(LowBit * 8);
  end;
end;

procedure TContextModel.AddToContext(Context, Symbol, Delta: Integer);
var
  Idx: Byte;
  V: Cardinal;
begin
  if (Context < 0) or (Context >= SymbolCount) then Exit;
  if (Symbol < 0) or (Symbol >= ByteCount) then Exit;
  if Delta <= 0 then Exit;

  V := Cardinal(Freq[Context, Symbol]) + Cardinal(Delta);
  if V > High(Word) then V := High(Word);
  Freq[Context, Symbol] := Word(V);

  Idx := Byte(Symbol + 1);
  while Idx <> 0 do
  begin
    V := Cardinal(Tree[Context, Idx]) + Cardinal(Delta);
    if V > High(Word) then V := High(Word);
    Tree[Context, Idx] := Word(V);
    Idx := Byte(Idx + (Integer(Idx) and -Integer(Idx)));
  end;

  V := Cardinal(Tree[Context, 0]) + Cardinal(Delta);
  if V > High(Word) then V := High(Word);
  Tree[Context, 0] := Word(V);
end;

function TContextModel.PrefixSum(Context, SymbolExclusive: Integer): Cardinal;
var
  Idx: Integer;
begin
  Result := 0;
  if (Context < 0) or (Context >= SymbolCount) then Exit;
  if SymbolExclusive <= 0 then Exit;
  if SymbolExclusive > ByteCount then SymbolExclusive := ByteCount;

  Idx := SymbolExclusive;
  while Idx > 0 do
  begin
    Inc(Result, Tree[Context, Idx and $FF]);
    Dec(Idx, Idx and -Idx);
  end;
end;

function TContextModel.TotalOf(Context: Integer; PreviousLiteral: Integer): Cardinal;
begin
  if (Context < 0) or (Context >= SymbolCount) then
    Context := EscapeContext;
  Result := Tree[Context, 0];
  if (PreviousLiteral >= 0) and (PreviousLiteral < ByteCount) then
    if Result > Freq[Context, PreviousLiteral] then
      Dec(Result, Freq[Context, PreviousLiteral])
    else
      Result := 0;
end;

function TContextModel.SelectByCumulative(Context, PreviousLiteral: Integer;
  Threshold: Cardinal; var Symbol: Integer; var Low, High: Cardinal): Boolean;
var
  BitMask, Next, Idx: Integer;
  Acc, Step: Cardinal;
begin
  Result := False;
  Symbol := 0;
  Low := 0;
  High := 0;

  if (Context < 0) or (Context >= SymbolCount) then
    Exit;

  if PreviousLiteral < 0 then
  begin
    Idx := 0;
    Acc := 0;
    BitMask := 128;
    while BitMask <> 0 do
    begin
      Next := Idx + BitMask;
      if Next < ByteCount then
      begin
        Step := Tree[Context, Next];
        if Acc + Step <= Threshold then
        begin
          Idx := Next;
          Inc(Acc, Step);
        end;
      end;
      BitMask := BitMask shr 1;
    end;

    if Idx >= ByteCount then
      Exit;

    Symbol := Idx;
    Low := Acc;
    High := Acc + Freq[Context, Symbol];
    Result := (Low <= Threshold) and (Threshold < High);
    Exit;
  end;

  Acc := 0;
  for Idx := 0 to ByteCount - 1 do
  begin
    if Idx = PreviousLiteral then
      Continue;
    Step := Freq[Context, Idx];
    if Step = 0 then
      Continue;
    if Threshold < Acc + Step then
    begin
      Symbol := Idx;
      Low := Acc;
      High := Acc + Step;
      Exit(True);
    end;
    Inc(Acc, Step);
  end;
end;

function TContextModel.DecodeFromContext(var Rc: TRangeDecoder; Context: Integer;
  PreviousLiteral: Integer; Total: Cardinal): Integer;
var
  Threshold, Low, High: Cardinal;
  Symbol: Integer;
begin
  Threshold := Rc.GetThreshold(Total);
  if SelectByCumulative(Context, PreviousLiteral, Threshold, Symbol, Low, High) then
  begin
    Rc.Remove(Low, High);
    Exit(Symbol);
  end;

  Rc.Corrupt := True;
  Result := 0;
end;

function TContextModel.DecodeExcludedEscape(var Rc: TRangeDecoder; Context: Integer;
  PreviousLiteral: Integer): Integer;
var
  S, Symbol: Integer;
  Total, Low, High, Threshold, Acc, Step: Cardinal;
begin
  Total := 0;
  for S := 0 to ByteCount - 1 do
    if (S <> PreviousLiteral) and (Freq[Context, S] = 0) then
      Inc(Total, Freq[EscapeContext, S]);

  if Total = 0 then
  begin

    Rc.Corrupt := True;
    Exit(0);
  end;

  Threshold := Rc.GetThreshold(Total);
  Acc := 0;
  for S := ByteCount - 1 downto 0 do
  begin
    if (S = PreviousLiteral) or (Freq[Context, S] <> 0) then
      Continue;
    Step := Freq[EscapeContext, S];
    if Threshold < Acc + Step then
    begin
      Symbol := S;
      Low := Acc;
      High := Acc + Step;
      Rc.Remove(Low, High);
      Exit(Symbol);
    end;
    Inc(Acc, Step);
  end;

  Rc.Corrupt := True;
  Result := 0;
end;

function TContextModel.DecodeSymbol(var Rc: TRangeDecoder; Context: Integer;
  PreviousLiteral: Integer): Integer;
var
  DirectTotal, CombinedTotal, Threshold: Cardinal;
  S: Integer;
  Low, High: Cardinal;
begin
  if (Context < 0) or (Context >= SymbolCount) then
    Context := EscapeContext;

  DirectTotal := TotalOf(Context, PreviousLiteral);

  if Context = EscapeContext then
  begin
    if DirectTotal = 0 then DirectTotal := Tree[EscapeContext, 0];
    Exit(DecodeFromContext(Rc, EscapeContext, PreviousLiteral, DirectTotal));
  end;

  if DirectTotal <> 0 then
  begin
    CombinedTotal := DirectTotal + EscapeWeight[Context];
    Threshold := Rc.GetThreshold(CombinedTotal);
    if Threshold < DirectTotal then
    begin

      Low := 0;
      for S := ByteCount - 1 downto 0 do
      begin
        if S = PreviousLiteral then
          Continue;
        High := Low + Freq[Context, S];
        if Threshold < High then
        begin
          Rc.Remove(Low, High);
          Exit(S);
        end;
        Low := High;
      end;
      Rc.Corrupt := True;
      Exit(0);
    end;

    Rc.Remove(DirectTotal, CombinedTotal);
  end;

  Result := DecodeExcludedEscape(Rc, Context, PreviousLiteral);
end;

procedure TContextModel.UpdateSymbol(Context, Symbol: Integer);
begin
  if (Context < 0) or (Context >= SymbolCount) then Exit;
  if (Symbol < 0) or (Symbol >= ByteCount) then Exit;

  if (Context <> EscapeContext) and (Freq[Context, Symbol] = 0) then
  begin
    Inc(EscapeWeight[Context], 32);
    AddToContext(EscapeContext, Symbol, 16);
    if Tree[EscapeContext, 0] >= ModelRescaleLimit then
      RescaleContext(EscapeContext);
  end;

  AddToContext(Context, Symbol, 32);
  if Cardinal(Tree[Context, 0]) + Cardinal(EscapeWeight[Context]) >= ModelRescaleLimit then
    RescaleContext(Context);
end;

class function TContextModel.RescaledFrequency(F: Word): Word;
begin

  if F = 0 then
    Result := 0
  else
    Result := Word((Cardinal(F) + 1) shr 1);
end;

procedure TContextModel.RebuildTree(Context: Integer);
var
  I, StartSymbol, S, LowBit: Integer;
  Sum: Cardinal;
begin
  if (Context < 0) or (Context >= SymbolCount) then Exit;

  FillChar(Tree[Context], SizeOf(Tree[Context]), 0);

  Sum := 0;
  for S := 0 to ByteCount - 1 do
    Inc(Sum, Freq[Context, S]);
  if Sum > High(Word) then Sum := High(Word);
  Tree[Context, 0] := Word(Sum);

  for I := 1 to ByteCount - 1 do
  begin
    LowBit := I and -I;
    StartSymbol := I - LowBit;
    Sum := 0;
    for S := StartSymbol to I - 1 do
      Inc(Sum, Freq[Context, S]);
    if Sum > High(Word) then Sum := High(Word);
    Tree[Context, I] := Word(Sum);
  end;
end;

procedure TContextModel.RescaleContext(Context: Integer);
var
  S: Integer;
begin
  if (Context < 0) or (Context >= SymbolCount) then Exit;

  for S := 0 to ByteCount - 1 do
    Freq[Context, S] := RescaledFrequency(Freq[Context, S]);

  if Context < EscapeContext then
    EscapeWeight[Context] := Word((Cardinal(EscapeWeight[Context]) shr 2) + 1);

  RebuildTree(Context);
end;

procedure TUhaLzpDecoder.Reset(AOrder: Integer; const Source: array of Byte;
  UnpackedSize: Cardinal);
var
  I, C, N: Integer;
  Initial, Group: Cardinal;
begin
  Order := AOrder;

  RingSize := Cardinal(1) shl (Order + 2);
  RingMask := RingSize - 1;

  Rc.Init(Source);
  Model.Init;

  SetLength(Ring, RingSize + 256);
  FillChar(Ring[0], Length(Ring), 0);

  for I := Low(Hash) to High(Hash) do
  begin
    Hash[I].Position := NoPos;
    Hash[I].Signature := NoPos;
    HashSeen[I] := 0;
  end;
  FillChar(PairSeen, SizeOf(PairSeen), 0);
  for I := Low(LastPosByPair) to High(LastPosByPair) do
    LastPosByPair[I] := NoPos;

  for I := Low(DecisionProb) to High(DecisionProb) do
    DecisionProb[I].Init(SeedLzpDecisionProbs[I].Split, SeedLzpDecisionProbs[I].Total);

  Initial := 2560;
  for Group := 0 to 9 do
  begin
    for N := 0 to 511 do
      RankProb[Group, N].Init(Word(Initial));
    if Initial > 64 then Dec(Initial, 64);
  end;

  OutPos := 0;
  MatchRunCount := 0;
  LastPredictedPos := NoPos;
  PreviousLiteralPtr := -1;
  LastWord := 0;
  RingWritePos := 0;
  LastMatchDistance := NoPos;
  LastAdjustment := 0;
end;

function TUhaLzpDecoder.HashOfHistory: Cardinal;
begin
  Result := (LastWord xor (LastWord shr 13)) and $3FFFF;
end;

function TUhaLzpDecoder.CurrentPair: Word;
begin
  Result := Word(LastWord and $FFFF);
end;

procedure TUhaLzpDecoder.RememberCurrentPosition;
var
  H: Cardinal;
begin
  H := HashOfHistory;
  Hash[H].Position := RingWritePos;
  Hash[H].Signature := LastWord;
  HashSeen[H] := 1;
  LastPosByPair[CurrentPair] := RingWritePos;
end;

function TUhaLzpDecoder.LiteralContextFromHistory: Integer;
var
  Lo, Hi: Byte;
begin
  Lo := Byte(LastWord and $FF);
  Hi := Byte((LastWord shr 8) and $FF);

  if CurrentPair = $FFFF then Exit(LiteralCtxAllFF);
  if CurrentPair = $D1DF then Exit(LiteralCtxD1DF);
  if CurrentPair = $D3DF then Exit(LiteralCtxD3DF);

  if (Lo = $DF) and (TextClassMap[Hi] <> 0) then
    Exit(LiteralCtxHighDF);

  if (TextClassMap[Lo] = 0) and (TextClassMap[Hi] <> 0) then
    Exit(Lo + 123);

  Result := Lo;
end;

function TUhaLzpDecoder.DecodeOneLiteral: Byte;
var
  Context: Integer;
  Symbol: Integer;
  PredictedLiteral: Integer;
begin
  Context := LiteralContextFromHistory;

  if PreviousLiteralPtr >= 0 then
    PredictedLiteral := Ring[Cardinal(PreviousLiteralPtr) and RingMask]
  else
    PredictedLiteral := -1;

  Symbol := Model.DecodeSymbol(Rc, Context, PredictedLiteral);
  Model.UpdateSymbol(Context, Symbol);

  PreviousLiteralPtr := -1;
  if (LastPredictedPos <> NoPos) and
     (Byte(Symbol) = Ring[LastPredictedPos and RingMask]) then
    PreviousLiteralPtr := Integer((LastPredictedPos + 1) and RingMask);

  Result := Byte(Symbol);
end;

procedure TUhaLzpDecoder.PutByte(var Output: array of Byte; B: Byte);
begin

  Output[OutPos] := Byte(not B);
  Ring[RingWritePos] := B;
  if RingWritePos < 256 then
    Ring[RingSize + RingWritePos] := B;

  LastWord := ((LastWord shl 8) or B) and $FFFFFFFF;
  Inc(OutPos);
  RingWritePos := (RingWritePos + 1) and RingMask;
end;

procedure TUhaLzpDecoder.CopyPredictedBytes(var Output: array of Byte; FromPos,
  Count, UnpackedSize: Cardinal);
var
  B: Byte;
begin
  while (Count <> 0) and (OutPos < UnpackedSize) do
  begin
    B := Ring[FromPos and RingMask];
    PutByte(Output, B);
    FromPos := (FromPos + 1) and RingMask;
    Dec(Count);
  end;
end;

function TUhaLzpDecoder.DecodeRankSymbol(TreeGroup: Integer; SeenCount: Byte): Byte;
var
  State: Byte;
  BranchIndex, Node: Integer;
  Bit: Integer;
begin
  if TreeGroup < 0 then TreeGroup := 0;
  if TreeGroup > 9 then TreeGroup := 9;

  State := 6;
  Result := $FF;

  while State <> 0 do
  begin
    BranchIndex := Ord(SeenCount <= State);
    Node := State + BranchIndex * 256;
    Bit := RankProb[TreeGroup, Node].DecodeBit(Rc);
    if Bit = 0 then
      Result := State;

    State := RankNextState[State * 2 + Ord(Result > State)];
  end;
end;

function TUhaLzpDecoder.CandidatePairAt(SourcePos: Cardinal): Word;
var
  NextPos: Cardinal;
begin

  Result := Word(Cardinal(Ring[SourcePos and RingMask]) shl 8);
  NextPos := (SourcePos + 1) and RingMask;
  if NextPos <> RingWritePos then
    Result := Result or Ring[NextPos];
end;

function TUhaLzpDecoder.HasRecentFourByteEvidence(SourcePos: Cardinal): Boolean;
var
  B0, B1, B2, B3: Byte;
  Recent: Cardinal;
begin

  B0 := Ring[(SourcePos - 4) and RingMask];
  B1 := Ring[(SourcePos - 3) and RingMask];
  B2 := Ring[(SourcePos - 2) and RingMask];
  B3 := Ring[(SourcePos - 1) and RingMask];
  Recent := (Cardinal(B0) shl 24) or (Cardinal(B1) shl 16) or
            (Cardinal(B2) shl 8) or Cardinal(B3);

  Result := ((Recent and $0000FFFF) = (LastWord and $0000FFFF)) or
            ((Recent and $FFFF00FF) = (LastWord and $FFFF00FF)) or
            ((Recent and $FFFFFF00) = (LastWord and $FFFFFF00));
end;

function TUhaLzpDecoder.TryLzpOrMatch(var Output: array of Byte;
  UnpackedSize: Cardinal): Boolean;
var
  H: Cardinal;
  Entry: TLzpHashEntry;
  WasSeen: Byte;
  PredPos, Dist, Available: Cardinal;
  DecisionIndex: Integer;
  DecisionBit: Integer;
  Pair: Word;
  PairSeenCount: Byte;
  RankSeenCount: Byte;
  LengthSymbol: Byte;
  TreeGroup: Integer;
  PairPos: Cardinal;
  HasHashCandidate: Boolean;
begin
  Result := False;

  H := HashOfHistory;
  Entry := Hash[H];
  WasSeen := HashSeen[H];
  PairPos := LastPosByPair[CurrentPair];
  LastPredictedPos := NoPos;

  PredPos := NoPos;
  DecisionIndex := 0;
  HasHashCandidate := False;

  if MatchRunCount <> 0 then
  begin
    PredPos := (RingWritePos - LastMatchDistance) and RingMask;
    DecisionIndex := 48 + Ord(MatchRunCount > 2);
  end
  else if (Entry.Position <> NoPos) and (Entry.Signature = LastWord) then
  begin

    PredPos := Entry.Position and RingMask;
    HasHashCandidate := True;
    DecisionIndex := 1;
  end
  else
  begin

    PredPos := (RingWritePos - LastMatchDistance) and RingMask;
    if ((PredPos - RingWritePos) and RingMask) >= $104 then
      if HasRecentFourByteEvidence(PredPos) then
        DecisionIndex := 9;

    if (DecisionIndex = 0) and (PairPos <> NoPos) then
    begin
      PredPos := PairPos and RingMask;
      DecisionIndex := 17;
    end;
  end;

  Hash[H].Position := RingWritePos;
  Hash[H].Signature := LastWord;
  LastPosByPair[CurrentPair] := RingWritePos;

  if (DecisionIndex = 0) or (PredPos = NoPos) then
  begin
    MatchRunCount := 0;
    Exit;
  end;

  Dist := (RingWritePos - PredPos) and RingMask;

  if ((PredPos - RingWritePos) and RingMask) < 256 then
  begin
    MatchRunCount := 0;
    Exit;
  end;

  if MatchRunCount = 0 then
  begin
    if WasSeen = 0 then
      Inc(DecisionIndex, 23)
    else
      Dec(DecisionIndex);
    Inc(DecisionIndex, LastAdjustment);
  end;
  if DecisionIndex < 0 then DecisionIndex := 0;
  if DecisionIndex > High(DecisionProb) then DecisionIndex := High(DecisionProb);

  if (PreviousLiteralPtr >= 0) and
     (Ring[PreviousLiteralPtr and Integer(RingMask)] = Ring[PredPos and RingMask]) then
  begin
    DecisionProb[DecisionIndex].UpdateAfterSyntheticOne;
    LastAdjustment := LastAdjustmentTransition[(LastAdjustment * 2 + 1) and 15];
    MatchRunCount := 0;
    Exit;
  end;

  LastPredictedPos := PredPos;
  DecisionBit := DecisionProb[DecisionIndex].DecodeBit(Rc);
  LastAdjustment := LastAdjustmentTransition[(LastAdjustment * 2 + DecisionBit) and 15];

  if DecisionBit <> 0 then
  begin
    HashSeen[H] := 0;
    Pair := CandidatePairAt(PredPos);
    PairSeen[Pair] := 0;
    MatchRunCount := 0;
    Exit;
  end;

  Pair := CandidatePairAt(PredPos);
  PairSeenCount := PairSeen[Pair];

  RankSeenCount := PairSeenCount;

  if MatchRunCount <> 0 then
    TreeGroup := 8 + Ord(MatchRunCount > 2)
  else if HasHashCandidate then
    TreeGroup := SeenToTreeGroup[WasSeen]
  else
    TreeGroup := SeenToTreeGroup[PairSeenCount];

  LengthSymbol := DecodeRankSymbol(TreeGroup, RankSeenCount);
  HashSeen[H] := LengthSymbol;
  PairSeen[Pair] := LengthSymbol;

  LastMatchDistance := Dist;
  LastPredictedPos := PredPos;

  Available := UnpackedSize - OutPos;
  if LengthSymbol = $FF then
  begin
    if Available > 255 then Available := 255;
    PreviousLiteralPtr := -1;
    Inc(MatchRunCount);
  end
  else
  begin
    if Cardinal(LengthSymbol) < Available then
      Available := Cardinal(LengthSymbol);
    PreviousLiteralPtr := Integer((PredPos + Available) and RingMask);
    MatchRunCount := 0;
  end;

  if Available = 0 then
    Exit;

  CopyPredictedBytes(Output, PredPos, Available, UnpackedSize);
  Result := True;
end;

function TUhaLzpDecoder.DecodeTo(var Output: array of Byte;
  UnpackedSize: Cardinal; const MemberEnds: array of Cardinal): TLzpStatus;
var
  B: Byte;
  NextBoundary, Target, CurrentSize, NextSize: Cardinal;
  Member, I: Integer;
  procedure AdvanceBoundary;
  begin
    if UnpackedSize - NextBoundary > $10000 then Target := NextBoundary + $10000
    else Target := UnpackedSize;
    while (Member <= High(MemberEnds)) and (MemberEnds[Member] < Target) do Inc(Member);
    if Member > High(MemberEnds) then NextBoundary := UnpackedSize
    else
    begin
      NextBoundary := MemberEnds[Member];

      if (Member > 0) and (Member < High(MemberEnds)) then
      begin
        CurrentSize := MemberEnds[Member] - MemberEnds[Member - 1];
        if CurrentSize < $4000 then
          while Member < High(MemberEnds) do
          begin
            NextSize := MemberEnds[Member + 1] - MemberEnds[Member];
            if NextSize >= CurrentSize then Break;
            Inc(Member);
            NextBoundary := MemberEnds[Member];
            CurrentSize := NextSize;
          end;
      end;
    end;
  end;
begin
  Member := 0;
  NextBoundary := 0;
  AdvanceBoundary;
  Result := lzpsOk;
  while OutPos < UnpackedSize do
  begin
    if OutPos >= NextBoundary then
    begin

      Model.Init;
      for I := Low(DecisionProb) to High(DecisionProb) do
      begin
        DecisionProb[I].Split := (DecisionProb[I].Split + 7) shr 3;
        DecisionProb[I].Total := (DecisionProb[I].Total + 15) shr 3;
      end;
      AdvanceBoundary;
    end;
    if Rc.Corrupt then
      Exit(lzpsCorruptInput);

    if TryLzpOrMatch(Output, UnpackedSize) then
      Continue;

    if Rc.Corrupt then
      Exit(lzpsCorruptInput);

    B := DecodeOneLiteral;
    if Rc.Corrupt then
      Exit(lzpsCorruptInput);
    PutByte(Output, B);
  end;

  if Rc.Corrupt then
    Result := lzpsCorruptInput;
end;

function LZP_DecodeMembers(const Compressed: array of Byte; Order: Integer;
  UnpackedSize: Cardinal; const MemberEnds: array of Cardinal;
  var Output: array of Byte): Integer;
var
  D: ^TUhaLzpDecoder;
  Status: TLzpStatus;
begin
  if (Order < MinOrder) or (Order > MaxOrder) then
    Exit(Ord(lzpsBadOrder));
  if Cardinal(Length(Output)) < UnpackedSize then
    Exit(Ord(lzpsOutputTooSmall));

  New(D);
  try
    D^.Reset(Order, Compressed, UnpackedSize);
    Status := D^.DecodeTo(Output, UnpackedSize, MemberEnds);
    Result := Ord(Status);
  finally
    Dispose(D);
  end;
end;

function LZP_Decode(const Compressed: array of Byte; Order: Integer;
  UnpackedSize: Cardinal; var Output: array of Byte): Integer;
begin
  Result := LZP_DecodeMembers(Compressed, Order, UnpackedSize, [], Output);
end;

end.
