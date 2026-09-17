unit uha_ppm_m4;

{$mode delphi}{$H+}{$Q-}{$R-}

interface

uses uha_ppm_textbook, uha_ppm_kernel, uha_ppm_model, uha_ppm_mf,
  uha_ppm_lzpclass, uha_ppm_post, uha_ppm_cascade, uha_ppm_bc1sub;

type

  TPpmTraceInfo = record
    NSym    : Integer;
    OutPos  : Integer;
    Code    : Cardinal;
    Rng     : Cardinal;
    Pos     : Integer;
    IsMatch : Boolean;
    RawLen  : Integer;
    Route   : Integer;
    Sym     : Integer;
    Ctx0    : Cardinal;
    Ctx1    : Cardinal;
    Ctx2    : Cardinal;
  end;
  TPpmTraceProc = procedure(const T: TPpmTraceInfo);

var
  PpmTrace: TPpmTraceProc = nil;
  PpmFpEvery: Integer = 0;

function PPM_Decode(const FileData: array of Byte; Order: Integer;
  USize: Cardinal; var OutBuf: array of Byte): Integer;
function PPM_DecodeMembers(const FileData: array of Byte; Order: Integer;
  USize: Cardinal; const MemberEnds: array of Cardinal;
  var OutBuf: array of Byte): Integer;

implementation

uses SysUtils, uha_ppm_records;

var FullDbg: Boolean = False; FullLim: Integer = 0;

var RouteLo: Integer = 24666; RouteHi: Integer = 24674;
var R1Prev0: Integer = -1; R1Prev1: Integer = -1; R1PrevD: Integer = -1;

procedure PpmFingerprint(const M: TPpmModel; NSym: Integer);
var
  s: string;

  function SumW2D(const A: array of TFenwickRow; Rows: Integer): Cardinal;
  var i, j: Integer;
  begin
    Result := 0;
    for i := 0 to Rows - 1 do
      for j := 0 to $FF do
        Inc(Result, A[i][j]);
  end;

  function SumWords(const A: array of Word; N: Integer): Cardinal;
  var i: Integer;
  begin
    Result := 0;
    for i := 0 to N - 1 do Inc(Result, A[i]);
  end;

  function SumCards(const A: array of Cardinal; N: Integer): Cardinal;
  var i: Integer;
  begin
    Result := 0;
    for i := 0 to N - 1 do Inc(Result, A[i]);
  end;

  function SumBytes(const A: array of Byte; N: Integer): Cardinal;
  var i: Integer;
  begin
    Result := 0;
    for i := 0 to N - 1 do Inc(Result, A[i]);
  end;

  function SumRec1: Cardinal;
  var i, j: Integer;
  begin
    Result := 0;
    for i := 0 to REC1_COUNT - 1 do
      for j := 0 to $1F do
        Inc(Result, M.Rec1s[i][j]);
  end;

  function SumRec2: Cardinal;
  var i, j: Integer;
  begin
    Result := 0;
    for i := 0 to REC2_COUNT - 1 do
      for j := 0 to $13 do
        Inc(Result, M.Rec2s[i][j]);
  end;

  function SumLzpc: Cardinal;
  var i, j: Integer;
  begin
    Result := 0;
    for i := 0 to 255 do
      for j := 0 to 3 do
        Inc(Result, M.LzpClassRec[i][j]);
  end;

  procedure P(const Name: string; V: Cardinal);
  begin
    s := s + ' ' + Name + '=' + LowerCase(IntToHex(V, 8));
  end;

  procedure PS(const Name: string; V: Cardinal);
  begin
    s := s + ' ' + Name + '=' + LowerCase(IntToHex(V, 1));
  end;

