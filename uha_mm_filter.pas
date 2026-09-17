unit uha_mm_filter;
{$mode delphi}{$H+}{$Q-}{$R-}
interface

procedure RestoreMultimediaFilter(var Buf: array of Byte; USize: Cardinal);
implementation
const
  Headers: array[0..2, 0..35] of Byte = (
    ($42, $4D, $3F, $3F, $3F, $3F, $3F, $3F, $3F, $3F, $3F, $3F, $3F, $3F, $3F, $3F, $3F, $3F, $3F, $3F, $3F, $3F, $3F, $3F, $3F, $3F, $01, $00, $18, $00, $00, $00, $00, $00, $3F, $3F),
    ($52, $49, $46, $46, $3F, $3F, $3F, $3F, $57, $41, $56, $45, $66, $6D, $74, $20, $3F, $3F, $3F, $3F, $01, $00, $3F, $00, $3F, $3F, $3F, $3F, $3F, $3F, $3F, $3F, $3F, $3F, $3F, $00),
    ($43, $72, $65, $61, $74, $69, $76, $65, $20, $56, $6F, $69, $63, $65, $20, $46, $69, $6C, $65, $1A, $1A, $00, $0A, $01, $29, $11, $01, $3F, $3F, $3F, $3F, $00, $3F, $3F, $3F, $3F)
  );
procedure RestoreMultimediaFilter(var Buf: array of Byte; USize: Cardinal);
var
  Kind, I, J, Stride, Phase, Shift: Integer;
  Matches: Boolean;
  Direction: array[0..3] of Boolean;
  History: Cardinal;
  Raw, Delta: Byte;
begin

  if (USize < 1024) or (USize > Cardinal(Length(Buf))) then Exit;
  Kind := -1;
  for J := 0 to 2 do
  begin
    Matches := True;
    for I := 0 to 35 do
      if (Headers[J, I] <> $3F) and (Headers[J, I] <> Buf[I]) then
        Matches := False;
    if Matches then Kind := J;
  end;
  case Kind of
    0: Stride := 3;
    1: begin
      Stride := Buf[22];
      if (Stride <> 1) and (Stride <> 2) then Exit;
      if Buf[34] = 16 then Stride := Stride * 2
      else if Buf[34] <> 8 then Exit;
    end;
    2: Stride := 1;
    else Exit;
  end;
  FillChar(Direction, SizeOf(Direction), 0);
  History := 0;
  Shift := Stride * 8 - 8;
  for I := 36 to Integer(USize) - 1 do
  begin
    Phase := I mod Stride;
    Raw := Buf[I];
    Delta := Raw;
    if Direction[Phase] then Delta := Byte(-Integer(Raw));
    if Raw >= $80 then Direction[Phase] := not Direction[Phase];
    Buf[I] := Byte(Delta + ((History shr Shift) and $FF));
    History := (History shl 8) or Buf[I];
  end;
end;
end.
