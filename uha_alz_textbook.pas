unit uha_alz_textbook;

{$mode delphi}{$H+}{$Q-}{$R-}

interface

const
  alzOk = 0;
  alzBadOrder = 1;
  alzCorruptInput = 2;
  alzOutputTooSmall = 3;

function ALZ_Decode(const FileData: array of Byte; Order: Integer;
  USize: Cardinal; var OutBuf: array of Byte): Integer;
function ALZ_DecodeMembers(const FileData: array of Byte; Order: Integer;
  USize: Cardinal; const MemberEnds: array of Cardinal;
  var OutBuf: array of Byte): Integer;

procedure RestoreFilter(var Buf: array of Byte; USize: Cardinal;
  PpmByteSwap: Boolean = False);

implementation

uses SysUtils, Math, uha_ppm_statics;

var AlzItemTrace: Boolean;

var AlzSseMap: array[0..16384] of Word;
var AlzDistanceBase: array[0..43] of Cardinal;
var AlzEntryStep: array[0..$41F] of Word;
var AlzEscStep:   array[0..$41F] of Word;

const
  RangeTop       = $01000000;
  FixedProbScale = 4096;
  InitProb       = 2048;
  MaxRecentDistances = 12;

  alzFast = 1;
  alzNormal = 2;
  alzBest = 3;

  AlzTokenSeedNormal: array[0..5] of Word = (0, 1, 34, 45, 57, 101);
  AlzTokenSeedRepeat: array[0..5] of Word = (0, 1, 28, 78, 89, 100);

  AlzLiteralModeNext: array[0..159] of Byte = (
    16, 16, 16, 16, 17, 17, 17, 17, 20, 20, 20, 20, 18, 18, 18, 19,
    21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21,
    22, 22, 22, 22, 24, 23, 23, 24, 27, 27, 27, 27, 25, 25, 25, 26,
    28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28,
    29, 29, 29, 29, 29, 29, 29, 29, 30, 30, 30, 30, 30, 30, 30, 30,
    31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31,
    0, 0, 0, 0, 1, 2, 2, 3, 4, 4, 7, 7, 5, 5, 5, 6,
    8, 8, 8, 8, 8, 9, 12, 12, 12, 13, 13, 14, 15, 10, 10, 11,
    0, 0, 0, 0, 1, 3, 0, 0, 2, 6, 0, 0, 5, 7, 0, 0,
    4, 12, 0, 0, 9, 11, 0, 0, 10, 14, 0, 0, 13, 15, 0, 0
  );

  AlzFullDistanceNext: array[0..127] of Byte = (
    0, 0, 0, 0, 1, 3, 0, 0, 2, 6, 0, 0, 5, 7, 0, 0,
    4, 12, 0, 0, 9, 11, 0, 0, 10, 14, 0, 0, 13, 15, 0, 0,
    8, 32, 0, 0, 17, 19, 0, 0, 18, 22, 0, 0, 21, 23, 0, 0,
    20, 28, 0, 0, 25, 27, 0, 0, 26, 30, 0, 0, 29, 31, 0, 0,
    24, 40, 0, 0, 33, 35, 0, 0, 34, 38, 0, 0, 37, 39, 0, 0,
    36, 44, 0, 0, 41, 43, 0, 0, 42, 0, 0, 0, 0, 2, 0, 4,
    0, 0, 3, 8, 0, 0, 5, 7, 0, 0, 6, 10, 0, 0, 9, 0,
    0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 3, 5, 0, 0, 2, 8);

  AlzShortDistanceNext: array[0..63] of Byte = (
    0, 0, 0, 2, 0, 4, 0, 0, 3, 8, 0, 0, 5, 7, 0, 0,
    6, 10, 0, 0, 9, 0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0,
    3, 5, 0, 0, 2, 8, 0, 0, 7, 9, 0, 0, 6, 18, 0, 0,
    11, 13, 0, 0, 12, 16, 0, 0, 15, 17, 0, 0, 14, 30, 0, 0);

  AlzLengthNext: array[0..513] of Byte = (
    0, 0, 0, 0, 0, 4, 0, 0, 3, 5, 0, 0, 2, 8, 0, 0,
    7, 9, 0, 0, 6, 18, 0, 0, 11, 13, 0, 0, 12, 16, 0, 0,
    15, 17, 0, 0, 14, 30, 0, 0, 19, 21, 0, 0, 20, 26, 0, 0,
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
    247, 249, 0, 0, 248, 252, 0, 0, 251, 253, 0, 0, 126, 0, 0, 0,
    0, 0
  );

  AlzDistanceSpan: array[0..43] of Cardinal = (
    1, 2, 4, 8, 16, 32, 32, 32,
    64, 64, 128, 128, 256, 256, 512, 512,
    1024, 1024, 2048, 2048, 4096, 4096, 8192, 8192,
    16384, 16384, 32768, 32768, 65536, 65536, 131072, 131072,
    262144, 262144, 524288, 524288, 1048576, 1048576, 2097152, 2097152,
    4194304, 4194304, 8388608, 8388608);

  AlzSelectorPrimaryKind: array[0..10] of Cardinal = (
    1, 1, 2, 3, 4, 1, 1, 2, 2, 4, 0);

  AlzSelectorSecondaryBase: array[0..10] of Cardinal = (
    0, 769, 801, 833, 929, 993, 997, 1001, 1009, 1012, 0);

  AlzSelectorLiteralBias: array[0..10] of Byte = (
    0, 0, 8, 16, 24, 0, 0, 0, 0, 0, 0);

  AlzByteStep = 32;
  BM_NCTX = $420;

{$I ALZ_SELTAB.inc}
{$I ALZ_CAND.inc}

{$I ALZ_S3.inc}

type
  TByteReader = record
    Data: PByte;
    Size: NativeInt;
    Pos: NativeInt;
    Exhausted: Boolean;
    procedure Init(const Src: array of Byte);
    function ReadByte: Byte;
  end;

  TRangeDecoder = record
    Reader: ^TByteReader;
    Code: Cardinal;
    Range: Cardinal;
    Corrupt: Boolean;
    procedure Init(var R: TByteReader);
    procedure Normalize;
    function GetThreshold(Total: Cardinal): Cardinal;
    procedure RemoveInterval(Low, High, Total: Cardinal);
    function DecodeUniform(Total: Cardinal): Cardinal;
    function DecodeBit(var Prob: Word): Integer;
    function DecodeBitFast12(var Prob: Word): Integer;
    function DecodeBitFast12Shift(var Prob: Word; Shift: Integer): Integer;
  end;

  TAlzProbTree = record
    Prob: array of Word;
    procedure Init(NodeCount: Integer; Initial: Word = InitProb);
    function DecodeLeaf(var Rc: TRangeDecoder; FirstNode: Integer;
      const Next: array of Byte): Integer;
  end;

  TAlzMode = record
    MethodClass: Integer;
    DictionarySize: Cardinal;
    DictionaryMask: Cardinal;
    RebuildPeriod: Cardinal;
  end;

  TAlzState = record
    LastByte: Byte;
    PrevByte: Byte;
    PrevDelta: Byte;
    MatchFlagByte: Byte;
    LiteralMode: Byte;
    RepeatRun: Cardinal;
    OutputPos: Cardinal;
    WindowPos: Cardinal;
    RollingHistory: Cardinal;
    LastMatchTailByte: Byte;
    RangeModelEpoch: Cardinal;
    EscapeSelector: Byte;
    EscapeChanged: Boolean;
    EscapeModelFlag: Byte;
    EscapeLiteralBias: Byte;
    SideModelPrimaryKind: Cardinal;
    SideModelSecondaryBase: Cardinal;
    SideBias: Byte;
    SideDir: Byte;
    BMSideActive: Boolean;
    SideModCount: Cardinal;
    SlotHash: array[0..15] of Cardinal;
    SlotHash74: array[0..15] of Cardinal;
    SlotHash78: array[0..15] of Cardinal;
    SlotDir: array[0..15] of Byte;

    MMHist: array[0..9, 0..4] of LongInt;
    MMCoef: array[0..9, 0..4] of LongInt;
    MMLast: array[0..9] of LongInt;
    MMDelta: array[0..9] of LongInt;
    MMAcc: array[0..9, 0..10] of LongInt;
    MMCost5c: array[0..9] of LongInt;
    MMCost60: array[0..9] of LongInt;
    MMCost64: array[0..9] of LongInt;
    MMCost68: array[0..9] of LongInt;
    MMCounter: array[0..9] of Cardinal;
    MMGlobal: LongInt;
    MMGlobal2: LongInt;
    MMPrevScore: LongInt;
    MMOutCount: Cardinal;

    CandAcc: array[0..123] of LongInt;
    DeltaRing: array[0..127] of LongInt;
    CandScore: array[0..5] of LongInt;
    CandBest0: LongInt;
    CandBest1: LongInt;
    CandBest2: LongInt;
    CandCur: LongInt;
    CandPrev: LongInt;
    ResBank: array[0..5, 0..256] of LongInt;

    S3Counter: array[0..7] of LongInt;
    S3PredTab: array[0..7] of Byte;
    S3Streak: LongInt;
    S3Idx: Byte;
    S3Active: Byte;
    S3DirSaved: Byte;
    RecentDistance: array[0..MaxRecentDistances - 1] of Cardinal;
    procedure Reset;
    procedure RememberDistance(Dist: Cardinal);
    function RecallDistance(Slot: Integer): Cardinal;
  end;

  TAlzDecoder = record
    Reader: TByteReader;
    Rc: TRangeDecoder;
    Mode: TAlzMode;
    State: TAlzState;
    Window: array of Byte;

    TokenClass: array[0..65, 0..5] of Word;
    LiteralAdjust: array[0..1035] of Word;
    LengthTree: array[0..32767] of Word;
    DistanceTree: array[0..3075] of Word;
    DistanceSlotFast: array[0..63] of Word;
    DistanceSlotNormal: array[0..127] of Word;
    LengthByBucket: array[0..5, 0..63] of Word;
    TokenHistory: array[0..65535] of Byte;
    LengthHistory: array[0..262143] of Byte;
    LongDistanceBit: Word;

    BMTree: array[0..BM_NCTX-1, 0..255] of Word;
    BMFreq: array[0..BM_NCTX-1, 0..255] of Word;
    BMEW: array[0..BM_NCTX-1] of Word;
    BMCounter: array[0..BM_NCTX-1] of Cardinal;
    BMMixer: Cardinal;
    BMAcc80, BMAcc8c, BMAcc90: Cardinal;
    BMTable: array[0..255] of Cardinal;
    BMPCounter: Byte;
    BMFlag: Byte;
    BMPredB: Byte;
    BMEscCtx: Integer;

    MSlotShort: array[0..63] of Word;
    MSlotLong: array[0..63] of Word;
    MLowBit: Word;
    MLength: array[0..8191] of Word;
    MLenPred: array[0..$3FFFF] of Byte;

    procedure Init(const FileData: array of Byte; Order: Integer; USize: Cardinal);
    procedure ResetModels;
    procedure ResetByteModel;
    procedure RebuildBlockModel;
    function BMGetThreshold(Total: Cardinal): Cardinal;
    procedure BMRemove(Low, Width: Cardinal);
    procedure BMSse(Width, Total: Cardinal);
    procedure BMFenwickAdd(Ctx, Sym: Integer; Step: Word);
    procedure BMRebuildFenwick(Ctx: Integer);
    function BMCtxTotal(C: Integer): Word;
    function BMInContext(C: Integer; Bx, Threshold, SseTotal: Cardinal): Integer;
    function BMDecodeFromContexts(Ctx, Ctx2: Integer): Integer;
    procedure BMRescaleEntry(Ctx: Integer);
    procedure BMRescaleCtx2(Ctx: Integer);
    procedure BMEscapeIncrement(InnerCtx, Sym: Integer);
    procedure BMUpdate(Ctx, Sym: Integer);
    function BMTotalOfFor(C: Integer): Cardinal;
    function BMKnownMap(C, Sym: Integer; ExcludeCtx: Integer): Cardinal;
    function BMSseEval(Ctx, Sym: Integer): Cardinal;
    procedure BMPredTail(Mixer: Cardinal; DoAcc80, DoAcc90: Boolean);
    function BMDecodeLiteral(Ctx, Ctx2: Integer): Integer;
    procedure ResetMatchModel;
    function MDistSlot(var ProbArr: array of Word; const Trans: array of Byte;
      InitState, Fallback: Integer): Integer;
    function MUniform(Total: Cardinal): Cardinal;
    function MClass1Dist: Cardinal;
    function MLengthDecode(Cls: Integer; Dist: Cardinal): Integer;
    function MDecodeMatch(Token: Integer; var Dist, Count: Cardinal): Boolean;
    procedure UpdateLiteralMode(DecodedClass: Integer);
    procedure PutByte(B: Byte; var OutBuf: array of Byte);
    function PreviousByte(Distance: Cardinal): Byte;
    procedure CopyMatch(Distance, Count: Cardinal; var OutBuf: array of Byte);
    function SourceByteAfterMatch(Distance, Count, SourceWindowPosBeforeCopy: Cardinal): Byte;
    function SourcePairKeyBeforeMatch(Distance: Cardinal): Word;
    function TokenHistoryKey: Word;
    procedure UpdateTokenHistory(Key: Word; DecodedClass: Integer);

    function DecodeTokenClass: Integer;
    function DecodeEscapeSelector: Integer;
    procedure HandleEscapeClass;
    function LiteralContext(PredictorKind: Integer): Integer;
    function DecodeLiteral(Context: Integer; Predicted: Byte): Byte;
    function SideDecodeLiteral: Byte;
    procedure SidePostUpdate(OutputByte: Byte);
    procedure SideRecomputeBase(Delta: Byte);
    procedure MMSlotUpdate(S: Integer; OutByte, DeltaByte: Byte);
    procedure MMScore(S: Integer);
    procedure MMSlotUpdate6(OutByte, DeltaByte: Byte);
    procedure MMScore6(Sel: Integer);
    procedure ApplyPostMatchLiteralAdjustment(Actual, Predicted: Byte);
    function DecodeFixedTree(var Tree: array of Word; FirstNode, LeafLimit: Integer;
      MoveToLeafOnZero: Boolean): Integer;
    function DecodeTransitionTree(var Tree: array of Word; const Next: array of Byte;
      FirstNode: Integer; InitialResult: Integer; RememberZeroNode: Boolean;
      AdaptShift: Integer): Integer;
    function DecodeExtraBits(BitCount: Integer; Context: Cardinal): Cardinal;
    function DecodeDistanceSuffix(Slot: Integer; Span: Cardinal): Cardinal;
    function DecodeLengthSymbol(Group: Integer; MinSymbol, ForceRightLimit, PreviousLength, OlderLength: Integer): Integer;
    function DistanceBucket(Distance: Cardinal): Integer;
    function DecodeDistanceSlot(Token: Integer): Integer;
    function DecodeDistanceFromSlot(Token, Slot: Integer): Cardinal;
    function ConstrainDistanceSpanToHistory(Base, Span: Cardinal): Cardinal;
    function DecodeMatchLength(Token: Integer; Distance: Cardinal): Cardinal;
    function DecodeLengthAndDistance(Token: Integer; var Distance, Count: Cardinal): Boolean;
    function DecodeItem(var OutBuf: array of Byte): Boolean;
    function DecodeTo(USize: Cardinal; const MemberEnds: array of Cardinal;
      var OutBuf: array of Byte): Integer;
  end;

