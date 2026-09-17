unit uha_ppm_maint;

{$mode delphi}{$H+}{$Q-}{$R-}

interface

uses uha_ppm_kernel, SysUtils;

procedure MarkerMachine(var M: TPpmModel; Sym: Integer);
procedure RankMachinery(var M: TPpmModel; Sym: Integer);

procedure RingRecompute(var M: TPpmModel);

procedure RingStore(var M: TPpmModel; Sym: Integer);

procedure LastsymPredict(var M: TPpmModel);

implementation

procedure RingRecompute(var M: TPpmModel);
var c0, c1: Cardinal;
begin
  c0 := M.RollCtx0; c1 := M.RollCtx1;
  M.RingOff[0] := (((c0 shr $10) and $FF00) + (c1 shr $18)) and $FFFFFFFF;
  M.RingOff[1] := (((c0 shr 8) and $FFFF) + $10000) and $FFFFFFFF;
  M.RingOff[2] := (((c0 shr 8) and $FF00) + $20000 + (c0 and $FF)) and $FFFFFFFF;
  M.RingOff[3] := (((c0 shl 8) and $FF00) + $30000 + (c1 and $FF)) and $FFFFFFFF;
end;

procedure RingStore(var M: TPpmModel; Sym: Integer);
var i: Integer;
begin
  for i := 0 to 3 do M.RingBuf[M.RingOff[i]] := Sym and $FF;
end;

procedure LastsymPredict(var M: TPpmModel);
var i: Integer; b: Byte;
begin
  for i := 0 to 3 do
  begin
    b := M.RingBuf[M.RingOff[i]];
    M.LastSym[b] := M.LastCtx;
  end;
end;

procedure MarkerMachine(var M: TPpmModel; Sym: Integer);
var bh, obh: Integer; ch, other: Byte;
begin
  bh := M.LastCtx and 1; obh := 1 - bh;
  M.MarkerC[bh]     := (M.MarkerC[bh] * 2) and $F;
  M.MarkerC[2 + bh] := (M.MarkerC[2 + bh] * 2) and $F;
  M.MarkerFl := 0;
  if Sym < $80 then Exit;
  if Sym = $FF then
  begin
    M.MarkerC[2 + bh] := (M.MarkerC[2 + bh] + 1) and $FF;
    other := M.MarkerC[obh];
    if (other = $F) and (other = M.MarkerC[2 + bh]) then M.MarkerFl := 2;
    Exit;
  end;
  if ((Sym >= $80) and (Sym <= $DF)) or ((Sym >= $F2) and (Sym <= $F6)) then
  begin
    ch := (M.MarkerC[bh] + 1) and $FF;
    M.MarkerC[bh] := ch;
    other := M.MarkerC[2 + obh];
    if (other = $F) and (ch = other) then M.MarkerFl := 1;
  end;
end;

procedure RankMachinery(var M: TPpmModel; Sym: Integer);
label Stamp;
var
  mask, winpos, eax, ebp, edx, edx2, ecx, a: Cardinal;
  i: Integer;
begin
  mask := M.WinMask; winpos := M.WinPos;

  if (Sym = 0) or (Sym = $FF) then goto Stamp;
  eax := (winpos - M.Recency[Sym]) and mask;
  if eax >= $100 then
  begin
    eax := (winpos - M.Recency[(Sym - 1) and $FF]) and mask;
    if eax >= $100 then
      eax := (winpos - M.Recency[(Sym + 1) and $FF]) and mask;
  end;
  if (eax <> 0) and (eax < $100) then
  begin
    M.Hist[eax] := (M.Hist[eax] + 1) and $FFFFFFFF;
    ebp := M.Br18;
    if eax <> ebp then
    begin
      edx := (winpos - ebp) and mask;
      if Sym = M.Window[edx] then
        M.Hist[ebp] := (M.Hist[ebp] + 1) and $FFFFFFFF
      else
        M.Br10 := (M.Br10 + 2) and $FFFFFFFF;
      edx2 := M.Br14;
      if eax = edx2 then
      begin
        ecx := M.Br18;
        if M.Hist[edx2] >= M.Hist[ecx] then
        begin
          M.Br14 := ecx; M.Br18 := eax;
          if eax > 1 then M.Brf0 := eax;
        end;
      end
      else
        M.Br14 := eax;
    end;
  end;
  M.Br10 := (M.Br10 + 1) and $FFFFFFFF;
  if M.Br10 >= $28 then
  begin
    for i := 0 to $FF do M.Hist[i] := M.Hist[i] shr 1;
    a := M.Br18;
    M.Hist[a] := (M.Hist[a] + 1) and $FFFFFFFF;
    M.Br10 := 0;
    if a = 1 then
    begin
      ebp := M.Hist[1];
      if ebp < 4 then M.Hist[1] := (a + ebp) and $FFFFFFFF;
    end;
  end;
  M.Recency[Sym] := winpos;
Stamp:

  if M.ByteClass <> 0 then
    M.T46A[Sym and $FF] := (winpos + $40) and $FFFFFFFF;
end;

end.
