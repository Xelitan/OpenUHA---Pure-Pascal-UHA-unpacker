unit uha_ppm_lzpclass;

{$mode delphi}{$H+}{$Q-}{$R-}

interface

uses uha_ppm_textbook, uha_ppm_kernel;

function Lzp_DecodeClass(var M: TPpmModel; var R: TRangeDecoder; CtxByte: Integer): Integer;

procedure Lzp_ApplyUpdate(var M: TPpmModel; CtxByte, Cls: Integer);

implementation

uses uha_ppm_statics, uha_ppm_model, SysUtils;

procedure Lzp_ApplyUpdate(var M: TPpmModel; CtxByte, Cls: Integer);
var
  tot, cx, bx, ebx, ecx: Cardinal;
begin
  CtxByte := CtxByte and $FF;
  if Cls = 1 then
    M.LzpClassRec[CtxByte][2] := (M.LzpClassRec[CtxByte][2] + $20) and $FFFF;

  tot := (M.LzpClassRec[CtxByte][3] + $20) and $FFFF;
  M.LzpClassRec[CtxByte][3] := tot;
  if tot >= $4000 then
  begin
    cx := M.LzpClassRec[CtxByte][2];
    bx := M.LzpClassRec[CtxByte][1];
    ebx := ((cx - bx) + 1) shr 1;
    ecx := ((M.LzpClassRec[CtxByte][3] - cx) + 1) shr 1;
    ebx := ebx + M.LzpClassRec[CtxByte][1];
    M.LzpClassRec[CtxByte][2] := ebx and $FFFF;
    M.LzpClassRec[CtxByte][3] := (ecx + ebx) and $FFFF;
  end;

  M.Base46 := PPMS_LZPTRANS[M.Base46 * 2 + Cls];
end;

function Lzp_DecodeClass(var M: TPpmModel; var R: TRangeDecoder; CtxByte: Integer): Integer;
var
  order, total, freq, counter, idx, sel: Integer;
  low, high: Cardinal;
begin
  order := M.Flag3934;
  if (M.ByteClass <> 0) and (GetEnvironmentVariable('PPM_CLSDBG') <> '') then
    writeln(ErrOutput, 'CLS wpos=', M.WinPos, ' ctx=', CtxByte,
      ' Code=', IntToHex(R.Code,8), ' Rng=', IntToHex(R.Range,8),
      ' rec=', M.LzpClassRec[CtxByte][0], ',', M.LzpClassRec[CtxByte][1], ',',
      M.LzpClassRec[CtxByte][2], ',', M.LzpClassRec[CtxByte][3], ' order=', order);
  while True do
  begin
    total := M.LzpClassRec[CtxByte][3];
    R.Range := R.Range div Cardinal(total);
    freq := (R.Code div R.Range) and $FFFF;

    counter := 3; idx := 3;
    while counter <> 0 do
    begin
      Dec(counter); Dec(idx);
      if freq >= M.LzpClassRec[CtxByte][idx] then Break;
    end;
    low  := M.LzpClassRec[CtxByte][idx];
    high := M.LzpClassRec[CtxByte][idx + 1];
    RD_Decode(R, low, (high - low) and $FFFFFFFF);
    if counter <> 0 then Exit(counter);

    R.Range := R.Range div $A;
    sel := (R.Code div R.Range) and $FFFF;
    RD_Decode(R, sel, 1);

    if not PpmSelectClass(M, sel) then Exit(-1);
    order := M.Flag3934;
  end;
end;

end.