{$I ALZ_LITERAL.inc}
{$I ALZ_MATCH.inc}

procedure TByteReader.Init(const Src: array of Byte);
begin
  if Length(Src) = 0 then
    Data := nil
  else
    Data := @Src[0];
  Size := Length(Src);
  Pos := 0;
  Exhausted := False;
end;

function TByteReader.ReadByte: Byte;
begin
  if Pos >= Size then
  begin
    Exhausted := True;
    Result := 0;
    Exit;
  end;
  Result := PByte(NativeUInt(Data) + NativeUInt(Pos))^;
  Inc(Pos);
end;

procedure TRangeDecoder.Init(var R: TByteReader);
var
  I: Integer;
begin
  Reader := @R;
  Code := 0;
  Range := $FFFFFFFF;
  Corrupt := False;
  for I := 0 to 4 do
    Code := (Code shl 8) or Reader^.ReadByte;
  if Reader^.Exhausted then
    Corrupt := True;
end;

procedure TRangeDecoder.Normalize;
begin
  while Range < RangeTop do
  begin
    Code := (Code shl 8) or Reader^.ReadByte;
    Range := Range shl 8;
    if Reader^.Exhausted then
      Corrupt := True;
  end;
end;

function TRangeDecoder.GetThreshold(Total: Cardinal): Cardinal;
begin
  if (Total = 0) or Corrupt then
  begin
    Corrupt := True;
    Result := 0;
    Exit;
  end;
  Range := Range div Total;
  Result := Code div Range;
  if Result >= Total then
  begin
    if GetEnvironmentVariable('ALZ_DBG') <> '' then
      writeln(ErrOutput, 'CORRUPT@GetThreshold Result=', Result, ' Total=', Total,
        ' Code=', Code, ' Range=', Range);
    Corrupt := True;
    Result := Total - 1;
  end;
end;

procedure TRangeDecoder.RemoveInterval(Low, High, Total: Cardinal);
begin
  if (High <= Low) or (High > Total) or Corrupt then
  begin
    Corrupt := True;
    Exit;
  end;
  Code := Code - (Range * Low);
  Range := Range * (High - Low);
  Normalize;
end;

function TRangeDecoder.DecodeUniform(Total: Cardinal): Cardinal;
var
  T: Cardinal;
begin
  T := GetThreshold(Total);
  RemoveInterval(T, T + 1, Total);
  Result := T;
end;

function TRangeDecoder.DecodeBit(var Prob: Word): Integer;
var
  T: Cardinal;
begin
  T := GetThreshold(FixedProbScale);
  if T < Prob then
  begin
    RemoveInterval(0, Prob, FixedProbScale);
    Prob := Prob + ((FixedProbScale - Prob) shr 6);
    Result := 0;
  end
  else
  begin
    RemoveInterval(Prob, FixedProbScale, FixedProbScale);
    Prob := Prob - (Prob shr 6);
    Result := 1;
  end;
end;

function TRangeDecoder.DecodeBitFast12(var Prob: Word): Integer;
begin
  Result := DecodeBitFast12Shift(Prob, 6);
end;

function TRangeDecoder.DecodeBitFast12Shift(var Prob: Word; Shift: Integer): Integer;
var
  T: Cardinal;
begin
  if Corrupt then
  begin
    Result := 0;
    Exit;
  end;

  if Shift < 1 then
    Shift := 1
  else if Shift > 12 then
    Shift := 12;

  Range := Range shr 12;
  if Range = 0 then
  begin
    Corrupt := True;
    Result := 0;
    Exit;
  end;

  T := Code div Range;
  if T >= FixedProbScale then
  begin
    if GetEnvironmentVariable('ALZ_DBG') <> '' then
      writeln(ErrOutput, 'CORRUPT@BitFast12Shift T=', T, ' scale=', FixedProbScale,
        ' Code=', Code, ' Range=', Range, ' Prob=', Prob);
    Corrupt := True;
    T := FixedProbScale - 1;
  end;

  if T < Prob then
  begin
    Range := Range * Prob;
    Prob := Prob + Word((FixedProbScale - Prob) shr Shift);
    Result := 0;
  end
  else
  begin
    Code := Code - Range * Prob;
    Range := Range * (FixedProbScale - Prob);
    Prob := Prob - Word(Prob shr Shift);
    Result := 1;
  end;
  Normalize;
end;

procedure TAlzProbTree.Init(NodeCount: Integer; Initial: Word);
var
  I: Integer;
begin
  SetLength(Prob, NodeCount);
  for I := 0 to NodeCount - 1 do
    Prob[I] := Initial;
end;

function TAlzProbTree.DecodeLeaf(var Rc: TRangeDecoder; FirstNode: Integer;
  const Next: array of Byte): Integer;
var
  Node, Bit: Integer;
begin
  Node := 1;
  repeat
    Bit := Rc.DecodeBitFast12(Prob[FirstNode + Node]);
    Node := Node * 2 + Bit;
    if Node < Length(Next) then
      Node := Next[Node]
    else
      Node := 0;
  until (Node = 0) or Rc.Corrupt;
  Result := Node;
end;

procedure TAlzState.Reset;
var
  I: Integer;