begin
  s := 'FP n=' + IntToStr(NSym);
  P('cum', SumW2D(M.Cum, $30F));
  P('freq', SumW2D(M.Freq, $30F));
  P('entwt', SumWords(M.EntWt, $301));
  P('o0wt', SumCards(M.Order0Wt, $301));
  P('budget', SumCards(M.Budget, $300));
  P('pb', SumBytes(M.PredByte, $301));
  P('cls', SumBytes(M.ClsIdx, $301));
  P('sseprob', SumCards(M.SseProb, $800));
  P('sse2', SumCards(M.Sse2, $20));
  P('escm', SumCards(M.EscMass, $2000));
  P('pprob', SumCards(M.PredProb, $2000));
  P('eprob', SumCards(M.EntryProb, $100));
  P('lprob', SumCards(M.LenProb, $800));
  P('rwa', SumCards(M.RwA, $800));
  P('rwb', SumCards(M.RwB, $200));
  P('rwc', SumCards(M.RwC, $100));
  P('rwe', SumCards(M.RwE, $200));
  P('r2a', SumCards(M.R2A, $800));
  P('r2b', SumCards(M.R2B, $100));
  P('r2e', SumCards(M.R2E, $200));
  P('r2esc', SumCards(M.R2Esc, $20));
  P('rec1', SumRec1);
  P('rec2', SumRec2);
  P('ht1', SumCards(M.Ht1Pos, HASH_COUNT) + SumCards(M.Ht1Ctx, HASH_COUNT));
  P('ht2', SumCards(M.Ht2New, HASH_COUNT) + SumCards(M.Ht2Prev, HASH_COUNT));
  P('lentab', SumBytes(M.LenTab, HASH_COUNT));
  P('linktab', SumBytes(M.LinkTab, HASH_COUNT));
  P('ring', SumBytes(M.RingBuf, $40000));
  P('winb', SumBytes(M.Window, Integer(M.WinWrap) + $100));
  P('lzpc', SumLzpc);
  P('recency', SumCards(M.Recency, $100));
  P('t46a', SumCards(M.T46A, $100));
  P('hist', SumCards(M.Hist, $100));
  P('agering', SumCards(M.AgeRing, $100));
  P('lastsym', SumCards(M.LastSym, $100));
  P('ranks', SumCards(M.RankSmall, $109) + SumCards(M.RankLarge, $187));
  writeln(s);

  s := 'FS n=' + IntToStr(NSym);
  PS('c38', M.C38); PS('c40', M.C40); PS('c44', M.C44); PS('c48', M.C48);
  PS('c4c', M.C4C); PS('c50', M.C50); PS('c54', M.C54); PS('c1c', M.C1C);
  PS('c20', M.C20); PS('c24', M.C24); PS('c28', M.C28); PS('c3c', M.C3C);
  PS('bfc', M.BFC); PS('bec', M.Bec);
  PS('s41', M.S41); PS('s45', M.S45); PS('s47', M.S47); PS('s48', M.S48);
  PS('s49', M.S49); PS('nexcl', Cardinal(M.NExcl)); PS('b46', M.Base46);
  PS('d4', M.D4); PS('d8', M.D8); PS('b8', M.B8);
  PS('c4g', M.C4G); PS('dcg', M.DCG); PS('a8g', M.A8G);
  PS('age', M.Age); PS('agectr', M.AgeCtr);
  PS('br10', M.Br10); PS('br14', M.Br14); PS('br18', M.Br18);
  PS('brf0', M.Brf0); PS('lastctx', M.LastCtx); PS('winpos', M.WinPos);
  PS('mk', Cardinal(M.MarkerC[0]) or (Cardinal(M.MarkerC[1]) shl 8) or
    (Cardinal(M.MarkerC[2]) shl 16) or (Cardinal(M.MarkerC[3]) shl 24));
  PS('mkfl', M.MarkerFl);
  PS('dflag', M.Detr.Flag); PS('darg', M.Detr.Arg);
  PS('roll0', M.RollCtx0); PS('roll1', M.RollCtx1); PS('roll2', M.RollCtx2);
  writeln(s);
end;

function PPM_DecodeMembers(const FileData: array of Byte; Order: Integer;
  USize: Cardinal; const MemberEnds: array of Cardinal;
  var OutBuf: array of Byte): Integer;
var
  M: TPpmModel;
  R: TRangeDecoder;
  work: array of Byte;
  outLen, i, n, nsym: Integer;
  rawSyms: array[0..255] of Byte;
  MR: TMatchResult;
  dl: Boolean;
  route: TCascadeRoute;
  sym: Integer;
  TI: TPpmTraceInfo;
  NextBoundary, Target, Period: Cardinal;
  Member, StopAt: Integer;
  procedure AdvanceBoundary;
  begin
    Period := $40000 shr (M.ByteClass * 2);
    if USize - NextBoundary > Period then Target := NextBoundary + Period
    else Target := USize;
    if Target > M.E0BlkLen then Target := M.E0BlkLen;
    if Target > M.DetrThr1 then Target := M.DetrThr1;
    while (Member <= High(MemberEnds)) and (MemberEnds[Member] < Target) do Inc(Member);
    if Member <= High(MemberEnds) then NextBoundary := MemberEnds[Member]
    else NextBoundary := USize;
  end;
