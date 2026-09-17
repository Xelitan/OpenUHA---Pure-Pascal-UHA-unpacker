unit uha_ppm_mf;

{$mode delphi}{$H+}{$Q-}{$R-}

interface

uses uha_ppm_textbook, uha_ppm_kernel, uha_ppm_statics, uha_ppm_lzpclass;

type
  TMatchResult = record
    IsMatch : Boolean;
    LzpCtx  : Integer;
    LzpCls  : Integer;
    RawLen  : Integer;
  end;

procedure Matchfinder_Decode(var M: TPpmModel; var R: TRangeDecoder;
  RawSyms: PByte; out MR: TMatchResult);

procedure Matchfinder_LiteralTail(var M: TPpmModel);

procedure Lzp_NomatchTail(var M: TPpmModel);

implementation

uses SysUtils;

const M32 = $FFFFFFFF;

var MfDbg: Boolean;

function Hash1(Ctx0: Cardinal): Cardinal; inline;
begin
  Result := ((Ctx0 shr $D) xor Ctx0) and $3FFFF;
end;

function Hash2(Ctx0, Ctx1, Ctx2: Cardinal): Cardinal; inline;
begin
  Result := ((((Ctx0 shr $F) xor Ctx0) shl 4) xor
             (((Ctx1 shr $F) xor Ctx1) shl 6) xor
             ((Ctx2 shr $F) xor Ctx2)) and $3FFFF;
end;

procedure RegisterEntry(var M: TPpmModel; Ctx0, Ctx1, Ctx2, WinPos: Cardinal);
var h1, h2: Cardinal;
begin
  h1 := Hash1(Ctx0);
  h2 := Hash2(Ctx0, Ctx1, Ctx2);
  M.LinkPtr := h1;
  M.Ht1Pos[h1] := WinPos;
  M.Ht1Ctx[h1] := Ctx0;
  M.Ht2Prev[h2] := M.Ht2New[h2];
  M.Ht2New[h2] := WinPos;
end;

procedure Matchfinder_LiteralTail(var M: TPpmModel);
begin
  M.B8 := 0;
end;

procedure Lzp_NomatchTail(var M: TPpmModel);
var h1: Cardinal;
begin
  h1 := Hash1(M.RollCtx0);
  M.D8 := (M.D8 + 1) and M32;
  M.LenTab[h1] := 0;
end;

function Ptr1Check(const M: TPpmModel; Ctx0, H1: Cardinal; var Edi: Cardinal): Integer;
begin
  if Ctx0 <> M.Ht1Ctx[H1] then
  begin
    if Edi <> M32 then Result := $1F else Result := 0;
    Exit;
  end;
  Edi := M.Ht1Pos[H1];
  if Edi <> M32 then Result := 1 else Result := 0;
end;

function ClassifyLow(const M: TPpmModel; Ctx0, WinPos, Mask, H1: Cardinal;
  Saved18: Byte; var Edi: Cardinal): Integer;
var
  base, w, c0: Cardinal;
  dist: Cardinal;
begin
  Edi := (WinPos - M.D4) and Mask;
  dist := (Edi - WinPos) and Mask;
  if dist >= $104 then
  begin
    base := (Edi - 4) and Mask;

    w := Cardinal(M.Window[base + 3]) or
         (Cardinal(M.Window[base + 2]) shl 8) or
         (Cardinal(M.Window[base + 1]) shl 16) or
         (Cardinal(M.Window[base]) shl 24);
    c0 := Ctx0;
    if (w and $FFFF) = (c0 and $FFFF) then Exit($0B);
    if (w and $FFFF00FF) = (c0 and $FFFF00FF) then Exit($0B);
    if (w and $FFFFFF00) = (c0 and $FFFFFF00) then Exit($0B);
  end;

  if Saved18 >= $40 then
    if M.LenTab[H1] = 0 then Exit(0);
  Result := Ptr1Check(M, Ctx0, H1, Edi);
end;

procedure Matchfinder_Decode(var M: TPpmModel; var R: TRangeDecoder;
  RawSyms: PByte; out MR: TMatchResult);
