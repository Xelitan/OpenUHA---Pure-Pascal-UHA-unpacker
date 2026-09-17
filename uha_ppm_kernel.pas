unit uha_ppm_kernel;

{$mode delphi}{$H+}{$Q-}{$R-}

interface

uses uha_ppm_textbook, uha_ppm_mm6, uha_ppm_mm7;

const
  NUM_CTX  = $400;
  MAX_EXCL = 23;
  REC1_COUNT = $40000;
  REC2_COUNT = $20000;
  HASH_COUNT = $40000;

type
  TProbArray  = array of Cardinal;
  TWordArray  = array of Word;
  TByteArray2 = array of Byte;
  TCardArray  = array of Cardinal;

  TRec1Rec = array[0..$1F] of Byte;
  TRec2Rec = array[0..$13] of Byte;

  TPpmModel = record
    Cum      : array of TFenwickRow;
    Freq     : array of TFenwickRow;
    EntWt    : TWordArray;
    Order0Wt : TCardArray;
    SseProb  : TProbArray;
    Sse2     : TProbArray;
    PredByte : TByteArray2;
    ClsIdx   : TByteArray2;
    WTab     : TCardArray;
    Recency  : TCardArray;
    LastSym  : TCardArray;
    Novel    : TByteArray2;
    F154     : TWordArray;
    Excl     : array[0..MAX_EXCL-1] of Byte;
    NExcl    : Integer;
    WorkCtx  : Integer;
    ByteClass: Byte;
    LastCtx  : Cardinal;
    WinPos   : Cardinal;
    Detr     : TDetransform;
    DetrThr1 : Cardinal;
    DetrThr2 : Cardinal;
    OutCount : Cardinal;
    C38      : Cardinal;
    C44      : Cardinal;
    C48      : Cardinal;
    C4C      : Cardinal;
    C50      : Cardinal;
    C54      : Cardinal;
    BFC      : Cardinal;
    Bec      : Cardinal;
    S41      : Byte;
    S45      : Byte;
    S47      : Byte;
    S48      : Byte;
    S49      : Byte;
    RankPtrSmall: Cardinal;
    RankPtrLarge: Cardinal;
    RankSmall: array[0..$108] of Cardinal;
    RankLarge: array[0..$186] of Cardinal;
    RankSmallBase: array[0..4] of Cardinal;
    RankLargeBase: array[0..$10] of Cardinal;

    Age      : Cardinal;
    AgeCtr   : Cardinal;
    AgeRing  : array[0..255] of Cardinal;
    RecA     : array[0..3] of Cardinal;
    RecB     : array[0..3] of Cardinal;
    RollCtx0 : Cardinal;
    RollCtx1 : Cardinal;
    RollCtx2 : Cardinal;

    Window   : array of Byte;
    WinMask  : Cardinal;
    WinWrap  : Cardinal;
    Hist     : array[0..255] of Cardinal;
    Br10     : Cardinal;
    Br14     : Cardinal;
    Br18     : Cardinal;
    Brf0     : Cardinal;
    Flag3939 : Byte;
    MarkerC  : array[0..3] of Byte;
    MarkerFl : Byte;
    RingBuf  : array of Byte;
    RingOff  : array[0..3] of Cardinal;

    Budget   : array of Cardinal;
    TStep    : array of Word;
    TStep2   : array of Word;
    Flag3934 : Byte;

    ClsCtx   : Cardinal;
    ClsStride: Cardinal;
    ClsShift : Byte;
    MM6: TPpmMM6;
    MM7: TPpmMM7;
    ClsFlag31: Byte;
    ClsPhase : Cardinal;
    ClsBase  : Byte;
    ClsNeg   : Byte;
    Cls3Confidence: array[0..5] of Cardinal;
    Cls3Pred: array[0..5] of Byte;
    Cls3Index, Cls3Active, Cls3SavedNeg: Byte;
    Cls3Streak: Cardinal;

    WpA      : Cardinal;
    WpB      : Cardinal;
    WpAccAdd : Cardinal;
    WpPend   : Boolean;
    WpClassSelected: Boolean;
    WpArmed: Boolean;
    WpEngaged: Boolean;
    WpKernelWeight: Cardinal;
    Flag393C : Byte;
    C58      : Cardinal;
    LzpClassRec : array[0..255] of array[0..3] of Word;

    Rec1s    : array of TRec1Rec;
    Rec2s    : array of TRec2Rec;
    Ht1Pos   : TCardArray;
    Ht1Ctx   : TCardArray;
    Ht2New   : TCardArray;
    Ht2Prev  : TCardArray;
    LenTab   : TByteArray2;
    LinkTab  : TByteArray2;
    LinkPtr  : Cardinal;

    EscMass  : TCardArray;
    PredProb : TCardArray;
    EntryProb: TCardArray;
    LenProb  : TCardArray;
    RwA      : TCardArray;
    RwB      : TCardArray;
    RwC      : TCardArray;
    RwE      : TCardArray;
    R2A      : TCardArray;
    R2B      : TCardArray;
    R2E      : TCardArray;
    R2Esc    : TCardArray;
    T46A     : TCardArray;

    C1C      : Cardinal;
    C20      : Cardinal;
    C24      : Cardinal;
    C28      : Cardinal;

    D4       : Cardinal;
    D8       : Cardinal;
    B8       : Cardinal;
    HasCont  : Boolean;
    ContOfs  : Cardinal;
    C4G      : Cardinal;
    DCG      : Cardinal;
    A8G      : Cardinal;
    E0BlkLen : Cardinal;
    BlkLen4  : Cardinal;
    Base46   : Byte;
    C40      : Cardinal;
    C3C      : Cardinal;
    Flag3938 : Byte;
    Flag393B : Byte;
    Flag3943 : Byte;
    S3E      : Byte;
  end;

  TKState = record
    Weight    : Cardinal;
    LastTotal : Cardinal;
    Sse2Idx   : Integer;
    Sse2UpIdx : Integer;
    KernelExcl: Integer;
    Supported : Boolean;
  end;