begin
  Result := PPM_ERR_ORDER;
  if (Order < $18) or (Order > $27) then Exit;
  if not PpmModelAllocate(M, Order) then Exit;

  Result := PPM_ERR_CORRUPT;
  M.BlkLen4 := USize;

  if Length(FileData) = 0 then Exit;
  RD_Init(R, @FileData[0], Length(FileData));
  PPM_ReadBlockHeader(M, R);

  if GetEnvironmentVariable('PPM_DBG') <> '' then
    writeln(ErrOutput, 'PPM hdr: ByteClass=', M.ByteClass, ' order=', Order,
      ' usize=', USize, ' fdlen=', Length(FileData));
  if (M.ByteClass <> 0) and (GetEnvironmentVariable('PPM_BC1') = '0') then Exit;
  NextBoundary := 0; Member := 0;
  AdvanceBoundary;
  if not PpmBlockReset(M, R) then
  begin
    if GetEnvironmentVariable('PPM_DBG') <> '' then
      writeln(ErrOutput, 'PPM exit: PpmBlockReset failed (ByteClass=', M.ByteClass, ')');
    Exit;
  end;
  if M.ByteClass <> 0 then Bc1Reset;

  if GetEnvironmentVariable('PPM_ROUTEWIN') <> '' then
  begin
    i := Pos(':', GetEnvironmentVariable('PPM_ROUTEWIN'));
    RouteLo := StrToIntDef(Copy(GetEnvironmentVariable('PPM_ROUTEWIN'), 1, i-1), 0);
    RouteHi := StrToIntDef(Copy(GetEnvironmentVariable('PPM_ROUTEWIN'), i+1, 20), 0);
  end;
  FullDbg := GetEnvironmentVariable('PPM_FULLDBG') <> '';
  if FullDbg then
  begin
    FullLim := StrToIntDef(GetEnvironmentVariable('PPM_FULLDBG'), 0);
    if FullLim <= 1 then FullLim := MaxInt;
  end;
  SetLength(work, USize + $1000);
  outLen := 0;
  nsym := 0;
  StopAt := StrToIntDef(GetEnvironmentVariable('PPM_STOPAT'), MaxInt);

  while Cardinal(outLen) < USize do
  begin
    if outLen >= StopAt then
    begin
      if (outLen > 0) and (Length(OutBuf) >= outLen) then
        Move(work[0], OutBuf[0], outLen);
      if GetEnvironmentVariable('PPM_PARTOK') <> '' then Result := PPM_OK;
      Exit;
    end;
    if Cardinal(outLen) >= M.E0BlkLen then
    begin
      PpmPromoteToBc1(M);
      Bc1Reset;
      NextBoundary := Cardinal(outLen);
    end;
    if Cardinal(outLen) >= NextBoundary then
    begin
      AdvanceBoundary;
      if not PpmBlockReset(M, R) then Exit;
      if M.ByteClass <> 0 then Bc1BlockReset;
      M.OutCount := Cardinal(outLen);
    end;
    if (M.ByteClass <> 0) and (GetEnvironmentVariable('PPM_RB') <> '') then
      writeln(ErrOutput, 'RB ol=', outLen, ' RecB1=', M.RecB[1], ' RecA1=', M.RecA[1]);
    if (GetEnvironmentVariable('PPM_CAP') <> '') and (outLen >= 160) then
    begin
      Write(ErrOutput, 'OUT[138..152]=');
      for i := 138 to 152 do Write(ErrOutput, work[i], ',');
      Writeln(ErrOutput);
      Break;
    end;
    if (PpmFpEvery > 0) and (nsym mod PpmFpEvery = 0) then
      PpmFingerprint(M, nsym);
    if Assigned(PpmTrace) then
    begin
      TI.NSym := nsym; TI.OutPos := outLen;
      TI.Code := R.Code; TI.Rng := R.Range; TI.Pos := R.Pos;
      TI.Ctx0 := M.RollCtx0; TI.Ctx1 := M.RollCtx1; TI.Ctx2 := M.RollCtx2;
    end;

    if (M.ByteClass <> 0) and (GetEnvironmentVariable('PPM_REC2EV') <> '')
       and (nsym >= 33) and (nsym <= 37) then
      writeln(ErrOutput, 'HEAD nsym=', nsym, ' rec2[0xffff]=', M.Rec2s[$FFFF][0], ',',
        M.Rec2s[$FFFF][1], ',', M.Rec2s[$FFFF][2], ',', M.Rec2s[$FFFF][3], ',', M.Rec2s[$FFFF][4]);

    if (M.ByteClass <> 0) and (GetEnvironmentVariable('PPM_CUMDBG') <> '') and (outLen <= 2370) then
    begin
      Write(ErrOutput, 'CUM wpos=', outLen, ' ');
      for i := $200 to $208 do
        Write(ErrOutput, M.Cum[i][0], ',');
      for i := $300 to $305 do
      begin
        Write(ErrOutput, M.Cum[i][0]);
        if i < $305 then Write(ErrOutput, ',');
      end;
      Writeln(ErrOutput);
    end;
    if (GetEnvironmentVariable('PPM_R1WATCH') <> '') then
    begin
      if (M.Rec1s[21422][0] <> R1Prev0) or (M.Rec1s[21422][1] <> R1Prev1)
         or (M.Rec1s[21422][$0D] <> R1PrevD) then
      begin
        writeln(ErrOutput, 'R1W outLen=', outLen, ' rec1[21422] [0]=', M.Rec1s[21422][0],
          ' [1]=', M.Rec1s[21422][1], ' [D]=', M.Rec1s[21422][$0D],
          ' [1A]=', M.Rec1s[21422][$1A], ' tag=',
          IntToHex(Cardinal(M.Rec1s[21422][$1C]) or (Cardinal(M.Rec1s[21422][$1D]) shl 8)
                or (Cardinal(M.Rec1s[21422][$1E]) shl 16) or (Cardinal(M.Rec1s[21422][$1F]) shl 24), 8));
        R1Prev0 := M.Rec1s[21422][0]; R1Prev1 := M.Rec1s[21422][1]; R1PrevD := M.Rec1s[21422][$0D];
      end;
    end;
    if (M.ByteClass <> 0) and (GetEnvironmentVariable('PPM_C50DBG') <> '') and (outLen <= 17740) then
      writeln(ErrOutput, 'C ', outLen, ' ', M.C50, ' ', Rec2NewCount, ' ', Rec2FoundCount);
    if (M.ByteClass <> 0) and (GetEnvironmentVariable('PPM_GDBG') <> '') and (outLen <= 24680) then
    begin
      Write(ErrOutput, 'G ', outLen, ' ', IntToHex(R.Code,8), ' ', IntToHex(R.Range,8),
        ' ', IntToHex(M.RollCtx0,8), ' ', M.RecA[0], ' ', M.RecA[1],
        ' ', M.RecB[0], ' ', M.RecB[1], ' ', M.NExcl, ' ');
      for i := $200 to $208 do Write(ErrOutput, M.Cum[i][0], ',');
      for i := $300 to $305 do
      begin
        Write(ErrOutput, M.Cum[i][0]);
        if i < $305 then Write(ErrOutput, ',');
      end;
      Write(ErrOutput, ' | ', M.C50, ' ', Rec2NewCount, ' ', Rec2FoundCount, ' | ');
      for i := 0 to 15 do
      begin
        Write(ErrOutput, Bc1.Ring[i]);
        if i < 15 then Write(ErrOutput, ',');
      end;
      Writeln(ErrOutput);
    end;
    if (M.ByteClass <> 0) and FullDbg and (outLen <= FullLim) then
    begin
      Write(ErrOutput, 'F ', outLen, ' ', IntToHex(R.Code,8), ' ', IntToHex(R.Range,8),
        ' ', IntToHex(M.RollCtx0,8), ' ', M.RecA[0], ' ', M.RecA[1],
        ' ', M.RecB[0], ' ', M.RecB[1], ' ', M.NExcl, ' ');
      for i := $200 to $208 do Write(ErrOutput, M.Cum[i][0], ',');
      for i := $300 to $305 do
      begin
        Write(ErrOutput, M.Cum[i][0]);
        if i < $305 then Write(ErrOutput, ',');
      end;
      Writeln(ErrOutput);
    end;
    if (M.ByteClass <> 0) and (GetEnvironmentVariable('PPM_MFRC') <> '') and (outLen <= 2380) then
      writeln(ErrOutput, 'MFRC outLen=', outLen, ' Code=', IntToHex(R.Code,8),
        ' Rng=', IntToHex(R.Range,8), ' roll0=', IntToHex(M.RollCtx0,8));
    Matchfinder_Decode(M, R, @rawSyms[0], MR);
    if (MR.LzpCtx >= 0) and (MR.LzpCls < 0) then
    begin
      if GetEnvironmentVariable('PPM_DBG') <> '' then
        writeln(ErrOutput, 'PPM exit: unsupported class at outLen=', outLen);
      if (GetEnvironmentVariable('PPM_PARTIAL') <> '') and (outLen > 0)
         and (Length(OutBuf) >= outLen) then
      begin
        Move(work[0], OutBuf[0], outLen);
        if GetEnvironmentVariable('PPM_PARTOK') <> '' then Result := PPM_OK;
      end;
      Exit;
    end;
    if (M.ByteClass <> 0) and (GetEnvironmentVariable('PPM_BC1DBG') <> '') then
      writeln(ErrOutput, Format('MF n=%d ismatch=%d rawlen=%d lzpctx=%d lzpcls=%d winpos=%x',
        [nsym, Ord(MR.IsMatch), MR.RawLen, MR.LzpCtx, MR.LzpCls, M.WinPos]));

    if MR.LzpCtx >= 0 then
    begin
      Lzp_ApplyUpdate(M, MR.LzpCtx, MR.LzpCls);
      if MR.LzpCls <> 1 then
        Lzp_NomatchTail(M);
    end;

    if MR.IsMatch then
    begin
      n := MR.RawLen;
      for i := 0 to n - 1 do
      begin
        if Cardinal(outLen) >= USize then Break;
        dl := (n - i) <= 8;
        PpmMatchMaintain(M, rawSyms[i], dl, @work[0], outLen);
      end;
      if Assigned(PpmTrace) then
      begin
        TI.IsMatch := True; TI.RawLen := n; TI.Route := -1; TI.Sym := -1;
        PpmTrace(TI);
      end;
    end
    else
    begin
      Matchfinder_LiteralTail(M);
      if not DecodeLiteralCascade(M, R, @work[0], outLen, route, sym) then
      begin
        if GetEnvironmentVariable('PPM_DBG') <> '' then
          writeln(ErrOutput, 'PPM exit: cascade False at nsym=', nsym, ' outLen=', outLen);
        if (GetEnvironmentVariable('PPM_PARTIAL') <> '') and (outLen > 0)
           and (Cardinal(Length(OutBuf)) >= Cardinal(outLen)) then
        begin
          if USize>0 then Move(work[0], OutBuf[0], USize);
          if GetEnvironmentVariable('PPM_PARTOK')<>'' then Result := PPM_OK;
        end;
        Exit;
      end;
      if (GetEnvironmentVariable('PPM_ROUTE') <> '') and (M.ByteClass <> 0)
         and (outLen >= RouteLo) and (outLen <= RouteHi) then
        writeln(ErrOutput, 'ROUTE nsym=', nsym, ' outLen=', outLen, ' route=', Ord(route), ' sym=', sym);
      if Assigned(PpmTrace) then
      begin
        TI.IsMatch := False; TI.RawLen := 0;
        TI.Route := Ord(route); TI.Sym := sym;
        PpmTrace(TI);
      end;
    end;

    Inc(nsym);
  end;

  if Cardinal(outLen) <> USize then
  begin
    if GetEnvironmentVariable('PPM_DBG') <> '' then
      writeln(ErrOutput, 'PPM exit: outLen=', outLen, ' <> USize=', USize,
        ' at nsym=', nsym);
    Exit;
  end;
  if Cardinal(Length(OutBuf)) < USize then Exit;
  if USize > 0 then
    Move(work[0], OutBuf[0], USize);
  if GetEnvironmentVariable('PPM_REC1SCAN') <> '' then
  begin
    nsym := 0; i := 0;
    for i := 0 to REC1_COUNT - 1 do
      if (M.Rec1s[i][0] = 0) and ((M.Rec1s[i][1] <> 0) or (M.Rec1s[i][2] <> 0)) then
        Inc(nsym);
    writeln(ErrOutput, 'REC1SCAN zero-count-but-populated records: ', nsym);
  end;
  Result := PPM_OK;
end;

function PPM_Decode(const FileData: array of Byte; Order: Integer;
  USize: Cardinal; var OutBuf: array of Byte): Integer;
begin
  Result := PPM_DecodeMembers(FileData, Order, USize, [], OutBuf);
end;

end.