var
  ctx0, ctx1, ctx2, mask, wrap, winpos: Cardinal;
  h1, h2: Cardinal;
  saved18: Byte;
  type1c, flag30, depth: Integer;
  bestlen, matchlen: Cardinal;
  edi, cand, dist, cur, cur14, ebx: Cardinal;
  a, b, n: Cardinal;
  inprog, ddc, d4a8: Cardinal;
  cls, bank, node, declen, bit, nxt: Integer;
  maxlen, v: Cardinal;
  runit, freq, prob: Cardinal;
  pidx: Cardinal;
  length_, eEdi: Cardinal;
  i: Integer;
  ovBase: Cardinal;

  function ReadWin(Idx: Cardinal): Byte;
  var d: Cardinal;
  begin

    Idx := Idx and mask;
    d := (Idx - ovBase) and mask;
    if d < Cardinal(MR.RawLen) then
      Result := RawSyms[d]
    else
      Result := M.Window[Idx];
  end;

begin
  MR.IsMatch := False; MR.LzpCtx := -1; MR.LzpCls := 0; MR.RawLen := 0;

  ctx0 := M.RollCtx0; ctx1 := M.RollCtx1; ctx2 := M.RollCtx2;
  mask := M.WinMask; wrap := M.WinWrap; winpos := M.WinPos;

  h1 := Hash1(ctx0);
  h2 := Hash2(ctx0, ctx1, ctx2);
  M.LinkPtr := h1;
  saved18 := M.LinkTab[h1];

  type1c := 0;
  flag30 := 0;
  bestlen := 0;
  edi := 0;
  cur := winpos;
  while cur < $40 do
    Inc(cur, wrap);
  cur14 := cur - 1;

  for depth := 0 to 1 do
  begin
    if depth = 0 then cand := M.Ht2Prev[h2]
    else cand := M.Ht2New[h2];
    if cand <> M32 then
    begin
      dist := (cand - winpos) and mask;
      if dist >= $140 then
      begin
        ebx := cand;
        if ebx < $40 then Inc(ebx, wrap);
        if M.Window[cur - $C] = M.Window[ebx - $C] then
        begin
          n := 0;
          a := cur14; b := ebx - 1;
          while (n < $40) and (M.Window[a] = M.Window[b]) do
          begin
            Inc(n); Dec(a); Dec(b);
          end;
          matchlen := n;
          if matchlen >= bestlen then
          begin
            bestlen := matchlen;
            edi := cand;
          end;
        end;
      end;
    end;
  end;

  inprog := M.B8;
  if inprog <> 0 then
  begin
    edi := (winpos - M.D4) and mask;
    type1c := $50 + Ord(inprog > 2);
    flag30 := 1;
  end
  else
  begin
    if M.D8 >= $10 then v := $C else v := $30;
    if bestlen >= v then
      type1c := $15
    else
    begin
      type1c := ClassifyLow(M, ctx0, winpos, mask, h1, saved18, edi);
      if type1c = $0B then flag30 := 1;
    end;
  end;

  if MfDbg then
    writeln(ErrOutput, Format('  MFD ctx0=%.8x h1=%x type1c=%x saved18=%x lentab=%x ' +
      'ht1ctx=%.8x ht1pos=%x bestlen=%d edi=%x winpos=%x d4=%x b8=%x',
      [ctx0, h1, type1c, saved18, M.LenTab[h1], M.Ht1Ctx[h1], M.Ht1Pos[h1],
       bestlen, edi, winpos, M.D4, M.B8]));
  RegisterEntry(M, ctx0, ctx1, ctx2, winpos);
  if type1c = 0 then Exit;
  if ((edi - winpos) and mask) < $100 then Exit;
  if inprog = 0 then
  begin
    if M.LenTab[h1] = 0 then
      type1c := (type1c + M.Base46 + $27) and $FF
    else
      type1c := (type1c + M.Base46 - 1) and $FF;
  end;

  if M.HasCont then
  begin

    if M.Window[M.ContOfs] = M.Window[edi and mask] then
    begin
      Lzp_ApplyUpdate(M, type1c and $FF, 2);
      M.LenTab[h1] := 0;
      M.B8 := 0;
      Exit;
    end;

  end;

  cls := Lzp_DecodeClass(M, R, type1c and $FF);
  MR.LzpCtx := type1c and $FF;
  MR.LzpCls := cls;
  if cls <> 1 then Exit;

  ddc := M.DCG;
  if flag30 <> 0 then
  begin
    maxlen := PPMS_MAXLEN20[(M.C4G shl 2) div ddc];
    bank := Ord(M.B8 > 0) + 3 + Ord(M.B8 > 2);
  end
  else
  begin
    d4a8 := M.A8G;
    if d4a8 > ddc then
      maxlen := PPMS_MAXLEN10[(d4a8 shl 2) div ddc]
    else
    begin
      v := (PPMS_MAXLEN30[(M.C4G shl 2) div ddc] - M.ByteClass) and $FF;
      if M.MarkerFl <> 0 then
        v := (v + v) and $FF;
      maxlen := v;
    end;
    v := M.LenTab[h1];
    bank := Ord(v > $E) + Ord(v > $3E);
  end;

  if (M.ByteClass <> 0) and (GetEnvironmentVariable('PPM_MAXDBG') <> '') then
    writeln(ErrOutput, 'MAX winpos=', IntToHex(M.WinPos,3), ' flag30=', flag30,
      ' maxlen=', maxlen, ' bank=', bank, ' ddc=', ddc, ' C4G=', M.C4G,
      ' A8G=', M.A8G, ' mkfl=', M.MarkerFl, ' lentab=', M.LenTab[h1]);
  if MfDbg then
    writeln(ErrOutput, 'TREE winpos=', M.WinPos, ' maxlen=', maxlen, ' node=14',
      ' code=', IntToHex(R.Code,8), ' rng=', IntToHex(R.Range,8), ' bank=', bank);

  node := $E;
  declen := 0;
  while True do
  begin
    declen := (node + 1) and $FF;
    if maxlen < Cardinal(declen) then
    begin
      runit := R.Range div $1000;
      R.Range := runit;
      freq := (R.Code div runit) and $FFFF;
      pidx := Cardinal(bank) * $100 + Cardinal(node);
      prob := M.LenProb[pidx];
      if freq < prob then
      begin
        declen := node;
        M.LenProb[pidx] := (prob + (($1000 - prob) shr 4)) and M32;
        R.Code := R.Code;
        R.Range := (R.Range * prob) and M32;
        RD_Renorm(R);
      end
      else
      begin
        M.LenProb[pidx] := (prob - (prob shr 4)) and M32;
        R.Code := (R.Code - prob * R.Range) and M32;
        R.Range := (R.Range * (($1000 - prob) and M32)) and M32;
        RD_Renorm(R);
      end;
    end;
    if declen > node then bit := 1 else bit := 0;
    nxt := PPMS_LENTREE[node * 2 + bit];
    if nxt = 0 then Break;
    node := nxt;
  end;
  length_ := Cardinal(declen);

  dist := (winpos - (edi and mask)) and mask;
  if dist = M.D4 then
    M.D8 := M.D8 shr 1
  else
  begin
    M.D4 := dist;
    M.D8 := (M.D8 + length_) and M32;
  end;
  M.LenTab[h1] := length_ and $FF;
  if length_ = $FF then
  begin
    M.HasCont := False;
    M.ContOfs := 0;
    M.B8 := (M.B8 + 1) and M32;
  end
  else
  begin
    M.ContOfs := ((edi and mask) + length_) and mask;
    M.HasCont := True;
    M.B8 := 0;
  end;

  MR.IsMatch := True;
  MR.RawLen := 0;
  ovBase := winpos and mask;
  eEdi := edi and mask;
  for i := 1 to Integer(length_) do
  begin
    RawSyms[MR.RawLen] := ReadWin(eEdi);
    Inc(MR.RawLen);
    eEdi := (eEdi + 1) and mask;
  end;
end;

initialization
  MfDbg := GetEnvironmentVariable('PPM_MFDBG') <> '';

end.