begin
  LastByte := 0;
  PrevByte := 0;
  PrevDelta := 0;
  MatchFlagByte := 0;
  LiteralMode := 0;
  RepeatRun := 0;
  OutputPos := 0;
  WindowPos := 0;
  RollingHistory := 0;
  LastMatchTailByte := 0;
  RangeModelEpoch := 0;
  EscapeSelector := 0;
  EscapeChanged := False;
  EscapeModelFlag := 0;
  EscapeLiteralBias := 0;
  SideModelPrimaryKind := AlzSelectorPrimaryKind[0];
  SideModelSecondaryBase := AlzSelectorSecondaryBase[0];
  SideBias := 0;
  SideDir := 0;
  BMSideActive := False;
  SideModCount := 0;
  for I := 0 to 15 do begin SlotHash[I] := $FFFFFFFF; SlotDir[I] := 0; end;
  FillChar(MMHist, SizeOf(MMHist), 0);
  FillChar(MMCoef, SizeOf(MMCoef), 0);
  FillChar(MMLast, SizeOf(MMLast), 0);
  FillChar(MMDelta, SizeOf(MMDelta), 0);
  FillChar(MMAcc, SizeOf(MMAcc), 0);
  FillChar(MMCost5c, SizeOf(MMCost5c), 0);
  FillChar(MMCost60, SizeOf(MMCost60), 0);
  FillChar(MMCost64, SizeOf(MMCost64), 0);
  FillChar(MMCost68, SizeOf(MMCost68), 0);
  FillChar(MMCounter, SizeOf(MMCounter), 0);
  MMGlobal := 0;
  MMGlobal2 := 0;
  MMPrevScore := 0;
  MMOutCount := 0;
  FillChar(CandAcc, SizeOf(CandAcc), 0);
  FillChar(DeltaRing, SizeOf(DeltaRing), 0);
  FillChar(CandScore, SizeOf(CandScore), 0);
  FillChar(ResBank, SizeOf(ResBank), 0);
  FillChar(SlotHash74, SizeOf(SlotHash74), 0);
  FillChar(SlotHash78, SizeOf(SlotHash78), 0);

  FillChar(S3Counter, SizeOf(S3Counter), 0);
  FillChar(S3PredTab, SizeOf(S3PredTab), 0);
  S3Streak := 0; S3Idx := 0; S3Active := 0; S3DirSaved := 0;
  CandBest0 := 0; CandBest1 := 0; CandBest2 := 0; CandCur := 0; CandPrev := 0;
  for I := 0 to MaxRecentDistances - 1 do
    RecentDistance[I] := 1;
end;

procedure TAlzState.RememberDistance(Dist: Cardinal);
var
  I: Integer;
begin
  if Dist = 0 then
    Exit;

  for I := MaxRecentDistances - 1 downto 1 do
    RecentDistance[I] := RecentDistance[I - 1];
  RecentDistance[0] := Dist;
end;

function TAlzState.RecallDistance(Slot: Integer): Cardinal;
var
  I: Integer;
  D: Cardinal;
begin
  if Slot < 0 then
    Slot := 0
  else if Slot >= MaxRecentDistances then
    Slot := MaxRecentDistances - 1;

  D := RecentDistance[Slot];
  if D = 0 then
    D := 1;

  for I := Slot downto 1 do
    RecentDistance[I] := RecentDistance[I - 1];
  RecentDistance[0] := D;
  Result := D;
end;

procedure TAlzDecoder.Init(const FileData: array of Byte; Order: Integer; USize: Cardinal);
begin
  Reader.Init(FileData);
  State.Reset;

  if (Order >= 40) and (Order <= 55) then
    Mode.MethodClass := alzFast
  else if (Order >= 56) and (Order <= 71) then
    Mode.MethodClass := alzNormal
  else if (Order >= 72) and (Order <= 87) then
    Mode.MethodClass := alzBest
  else
    Mode.MethodClass := alzFast;

  Mode.DictionarySize := Cardinal(1) shl (Cardinal((Order - 40) mod 16) + 10);
  if Mode.DictionarySize < 1024 then
    Mode.DictionarySize := 1024;
  Mode.DictionaryMask := Mode.DictionarySize - 1;
  Mode.RebuildPeriod := USize;
  SetLength(Window, Mode.DictionarySize + 4096);

  ResetModels;
  Rc.Init(Reader);

  HandleEscapeClass;
end;

procedure TAlzDecoder.ResetModels;
var
  I, J: Integer;
begin

  for I := 0 to High(TokenClass) do
  begin
    if I < 64 then
      for J := 0 to 5 do
        TokenClass[I, J] := AlzTokenSeedNormal[J]
    else
      for J := 0 to 5 do
        TokenClass[I, J] := AlzTokenSeedRepeat[J];
  end;

  for I := 0 to High(LiteralAdjust) do
    LiteralAdjust[I] := InitProb;

  for I := 0 to High(LengthTree) do
    LengthTree[I] := InitProb;

  for I := 0 to High(DistanceTree) do
    DistanceTree[I] := InitProb;

  for I := 0 to High(DistanceSlotFast) do
    DistanceSlotFast[I] := InitProb;

  for I := 0 to High(DistanceSlotNormal) do
    DistanceSlotNormal[I] := InitProb;

  for I := 0 to High(LengthByBucket) do
    for J := 0 to High(LengthByBucket[I]) do
      LengthByBucket[I, J] := InitProb;

  for I := 0 to High(TokenHistory) do
    TokenHistory[I] := 0;

  for I := 0 to High(LengthHistory) do
    LengthHistory[I] := 0;

  LongDistanceBit := InitProb;

  ResetByteModel;
  ResetMatchModel;
end;

procedure TAlzDecoder.UpdateLiteralMode(DecodedClass: Integer);
var
  Index, OldMode: Integer;
begin

  if DecodedClass <= 0 then
    Exit;

  OldMode := State.LiteralMode and 31;
  Index := ((DecodedClass - 1) shl 5) + OldMode;
  if (Index < 0) or (Index > High(AlzLiteralModeNext)) then
  begin
    Rc.Corrupt := True;
    Exit;
  end;
  State.LiteralMode := AlzLiteralModeNext[Index];
end;

procedure TAlzDecoder.PutByte(B: Byte; var OutBuf: array of Byte);
begin
  if State.OutputPos <= Cardinal(High(OutBuf)) then
    OutBuf[State.OutputPos] := B;
  Window[State.WindowPos and Mode.DictionaryMask] := B;
  Inc(State.OutputPos);
  State.WindowPos := (State.WindowPos + 1) and Mode.DictionaryMask;

  State.RollingHistory := ((State.RollingHistory shl 8) or B) and $FFFFFFFF;

  State.PrevDelta := Byte(B - State.LastByte);
  State.PrevByte := State.LastByte;
  State.LastByte := B;
end;

function TAlzDecoder.PreviousByte(Distance: Cardinal): Byte;
var
  P: Cardinal;
begin
  if Distance = 0 then
    Distance := 1;
  P := (State.WindowPos - Distance) and Mode.DictionaryMask;
  Result := Window[P];
end;

procedure TAlzDecoder.CopyMatch(Distance, Count: Cardinal; var OutBuf: array of Byte);
var
  I: Cardinal;
  B: Byte;
begin

  for I := 0 to Count - 1 do
  begin
    B := PreviousByte(Distance);
    PutByte(B, OutBuf);
    if State.EscapeSelector <> 0 then
      SidePostUpdate(B);
  end;
end;

function TAlzDecoder.SourceByteAfterMatch(Distance, Count, SourceWindowPosBeforeCopy: Cardinal): Byte;
var
  SourceStart, SourceAfter: Cardinal;
begin

  if Distance = 0 then
    Distance := 1;
  SourceStart := (SourceWindowPosBeforeCopy - Distance) and Mode.DictionaryMask;
  SourceAfter := (SourceStart + Count) and Mode.DictionaryMask;
  Result := Window[SourceAfter];
end;

function TAlzDecoder.SourcePairKeyBeforeMatch(Distance: Cardinal): Word;
var
  P0, P1: Cardinal;
  B0, B1: Byte;
begin

  if Distance = 0 then
    Distance := 1;
  P0 := (State.WindowPos - Distance) and Mode.DictionaryMask;
  P1 := (P0 + 1) and Mode.DictionaryMask;
  B0 := Window[P0];
  B1 := Window[P1];
  Result := Word((Cardinal(B0) shl 8) or B1);
end;

function TAlzDecoder.TokenHistoryKey: Word;
begin

  Result := Word(State.RollingHistory and $FFFF);
end;

procedure TAlzDecoder.UpdateTokenHistory(Key: Word; DecodedClass: Integer);
var
  Stored, ClassMinusOne: Byte;
begin

  if DecodedClass <= 0 then
    Exit;

  ClassMinusOne := Byte((DecodedClass - 1) and 3);
  Stored := TokenHistory[Key];
  if (Stored shr 6) = ClassMinusOne then
  begin
    if (Stored and 63) <> 63 then
      Inc(Stored);
  end
  else
    Stored := ClassMinusOne shl 6;
  TokenHistory[Key] := Stored;
end;

function TAlzDecoder.DecodeTokenClass: Integer;
var
  ClassIndex, I: Integer;
  Total, Threshold, Low, High: Cardinal;
  HistKey: Word;
  HistByte: Byte;
  ProbedHistoryContext: Boolean;
  Freq: array[0..4] of Cardinal;
begin

  ProbedHistoryContext := False;
  HistKey := TokenHistoryKey;

  if State.RepeatRun <> 0 then
  begin
    if State.RepeatRun > 2 then
      ClassIndex := 65
    else
      ClassIndex := 64;
  end
  else
  begin
    ClassIndex := State.LiteralMode;

    if ClassIndex <= 15 then
    begin
      ProbedHistoryContext := True;
      HistByte := TokenHistory[HistKey];
      if (HistByte and $38) <> 0 then
        ClassIndex := 32 + (HistByte shr 3);
    end;
    if ClassIndex > 63 then
      ClassIndex := 63;
  end;

  Total := TokenClass[ClassIndex, 5];
  if Total = 0 then
  begin
    Rc.Corrupt := True;
    Result := 0;
    Exit;
  end;

  if (GetEnvironmentVariable('ALZ_DBG') <> '') and (State.OutputPos = 0) then
    writeln(ErrOutput, 'TokClass entry: Code=', IntToHex(Rc.Code,8), ' Range=', IntToHex(Rc.Range,8),
      ' ClassIndex=', ClassIndex, ' Total=', Total, ' LiteralMode=', State.LiteralMode,
      ' RepeatRun=', State.RepeatRun);
  Threshold := Rc.GetThreshold(Total);
  Result := 4;
  for I := 4 downto 0 do
  begin
    if Threshold >= TokenClass[ClassIndex, I] then
    begin
      Result := I;
      Break;
    end;
  end;

  Low := TokenClass[ClassIndex, Result];
  if Result = 4 then
    High := TokenClass[ClassIndex, 5]
  else
    High := TokenClass[ClassIndex, Result + 1];

  Rc.RemoveInterval(Low, High, Total);

  if Result <> 0 then
  begin
    for I := Result + 1 to 4 do
      TokenClass[ClassIndex, I] := Word(Cardinal(TokenClass[ClassIndex, I]) + 88);
    TokenClass[ClassIndex, 5] := Word(Cardinal(TokenClass[ClassIndex, 5]) + 88);
    Inc(State.RangeModelEpoch);

    if TokenClass[ClassIndex, 5] >= 16384 then
    begin

      Freq[1] := TokenClass[ClassIndex, 2] - TokenClass[ClassIndex, 1];
      Freq[2] := TokenClass[ClassIndex, 3] - TokenClass[ClassIndex, 2];
      Freq[3] := TokenClass[ClassIndex, 4] - TokenClass[ClassIndex, 3];
      Freq[4] := TokenClass[ClassIndex, 5] - TokenClass[ClassIndex, 4];

      for I := 1 to 4 do
        Freq[I] := (Freq[I] + 1) shr 1;

      TokenClass[ClassIndex, 2] := Word(Cardinal(TokenClass[ClassIndex, 1]) + Freq[1]);
      TokenClass[ClassIndex, 3] := Word(Cardinal(TokenClass[ClassIndex, 2]) + Freq[2]);
      TokenClass[ClassIndex, 4] := Word(Cardinal(TokenClass[ClassIndex, 3]) + Freq[3]);
      TokenClass[ClassIndex, 5] := Word(Cardinal(TokenClass[ClassIndex, 4]) + Freq[4]);
    end;

    if ProbedHistoryContext then
      UpdateTokenHistory(HistKey, Result);

    UpdateLiteralMode(Result);
  end;