function Kernel_Decode(var M: TPpmModel; var R: TRangeDecoder; Ctx: Integer;
  out KS: TKState): Integer;

implementation

uses SysUtils;

function F154_4(const M: TPpmModel; key: Cardinal): Cardinal; inline;
begin
  Result := M.F154[(key * 2) and $FFFFFFFF] and $FFFF;
end;

function F154_2(const M: TPpmModel; key: Cardinal): Cardinal; inline;
begin
  Result := M.F154[key and $FFFFFFFF] and $FFFF;
end;

function InExcl(const Excl: array of Byte; NExcl: Integer; sym: Byte): Boolean;
var i: Integer;
begin
  for i := 0 to NExcl - 1 do
    if Excl[i] = sym then Exit(True);
  Result := False;
end;

var KernelRowAt: Integer = -1;

function DecodeWorkCtx(var M: TPpmModel; var R: TRangeDecoder; var KS: TKState;
  const Excl: array of Byte; NExcl: Integer): Integer; forward;
function SearchAndDecode(var M: TPpmModel; var R: TRangeDecoder; var KS: TKState;
  RowCtx: Integer; Total, Freq: Cardinal;
  const Excl: array of Byte; NExcl: Integer): Integer; forward;
function ContCebf(var M: TPpmModel; var R: TRangeDecoder; var KS: TKState;
  Ctx: Integer; Rem: Cardinal; const Excl: array of Byte; NExcl: Integer): Integer; forward;
function Secondary(var M: TPpmModel; var R: TRangeDecoder; var KS: TKState;
  Ctx: Integer; Rem: Cardinal; const Excl: array of Byte; NExcl: Integer): Integer; forward;
function Novel(var M: TPpmModel; var R: TRangeDecoder; var KS: TKState;
  Ctx: Integer; Rem, Total: Cardinal; const Excl: array of Byte; NExcl: Integer): Integer; forward;

function DecodeWorkCtx(var M: TPpmModel; var R: TRangeDecoder; var KS: TKState;
  const Excl: array of Byte; NExcl: Integer): Integer;
var
  wc, i: Integer;
  total, freq: Cardinal;
