unit uha_ppm_model;

{$mode delphi}{$H+}{$Q-}{$R-}

interface

uses SysUtils, uha_ppm_textbook, uha_ppm_kernel, uha_ppm_statics, uha_ppm_fenwick;

function PpmWindowSize(Order: Integer): Cardinal;
function PpmModelAllocate(var M: TPpmModel; Order: Integer): Boolean;

procedure PPM_ReadBlockHeader(var M: TPpmModel; var R: TRangeDecoder);

function PpmBlockReset(var M: TPpmModel; var R: TRangeDecoder): Boolean;
procedure PpmPromoteToBc1(var M: TPpmModel);
function PpmSelectClass(var M: TPpmModel; Cls: Integer): Boolean;

implementation

uses uha_ppm_records;

const M32 = $FFFFFFFF;

function PpmWindowSize(Order: Integer): Cardinal;
var shift: Integer;
begin
  shift := ((Order - $18) mod $10) + $0A;
  Result := Cardinal(1) shl shift;
end;

procedure SeedProbTables(var M: TPpmModel);
var
  ebp, esi, ebx, i, j: Integer;
  esiFlag, hi, val0: Cardinal;
  f68, f56, f72, f76, f64: Cardinal;
  adj: Cardinal;
begin

  for ebp := 0 to 31 do
  begin
    esiFlag := Cardinal(ebp) and 4;
    if ebp >= 16 then hi := 8 else hi := 0;
    for i := 0 to 15 do
    begin
      val0 := ((PPMS_43E130[i] + esiFlag + hi) shl 7) and M32;
      M.R2E[ebp * 16 + i] := val0;
      M.RwE[ebp * 16 + i] := val0;
    end;
    M.R2Esc[ebp] := $1000;
    M.Sse2[ebp]  := (PPMS_43E1F4[ebp] shl 7) and M32;
  end;

  for esi := 0 to 127 do
  begin
    if esi >= 16 then f68 := 1 else f68 := 0;
    f56 := f68; f76 := f68;
    if esi >= 8  then f72 := 4 else f72 := 0;
    if esi >= 16 then f76 := 4 else f76 := 0;
    if esi >= 64 then f64 := 4 else f64 := 0;
    for i := 0 to 15 do
    begin
      j := esi * 16 + i;
      val0 := PPMS_43E170[i];
      if esi < 16 then M.R2B[j] := ((val0 + f72) shl 7) and M32;
      if esi < 32 then M.RwB[j] := ((val0 + f76) shl 7) and M32;
      if esi < 16 then M.RwC[j] := ((val0 + f72) shl 7) and M32;
      M.SseProb[j] := ((val0 + f64) shl 7) and M32;
      M.R2A[j]     := ((val0 + f68 + f64) shl 7) and M32;
      M.RwA[j]     := ((val0 + f56 + f64) shl 7) and M32;
    end;
  end;

  for esi := 0 to 7 do
  begin
    for ebx := 0 to 7 do
    begin
      adj := 0;
      if ebx > esi then adj := PPMS_43E1B0[ebx - esi]
      else if esi > ebx then adj := (0 - PPMS_43E1B0[esi - ebx]) and M32;
      for i := 0 to 31 do
        M.EscMass[(esi shl 8) + ebx * 32 + i] := ($1000 + adj) and M32;
    end;
    for i := 0 to 31 do
      M.EntryProb[esi * 32 + i] := (PPMS_43E1D0[(i and 1) + esi] shl 7) and M32;
    for i := 0 to 1023 do
      M.PredProb[esi * 1024 + i] := (PPMS_43E1D0[(i and 1) + esi] shl 7) and M32;
    for i := 0 to 255 do
      M.LenProb[esi * 256 + i] := $800;
  end;
end;

function PpmModelAllocate(var M: TPpmModel; Order: Integer): Boolean;
var
  i: Integer;
  w: Cardinal;