end;

function TAlzDecoder.DecodeEscapeSelector: Integer;
begin

  Result := Integer(Rc.DecodeUniform(11));
  if Result < 0 then
    Result := 0
  else if Result > 10 then
    Result := 10;
end;

procedure TAlzDecoder.HandleEscapeClass;
var
  Selector, I: Integer;
begin
  Selector := DecodeEscapeSelector;
  if (GetEnvironmentVariable('ALZ_DBG') <> '') and (State.OutputPos <= 2) then
    writeln(ErrOutput, 'ESC out=', State.OutputPos, ' Selector=', Selector,
      ' prevEscSel=', State.EscapeSelector, ' Code=', IntToHex(Rc.Code, 8));
  if Rc.Corrupt then
    Exit;

  if Selector = State.EscapeSelector then
  begin
    State.EscapeChanged := False;
    Exit;
  end;

  State.EscapeChanged := Selector = 10;

  if Selector = 10 then
  begin
    for I := $200 to $2FF do
      BMRescaleEntry(I);
    Selector := 0;
  end;

  State.EscapeSelector := Byte(Selector);

  State.SideModelPrimaryKind := AlzSelectorPrimaryKind[Selector];
  State.SideModelSecondaryBase := AlzSelectorSecondaryBase[Selector];
  State.EscapeLiteralBias := AlzSelectorLiteralBias[Selector];

  State.SideDir := 0;
  State.SideBias := 0;
  State.SideModCount := 0;

  if Selector >= 5 then
  begin
    FillChar(State.MMHist, SizeOf(State.MMHist), 0);
    FillChar(State.MMCoef, SizeOf(State.MMCoef), 0);
    FillChar(State.MMLast, SizeOf(State.MMLast), 0);
    FillChar(State.MMDelta, SizeOf(State.MMDelta), 0);
    FillChar(State.MMAcc, SizeOf(State.MMAcc), 0);
    FillChar(State.MMCost5c, SizeOf(State.MMCost5c), 0);
    FillChar(State.MMCost60, SizeOf(State.MMCost60), 0);
    FillChar(State.MMCost64, SizeOf(State.MMCost64), 0);
    FillChar(State.MMCost68, SizeOf(State.MMCost68), 0);
    FillChar(State.MMCounter, SizeOf(State.MMCounter), 0);
    State.MMGlobal := 0;
    State.MMGlobal2 := 0;
    State.MMPrevScore := 0;

    FillChar(State.CandAcc, SizeOf(State.CandAcc), 0);
    FillChar(State.DeltaRing, SizeOf(State.DeltaRing), 0);
    FillChar(State.CandScore, SizeOf(State.CandScore), 0);
    FillChar(State.ResBank, SizeOf(State.ResBank), 0);
    State.CandCur := 0; State.CandPrev := 0;
    State.CandBest0 := 0; State.CandBest1 := 0; State.CandBest2 := 2;
    for I := 0 to 15 do
    begin
      State.SlotDir[I] := 0;
      if I <= 3 then State.SlotHash[I] := $FFFFFFFF else State.SlotHash[I] := 0;
      if I <= 2 then
      begin State.SlotHash74[I] := $FFFFFFFF; State.SlotHash78[I] := $FFFFFFFF; end
      else
      begin State.SlotHash74[I] := 0; State.SlotHash78[I] := 0; end;
    end;
  end;

  if (Selector = 5) or (Selector = 6) then
    State.EscapeModelFlag := 1
  else
    State.EscapeModelFlag := 0;

end;

function TAlzDecoder.LiteralContext(PredictorKind: Integer): Integer;
var
  Base: Cardinal;
begin

  if PredictorKind < 0 then
    PredictorKind := 0
  else if PredictorKind > 3 then
    PredictorKind := 3;

  Base := State.SideModelSecondaryBase;
  if Base = 0 then
    Base := 1025;

  Result := Integer(Base + Cardinal(PredictorKind) +
    ((State.SideModelPrimaryKind and 3) shl 3) + State.EscapeLiteralBias);

  if Result < 0 then
    Result := 0
  else if Result > High(LiteralAdjust) then
    Result := High(LiteralAdjust);
end;

function TAlzDecoder.DecodeLiteral(Context: Integer; Predicted: Byte): Byte;
var
  Last, Prev, Ctx, Ctx2: Integer;
begin

  Last := State.LastByte;
  Prev := State.PrevByte;
  if not State.EscapeChanged then
  begin
    Ctx := Last;
    if (Last and $C0) = (Prev and $C0) then Ctx := Ctx + $100;
    Ctx2 := ((Last and $E0) shr 5) + $3F9;
  end
  else
  begin
    Ctx := Last + $200; Ctx2 := $401;
  end;
  State.BMSideActive := False;
  Result := Byte(BMDecodeLiteral(Ctx, Ctx2));
end;

function TAlzDecoder.SideDecodeLiteral: Byte;
var
  Ctx, Ctx2, Decoded: Integer;
  Bias: Byte;
begin
  Ctx := Integer(State.SideModelSecondaryBase);
  Ctx2 := $402 + State.EscapeSelector;
  Bias := State.SideBias;

  if BMFlag <> 0 then
  begin
    if State.SideDir = 0 then
      BMPredB := Byte(BMPredB - Bias)
    else
      BMPredB := Byte(Bias - BMPredB);
  end;

  State.BMSideActive := True;
  Decoded := BMDecodeLiteral(Ctx, Ctx2);

  if State.SideDir = 0 then
    Result := Byte(Bias + Decoded)
  else
    Result := Byte(Bias - Decoded);
end;

procedure TAlzDecoder.SidePostUpdate(OutputByte: Byte);
var
  Delta: Byte;
  OldEdi, NewEdi, Base7: Integer;
  OldSMC, BaseIdx, RefB, IdxB, StatIdx, Pred: Integer;
  Confident, Active: Boolean;
begin

  Delta := Byte(OutputByte - State.SideBias);
  if State.SideDir <> 0 then
    Delta := Byte(-Delta);
  if Delta >= $80 then
  begin
    if State.SideDir = 0 then State.SideDir := 1 else State.SideDir := 0;
  end;

  if (State.EscapeSelector >= 1) and (State.EscapeSelector <= 4)
     and (State.EscapeSelector <> 3) then
  begin
    case State.EscapeSelector of
      1: State.SideModelSecondaryBase := Cardinal($301 +
           (Integer(AlzSelTab16[(Integer(State.SideModelSecondaryBase) - $301) and $F]) shl 4) +
           Integer(AlzSelTab2[Delta]));
      2: State.SideModelSecondaryBase := Cardinal($321 +
           (Integer(State.SideModCount) shl 4) + Integer(AlzSelTab2[Delta]));
      4: State.SideModelSecondaryBase := Cardinal($3A1 +
           (Integer(State.SideModCount) shl 4) + Integer(AlzSelTab2[Delta]));
    end;

    if State.SideModelPrimaryKind <> 0 then
      State.SideModCount := State.OutputPos mod State.SideModelPrimaryKind
    else
      State.SideModCount := 0;
    State.SideBias := Byte(State.RollingHistory shr State.EscapeLiteralBias);
    Inc(State.MMOutCount);
    Exit;
  end;

  if (State.EscapeSelector = 5) or (State.EscapeSelector = 6) then
  begin

    if State.EscapeSelector = 5 then
      MMSlotUpdate6(Byte(OutputByte xor $80), Delta)
    else
      MMSlotUpdate6(OutputByte, Delta);
    Inc(State.MMOutCount);
    if State.SideModelPrimaryKind <> 0 then
      State.SideModCount := State.OutputPos mod State.SideModelPrimaryKind
    else
      State.SideModCount := 0;
    State.SideBias := Byte(State.RollingHistory shr State.EscapeLiteralBias);
    MMScore6(State.EscapeSelector);
    Exit;
  end;

  if State.EscapeSelector = 7 then
  begin
    OldEdi := Integer(State.SideModCount) and $F;
    MMSlotUpdate(OldEdi, Byte(OutputByte xor $80), Delta);
    Inc(State.MMOutCount);
    if State.SideModelPrimaryKind <> 0 then
      NewEdi := Integer(State.OutputPos mod State.SideModelPrimaryKind)
    else
      NewEdi := 0;
    State.SideModCount := Cardinal(NewEdi);
    MMScore(NewEdi);
    State.SideBias := Byte(State.SideBias + $80);
    Base7 := $3E9 + NewEdi;
    if State.SlotHash[NewEdi and $F] = 0 then Base7 := Base7 + 2
    else if State.SlotHash74[NewEdi and $F] = 0 then Base7 := Base7 + 4
    else if State.SlotHash78[NewEdi and $F] = 0 then Base7 := Base7 + 6;
    State.SideModelSecondaryBase := Cardinal(Base7);
    State.SideDir := State.SlotDir[NewEdi and $F];
    Exit;
  end;

  if State.EscapeSelector = 3 then
  begin
    OldSMC := Integer(State.SideModCount);

    if State.S3Active <> 0 then
    begin

      RefB := (Integer(State.RollingHistory) shr 24) and $FF;
      IdxB := (Integer(OutputByte) - RefB) and $FF;
      State.SideDir := State.S3DirSaved;
      if State.SideDir <> 0 then IdxB := (-IdxB) and $FF;
      if IdxB >= $80 then
        if State.SideDir = 0 then State.SideDir := 1 else State.SideDir := 0;
      BaseIdx := IdxB;
    end
    else
      BaseIdx := Delta;

    if Integer(OutputByte) = Integer(State.S3PredTab[State.S3Idx]) then
      Inc(State.S3Counter[State.S3Idx])
    else
      State.S3Counter[State.S3Idx] := State.S3Counter[State.S3Idx] shr 1;
    State.SideModelSecondaryBase :=
      Cardinal($341 + (OldSMC shl 5) + Integer(AlzS3Tab[BaseIdx and $FF]));

    Inc(State.MMOutCount);
    if State.SideModelPrimaryKind <> 0 then
      State.SideModCount := State.OutputPos mod State.SideModelPrimaryKind
    else
      State.SideModCount := 0;
    State.SideBias := Byte(State.RollingHistory shr State.EscapeLiteralBias);

    StatIdx := Integer(State.OutputPos mod 6);
    State.S3Idx := Byte(StatIdx);
    Confident := State.S3Counter[StatIdx] > 8;
    Pred := (Integer(State.SideBias)
             + (Integer(State.RollingHistory) and $FF)
             - ((Integer(State.RollingHistory) shr 24) and $FF)) and $FF;
    State.S3PredTab[StatIdx] := Byte(Pred);
    Active := Confident and (State.S3Streak < 5);
    if Active then State.S3Active := 1 else State.S3Active := 0;
    if Active then
    begin
      State.S3DirSaved := State.SideDir;
      State.SideModelSecondaryBase := Cardinal($351 + (OldSMC shl 5));
      State.SideBias := State.S3PredTab[StatIdx];
      State.SideDir := 0;
    end;
    if Confident then Inc(State.S3Streak) else State.S3Streak := 0;
    Exit;
  end;

  if State.EscapeSelector < 8 then
  begin
    SideRecomputeBase(Delta);
    Exit;
  end;

  OldEdi := Integer(State.SideModCount) and $F;
  MMSlotUpdate(OldEdi, OutputByte, Delta);
  Inc(State.MMOutCount);

  if State.SideModelPrimaryKind <> 0 then
    NewEdi := Integer(State.OutputPos mod State.SideModelPrimaryKind)
  else
    NewEdi := 0;
  State.SideModCount := Cardinal(NewEdi);

  MMScore(NewEdi);
  if State.SlotHash[NewEdi and $F] <> 0 then
    State.SideModelSecondaryBase :=
      AlzSelectorSecondaryBase[State.EscapeSelector] + Cardinal(NewEdi)
  else
    State.SideModelSecondaryBase :=
      AlzSelectorSecondaryBase[State.EscapeSelector] + 4;
  State.SideDir := State.SlotDir[NewEdi and $F];
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