begin
  wc := M.WorkCtx;
  total := M.Cum[wc][0];
  if Integer(M.WinPos) = KernelRowAt then
  begin
    Write(ErrOutput, 'KROW freq=');
    for i := 0 to 255 do Write(ErrOutput, M.Freq[wc][i], ',');
    Write(ErrOutput, ' cum=');
    for i := 0 to 255 do Write(ErrOutput, M.Cum[wc][i], ',');
    Writeln(ErrOutput);
  end;
  for i := 0 to NExcl - 1 do
    total := (total - M.Freq[wc][Excl[i]]) and $FFFF;
  if (M.ByteClass <> 0) and (GetEnvironmentVariable('PPM_KDBG') <> '') then
    writeln(ErrOutput, 'KDBG wpos=', M.WinPos, ' wc=', IntToHex(wc, 3), ' total=', total, ' nexcl=', NExcl,
      ' code=', IntToHex(R.Code, 8), ' rng=', IntToHex(R.Range, 8),
      ' wc_cum0=', M.Cum[wc][0], ' wc_entwt=', M.EntWt[wc], ' wc_ord0=', M.Order0Wt[wc]);
  if total = 0 then
  begin KS.Supported := False; Result := -1; Exit; end;
  R.Range := R.Range div total;
  KS.LastTotal := total;
  freq := R.Code div R.Range;
  Result := SearchAndDecode(M, R, KS, wc, total, freq, Excl, NExcl);
end;

function SearchAndDecode(var M: TPpmModel; var R: TRangeDecoder; var KS: TKState;
  RowCtx: Integer; Total, Freq: Cardinal;
  const Excl: array of Byte; NExcl: Integer): Integer;
var
  symbol: Integer;
  rem, high, lowWord, low: Cardinal;
begin
  if NExcl = 0 then
    symbol := Fenwick_BSearch(M.Cum[RowCtx], Total, Freq, rem)
  else
    symbol := Fenwick_MixSearch(M.Cum[RowCtx], M.Freq[RowCtx], Total, Freq, Excl, NExcl, rem);
  high    := (rem + Freq) and $FFFF;
  lowWord := M.Freq[RowCtx][symbol] and $FFFF;
  low     := (high - lowWord) and $FFFFFFFF;

  if ((high - low) and $FFFFFFFF) = 0 then
  begin KS.Supported := False; Result := -1; Exit; end;
  RD_Decode(R, low, (high - low) and $FFFFFFFF);

  if KS.LastTotal <> 0 then
    KS.Weight := (KS.Weight + F154_2(M, (lowWord shl 14) div KS.LastTotal)) and $FFFFFFFF;
  Result := symbol;
end;

function ContCebf(var M: TPpmModel; var R: TRangeDecoder; var KS: TKState;
  Ctx: Integer; Rem: Cardinal; const Excl: array of Byte; NExcl: Integer): Integer;
begin

  if Rem = 0 then
    Result := DecodeWorkCtx(M, R, KS, Excl, NExcl)
  else
    Result := Secondary(M, R, KS, Ctx, Rem, Excl, NExcl);
end;

function Secondary(var M: TPpmModel; var R: TRangeDecoder; var KS: TKState;
  Ctx: Integer; Rem: Cardinal; const Excl: array of Byte; NExcl: Integer): Integer;
var
  c, total, idx, sse2, freq, t: Cardinal;
  haveIdx: Boolean;
begin
  c := M.EntWt[Ctx];
  haveIdx := False; idx := 0;
  if (Ctx >= $200) or (Rem >= $2000) then
    total := (Rem + c) and $FFFFFFFF
  else
  begin
    idx  := ((c shl 5) div ((Rem + c) and $FFFFFFFF)) and $FFFFFFFF;
    sse2 := M.Sse2[idx];
    t := ((Rem shl 13) div sse2) + 1;
    if t >= $4000 then t := $3FFF;
    total := t;
    haveIdx := True;
  end;
  R.Range := R.Range div total;
  if Integer(M.WinPos) = KernelRowAt then
    Writeln(ErrOutput, 'SECONDARY ctx=', Ctx, ' rem=', Rem, ' ent=', c,
      ' idx=', idx, ' prob=', M.Sse2[idx], ' total=', total,
      ' code=', IntToHex(R.Code,8), ' rng=', IntToHex(R.Range,8));
  KS.LastTotal := total;
  freq := R.Code div R.Range;
  if (freq and $FFFF) < Rem then
  begin
    Result := SearchAndDecode(M, R, KS, Ctx, Rem, freq, Excl, NExcl);
    if haveIdx then KS.Sse2UpIdx := idx;
  end
  else
  begin
    if haveIdx then KS.Sse2Idx := idx;

    KS.Weight := (KS.Weight + F154_2(M, ((total - Rem) shl 14) div total)) and $FFFFFFFF;
    Result := Novel(M, R, KS, Ctx, Rem, total, Excl, NExcl);
  end;
