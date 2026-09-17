unit uha_ppm_statics;

{$mode delphi}{$H+}{$Q-}{$R-}

interface

{$I uha_ppm_tables.inc}

var
  PPMS_F154:       array[0..16383] of Word;
  PPMS_RANKBASE_S: array[0..4]  of Cardinal;
  PPMS_RANKBASE_L: array[0..16] of Cardinal;
  AlzS7BankC:      array[0..255] of LongInt;
  AlzS7BankD:      array[0..255] of LongInt;
  AlzCandBucket9:  array[0..511] of LongInt;
  AlzSelTab2:      array[0..255] of Byte;
  AlzMMCost:       array[0..255] of Cardinal;
  PPMS_43A590:     array[0..255] of Cardinal;
  PPMS_PAGETAB:    array[0..287] of Cardinal;
  PPMS_REC1THR:    array[0..255] of Byte;
  PPMS_REC2THR:    array[0..255] of Byte;
  PPMS_LZPCLASS_INIT: array[0..655] of Byte;
  PPMS_ROWSEED:    array[0..255] of Word;

implementation

uses Math;

function ISqrt(x: LongInt): LongInt;
begin
  Result := 0;
  while (Result + 1) * (Result + 1) <= x do Inc(Result);
end;

function Bucket(const Thr: array of LongInt; hi, i: Integer): Integer;
var v: Integer;
begin
  Result := 0;
  for v := 0 to hi do
    if Thr[v] <= i then Result := v;
end;

const
  THR_43A590: array[0..6] of LongInt = (0, 4, 8, 14, 24, 40, 64);
  THR_PAGETAB: array[0..6] of LongInt = (0, 2, 4, 6, 10, 16, 30);

  LZPC_BASE: array[0..7] of Byte = (11, 11, 24, 11, 6, 6, 11, 6);
  LZPC_CAP:  array[0..7] of Byte = (14, 14, 24, 14, 9, 9, 11, 9);

procedure GenPpmStaticTables;
var
  i, j, v, m: Integer;
  fib: array[0..8] of LongInt;
  T2: array[0..15] of LongInt;
  rthr: array[0..12] of LongInt;
  fthr: array[0..10] of LongInt;
begin

  PPMS_F154[0] := 0;
  for i := 1 to 16383 do
    PPMS_F154[i] := Word(65520 - Ceil(4680.0 * Log2(i)));

  for i := 0 to 16 do
    if i < 2 then PPMS_RANKBASE_L[i] := 0
    else PPMS_RANKBASE_L[i] := Cardinal(255 + i * (i - 1) div 2);
  for i := 0 to 4 do PPMS_RANKBASE_S[i] := PPMS_RANKBASE_L[i];

  for i := 0 to 255 do
  begin
    j := i; if 256 - i < j then j := 256 - i;
    AlzS7BankC[i] := j shr 3;
    AlzS7BankD[i] := j shr 6;
  end;
  for i := 0 to 511 do
  begin
    j := i; if 512 - i < j then j := 512 - i;
    if j = 0 then AlzCandBucket9[i] := 0 else AlzCandBucket9[i] := ISqrt(j - 1) + 1;
  end;

  fib[0] := 1; fib[1] := 1;
  for i := 2 to 8 do fib[i] := fib[i - 1] + fib[i - 2];

  T2[0] := 0;
  for v := 1 to 8 do T2[v] := T2[v - 1] + fib[v];
  T2[9] := 170;
  for v := 10 to 15 do T2[v] := T2[v - 1] + fib[8 - (v - 10)];
  for i := 0 to 255 do AlzSelTab2[i] := Byte(Bucket(T2, 15, i));

  for v := 0 to 5 do rthr[v] := v;
  rthr[6] := 7;
  for v := 7 to 12 do rthr[v] := rthr[v - 1] + fib[v - 4];
  fthr[0] := 166;
  fthr[1] := fthr[0] + fib[8];  fthr[2] := fthr[1] + fib[7];
  fthr[3] := fthr[2] + fib[6];  fthr[4] := fthr[3] + fib[5];
  fthr[5] := fthr[4] + fib[4];  fthr[6] := fthr[5] + fib[3];
  fthr[7] := fthr[6] + fib[2];  fthr[8] := fthr[7] + fib[1];
  fthr[9] := fthr[8] + fib[0];  fthr[10] := fthr[9] + 1;
  for i := 0 to 255 do
  begin
    if i < 91 then AlzMMCost[i] := Cardinal(Bucket(rthr, 12, i))
    else if i <= 165 then AlzMMCost[i] := 12
    else AlzMMCost[i] := Cardinal(11 - Bucket(fthr, 10, i));
  end;

  for i := 0 to 255 do PPMS_43A590[i] := Cardinal(Bucket(THR_43A590, 6, i));
  for i := 0 to 287 do PPMS_PAGETAB[i] := Cardinal(Bucket(THR_PAGETAB, 6, i));

  for i := 0 to 255 do begin PPMS_REC1THR[i] := 125; PPMS_REC2THR[i] := 125; end;
  for i := 0 to 4 do begin PPMS_REC1THR[i] := 253; PPMS_REC2THR[i] := 247; end;
  PPMS_REC1THR[5] := 221; PPMS_REC1THR[6] := 157;
  PPMS_REC2THR[5] := 217; PPMS_REC2THR[6] := 155;

  for i := 0 to 81 do
  begin
    if i < 80 then
    begin
      v := LZPC_BASE[i div 10] + (i mod 10);
      if v > LZPC_CAP[i div 10] then v := LZPC_CAP[i div 10];
    end
    else if i = 80 then v := 49
    else v := 79;
    j := i * 8;
    PPMS_LZPCLASS_INIT[j]     := 0;  PPMS_LZPCLASS_INIT[j + 1] := 0;
    PPMS_LZPCLASS_INIT[j + 2] := 1;  PPMS_LZPCLASS_INIT[j + 3] := 0;
    PPMS_LZPCLASS_INIT[j + 4] := Byte(v);
    PPMS_LZPCLASS_INIT[j + 5] := 0;  PPMS_LZPCLASS_INIT[j + 6] := $63;
    PPMS_LZPCLASS_INIT[j + 7] := 0;
  end;

  for i := 0 to 63 do
  begin
    if i = 0 then v := 256
    else begin v := 4; m := i; while (m and 1) = 0 do begin v := v shl 1; m := m shr 1; end; end;
    j := i * 4;
    PPMS_ROWSEED[j] := Word(v); PPMS_ROWSEED[j + 1] := 1;
    PPMS_ROWSEED[j + 2] := 2;   PPMS_ROWSEED[j + 3] := 1;
  end;
end;

initialization
  GenPpmStaticTables;

end.