procedure TAlzDecoder.MMSlotUpdate(S: Integer; OutByte, DeltaByte: Byte);
var
  OutS, BaseVal, MinV, V: LongInt;
  I, K: Integer;
begin
  State.SlotDir[S] := State.SideDir;
  OutS := AlzSExt8(OutByte);
  BaseVal := AlzSExt8(Byte(State.MMPrevScore - OutS)) shl 4;

  State.MMAcc[S, 0] := State.MMAcc[S, 0] + AlzMMW(BaseVal);
  State.MMAcc[S, 1] := State.MMAcc[S, 1] + AlzMMW(BaseVal - State.MMHist[S, 0]);
  State.MMAcc[S, 2] := State.MMAcc[S, 2] + AlzMMW(BaseVal + State.MMHist[S, 0]);
  State.MMAcc[S, 3] := State.MMAcc[S, 3] + AlzMMW(BaseVal - State.MMHist[S, 1]);
  State.MMAcc[S, 4] := State.MMAcc[S, 4] + AlzMMW(BaseVal + State.MMHist[S, 1]);
  State.MMAcc[S, 5] := State.MMAcc[S, 5] + AlzMMW(BaseVal - State.MMHist[S, 2]);
  State.MMAcc[S, 6] := State.MMAcc[S, 6] + AlzMMW(BaseVal + State.MMHist[S, 2]);
  State.MMAcc[S, 7] := State.MMAcc[S, 7] + AlzMMW(BaseVal - State.MMHist[S, 3]);
  State.MMAcc[S, 8] := State.MMAcc[S, 8] + AlzMMW(BaseVal + State.MMHist[S, 3]);
  State.MMAcc[S, 9] := State.MMAcc[S, 9] + AlzMMW(BaseVal - State.MMGlobal);
  State.MMAcc[S, 10] := State.MMAcc[S, 10] + AlzMMW(BaseVal + State.MMGlobal);

  State.MMCost5c[S] := State.MMCost5c[S] +
    LongInt(AlzMMCost[Byte(State.MMPrevScore - OutS) and $FF]);
  State.MMCost60[S] := State.MMCost60[S] +
    LongInt(AlzMMCost[Byte(State.MMLast[S] - OutS) and $FF]);
  State.MMDelta[S] := AlzSExt8(Byte(OutS - State.MMLast[S]));
  State.MMGlobal := State.MMDelta[S];
  Inc(State.MMCounter[S]);
  State.MMLast[S] := OutS;

  if (State.MMCounter[S] and $F) = 0 then
  begin

    MinV := State.MMAcc[S, 0]; K := 0; State.MMAcc[S, 0] := 0;
    for I := 1 to 10 do
    begin
      V := State.MMAcc[S, I];
      if MinV > V then begin MinV := V; K := I; end;
      State.MMAcc[S, I] := 0;
    end;
    Dec(K);
    case K of
      0: if State.MMCoef[S, 0] > -$20 then Dec(State.MMCoef[S, 0]);
      1: if State.MMCoef[S, 0] <  $20 then Inc(State.MMCoef[S, 0]);
      2: if State.MMCoef[S, 1] > -$20 then Dec(State.MMCoef[S, 1]);
      3: if State.MMCoef[S, 1] <  $20 then Inc(State.MMCoef[S, 1]);
      4: if State.MMCoef[S, 2] > -$20 then Dec(State.MMCoef[S, 2]);
      5: if State.MMCoef[S, 2] <  $20 then Inc(State.MMCoef[S, 2]);
      6: if State.MMCoef[S, 3] > -$20 then Dec(State.MMCoef[S, 3]);
      7: if State.MMCoef[S, 3] <  $20 then Inc(State.MMCoef[S, 3]);
      8: if State.MMCoef[S, 3] > -$20 then Dec(State.MMCoef[S, 4]);
      9: if State.MMCoef[S, 3] <  $20 then Inc(State.MMCoef[S, 4]);
    end;
    if (State.MMCounter[S] and $FF) = 0 then
    begin
      State.MMCost5c[S] := State.MMCost5c[S] - State.MMCost64[S];
      State.MMCost64[S] := State.MMCost5c[S];
      State.MMCost60[S] := State.MMCost60[S] - State.MMCost68[S];
      State.MMCost68[S] := State.MMCost60[S];
    end;
  end;

  if State.EscapeSelector = 9 then
  begin
    I := State.MMGlobal; State.MMGlobal := State.MMGlobal2; State.MMGlobal2 := I;
  end;

  State.SlotHash[S] := (State.SlotHash[S] shl 8 + DeltaByte) and $FFFFFFFF;

  if State.EscapeSelector = 7 then
  begin
    State.SlotHash74[S] := (State.SlotHash74[S] shl 8 + Cardinal(AlzS7BankC[DeltaByte])) and $FFFFFFFF;
    State.SlotHash78[S] := (State.SlotHash78[S] shl 8 + Cardinal(AlzS7BankD[DeltaByte])) and $FFFFFFFF;
  end;
end;

procedure TAlzDecoder.MMScore(S: Integer);
var
  NewH1, H1Old, H2Old, Score: LongInt;
begin
  H1Old := State.MMHist[S, 1];
  H2Old := State.MMHist[S, 2];
  NewH1 := State.MMDelta[S] - State.MMHist[S, 0];

  Score := (State.MMLast[S] shl 4)
         + State.MMCoef[S, 0] * State.MMDelta[S]
         + State.MMCoef[S, 1] * NewH1
         + State.MMCoef[S, 2] * H1Old
         + State.MMCoef[S, 3] * H2Old
         + State.MMCoef[S, 4] * State.MMGlobal;

  State.MMHist[S, 3] := H2Old;
  State.MMHist[S, 2] := H1Old;
  State.MMHist[S, 1] := NewH1;
  State.MMHist[S, 0] := State.MMDelta[S];

  Score := Score div 16;
  State.MMPrevScore := Score;

  if State.MMCost5c[S] > State.MMCost60[S] then
    State.SideBias := Byte(State.MMLast[S])
  else
    State.SideBias := Byte(Score);
end;

procedure TAlzDecoder.MMSlotUpdate6(OutByte, DeltaByte: Byte);
var
  OutS, BaseVal, RingDelta, MinV, V, Sum, D1, D2, D3, EdiMin: LongInt;
  I, K, A, Cnt, RingPos, Bv, GCnt: Integer;
  Res: array[0..5] of LongInt;