end;

function Novel(var M: TPpmModel; var R: TRangeDecoder; var KS: TKState;
  Ctx: Integer; Rem, Total: Cardinal; const Excl: array of Byte; NExcl: Integer): Integer;
var
  bitmap: array[0..255] of Boolean;
  wc, b, i: Integer;
  si, novelTotal, freq2, dx, high, fb, low: Cardinal;

  function Ineligible(bb: Integer): Boolean; inline;
  begin
    Result := (M.Freq[Ctx][bb] <> 0) or bitmap[bb];
  end;

begin

  if ((Total - Rem) and $FFFFFFFF) <> 0 then
    RdSite := 332; RD_Decode(R, Rem, (Total - Rem) and $FFFFFFFF);
  for i := 0 to 255 do bitmap[i] := False;

  for i := 0 to NExcl - 1 do bitmap[Excl[i]] := True;
  wc := M.WorkCtx;
  si := 0;
  for b := 0 to 255 do
    if Ineligible(b) then si := (si + M.Freq[wc][b]) and $FFFF;
  novelTotal := (M.Cum[wc][0] - si) and $FFFF;
  if novelTotal = 0 then begin KS.Supported := False; Result := -1; Exit; end;
  R.Range := R.Range div novelTotal;
  KS.LastTotal := novelTotal;
  freq2 := (R.Code div R.Range) and $FFFF;
  if (M.ByteClass <> 0) and (GetEnvironmentVariable('PPM_NOVDBG') <> '') then
    writeln(ErrOutput, 'NOVEL wpos=', M.WinPos, ' wc=', IntToHex(wc,3),
      ' cum_wc=', M.Cum[wc][0], ' si=', si, ' novelTotal=', novelTotal, ' freq=', freq2,
      ' nexcl=', NExcl, ' Rem=', Rem, ' Total=', Total,
      ' Code=', IntToHex(R.Code,8), ' Rng=', IntToHex(R.Range,8));
  dx := 0; b := $100;
  while True do
  begin
    Dec(b);
    if not Ineligible(b) then dx := (dx + M.Freq[wc][b]) and $FFFF;
    if (dx > freq2) or (b = 0) then Break;
  end;
  high := dx and $FFFF;
  fb   := M.Freq[wc][b] and $FFFF;
  low  := (high - fb) and $FFFFFFFF;
  RdSite := 362; RD_Decode(R, low, (high - low) and $FFFFFFFF);

  if KS.LastTotal <> 0 then
    KS.Weight := (KS.Weight + F154_2(M, (fb shl 14) div KS.LastTotal)) and $FFFFFFFF;
  Result := b;
end;

function LowCountSse(var M: TPpmModel; var R: TRangeDecoder; var KS: TKState;
  Ctx: Integer; EntTotal: Cardinal; const Excl: array of Byte; NExcl: Integer): Integer;
var
  rem, freqPred, w, c, sse, prob, fdec: Cardinal;
  pb, i: Integer;
  excl2: array[0..MAX_EXCL-1] of Byte;
  n2: Integer;