begin
  Result := False;
  if (Order < $18) or (Order > $27) then Exit;

  Finalize(M);
  FillChar(M, SizeOf(M), 0);

  w := PpmWindowSize(Order);
  SetLength(M.Cum, NUM_CTX);
  SetLength(M.Freq, NUM_CTX);
  SetLength(M.EntWt, NUM_CTX);
  SetLength(M.Order0Wt, NUM_CTX);
  SetLength(M.SseProb, $800);
  SetLength(M.Sse2, $20);
  SetLength(M.PredByte, NUM_CTX);
  SetLength(M.ClsIdx, NUM_CTX);
  SetLength(M.WTab, $10);
  SetLength(M.Recency, $100);
  SetLength(M.LastSym, $100);
  SetLength(M.Novel, $100);
  SetLength(M.F154, $4000);
  SetLength(M.Window, w + $100);
  SetLength(M.RingBuf, $40000);
  SetLength(M.Budget, NUM_CTX);
  SetLength(M.TStep, NUM_CTX);
  SetLength(M.TStep2, NUM_CTX);
  SetLength(M.Rec1s, REC1_COUNT);
  SetLength(M.Rec2s, REC2_COUNT);
  SetLength(M.Ht1Pos, HASH_COUNT);
  SetLength(M.Ht1Ctx, HASH_COUNT);
  SetLength(M.Ht2New, HASH_COUNT);
  SetLength(M.Ht2Prev, HASH_COUNT);
  SetLength(M.LenTab, HASH_COUNT);
  SetLength(M.LinkTab, HASH_COUNT);
  SetLength(M.EscMass, $2000);
  SetLength(M.PredProb, $2000);
  SetLength(M.EntryProb, $100);
  SetLength(M.LenProb, $800);
  SetLength(M.RwA, $800);
  SetLength(M.RwB, $200);
  SetLength(M.RwC, $100);
  SetLength(M.RwE, $200);
  SetLength(M.R2A, $800);
  SetLength(M.R2B, $100);
  SetLength(M.R2E, $200);
  SetLength(M.R2Esc, $20);
  SetLength(M.T46A, $100);

  M.WinWrap := w;
  M.WinMask := w - 1;
  M.WinPos := 0;

  for i := 0 to HASH_COUNT - 1 do
  begin
    M.Ht1Pos[i] := M32; M.Ht1Ctx[i] := M32;
    M.Ht2New[i] := M32; M.Ht2Prev[i] := M32;
  end;

  for i := 0 to $FF do M.Novel[i] := PPMS_NOVEL[i];
  for i := 0 to $3FFF do M.F154[i] := PPMS_F154[i];
  for i := 0 to $F do M.WTab[i] := PPMS_WTAB[i];
  for i := 0 to High(M.RankSmallBase) do M.RankSmallBase[i] := PPMS_RANKBASE_S[i];
  for i := 0 to High(M.RankLargeBase) do M.RankLargeBase[i] := PPMS_RANKBASE_L[i];

  for i := 0 to $300 do M.Order0Wt[i] := 1;
  for i := 0 to $300 do M.Budget[i] := $4000;
  for i := $209 to $300 do M.EntWt[i] := 1;
  for i := 0 to $300 do M.TStep2[i] := $20;
  for i := 0 to $300 do M.TStep[i] := $10;
  for i := $2F9 to $300 do M.TStep2[i] := $0A;
  for i := $2E9 to $300 do M.TStep[i] := $08;
  M.TStep[$200] := $06;
  for i := 0 to $300 do M.PredByte[i] := $FF;

  SeedProbTables(M);

  M.E0BlkLen := M32;
  M.D4 := M32; M.D8 := 0; M.B8 := 0;
  M.HasCont := False; M.ContOfs := 0;
  M.DetrThr1 := M32;
  M.DCG := 1; M.C4G := 1; M.A8G := 1;
  M.RollCtx0 := 0; M.RollCtx1 := 0; M.RollCtx2 := 0;
  M.LastCtx := 0;
  M.Base46 := 0;
  M.Flag3934 := 0;
  M.ClsCtx := $201;
  M.ClsStride := 1;
  Detr_Init(M.Detr);

  Result := True;