begin

  GCnt := Integer(State.OutputPos) - 1;
  OutS := AlzSExt8(OutByte);
  RingDelta := OutS - State.CandCur;
  BaseVal := AlzSExt8(Byte(State.CandScore[3] - OutS)) shl 4;

  State.MMAcc[0,0]  := State.MMAcc[0,0]  + AlzMMW(BaseVal);
  State.MMAcc[0,1]  := State.MMAcc[0,1]  + AlzMMW(BaseVal - State.MMHist[0,0]);
  State.MMAcc[0,2]  := State.MMAcc[0,2]  + AlzMMW(BaseVal + State.MMHist[0,0]);
  State.MMAcc[0,3]  := State.MMAcc[0,3]  + AlzMMW(BaseVal - State.MMHist[0,1]);
  State.MMAcc[0,4]  := State.MMAcc[0,4]  + AlzMMW(BaseVal + State.MMHist[0,1]);
  State.MMAcc[0,5]  := State.MMAcc[0,5]  + AlzMMW(BaseVal - State.MMHist[0,2]);
  State.MMAcc[0,6]  := State.MMAcc[0,6]  + AlzMMW(BaseVal + State.MMHist[0,2]);
  State.MMAcc[0,7]  := State.MMAcc[0,7]  + AlzMMW(BaseVal - State.MMHist[0,3]);
  State.MMAcc[0,8]  := State.MMAcc[0,8]  + AlzMMW(BaseVal + State.MMHist[0,3]);
  State.MMAcc[0,9]  := State.MMAcc[0,9]  + AlzMMW(BaseVal - State.MMHist[0,4]);
  State.MMAcc[0,10] := State.MMAcc[0,10] + AlzMMW(BaseVal + State.MMHist[0,4]);

  Inc(State.MMCounter[0]);
  State.MMDelta[0] := AlzSExt8(Byte(OutS - State.MMLast[0]));
  State.MMLast[0] := OutS;

  if (State.MMCounter[0] and $F) = 0 then
  begin
    MinV := State.MMAcc[0,0]; K := 0; State.MMAcc[0,0] := 0;
    for I := 1 to 10 do
    begin
      V := State.MMAcc[0,I];
      if MinV > V then begin MinV := V; K := I; end;
      State.MMAcc[0,I] := 0;
    end;
    Dec(K);
    case K of
      0: if State.MMCoef[0,0] > -$20 then Dec(State.MMCoef[0,0]);
      1: if State.MMCoef[0,0] <  $20 then Inc(State.MMCoef[0,0]);
      2: if State.MMCoef[0,1] > -$20 then Dec(State.MMCoef[0,1]);
      3: if State.MMCoef[0,1] <  $20 then Inc(State.MMCoef[0,1]);
      4: if State.MMCoef[0,2] > -$20 then Dec(State.MMCoef[0,2]);
      5: if State.MMCoef[0,2] <  $20 then Inc(State.MMCoef[0,2]);
      6: if State.MMCoef[0,3] > -$20 then Dec(State.MMCoef[0,3]);
      7: if State.MMCoef[0,3] <  $20 then Inc(State.MMCoef[0,3]);
      8: if State.MMCoef[0,3] > -$20 then Dec(State.MMCoef[0,4]);
      9: if State.MMCoef[0,3] <  $20 then Inc(State.MMCoef[0,4]);
    end;
  end;

  State.DeltaRing[GCnt and $7F] := RingDelta;

  if (AlzCandMask[State.CandBest0] and LongInt(GCnt)) = 0 then
  begin
    State.CandBest1 := 2; State.CandBest2 := 2; EdiMin := $FFFF;
    Cnt := GCnt;
    for A := 2 to 123 do
    begin
      D1 := (State.DeltaRing[(Cnt-1) and $7F]   - State.DeltaRing[(Cnt-1-A) and $7F]) and $FFF;
      D2 := (State.DeltaRing[Cnt and $7F]       - State.DeltaRing[(Cnt-A) and $7F])   and $FFF;
      D3 := (State.DeltaRing[(Cnt-2) and $7F]   - State.DeltaRing[(Cnt-2-A) and $7F]) and $FFF;
      Sum := AlzMMW(D1) + AlzMMW(D2) + AlzMMW(D3);
      State.CandAcc[A] := ((State.CandAcc[A] * 13) shr 4) + Sum;
      if State.CandAcc[A] < State.CandAcc[State.CandBest1] then State.CandBest1 := A;
      if Sum < EdiMin then begin EdiMin := Sum; State.CandBest2 := A; end;
    end;
  end;

  Res[0] := OutS - State.CandScore[0];
  Res[1] := OutS - State.CandScore[1];
  Res[2] := OutS - State.CandScore[2];
  Res[3] := OutS - State.CandScore[3];
  Res[4] := RingDelta - State.CandScore[4];
  Res[5] := RingDelta - State.CandScore[5];
  State.CandBest0 := 0;
  RingPos := GCnt and $FF;
  for K := 0 to 5 do
  begin
    State.ResBank[K,256] := State.ResBank[K,256] - State.ResBank[K,RingPos];
    Bv := AlzCandBucket9[Res[K] and $1FF];
    State.ResBank[K,RingPos] := Bv;
    State.ResBank[K,256] := State.ResBank[K,256] + Bv;
    if State.ResBank[K,256] < State.ResBank[State.CandBest0,256] then State.CandBest0 := K;
  end;

  State.CandPrev := State.CandCur;
  State.CandCur := OutS;

  State.SlotHash[0]   := (State.SlotHash[0]   shl 8) + DeltaByte;
  State.SlotHash74[0] := (State.SlotHash74[0] shl 8) + Cardinal(AlzCandByteA[DeltaByte]);
  State.SlotHash78[0] := (State.SlotHash78[0] shl 8) + Cardinal(AlzCandByteB[DeltaByte]);
end;

procedure TAlzDecoder.MMScore6(Sel: Integer);
var
  RingIdx1, RingIdx2, Base: Integer;
  RingV, OldH1, OldH2, NewH1, Score: LongInt;
  SB: Byte;
begin
  State.CandScore[0] := 0;
  State.CandScore[1] := State.CandCur;
  State.CandScore[2] := (State.CandCur + State.CandCur) - State.CandPrev;

  RingIdx1 := (Integer(State.OutputPos) - State.CandBest1) and $7F;
  RingV := State.DeltaRing[RingIdx1];

  OldH1 := State.MMHist[0,1]; OldH2 := State.MMHist[0,2];
  NewH1 := State.MMDelta[0] - State.MMHist[0,0];
  State.MMHist[0,4] := RingV;
  State.MMHist[0,3] := OldH2;
  State.MMHist[0,2] := OldH1;
  State.MMHist[0,1] := NewH1;
  State.MMHist[0,0] := State.MMDelta[0];

  Score := (State.MMLast[0] shl 4)
         + State.MMCoef[0,0] * State.MMDelta[0]
         + State.MMCoef[0,1] * NewH1
         + State.MMCoef[0,2] * OldH1
         + State.MMCoef[0,3] * OldH2
         + State.MMCoef[0,4] * RingV;
  Score := Score div 16;
  State.CandScore[3] := Score;
  State.CandScore[4] := RingV;
  RingIdx2 := (Integer(State.OutputPos) - State.CandBest2) and $7F;
  State.CandScore[5] := State.DeltaRing[RingIdx2];

  SB := Byte(State.CandScore[State.CandBest0]);
  if State.CandBest0 >= 4 then SB := Byte(SB + Byte(State.CandCur));
  State.SideBias := SB;

  if Sel = 5 then
  begin
    State.SideBias := Byte(State.SideBias + $80);
    Base := $3E1;
  end
  else
    Base := $3E5;
  if State.SlotHash[0] = 0 then Inc(Base)
  else if State.SlotHash74[0] = 0 then Base := Base + 2
  else if State.SlotHash78[0] = 0 then Base := Base + 3;
  State.SideModelSecondaryBase := Cardinal(Base);
end;

procedure TAlzDecoder.SideRecomputeBase(Delta: Byte);
begin
  Rc.Corrupt := True;
end;

procedure TAlzDecoder.ApplyPostMatchLiteralAdjustment(Actual, Predicted: Byte);
var
  Index: Integer;
  P: Cardinal;
begin

  if State.MatchFlagByte = 0 then
    Exit;

  Index := 768 + Integer(State.LastMatchTailByte);
  if Index > High(LiteralAdjust) then
    Index := High(LiteralAdjust);

  P := LiteralAdjust[Index];
  if Actual = State.LastMatchTailByte then
    P := P + ((FixedProbScale - P) shr 5)
  else if Actual <> Predicted then
    P := P - (P shr 5)
  else
    P := P - (P shr 6);

  if P > FixedProbScale then
    P := FixedProbScale;
  LiteralAdjust[Index] := Word(P);

  State.MatchFlagByte := 0;
end;

function TAlzDecoder.DecodeFixedTree(var Tree: array of Word; FirstNode,
  LeafLimit: Integer; MoveToLeafOnZero: Boolean): Integer;
var
  Node, Bit, P: Integer;
begin

  Node := FirstNode;
  Result := 0;
  while (Node > 0) and (Node < LeafLimit) and not Rc.Corrupt do
  begin
    P := Node;
    if P > High(Tree) then
    begin
      Rc.Corrupt := True;
      Break;
    end;

    Bit := Rc.DecodeBitFast12(Tree[P]);
    if (Bit = 0) and MoveToLeafOnZero then
      Result := Node;

    Node := Node * 2 + Bit;
  end;

  if not MoveToLeafOnZero then
    Result := Node - LeafLimit
  else if Result = 0 then
    Result := Node - LeafLimit;

  if Result < 0 then
    Result := 0;
end;

function TAlzDecoder.DecodeTransitionTree(var Tree: array of Word;
  const Next: array of Byte; FirstNode: Integer; InitialResult: Integer;
  RememberZeroNode: Boolean; AdaptShift: Integer): Integer;
var
  Node, Index, Bit, LastZeroNode: Integer;
begin

  Node := FirstNode;
  LastZeroNode := InitialResult;

  while (Node <> 0) and not Rc.Corrupt do
  begin
    if (Node < 0) or (Node > High(Tree)) then
    begin
      Rc.Corrupt := True;
      Break;
    end;

    Bit := Rc.DecodeBitFast12Shift(Tree[Node], AdaptShift);
    if (Bit = 0) and RememberZeroNode then
      LastZeroNode := Node;

    Index := Node * 2 + Bit;
    if (Index < 0) or (Index > High(Next)) then
    begin
      Rc.Corrupt := True;
      Break;
    end;
    Node := Next[Index];
  end;

  if RememberZeroNode then
    Result := LastZeroNode
  else
    Result := Node;
end;

function TAlzDecoder.DecodeExtraBits(BitCount: Integer; Context: Cardinal): Cardinal;
var
  I, Index: Integer;
begin
  Result := 0;
  for I := BitCount - 1 downto 0 do
  begin
    Index := Integer((Context * 17 + Cardinal(I)) mod Cardinal(Length(DistanceTree)));
    Result := (Result shl 1) or Cardinal(Rc.DecodeBitFast12(DistanceTree[Index]));
  end;
end;

function TAlzDecoder.DecodeDistanceSuffix(Slot: Integer; Span: Cardinal): Cardinal;
var
  FirstBit: Integer;
  BlockCount, Block, TailSpan: Cardinal;
  OriginalSpan: Cardinal;
begin

  Result := 0;
  OriginalSpan := Span;
  if OriginalSpan <= 1 then
    Exit;

  FirstBit := -1;
  if Span >= 4 then
  begin
    FirstBit := Rc.DecodeBitFast12Shift(LongDistanceBit, 6);
    Span := Span shr 1;
  end;

  if Span > 2048 then
  begin
    BlockCount := ((Span - 1) shr 11) + 1;
    Block := Rc.DecodeUniform(BlockCount);
    Result := Block shl 11;

    if Block + 1 = BlockCount then
      TailSpan := Span - Result
    else
      TailSpan := 2048;
  end
  else
    TailSpan := Span;

  if TailSpan >= 2 then
    Inc(Result, Rc.DecodeUniform(TailSpan));

  if FirstBit >= 0 then
    Result := (Result shl 1) + Cardinal(FirstBit);

  if Result >= OriginalSpan then
    Result := OriginalSpan - 1;
end;

function TAlzDecoder.DecodeLengthSymbol(Group: Integer; MinSymbol, ForceRightLimit, PreviousLength, OlderLength: Integer): Integer;
var
  Node, Index, Bit, CandidateSymbol: Integer;
begin

  if Group < 0 then
    Group := 0;
  if Group > 7 then
    Group := 7;
  if ForceRightLimit > 7 then
    ForceRightLimit := 7;

  Node := MinSymbol;
  if Node < 1 then
    Node := 1;
  CandidateSymbol := Node;

  while (Node <> 0) and not Rc.Corrupt do
  begin
    CandidateSymbol := Node + 1;

    if ForceRightLimit >= CandidateSymbol then
      Bit := 1
    else
    begin
      Index := Group * 4096;
      if Node >= PreviousLength then
        Inc(Index, 1024);
      if OlderLength <= Node then
        Inc(Index, 2048);
      Inc(Index, Node);
      if (Index < 0) or (Index > High(LengthTree)) then
      begin
        Rc.Corrupt := True;
        Break;
      end;

      Bit := Rc.DecodeBitFast12Shift(LengthTree[Index], 5);
      if Bit = 0 then
        CandidateSymbol := Node;
    end;

    Index := Node * 2 + Bit;
    if (Index < 0) or (Index > High(AlzLengthNext)) then
    begin
      Rc.Corrupt := True;
      Break;
    end;
    Node := AlzLengthNext[Index];

  end;

  Result := CandidateSymbol;