begin
  rem := EntTotal;
  for i := 0 to NExcl - 1 do
    rem := (rem - M.Freq[Ctx][Excl[i]]) and $FFFF;
  if (M.ByteClass <> 0) and (Ctx = 255) and (EntTotal = 288) and (GetEnvironmentVariable('PPM_LCS') <> '') then
    Writeln(ErrOutput, 'LCS ctx=255 entTotal=288 rem=', rem, ' pb=', M.PredByte[Ctx],
      ' pbExcl=', InExcl(Excl, NExcl, M.PredByte[Ctx]), ' gate=', Ctx >= (Cardinal($200) shr M.ByteClass));
  if Ctx >= (Cardinal($200) shr M.ByteClass) then
    Exit(ContCebf(M, R, KS, Ctx, rem, Excl, NExcl));
  pb := M.PredByte[Ctx];
  if InExcl(Excl, NExcl, pb) then
    Exit(ContCebf(M, R, KS, Ctx, rem, Excl, NExcl));

  freqPred := M.Freq[Ctx][pb];
  w := M.WTab[M.ClsIdx[Ctx]];
  c := M.EntWt[Ctx];
  sse := (((w + freqPred) and $FFFFFFFF) shl 4) div ((w + c + rem) and $FFFFFFFF);
  if      freqPred > $600 then
  else if freqPred > $100 then sse := sse or $30
  else if freqPred > $40  then sse := sse or $20
  else                         sse := sse or $10;
  if (Ctx and $C0) = $C0 then sse := sse or $40;
  if (pb and $C0) = $C0 then
  begin
    if pb = $FF then sse := sse or $100 else sse := sse or $80;
  end;
  if M.ByteClass <> 0 then
  begin
    if ((M.WinPos - M.Recency[pb]) and $FFFFFFFF) <= $40 then sse := sse or $200;
  end
  else
    if M.Novel[pb] <> 0 then sse := sse or $200;
  if M.LastCtx = M.LastSym[pb] then sse := sse or $400;
  prob := M.SseProb[sse];
  R.Range := R.Range div $2000;
  fdec := (R.Code div R.Range) and $FFFF;
  if fdec < prob then
  begin
    RdSite := 415; RD_Decode(R, 0, prob);
    KS.Weight := (KS.Weight + F154_4(M, prob)) and $FFFFFFFF;
    Exit(pb);
  end;

  RdSite := 420; RD_Decode(R, prob, ($2000 - prob) and $FFFFFFFF);
  KS.Weight := (KS.Weight + F154_4(M, ($2000 - prob) and $FFFFFFFF)) and $FFFFFFFF;
  KS.KernelExcl := pb;
  rem := (rem - freqPred) and $FFFF;
  for i := 0 to NExcl - 1 do excl2[i] := Excl[i];
  excl2[NExcl] := pb; n2 := NExcl + 1;
  Result := ContCebf(M, R, KS, Ctx, rem, excl2, n2);
end;

function Kernel_Decode(var M: TPpmModel; var R: TRangeDecoder; Ctx: Integer;
  out KS: TKState): Integer;
var
  entTotal, entWeight: Cardinal;
begin
  KS.Weight := 0; KS.LastTotal := 0; KS.Sse2Idx := -1; KS.Sse2UpIdx := -1;
  KS.KernelExcl := -1;
  KS.Supported := True;
  entTotal  := M.Cum[Ctx][0];
  entWeight := (Cardinal(M.EntWt[Ctx]) * M.Order0Wt[Ctx]) and $FFFFFFFF;
  if (Integer(M.WinPos) = KernelRowAt) or
     ((M.ByteClass <> 0) and (GetEnvironmentVariable('PPM_KENT') <> '')) then
  begin
    Write(ErrOutput, 'KENT wpos=', M.WinPos, ' kctx=', Ctx, ' entTotal=', entTotal, ' entWeight=', entWeight, ' nexcl=', M.NExcl, ' excl=');
    if M.NExcl > 0 then
      for entWeight := 0 to Cardinal(M.NExcl) - 1 do Write(ErrOutput, M.Excl[entWeight], ',');
    Write(ErrOutput, ' freqs=');
    for entWeight := 0 to 255 do if M.Freq[Ctx][entWeight] <> 0 then Write(ErrOutput, entWeight, ':', M.Freq[Ctx][entWeight], ' ');
    entWeight := (Cardinal(M.EntWt[Ctx]) * M.Order0Wt[Ctx]) and $FFFFFFFF;
    Writeln(ErrOutput);
  end;
  if entTotal > entWeight then
    Result := LowCountSse(M, R, KS, Ctx, entTotal, M.Excl, M.NExcl)
  else
    Result := DecodeWorkCtx(M, R, KS, M.Excl, M.NExcl);
end;

initialization
  KernelRowAt := StrToIntDef(GetEnvironmentVariable('PPM_KROW'), -1);

end.