end;

procedure QuarterRec1(var M: TPpmModel);
var Base, Index, Next, Slot, Sum: Integer;
begin
  for Base := 0 to $7FFF do
  begin
    Index := Base;
    while (Index < $40000) and (M.Rec1s[Index][0] <> 0) do
    begin
      Sum := 0;
      for Slot := 1 to 12 do
      begin
        M.Rec1s[Index][Slot] := M.Rec1s[Index][Slot] shr 2;
        Inc(Sum, M.Rec1s[Index][Slot]);
      end;
      if Sum = 0 then
      begin
        Next := Index;
        while (Next + $8000 < $40000) and (M.Rec1s[Next + $8000][0] <> 0) do
        begin
          M.Rec1s[Next] := M.Rec1s[Next + $8000];
          Inc(Next, $8000);
        end;
        M.Rec1s[Next][0] := 0;
      end
      else
      begin
        M.Rec1s[Index][0] := (M.Rec1s[Index][0] shr 2) + 1;
        M.Rec1s[Index][$19] := (M.Rec1s[Index][$19] and $3F) shr 1;
        M.Rec1s[Index][$1A] := M.Rec1s[Index][$1A] and $F;
        M.Rec1s[Index][$1B] := 0;
        if M.Rec1s[Index][M.Rec1s[Index][$1A] + 1] = 0 then M.Rec1s[Index][$1A] := 0;
        Inc(Index, $8000);
      end;
    end;
  end;
end;

procedure PpmPromoteToBc1(var M: TPpmModel);
var
  Saved: array[0..255] of Byte;
  Expanded: array[0..31] of Byte;
  D: TDetransform;
  OldPos, StartPos, ReadPos, WritePos, Half, StopPos, WarmPos: Cardinal;
  H1, H2, Ctx, Index, SavedDC, SavedC4, SavedA8: Cardinal;
  I, J, Count: Integer;
  Dump: File;
  procedure Save(const Name: string; const Data; Size: Integer);
  begin
    AssignFile(Dump, GetEnvironmentVariable('PPM_TRANSDUMP') + Name + '.bin');
    Rewrite(Dump, 1);
    BlockWrite(Dump, Data, Size);
    CloseFile(Dump);
  end;