end;

function TAlzDecoder.DistanceBucket(Distance: Cardinal): Integer;
var
  Residual: Cardinal;
begin

  Residual := Distance;

  if Residual < 256 then
  begin
    Result := 0;
    Exit;
  end;
  Dec(Residual, 256);

  if Residual < 4096 then
  begin
    Result := 1;
    Exit;
  end;
  Dec(Residual, 4096);

  if Residual < 65536 then
  begin
    Result := 2;
    Exit;
  end;
  Dec(Residual, 65536);

  if Residual < 1048576 then
    Result := 3
  else
    Result := 4;
end;

function TAlzDecoder.DecodeDistanceSlot(Token: Integer): Integer;
begin
  case Token of
    2:
      Result := 0;
    1:
      begin
        Result := DecodeTransitionTree(DistanceSlotNormal, AlzFullDistanceNext,
          16, 44, True, 6);

        Dec(Result);
        if Result < 0 then
          Result := 0;
      end;
  else
      Result := DecodeTransitionTree(DistanceSlotFast, AlzShortDistanceNext,
        1, 11, True, 6);
  end;
end;

function TAlzDecoder.ConstrainDistanceSpanToHistory(Base, Span: Cardinal): Cardinal;
var
  AvailableHistory: Cardinal;
begin

  if Span <= 1 then
  begin
    Result := Span;
    Exit;
  end;

  AvailableHistory := State.OutputPos;
  if AvailableHistory > Mode.DictionarySize then
    AvailableHistory := Mode.DictionarySize;

  if Base = 0 then
    Base := 1;

  if Base > AvailableHistory then
  begin
    Rc.Corrupt := True;
    Result := 1;
    Exit;
  end;

  if Span - 1 > AvailableHistory - Base then
    Result := AvailableHistory - Base + 1
  else
    Result := Span;

  if Result = 0 then
  begin
    Rc.Corrupt := True;
    Result := 1;
  end;
end;

function TAlzDecoder.DecodeDistanceFromSlot(Token, Slot: Integer): Cardinal;
var
  Extra, Base, Span: Cardinal;
begin

  if Token = 2 then
  begin

    Result := State.RecallDistance(0);
    Exit;
  end;

  if (Token <> 1) and (Slot = 255) then
    Slot := MaxRecentDistances - 1;

  if (Token <> 1) and (Slot >= 0) and (Slot < MaxRecentDistances) then
  begin

    Result := State.RecallDistance(Slot);
    Exit;
  end;

  if Slot < 0 then
    Slot := 0;
  if Slot > High(AlzDistanceBase) then
    Slot := High(AlzDistanceBase);

  Base := AlzDistanceBase[Slot];
  Span := AlzDistanceSpan[Slot];

  Span := ConstrainDistanceSpanToHistory(Base, Span);
  if Rc.Corrupt then
  begin
    Result := 1;
    Exit;
  end;

  Extra := DecodeDistanceSuffix(Slot, Span);

  Result := Base + Extra;
  if Result = 0 then
    Result := 1;

  State.RememberDistance(Result);
end;

function TAlzDecoder.DecodeMatchLength(Token: Integer; Distance: Cardinal): Cardinal;
var
  Group, Symbol: Integer;
  HistoryKey: Cardinal;
  UseLengthHistory: Boolean;
  PreviousLengthForPair: Integer;
  OlderLengthForPair: Integer;
  ForceRightLimit: Integer;
begin

  if Token = 1 then
  begin
    Group := DistanceBucket(Distance) + 3;
    ForceRightLimit := Group;
  end
  else
  begin
    Group := 5;
    ForceRightLimit := 2;
    if State.RepeatRun <> 0 then
    begin
      if State.RepeatRun > 2 then
        Group := 7
      else
        Group := 6;
    end;
  end;

  if Group > 7 then
    Group := 7;
  if ForceRightLimit > 7 then
    ForceRightLimit := 7;

  UseLengthHistory := False;
  HistoryKey := 0;
  PreviousLengthForPair := 0;
  OlderLengthForPair := 0;

  if (Group <= 5) and (Distance > 1) then
  begin
    HistoryKey := SourcePairKeyBeforeMatch(Distance);
    if Group = 5 then
      Inc(HistoryKey, 65536);
    if HistoryKey <= 131071 then
    begin
      UseLengthHistory := True;
      PreviousLengthForPair := LengthHistory[HistoryKey];
      OlderLengthForPair := LengthHistory[HistoryKey + 131072];
      LengthHistory[HistoryKey + 131072] := Byte(PreviousLengthForPair);
    end;
  end;

  Symbol := DecodeLengthSymbol(Group, 10, ForceRightLimit, PreviousLengthForPair, OlderLengthForPair);
  if Symbol < 2 then
    Symbol := 2;

  if UseLengthHistory then
    LengthHistory[HistoryKey] := Byte(Symbol and $FF);

  Result := Cardinal(Symbol);

  if (Token = 2) and (Result < 3) then
    Result := 3;
end;

function TAlzDecoder.DecodeLengthAndDistance(Token: Integer; var Distance,
  Count: Cardinal): Boolean;
var
  Slot: Integer;
begin
  Slot := DecodeDistanceSlot(Token);
  Distance := DecodeDistanceFromSlot(Token, Slot);
  Count := DecodeMatchLength(Token, Distance);

  if Distance = 0 then
    Distance := 1;
  Result := not Rc.Corrupt;
end;

function TAlzDecoder.DecodeItem(var OutBuf: array of Byte): Boolean;
var
  Token: Integer;
  EscapeCount: Integer;
  B: Byte;
  Predicted: Byte;
  LiteralCtx: Integer;
  Dist, Count: Cardinal;
  TailAfterSourceRun: Byte;
  SourceWindowPosBeforeCopy: Cardinal;
begin
  Result := False;
  if AlzItemTrace then
    WriteLn(ErrOutput, 'ITEMSTATE ', State.OutputPos, ' ', IntToHex(Rc.Code, 8),
      ' ', IntToHex(Rc.Range, 8));

  EscapeCount := 0;
  repeat
    Token := DecodeTokenClass;
    if (GetEnvironmentVariable('ALZ_DBG') <> '') and (State.OutputPos <= 24) then
      writeln(ErrOutput, 'ITEM out=', State.OutputPos, ' Token=', Token,
        ' Code=', IntToHex(Rc.Code, 8), ' Corrupt=', Rc.Corrupt);
    if Rc.Corrupt then
      Exit;

    if Token <> 0 then
      Break;

    HandleEscapeClass;
    Inc(EscapeCount);

    if EscapeCount > 64 then
    begin
      Rc.Corrupt := True;
      Exit;
    end;
  until Rc.Corrupt;

  if Token = 4 then
  begin

    if State.EscapeSelector <> 0 then
      B := SideDecodeLiteral
    else
      B := DecodeLiteral(0, 0);
    BMFlag := 0;
    if Rc.Corrupt then Exit;
    if State.OutputPos >= Cardinal(Length(OutBuf)) then
    begin
      Rc.Corrupt := True;
      Exit;
    end;
    if (GetEnvironmentVariable('ALZ_DBG') <> '') and (State.OutputPos <= 22) then
      writeln(ErrOutput, 'LIT out=', State.OutputPos, ' byte=', B);
    PutByte(B, OutBuf);
    if State.EscapeSelector <> 0 then
    begin
      SidePostUpdate(B);
      if Rc.Corrupt then Exit;
    end;
    State.RepeatRun := 0;
    Result := True;
    Exit;
  end;

  if MDecodeMatch(Token, Dist, Count) then
  begin

    if Count > Cardinal(Length(OutBuf)) - State.OutputPos then
    begin
      Rc.Corrupt := True;
      Exit;
    end;

    SourceWindowPosBeforeCopy := State.WindowPos;
    CopyMatch(Dist, Count, OutBuf);

    if Count <> 255 then
      TailAfterSourceRun := SourceByteAfterMatch(Dist, Count, SourceWindowPosBeforeCopy)
    else
      TailAfterSourceRun := 0;

    if Count <> 255 then
    begin
      State.MatchFlagByte := 1;
      State.LastMatchTailByte := TailAfterSourceRun;
    end
    else
      State.MatchFlagByte := 0;

    BMFlag := State.MatchFlagByte;
    if State.MatchFlagByte <> 0 then BMPredB := State.LastMatchTailByte;

    if Count = 255 then
      Inc(State.RepeatRun)
    else
      State.RepeatRun := 0;

    Result := True;
  end;
end;

function AsrI(V: LongInt; N: Byte): LongInt;
begin
  if V < 0 then
    Result := not (LongInt(not V) shr N)
  else
    Result := V shr N;
end;

function Sext16(W: Word): LongInt;
begin
  if (W and $8000) <> 0 then Result := LongInt(W) - $10000 else Result := W;
end;

procedure ApplyExeFilter(var Buf: array of Byte; Size, Limit, Start: Cardinal;
  PpmByteSwap: Boolean);
var
  I: LongInt;
  N, Ecx: LongInt;
  Eax, Swapped: Cardinal;
  Se: LongInt;
  Hi, Lo, Key, Tv: Word;
  Idx, K, Al, Found, Skip: LongInt;
  Tbl: array[0..127] of Word;

  function Rd32(P: LongInt): Cardinal;
  begin
    Result := Cardinal(Buf[P]) or (Cardinal(Buf[P+1]) shl 8) or
              (Cardinal(Buf[P+2]) shl 16) or (Cardinal(Buf[P+3]) shl 24);
  end;
  function Rd16(P: LongInt): Word;
  begin
    Result := Word(Buf[P]) or (Word(Buf[P+1]) shl 8);
  end;
  procedure Wr32(P: LongInt; V: Cardinal);
  begin
    Buf[P] := Byte(V);        Buf[P+1] := Byte(V shr 8);
    Buf[P+2] := Byte(V shr 16); Buf[P+3] := Byte(V shr 24);
  end;
  procedure Wr16(P: LongInt; V: Word);
  begin
    Buf[P] := Byte(V); Buf[P+1] := Byte(V shr 8);
  end;

