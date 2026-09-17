unit uha_ppm_c550;

{$mode delphi}{$H+}{$Q-}{$R-}

interface

uses uha_ppm_textbook, uha_ppm_kernel, SysUtils;

type
  TC550Result = record
    Sym       : Integer;
    Supported : Boolean;
    KCtx      : Integer;
    WorkCtx   : Integer;
    Weight    : Cardinal;
    Sse2Idx   : Integer;
    Sse2UpIdx : Integer;
    KernelExcl: Integer;
    PathA     : Boolean;
  end;

function C550_Decode(var M: TPpmModel; var R: TRangeDecoder;
  Ctx, NextCtx: Integer; out Res: TC550Result): Boolean;

implementation

var
  C550Dbg: Boolean;
  C550Lo: Integer = 139;
  C550Hi: Integer = 144;
  C550Window: string;
  C550Sep: Integer;

function C550_Decode(var M: TPpmModel; var R: TRangeDecoder;
  Ctx, NextCtx: Integer; out Res: TC550Result): Boolean;
var
  idx, age, freq: Cardinal;
  flag, kctx, workctx: Integer;
  KS: TKState;
begin
  Res.Sse2Idx := -1; Res.Sse2UpIdx := -1; Res.KernelExcl := -1; Res.Weight := 0;
  Res.PathA := False;

  idx := (M.AgeCtr + 1) and $FF;
  age := (M.Age - M.AgeRing[idx]) and $FFFFFFFF;
  flag := 0;
  if NextCtx = $301 then flag := 1;
  if (M.ByteClass <> 0) and (GetEnvironmentVariable('PPM_AGEDBG') <> '')
     and (M.WinPos >= 130) and (M.WinPos <= 133) then
    writeln(ErrOutput, 'AGE wpos=', M.WinPos, ' code=', IntToHex(R.Code,8),
      ' rng=', IntToHex(R.Range,8), ' age=', age, ' Age=', M.Age,
      ' ring[', idx, ']=', M.AgeRing[idx], ' ctr=', M.AgeCtr,
      ' nextctx=', IntToHex(NextCtx,3), ' path=',
      Chr(Ord('A') + Ord((age < $6D4250) or (age >= $FEFF01))*2 + Ord((age >= $6D4250) and (age < $91ADC0))*1));

  if (age < $6D4250) or (age >= $FEFF01) then
  begin
    kctx := Ctx; workctx := NextCtx;
  end
  else if age < $91ADC0 then
  begin
    if M.RecA[flag] > M.RecB[flag] then
    begin
      kctx := $200; workctx := $302 + flag;
    end
    else
    begin
      kctx := Ctx; workctx := NextCtx;
    end;
  end
  else
  begin
    freq := RD_GetFreq(R, $100);
    if freq > $FF then freq := $FF;
    RD_Decode(R, freq, 1);
    Res.Sym := Integer(freq);
    Res.Supported := True;
    Res.PathA := True;
    if GetEnvironmentVariable('PPM_PADBG')<>'' then writeln(ErrOutput,'PATHA hit ctx=',Ctx,' sym=',Integer(freq));
    Res.KCtx := Ctx; Res.WorkCtx := NextCtx; Res.Weight := 0;
    Result := True;
    Exit;
  end;

  if (M.ByteClass <> 0) and C550Dbg
     and (M.WinPos >= C550Lo) and (M.WinPos <= C550Hi) then
    writeln(ErrOutput, 'C550 wpos=', M.WinPos, ' Ctx=', Ctx, ' NextCtx=', NextCtx,
      ' age=', age, ' flag=', flag, ' RecA=', M.RecA[flag], ' RecB=', M.RecB[flag],
      ' -> kctx=', kctx, ' cum0=', M.Cum[kctx][0],
      ' entwt=', M.EntWt[kctx], ' ord0=', M.Order0Wt[kctx],
      ' code=', IntToHex(R.Code,8), ' rng=', IntToHex(R.Range,8));
  M.WorkCtx := workctx;
  Res.Sym        := Kernel_Decode(M, R, kctx, KS);
  Res.Supported  := KS.Supported;
  Res.KCtx       := kctx;
  Res.WorkCtx    := workctx;
  Res.Weight     := KS.Weight;
  Res.Sse2Idx    := KS.Sse2Idx;
  Res.Sse2UpIdx  := KS.Sse2UpIdx;
  Res.KernelExcl := KS.KernelExcl;
  Result := KS.Supported;
end;

initialization
  C550Window := GetEnvironmentVariable('PPM_C550DBG');
  C550Dbg := C550Window <> '';
  C550Sep := Pos(':', C550Window);
  if C550Sep > 0 then
  begin
    C550Lo := StrToIntDef(Copy(C550Window, 1, C550Sep - 1), C550Lo);
    C550Hi := StrToIntDef(Copy(C550Window, C550Sep + 1, 20), C550Hi);
  end;

end.