begin
  SavedDC := M.DCG; SavedC4 := M.C4G; SavedA8 := M.A8G;
  OldPos := M.WinPos;
  for I := 0 to 255 do Saved[I] := M.Window[(OldPos + Cardinal(I)) and M.WinMask];
  StartPos := (OldPos + $140) and M.WinMask;
  Half := (M.WinWrap - $140) shr 1;
  ReadPos := (StartPos + Half) and M.WinMask;
  if Half > M.LastCtx then ReadPos := 0;
  WritePos := StartPos;
  Detr_Init(D);
  while ReadPos <> OldPos do
  begin
    Count := 0;
    Detr_Emit(D, M.Window[ReadPos], 0, M32, M32, @Expanded[0], Count);
    for J := 0 to Count - 1 do
    begin
      M.Window[WritePos] := not Expanded[J];
      WritePos := (WritePos + 1) and M.WinMask;
      if WritePos = ReadPos then Break;
    end;
    if WritePos = ReadPos then Break;
    ReadPos := (ReadPos + 1) and M.WinMask;
  end;
  M.WinPos := WritePos;
  for I := 0 to 255 do M.Window[(WritePos + Cardinal(I)) and M.WinMask] := Saved[I];
  for I := 1 to $40 do M.Window[(StartPos - Cardinal(I)) and M.WinMask] := 0;
  Move(M.Window[0], M.Window[M.WinWrap], $100);
  QuarterRec1(M);
  FillChar(M.Rec2s[0], Length(M.Rec2s) * SizeOf(TRec2Rec), 0);
  for I := 0 to HASH_COUNT - 1 do
  begin
    M.Ht1Pos[I] := M32; M.Ht1Ctx[I] := M32;
    M.Ht2New[I] := M32; M.Ht2Prev[I] := M32;
    M.LenTab[I] := 0; M.LinkTab[I] := 0;
  end;
  M.RollCtx0 := 0; M.RollCtx1 := 0; M.RollCtx2 := 0;
  M.Flag393B := 0;
  WarmPos := StartPos;
  StopPos := M32;
  if ((M.WinPos + M.WinWrap - StartPos) and M.WinMask) > $8000 then
    StopPos := (M.WinPos - $8000) and M.WinMask;
  while WarmPos <> M.WinPos do
  begin
    H1 := ((M.RollCtx0 shr 13) xor M.RollCtx0) and $3FFFF;
    H2 := ((((M.RollCtx0 shr 15) xor M.RollCtx0) shl 4) xor
      (((M.RollCtx1 shr 15) xor M.RollCtx1) shl 6) xor
      ((M.RollCtx2 shr 15) xor M.RollCtx2)) and $3FFFF;
    M.Ht2Prev[H2] := M.Ht2New[H2]; M.Ht2New[H2] := WarmPos;
    M.Ht1Pos[H1] := WarmPos; M.Ht1Ctx[H1] := M.RollCtx0;
    if WarmPos = StopPos then StopPos := M32;
    if StopPos = M32 then
    begin
      Ctx := M.RollCtx0;
      Index := ((Ctx shr 13) xor Ctx) and $7FFF;
      while Index < $40000 do
      begin
        if M.Rec1s[Index][0] = 0 then
        begin
          Inc(Index, $40000);
          Break;
        end;
        if (Cardinal(M.Rec1s[Index][$1C]) or (Cardinal(M.Rec1s[Index][$1D]) shl 8) or
            (Cardinal(M.Rec1s[Index][$1E]) shl 16) or (Cardinal(M.Rec1s[Index][$1F]) shl 24)) = Ctx then Break;
        Inc(Index, $8000);
      end;
      M.C48 := Ctx; M.C38 := Index;
      if Index < $40000 then
      begin
        M.C1C := M.Rec1s[Index][0];
        for I := 1 to 12 do Inc(M.C1C, M.Rec1s[Index][I]);
      end;
      Rec1_ApplyRecord(M, M.Window[WarmPos], Index, $FF);
    end;
    M.RollCtx2 := (M.RollCtx2 shl 8) or (M.RollCtx1 shr 24);
    M.RollCtx1 := (M.RollCtx1 shl 8) or (M.RollCtx0 shr 24);
    M.RollCtx0 := (M.RollCtx0 shl 8) or M.Window[WarmPos];
    WarmPos := (WarmPos + 1) and M.WinMask;
  end;
  M.DCG := SavedDC; M.C4G := SavedC4; M.A8G := SavedA8;
  SeedProbTables(M);
  M.E0BlkLen := M32;
  M.ByteClass := 1;
  if GetEnvironmentVariable('PPM_TRANSDUMP') <> '' then
  begin
    Save('window', M.Window[0], Length(M.Window));
    Save('rec1', M.Rec1s[0], Length(M.Rec1s) * SizeOf(TRec1Rec));
    Save('ht1pos', M.Ht1Pos[0], Length(M.Ht1Pos) * 4);
    Save('ht1ctx', M.Ht1Ctx[0], Length(M.Ht1Ctx) * 4);
    Save('ht2new', M.Ht2New[0], Length(M.Ht2New) * 4);
    Save('ht2prev', M.Ht2Prev[0], Length(M.Ht2Prev) * 4);
    Save('links', M.LinkTab[0], Length(M.LinkTab));
    WriteLn(ErrOutput, 'TRANS win=', M.WinPos, ' roll=', IntToHex(M.RollCtx0,8), ',',
      IntToHex(M.RollCtx1,8), ',', IntToHex(M.RollCtx2,8), ' last=', M.LastCtx,
      ' c38=', M.C38, ' c48=', IntToHex(M.C48,8), ' c1c=', M.C1C, ' link=', M.LinkPtr);
  end;
end;