begin
  if Size <= 15 then Exit;
  FillChar(Tbl, SizeOf(Tbl), 0);
  N := LongInt(Size) - 15;
  I := LongInt(Start);
  while I < N do
  begin
    if (Buf[I] <> $E8) and (Buf[I] <> $E9) then begin Inc(I); Continue; end;
    Ecx := I + 1;
    Eax := Rd32(Ecx);
    if Eax = 0 then begin Inc(I, 4); Continue; end;
    Skip := 4;
    if PpmByteSwap then
    begin
      Swapped := (Eax and $FF00FF00) or ((Eax shr 16) and $FF)
        or ((Eax shl 16) and $FF0000);
      if ((LongInt(Eax) >= -I) and (LongInt(Eax) < LongInt(Limit)))
         or ((LongInt(Swapped) >= -I) and (LongInt(Swapped) < LongInt(Limit))) then
      begin
        Eax := Swapped;
        Wr32(Ecx, Eax);
        Skip := 5;
      end;
    end;
    Se := LongInt(Eax);
    if (Se > 0) and (Eax < Limit) then
    begin
      if Eax = Cardinal(I) then Eax := 0;
      Eax := Eax - Cardinal(I);
      Wr32(Ecx, Eax); Inc(I, 5); Continue;
    end;
    if Se < 0 then
    begin
      if Se >= -I then
      begin
        Wr32(Ecx, Eax + Limit); Inc(I, 5); Continue;
      end;

    end;

    Hi := Rd16(Ecx + 2);
    if Hi = 0 then begin Inc(I, Skip); Continue; end;
    if Hi = Word((LongInt(Limit) - 1) shr 16) then begin Inc(I, Skip); Continue; end;
    if Hi = Word(AsrI(-I, 16)) then begin Inc(I, Skip); Continue; end;
    Lo := Rd16(Ecx);
    if ((Lo + Cardinal($FFFF8000)) and $FFFFFFFF) < $80 then
    begin

      Idx := LongInt(Lo) - $8000;
      Tv := Tbl[Idx];
      Wr16(Ecx, Word((Sext16(Tv) - I) and $FFFF));
      if Idx <> 0 then
      begin
        for K := Idx downto 1 do Tbl[K] := Tbl[K-1];
        Tbl[0] := Tv;
      end;
      Inc(I, Skip); Continue;
    end;

    Key := Word((LongInt(Lo) + I) and $FFFF);
    while True do
    begin
      Found := -1;
      Al := 0;
      while Al < $80 do
      begin
        if Tbl[Al] = Key then begin Found := Al; Break; end;
        Inc(Al);
      end;
      if Found >= 0 then
      begin
        Wr16(Ecx, Word($8000 or Found));
        Key := Word((($8000 or Found) + I) and $FFFF);
        Continue;
      end
      else
      begin
        if Sext16(Key) < Sext16($8080) then Break;
        for K := $7F downto 1 do Tbl[K] := Tbl[K-1];
        Tbl[0] := Key;
        Break;
      end;
    end;
    Inc(I, Skip);
  end;
end;

function ClassifyExe(const Buf: array of Byte; USize: Cardinal;
  out Mode: Integer; out StartOfs: Cardinal): Boolean;
var
  W0, D0, Word67, Word18: Cardinal;
begin
  Mode := 0; StartOfs := 0; Result := False;
  if USize < 2 then Exit;
  W0 := Cardinal(Buf[0]) or (Cardinal(Buf[1]) shl 8);
  D0 := 0;
  if USize >= 4 then
    D0 := Cardinal(Buf[0]) or (Cardinal(Buf[1]) shl 8) or
          (Cardinal(Buf[2]) shl 16) or (Cardinal(Buf[3]) shl 24);

  if (W0 = $5A4D) or (W0 = $4D5A) or (W0 = $514D) then
  begin

    if USize < 8 then begin Mode := 0; StartOfs := 0; Result := True; Exit; end;
    Word67 := Cardinal(Buf[6]) or (Cardinal(Buf[7]) shl 8);
    if (Word67 < $10) or (Word67 > $2000) then
    begin
      Mode := 0; StartOfs := 8; Result := True; Exit;
    end;

    Word18 := 0;
    if USize >= $1A then Word18 := Cardinal(Buf[$18]) or (Cardinal(Buf[$19]) shl 8);
    if (Word18 >= $1C) and ((Word18 + Word67 * 4) < USize) then Mode := 1 else Mode := 0;
    StartOfs := $1A;
    Result := True; Exit;
  end;

  if D0 = $464C457F then
  begin

    if (USize > $13) and (Buf[$12] = 3) and (Buf[$13] = 0) then
    begin Mode := 0; StartOfs := $14; Result := True; end;
    Exit;
  end;

  if D0 = $564F4246 then
  begin Mode := 0; StartOfs := 0; Result := True; Exit; end;
end;

procedure RestoreFilter(var Buf: array of Byte; USize: Cardinal;
  PpmByteSwap: Boolean);
var
  Mode: Integer;
  StartOfs, RelocOfs, RelocSize, Plane, I, J, V: Cardinal;
  Relocations: array of Byte;
begin
  if (USize > Cardinal(Length(Buf))) or (USize <= 15) then Exit;
  if not ClassifyExe(Buf, USize, Mode, StartOfs) then Exit;
  if Mode = 1 then
  begin
    RelocOfs := Cardinal(Buf[$18]) or (Cardinal(Buf[$19]) shl 8);
    RelocSize := (Cardinal(Buf[6]) or (Cardinal(Buf[7]) shl 8)) * 4;

    if RelocOfs + RelocSize > USize - 15 then Exit;
    SetLength(Relocations, RelocSize);
    J := RelocOfs;
    for Plane := 0 to 3 do
    begin
      I := Plane;
      while I < RelocSize do
      begin
        Relocations[I] := Buf[J];
        Inc(J); Inc(I, 4);
      end;
    end;

    I := 4;
    while I < RelocSize do
    begin
      V := Cardinal(Relocations[I]) or (Cardinal(Relocations[I+1]) shl 8);
      Inc(V, Cardinal(Relocations[I-4]) or (Cardinal(Relocations[I-3]) shl 8));
      Relocations[I] := Byte(V); Relocations[I+1] := Byte(V shr 8);
      Inc(I, 2);
    end;
    Move(Relocations[0], Buf[RelocOfs], RelocSize);
    StartOfs := RelocOfs + RelocSize;
  end;
  ApplyExeFilter(Buf, USize, USize, StartOfs, PpmByteSwap);
end;

procedure TAlzDecoder.RebuildBlockModel;
var C, S: Integer; Previous, Current, Acc: Cardinal;
begin
  for C := 0 to $300 do
  begin
    FillChar(BMTree[C], SizeOf(BMTree[C]), 0);
    FillChar(BMFreq[C], SizeOf(BMFreq[C]), 0);
    BMEW[C] := 1;
    BMCounter[C] := $4000;
  end;
  for C := 0 to High(TokenClass) do
  begin
    Previous := TokenClass[C, 1];
    Acc := Previous;
    for S := 2 to 5 do
    begin
      Current := TokenClass[C, S];
      Acc := Acc + ((Current - Previous + 1) shr 1);
      TokenClass[C, S] := Word(Acc);
      Previous := Current;
    end;
  end;
  for C := $301 to $3F8 do BMRescaleEntry(C);
  for C := $3F9 to $40B do BMRescaleCtx2(C);
  for C := 0 to 255 do BMTable[C] := $9240;
  BMPCounter := 255;
  BMAcc80 := $91ADC0;
  BMAcc8c := 0;
  BMAcc90 := 0;
  HandleEscapeClass;
end;

function TAlzDecoder.DecodeTo(USize: Cardinal; const MemberEnds: array of Cardinal;
  var OutBuf: array of Byte): Integer;
var NextBoundary, Target: Cardinal; Member: Integer;
  procedure AdvanceBoundary;
  begin
    if USize - NextBoundary > $20000 then Target := NextBoundary + $20000
    else Target := USize;
    while (Member <= High(MemberEnds)) and (MemberEnds[Member] < Target) do Inc(Member);
    if Member <= High(MemberEnds) then NextBoundary := MemberEnds[Member]
    else NextBoundary := USize;
  end;
begin
  Member := 0;
  NextBoundary := 0;
  AdvanceBoundary;
  if Cardinal(Length(OutBuf)) < USize then
  begin
    Result := alzOutputTooSmall;
    Exit;
  end;

  while State.OutputPos < USize do
  begin
    if State.OutputPos >= NextBoundary then
    begin
      RebuildBlockModel;
      AdvanceBoundary;
      if Rc.Corrupt then Break;
    end;
    if not DecodeItem(OutBuf) then
      Break;
    if Rc.Corrupt then
      Break;
  end;

  if (GetEnvironmentVariable('ALZ_DBG') <> '') and (Rc.Corrupt or (State.OutputPos <> USize)) then
    writeln(ErrOutput, 'ALZ fail: OutputPos=', State.OutputPos, ' USize=', USize,
      ' Corrupt=', Rc.Corrupt);
  if Rc.Corrupt or (State.OutputPos <> USize) then
    Result := alzCorruptInput
  else
    Result := alzOk;

end;

function ALZ_DecodeMembers(const FileData: array of Byte; Order: Integer;
  USize: Cardinal; const MemberEnds: array of Cardinal;
  var OutBuf: array of Byte): Integer;
var
  D: ^TAlzDecoder;
begin
  if not ((Order >= 40) and (Order <= 87)) then
  begin
    Result := alzBadOrder;
    Exit;
  end;

  AlzItemTrace := GetEnvironmentVariable('ALZ_ITEMTRACE') <> '';
  New(D);
  try
    FillChar(D^, SizeOf(TAlzDecoder), 0);
    D^.Init(FileData, Order, USize);
    Result := D^.DecodeTo(USize, MemberEnds, OutBuf);
  finally
    Dispose(D);
  end;
end;

function ALZ_Decode(const FileData: array of Byte; Order: Integer;
  USize: Cardinal; var OutBuf: array of Byte): Integer;
begin
  Result := ALZ_DecodeMembers(FileData, Order, USize, [], OutBuf);
end;

procedure GenAlzTables;
var
  i, k: Integer;
begin
  AlzSseMap[0] := 0;
  for i := 1 to 16384 do
    AlzSseMap[i] := Word(65520 - Ceil(4680.0 * Log2(i)));

  for i := 0 to 43 do
    if i < 6 then AlzDistanceBase[i] := Cardinal(1) shl i
    else
    begin
      k := 6 + (i - 6) div 2;
      if ((i - 6) and 1) = 0 then AlzDistanceBase[i] := Cardinal(1) shl k
      else AlzDistanceBase[i] := Cardinal(3) shl (k - 1);
    end;

  for i := 0 to $41F do AlzEntryStep[i] := 0;
  for i := 0 to 1008 do AlzEntryStep[i] := 32;
  for i := 1009 to 1016 do AlzEntryStep[i] := 10;
  AlzEntryStep[1017] := 65281; AlzEntryStep[1020] := 256;
  AlzEntryStep[1021] := 65280; AlzEntryStep[1022] := 2;

  for i := 0 to $41F do AlzEscStep[i] := 8;
  for i := 512 to 992 do AlzEscStep[i] := 16;
  AlzEscStep[768] := 6;
  for i := 1017 to $41F do AlzEscStep[i] := 32;
end;

initialization
  GenAlzTables;

end.
