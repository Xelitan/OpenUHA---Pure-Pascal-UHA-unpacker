unit uha_ppm_predict;

{$mode delphi}{$H+}{$Q-}{$R-}

interface

uses uha_ppm_textbook, uha_ppm_kernel, uha_ppm_statics;

function PpmCtxRes(const M: TPpmModel): Integer;

function Predicted_Decode(var M: TPpmModel; var R: TRangeDecoder;
  Rec1Idx: Cardinal; out Sym: Integer): Boolean;

function Entry_Decode(var M: TPpmModel; var R: TRangeDecoder;
  Rec2Idx: Cardinal; out ProbOut: Cardinal): Boolean;

implementation

uses SysUtils, uha_ppm_bc1sub;

var PredProbDbg: Boolean;

var Bc1WpFireP: Boolean;

const M32 = $FFFFFFFF;

function PpmCtxRes(const M: TPpmModel): Integer;
begin
  Result := M.C48 and $FF;
  if (M.ByteClass = 0) and (M.Novel[(M.C48 shr 8) and $FF] <> 0) then
    Inc(Result, $100);
end;

function BinDecode(var R: TRangeDecoder; Prob: Cardinal): Boolean;
var
  runit, freq, low, high: Cardinal;
begin
  runit := R.Range div $2000;
  if ((runit = 0) or (Prob = 0) or (Prob >= $2000)) and (GetEnvironmentVariable('PPM_RNGGUARD') <> '') then
    writeln(ErrOutput, 'RNG0-SITE BinDecode Prob=', Prob, ' runit=', runit,
      ' Range=', IntToHex(R.Range,8));
  freq := (R.Code div runit) and $FFFF;
  Result := freq < Prob;
  if Result then begin low := 0; high := Prob; end
  else begin low := Prob; high := $2000; end;
  R.Code  := (R.Code - low * runit) and M32;
  R.Range := ((high - low) * runit) and M32;
  RD_Renorm(R);
end;

function Predicted_Decode(var M: TPpmModel; var R: TRangeDecoder;
  Rec1Idx: Cardinal; out Sym: Integer): Boolean;
var
  rollctx, rec2idx: Cardinal;
  ctx, rd, localB8, localD0, d0slot: Integer;
  idx, sse, prob, pidx: Cardinal;
begin

  rollctx := M.C48;
  rec2idx := rollctx and $FFFF;
  if (M.ByteClass = 0) and (M.Novel[(rollctx shr 16) and $FF] <> 0) then
    Inc(rec2idx, $10000);
  ctx := PpmCtxRes(M);
  localB8 := M.PredByte[ctx];
  d0slot := M.Rec2s[rec2idx][$13] and $F;
  localD0 := M.Rec2s[rec2idx][d0slot + 9];
  rd := M.Rec1s[Rec1Idx][$D];

  idx := M.Rec1s[Rec1Idx][1];
  if rd = localD0 then
    Inc(idx, M.Rec2s[rec2idx][$13] shr 4);
  if rd = localB8 then
    Inc(idx, M.ClsIdx[ctx]);

  sse := 0;
  if rd = localD0 then sse := 1;
  if rd = localB8 then sse := sse or 1;
  if (M.Rec2s[rec2idx][7] <> 0) and (M.C54 < 6) then sse := sse or $10;

  if M.ByteClass = 0 then
  begin
    if M.Novel[rd] <> 0 then sse := sse or 2;
  end
  else
  begin
    if M.WinPos <= M.T46A[rd and $FF] then sse := sse or $100;
    if rd = Integer(rollctx and $FF) then sse := sse or 2;
  end;
  if idx < $1E then
  begin
    sse := sse or (rollctx and $E0);
    if M.ByteClass = 0 then
    begin
      sse := sse or (Cardinal(M.Novel[(rollctx shr 8) and $FF]) shl 2);
      sse := sse or (Cardinal(M.Novel[rollctx and $FF]) shl 3);
    end
    else
    begin
      if (rollctx and $E0) = ((rollctx shr 8) and $E0) then sse := sse or 8;
      if (rollctx and $E0) = (Cardinal(rd) and $E0) then sse := sse or 4;
    end;
  end;
  if M.LastCtx = M.LastSym[rd] then sse := sse or $200;

  pidx := PPMS_PAGETAB[idx] * $400 + sse;
  prob := M.PredProb[pidx] and $FFFF;
  if PredProbDbg then
    writeln(ErrOutput, 'PDEC wpos=', M.WinPos, ' pidx=', pidx, ' prob=', prob,
      ' code=', IntToHex(R.Code,8), ' rng=', IntToHex(R.Range,8));

  Result := BinDecode(R, prob);
  if Result then
  begin
    Sym := rd;
    M.PredProb[pidx] := (prob + (($2000 - prob) shr 6)) and M32;
  end
  else
  begin
    Sym := -1;
    M.PredProb[pidx] := (prob - (prob shr 6)) and M32;
  end;
end;

function Entry_Decode(var M: TPpmModel; var R: TRangeDecoder;
  Rec2Idx: Cardinal; out ProbOut: Cardinal): Boolean;
var
  ctx, r9, localB8: Integer;
  idx, sse, prob, pidx: Cardinal;
begin
  r9 := M.Rec2s[Rec2Idx][9];
  ctx := PpmCtxRes(M);

  if Bc1WpFireP and (M.ByteClass <> 0) then
    localB8 := Bc1.Pred[ctx and $FF]
  else
    localB8 := M.PredByte[ctx];
  sse := 0;
  if r9 = localB8 then sse := 1;
  idx := M.Rec2s[Rec2Idx][1] shr 1;
  if r9 = localB8 then
    Inc(idx, M.ClsIdx[ctx]);
  if idx < $10 then
  begin
    if M.ByteClass = 0 then
    begin
      sse := sse or (Cardinal(M.Novel[(M.C48 shr 8) and $FF]) shl 1);
      sse := sse or (Cardinal(M.Novel[M.C48 and $FF]) shl 2);
    end
    else
      sse := sse or ((M.C48 and $C0) shr 5);
  end;

  if M.WinPos <= M.T46A[r9 and $FF] then sse := sse or $8;
  if M.LastCtx = M.LastSym[r9] then sse := sse or $10;

  pidx := PPMS_PAGETAB[idx] * $20 + sse;
  prob := M.EntryProb[pidx] and $FFFF;
  ProbOut := prob;
  if (M.ByteClass <> 0) and (GetEnvironmentVariable('PPM_ENTDBG') <> '') then
    writeln(ErrOutput, 'ENT wpos=', M.WinPos, ' pidx=', pidx, ' prob=', prob,
      ' sse=', sse, ' idx=', idx, ' r9=', r9, ' ctx=', ctx,
      ' Code=', IntToHex(R.Code,8), ' Rng=', IntToHex(R.Range,8),
      ' runit=', R.Range div $2000, ' freq=', (R.Code div (R.Range div $2000)) and $FFFF);

  Result := BinDecode(R, prob);
  if Result then
    M.EntryProb[pidx] := (prob + (($2000 - prob) shr 6)) and M32
  else
    M.EntryProb[pidx] := (prob - (prob shr 6)) and M32;
end;

initialization
  Bc1WpFireP := GetEnvironmentVariable('PPM_WPFIRE') <> '0';
  PredProbDbg := GetEnvironmentVariable('PPM_PDECDBG') <> '';

end.