procedure PPM_ReadBlockHeader(var M: TPpmModel; var R: TRangeDecoder);
var
  bit, chunk, cont, total, shift: Cardinal;
begin
  RD_Init(R, R.Data, R.Size);
  R.Code := 0; R.Range := M32;

  for bit := 0 to 4 do
    R.Code := (R.Code shl 8) or RD_ReadByte(R);

  bit := RD_GetFreq(R, 2);
  M.ByteClass := bit and $FF;
  RD_Decode(R, bit, 1);
  if M.ByteClass <> 0 then Exit;

  total := 0; shift := 0;
  while True do
  begin
    chunk := RD_GetFreq(R, $800);
    RD_Decode(R, chunk, 1);
    total := (total + ((chunk shl shift) and M32)) and M32;
    Inc(shift, $0B);
    cont := RD_GetFreq(R, 2);
    RD_Decode(R, cont, 1);
    if (cont and $FFFF) = 0 then Break;
  end;
  M.E0BlkLen := total;
  M.DetrThr2 := total;
end;

procedure RescaleRec2Table(var M: TPpmModel);
var
  idx, limit, off: Integer;
  acc, b, cls: Cardinal;
begin
  limit := Integer(Cardinal($20000) shr M.ByteClass);
  if limit > REC2_COUNT then limit := REC2_COUNT;
  for idx := 0 to limit - 1 do
  begin
    if M.Rec2s[idx][0] = 0 then Continue;
    acc := 0;
    for off := 7 downto 0 do
    begin
      b := M.Rec2s[idx][1 + off] shr 2;
      M.Rec2s[idx][1 + off] := b;
      acc := (acc + b) and $FF;
    end;
    if acc = 0 then
      M.Rec2s[idx][0] := 0
    else
      M.Rec2s[idx][0] := ((M.Rec2s[idx][0] shr 2) + 1) and $FF;
    M.Rec2s[idx][$11] := M.Rec2s[idx][$11] shr 1;
    cls := M.Rec2s[idx][$13] and $0F;
    M.Rec2s[idx][$13] := cls;
    acc := (acc + M.Rec2s[idx][0]) and $FF;
    M.Rec2s[idx][$12] := acc;
    if M.Rec2s[idx][1 + cls] = 0 then
      M.Rec2s[idx][$13] := 0;
  end;
end;

const

  CLS_CTXBASE: array[0..9] of Cardinal =
    ($201, $209, $229, $249, $2A9, $2E9, $2ED, $2F1, $2F9, $2FC);
  CLS_STRIDE : array[0..9] of Cardinal = (1, 1, 2, 3, 4, 1, 1, 2, 2, 4);
  CLS_SHIFT  : array[0..9] of Byte     = (0, 0, 8, 16, 24, 0, 0, 0, 0, 0);

function PpmSelectClass(var M: TPpmModel; Cls: Integer): Boolean;
begin
  Result := False;
  if GetEnvironmentVariable('PPM_CLASS_TRACE') <> '' then
    Writeln(ErrOutput, 'PPMCLASS old=', M.Flag3934, ' new=', Cls, ' count=', M.LastCtx);
  if (Cls < 0) or (Cls > 9) then Exit;
  if Cls <> M.Flag3934 then
  begin
    M.Flag3934 := Byte(Cls);
    M.ClsCtx := CLS_CTXBASE[Cls];
    M.ClsStride := CLS_STRIDE[Cls];
    M.ClsShift := CLS_SHIFT[Cls];
    M.ClsFlag31 := Ord((Cls = 5) or (Cls = 6));
    if (Cls = 5) or (Cls = 6) then M.MM6.Reset;
    if Cls >= 7 then M.MM7.Reset(Cls);
    M.ClsPhase := 0;
    M.ClsNeg := 0;
    M.ClsBase := 0;
  end;
  Result := True;
end;

function PpmBlockReset(var M: TPpmModel; var R: TRangeDecoder): Boolean;
var
  i, row: Integer;
  sym, rng0, cls: Cardinal;
