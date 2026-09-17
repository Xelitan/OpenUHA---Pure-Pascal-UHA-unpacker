unit uha_ppm_update;

{$mode delphi}{$H+}{$Q-}{$R-}

interface

uses uha_ppm_kernel;

procedure Recency_Update(var Tbl: array of Cardinal; Flag: Integer; Bec: Cardinal);

procedure AgeRing_Commit(var M: TPpmModel; Idx: Integer; Bec: Cardinal);

procedure UpdatePredbyte(var M: TPpmModel; Ctx, Sym: Integer);

procedure UpdateRollingCtx(var M: TPpmModel; Sym: Integer);

implementation

uses SysUtils;

var PbWatch2: Boolean; PbWatchCtx2: Integer = -1;
var PbUpd: Boolean; PbUpdLim: Integer = 0;

procedure Recency_Update(var Tbl: array of Cardinal; Flag: Integer; Bec: Cardinal);
var old: Cardinal;
begin
  old := Tbl[Flag];
  Tbl[Flag] := (Bec + ((old * 31) shr 5)) and $FFFFFFFF;
end;

procedure AgeRing_Commit(var M: TPpmModel; Idx: Integer; Bec: Cardinal);
var oldRing: Cardinal;
begin
  M.AgeCtr := Idx;
  oldRing := M.AgeRing[Idx];
  M.Age := (M.Age - oldRing + Bec) and $FFFFFFFF;
  M.AgeRing[Idx] := Bec;
end;

procedure UpdatePredbyte(var M: TPpmModel; Ctx, Sym: Integer);
var c: Byte;
begin
  if PbUpd and (Integer(M.WinPos) <= PbUpdLim) then
    writeln(ErrOutput, 'UPD ctx=', IntToHex(Ctx,3), ' sym=', Sym,
      ' old=', M.PredByte[Ctx], ' wpos=', M.WinPos);
  if Sym = M.PredByte[Ctx] then
  begin
    c := M.ClsIdx[Ctx];
    if c < $F then M.ClsIdx[Ctx] := c + 1;
  end
  else
  begin
    if PbWatch2 and (Ctx = PbWatchCtx2) then
      writeln(ErrOutput, 'PBW update  ctx=', IntToHex(Ctx,3), ' old=', M.PredByte[Ctx],
        ' new=', Sym and $FF, ' wpos=', M.WinPos);
    M.PredByte[Ctx] := Sym and $FF;
    M.ClsIdx[Ctx] := 0;
  end;
end;

procedure UpdateRollingCtx(var M: TPpmModel; Sym: Integer);
var c0, c1, c2: Cardinal;
begin
  if (M.ByteClass = 0) and (Sym >= $04) and (Sym <= $06) then
  begin
    if (M.RollCtx0 and $FF) = $DF then Exit;
    Sym := $DF;
  end;
  c0 := M.RollCtx0; c1 := M.RollCtx1; c2 := M.RollCtx2;
  M.RollCtx0 := ((c0 shl 8) or (Sym and $FF)) and $FFFFFFFF;
  M.RollCtx1 := ((c1 shl 8) or ((c0 shr 24) and $FF)) and $FFFFFFFF;
  M.RollCtx2 := ((c2 shl 8) or ((c1 shr 24) and $FF)) and $FFFFFFFF;
end;

initialization
  PbWatch2 := GetEnvironmentVariable('PPM_PBWATCH') <> '';
  PbWatchCtx2 := StrToIntDef(GetEnvironmentVariable('PPM_PBWATCH'), -1);
  PbUpd := GetEnvironmentVariable('PPM_PBUPD') <> '';
  PbUpdLim := StrToIntDef(GetEnvironmentVariable('PPM_PBUPD'), 0);

end.