begin
  Result := False;

  for i := 0 to $208 do
  begin
    M.Order0Wt[i] := M.ByteClass;
    M.Budget[i] := $4000;
  end;

  for i := 0 to $208 do
  begin
    M.PredByte[i] := $FF;
    M.ClsIdx[i] := 0;
  end;

  for row := 0 to $208 do
  begin
    FillChar(M.Cum[row], SizeOf(TFenwickRow), 0);
    FillChar(M.Freq[row], SizeOf(TFenwickRow), 0);
  end;

  for row := $301 to $30E do
    for i := 0 to $FF do
      M.Cum[row][i] := (PPMS_ROWSEED[i] shl 3) and $FFFF;

  for row := $301 to $30E do
    for i := 0 to $FF do
      M.Freq[row][i] := 8;

  for i := 0 to $208 do M.EntWt[i] := 1;

  for i := 0 to 255 do
  begin
    M.LzpClassRec[i][0] := 0; M.LzpClassRec[i][1] := 0;
    M.LzpClassRec[i][2] := 0; M.LzpClassRec[i][3] := 0;
  end;
  for i := 0 to ($290 div 8) - 1 do
  begin
    M.LzpClassRec[i][0] := PPMS_LZPCLASS_INIT[i*8]   or (PPMS_LZPCLASS_INIT[i*8+1] shl 8);
    M.LzpClassRec[i][1] := PPMS_LZPCLASS_INIT[i*8+2] or (PPMS_LZPCLASS_INIT[i*8+3] shl 8);
    M.LzpClassRec[i][2] := PPMS_LZPCLASS_INIT[i*8+4] or (PPMS_LZPCLASS_INIT[i*8+5] shl 8);
    M.LzpClassRec[i][3] := PPMS_LZPCLASS_INIT[i*8+6] or (PPMS_LZPCLASS_INIT[i*8+7] shl 8);
  end;

  for i := $209 to $300 do
    T268_Rescale(M, i);

  RescaleRec2Table(M);

  M.C54 := 0;
  M.C50 := 0;
  M.C44 := 0;
  M.RankPtrSmall := 0;
  M.C58 := $1FF;
  M.Flag393C := 0;
  M.RankPtrLarge := 0;
  for i := 0 to High(M.RankSmall) do M.RankSmall[i] := 0;
  for i := 0 to High(M.RankLarge) do M.RankLarge[i] := 0;
  for i := 0 to $FF do
  begin
    M.T46A[i] := 0;
    M.Recency[i] := 0;
    M.Hist[i] := 0;
  end;
  M.Br10 := 0;
  M.Br14 := 0;
  M.Br18 := 1;
  M.Brf0 := 1;
  M.Flag3939 := 0;
  for i := 0 to $FF do M.AgeRing[i] := $9240;
  M.AgeCtr := $FF;
  M.RecA[0] := 0; M.RecA[1] := 0;
  M.RecB[0] := 0; M.RecB[1] := 0;
  M.Age := $91ADC0;

  M.WpA := 0; M.WpB := 0; M.WpAccAdd := 0; M.WpPend := False;
  M.Flag393B := 0; M.Flag3943 := 0;

  M.NExcl := 0;
  M.S41 := 0; M.S45 := 0; M.S47 := 0; M.S48 := 0; M.S49 := 0;
  M.S3E := 0;
  M.Bec := 0;
  M.BFC := 0;
  M.OutCount := 0;

  rng0 := R.Range div 10;
  R.Range := rng0;
  sym := R.Code div rng0;
  M.C20 := 10;
  M.C24 := sym and $FF;
  M.C28 := (sym + 1) and M32;
  R.Code := (R.Code - sym * rng0) and M32;
  RD_Renorm(R);
  if GetEnvironmentVariable('PPM_CLSDBG') <> '' then
    writeln(ErrOutput, 'CLASSEL selector=', sym and $FF, ' current=', M.Flag3934);

  cls := sym and $FF;
  Result := PpmSelectClass(M, cls);
end;

end.
