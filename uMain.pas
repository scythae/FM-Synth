unit uMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, System.Actions, Vcl.ActnList,
  Vcl.PlatformDefaultStyleActnCtrls, Vcl.ActnMan, Vcl.StdCtrls, Vcl.Buttons,
  System.UITypes, Math, MMSystem,

  uWaveApi, Vcl.ComCtrls, Vcl.ExtCtrls, Vcl.Imaging.pngimage;

type
  TWaveFormGenerator = reference to function(Period: Float): Float;

  TADSR = record
    Attack: Cardinal;
    Decay: Cardinal;
    Sustain: Extended;
    Release: Cardinal;
  end;

  TPreset = record
    Amplitude: Extended;
    WaveFormGenerator: TWaveFormGenerator;
    ModFreq: Extended;
    ModMultiplier: Extended;
    ADSR: TADSR;
  end;

  TWave = class(TComponent)
  public
    Preset: TPreset;
  private
    function GetAmplitudeEnvelope(Milliseconds: Float; ReleaseMilliseconds: Float): Float;
  public
    function GetWaveGenerator(Frequency: Float; KeyIsReleasedFunc: TFunc<Boolean>): TWaveGenerator;
  end;

  TWaveSet = TWave;

  TfrMain = class(TForm)
    imgKeyboard: TImage;
    tmrWaveRepaint: TTimer;
    pbWave: TPaintBox;
    Panel1: TPanel;
    eValue: TEdit;
    labelControlValue: TLabel;
    tbAmplitude: TTrackBar;
    labelAmplitude: TLabel;
    rgWaveForm: TRadioGroup;
    gbFM: TGroupBox;
    labelFMMultiplier: TLabel;
    labelFMFrequency: TLabel;
    tbModMultiplier: TTrackBar;
    tbModFreq: TTrackBar;
    gbADSR: TGroupBox;
    labelSustain: TLabel;
    labelAttack: TLabel;
    labelDecay: TLabel;
    labelRelease: TLabel;
    pbADSR: TPaintBox;
    tbSustain: TTrackBar;
    tbAttack: TTrackBar;
    tbDecay: TTrackBar;
    tbRelease: TTrackBar;
    tvWaves: TTreeView;
    btnPresetAdd: TButton;
    btnPresetDelete: TButton;
    procedure FormCreate(Sender: TObject);
    procedure OnUIChange(Sender: TObject);
    procedure pbWavePaint(Sender: TObject);
    procedure tmrWaveRepaintTimer(Sender: TObject);
    procedure pbADSRPaint(Sender: TObject);
    procedure btnPresetAddClick(Sender: TObject);
    procedure btnPresetDeleteClick(Sender: TObject);
    procedure tvWavesChange(Sender: TObject; Node: TTreeNode);
    procedure FormDestroy(Sender: TObject);
  const
    PaintWaveFrequency = 3;
    vkCodePaint = $FFFF;
  private
    Keyboard: array [0..255] of Boolean;
    KeysAndNoteIds: array [0..255] of Cardinal;
    KeysAndFrequencies: array [0..255] of Float;
    Wave: TWave;
    LastNoteTime: Cardinal;
    LastNoteFrequency: Float;
    PaintWaveFunc: TGetWaveVal;
    procedure OnAppMessage(var Msg: TMsg; var Handled: Boolean);
    procedure OnKeyDown(var vkCode: Cardinal);
    procedure OnKeyUp(var vkCode: Cardinal);
    procedure InitWaveFormGenerators();
    procedure InitKeyFrequencies();
    procedure UpdateUI;
    procedure OnControlMouseEnter(Sender: TObject);
    procedure PrepareUI;
    function GetControlValue(C: TControl): Variant;
    function GetWaveGenerator(Frequency: Float; KeyIsReleasedFunc: TFunc<Boolean> = nil): TWaveGenerator;
    function GetLastNoteTime: Cardinal;
    procedure PlayNote(vkCode: Cardinal);
    function GetTrackBarValue(tb: TTrackBar): Float;
    procedure StopNote(vkCode: Cardinal);
    procedure OnKeyUpDown(var Msg: TMsg; var Handled: Boolean);
    function GetControlDrawRect(Control: TControl): TRect;
    procedure CleanUpPaintBox(pb: TPaintBox);
  private
    Preset: TPreset;
  end;

var
  frMain: TfrMain;

implementation

{$R *.dfm}

type
  TWaveFormGeneratorType = (wfSine, wfTriangle, wfSaw, wfFlat, wfCosine);

var
  WaveFormGenerators: array[Low(TWaveFormGeneratorType)..High(TWaveFormGeneratorType)] of TWaveFormGenerator;

procedure TfrMain.FormCreate(Sender: TObject);
begin
  FillChar(Keyboard, Length(Keyboard), False);
  FillChar(KeysAndNoteIds, Length(KeysAndNoteIds), 0);

  Wave := TWaveSet.Create(Self);

  PaintWaveFunc := GetWaveGenerator(3)(0);
  LastNoteFrequency := 440;
  LastNoteTime := timeGetTime;

  InitWaveFormGenerators();
  InitKeyFrequencies();
  PrepareUI();
  Application.OnMessage := OnAppMessage;
end;

procedure TfrMain.FormDestroy(Sender: TObject);
var
  vkCode: Byte;
begin
  for vkCode := Low(Keyboard) to Low(Keyboard) do
    StopNote(vkCode);

  Sleep(500);
end;

type
  TLocalControl = class(TControl);

procedure TfrMain.PrepareUI();
var
  C: TComponent;
begin
  for C in Self do
    if C is TControl then
      TLocalControl(C).OnMouseEnter := OnControlMouseEnter;

  tvWaves.FullExpand();
  tvWaves.Selected := tvWaves.Items.GetFirstNode();
  UpdateUI();
end;

procedure TfrMain.OnUIChange(Sender: TObject);
begin
  OnControlMouseEnter(Sender);
  UpdateUI();
  pbADSR.Repaint();
end;

procedure TfrMain.UpdateUI();
begin
  Preset.WaveFormGenerator := WaveFormGenerators[TWaveFormGeneratorType(rgWaveForm.ItemIndex)];
  Preset.Amplitude := GetControlValue(tbAmplitude);
  Preset.ModFreq := GetControlValue(tbModFreq);
  Preset.ModMultiplier := GetControlValue(tbModMultiplier);
  Preset.ADSR.Attack := GetControlValue(tbAttack);
  Preset.ADSR.Decay := GetControlValue(tbDecay);
  Preset.ADSR.Sustain := GetControlValue(tbSustain);
  Preset.ADSR.Release := GetControlValue(tbRelease);
end;

function TfrMain.GetControlValue(C: TControl): Variant;
var
  tbVal: Variant;
begin
  if C is TTrackBar then
    tbVal := GetTrackBarValue(TTrackBar(C));

  if (C = tbAmplitude) or (C = tbSustain)  then
    Result := tbVal
  else if C = tbModFreq then
    Result := Power(tbVal, 6) * 1000
  else if C = tbModMultiplier then
    Result := 1 + Power(tbVal, 6) * 8
  else if (C = tbAttack) or (C = tbDecay) then
    Result := 1 + Round(Power(tbVal, 2) * 1999)
  else if C = tbRelease then
    Result := 1 + Round(Power(tbVal, 3) * 4999);
end;

function TfrMain.GetTrackBarValue(tb: TTrackBar): Float;
begin
  Result := (tb.Position - tb.Min) / (tb.Max - tb.Min)
end;

procedure TfrMain.OnAppMessage(var Msg: TMsg; var Handled: Boolean);
begin
  case Msg.message of
    WM_KEYDOWN, WM_KEYUP: OnKeyUpDown(Msg, Handled);
  end;
end;

procedure TfrMain.OnKeyUpDown(var Msg: TMsg; var Handled: Boolean);
var
  vkCode: Cardinal;
  Down: Boolean;
begin
  vkCode := Msg.wParam;
  if vkCode = 0 then
    Exit();

  Assert(vkCode in [0..255]);

  Down := Msg.message = WM_KEYDOWN;

  if Keyboard[vkCode] = Down then
    Exit();

  Keyboard[vkCode] := Down;

  if Down then
    OnKeyDown(vkCode)
  else
    OnKeyUp(vkCode);

  Handled := vkCode <> 0;
end;

procedure TfrMain.OnKeyDown(var vkCode: Cardinal);
begin
  if KeysAndFrequencies[vkCode] > 0 then
  begin
    StopNote(vkCode);
    PlayNote(vkCode);
  end;
end;

procedure TfrMain.OnKeyUp(var vkCode: Cardinal);
begin
end;

procedure TfrMain.StopNote(vkCode: Cardinal);
begin
  if KeysAndNoteIds[vkCode] > 0 then
  begin
    TWaveApi.Stop(KeysAndNoteIds[vkCode]);
    KeysAndNoteIds[vkCode] := 0;
  end;
end;

procedure TfrMain.PlayNote(vkCode: Cardinal);
begin
  LastNoteFrequency := KeysAndFrequencies[vkCode];
  LastNoteTime := timeGetTime;


  KeysAndNoteIds[vkCode] := TWaveApi.Play(Wave.GetWaveGenerator(
    KeysAndFrequencies[vkCode],
    function(): Boolean
    begin
      Result := not Keyboard[vkCode];
      if Result then
        Assert(True);
    end
  ));

  KeysAndNoteIds[vkCode] := TWaveApi.Play(GetWaveGenerator(
    KeysAndFrequencies[vkCode],
    function(): Boolean
    begin
      Result := not Keyboard[vkCode];
      if Result then
        Assert(True);
    end
  ));
end;

function TfrMain.GetWaveGenerator(Frequency: Float; KeyIsReleasedFunc: TFunc<Boolean>): TWaveGenerator;
var
  ReleaseMilliseconds: Float;
  GetAmplEnvelope: TGetWaveVal;
  GetWaveVal: TGetWaveVal;
begin
  if not Assigned(KeyIsReleasedFunc) then
    KeyIsReleasedFunc := function(): Boolean
    begin
      Result := False;
    end;

  ReleaseMilliseconds := 0;

  GetAmplEnvelope := function (Milliseconds: Float): Float
  begin
    if Milliseconds < Preset.ADSR.Attack then
      Result := 0.0001 + Milliseconds / Preset.ADSR.Attack
    else if Milliseconds < Preset.ADSR.Attack + Preset.ADSR.Decay then
      Result := 1 - (1 - Preset.ADSR.Sustain) * (Milliseconds - Preset.ADSR.Attack) / Preset.ADSR.Decay
    else if ReleaseMilliseconds = 0 then
      Result := Preset.ADSR.Sustain
    else
      Result := Preset.ADSR.Sustain * (1 - Power((Milliseconds - ReleaseMilliseconds) / Preset.ADSR.Release, 2));

    if Result < 0 then
      Result := 0;
  end;

  Result := function(Milliseconds: Float): TGetWaveVal
  var
    MustPlayPeriod: Float;
  begin
    if (ReleaseMilliseconds > 0) and (Milliseconds > ReleaseMilliseconds + Preset.ADSR.Release) then
      Exit(nil);

    MustPlayPeriod := Preset.ADSR.Attack + Preset.ADSR.Decay;
    if (Milliseconds > MustPlayPeriod) and (ReleaseMilliseconds = 0) and KeyIsReleasedFunc() then
      ReleaseMilliseconds := Milliseconds;

    Result := GetWaveVal;
  end;

  GetWaveVal := function(Milliseconds: Float): Float
  var
    FreqEnvelope: Float;
    AmplEnvelope: Float;
  begin
    AmplEnvelope := GetAmplEnvelope(Milliseconds);

    FreqEnvelope := Power(
      Preset.ModMultiplier,
      WaveFormGenerators[wfSine](Preset.ModFreq * Milliseconds / 1000)
    );

    Result := Preset.WaveFormGenerator(Frequency * Milliseconds / 1000 * FreqEnvelope)
      * Preset.Amplitude * AmplEnvelope;
  end;
end;

procedure TfrMain.tmrWaveRepaintTimer(Sender: TObject);
begin
  pbWave.Repaint();
end;

procedure TfrMain.pbWavePaint(Sender: TObject);
var
  C: TCanvas;
  SemiAmplitude, HCenter: Integer;
  X: Integer;
  DrawRect: TRect;

  function GetY(): Integer;
  var
    Time: Cardinal;
  begin
    Time := Round(GetLastNoteTime() * LastNoteFrequency / PaintWaveFrequency) div 1000;
    Result := Round(HCenter - SemiAmplitude * PaintWaveFunc(Time * 1000 + 1000 * X / (DrawRect.Width - 1)));
  end;
begin
  DrawRect := GetControlDrawRect(pbWave);
  HCenter := DrawRect.CenterPoint.Y;
  SemiAmplitude := DrawRect.Height div 2;

  CleanUpPaintBox(pbWave);

  C := pbWave.Canvas;

  C.Pen.Color := clGray;
  C.MoveTo(DrawRect.Left, DrawRect.Top);
  C.LineTo(DrawRect.Left, DrawRect.Bottom);
  C.MoveTo(DrawRect.Right, HCenter);
  C.LineTo(DrawRect.Left, HCenter);

  C.Pen.Color := clBlue;

  X := 0;
  C.MoveTo(X + DrawRect.Left, GetY());
  for X := 1 to DrawRect.Width - 1 do
    C.LineTo(X + DrawRect.Left, GetY());
end;

function TfrMain.GetControlDrawRect(Control: TControl): TRect;
var
  H, W, GapX, GapY: Integer;
begin
  H := Control.Height;
  W := Control.Width;
  GapX := W div 20;
  GapY := H div 10;
  Result := Rect(GapX, GapY, W - GapX, H - GapY);
end;

procedure TfrMain.CleanUpPaintBox(pb: TPaintBox);
begin
  pb.Canvas.Brush.Color := clCream;
  pb.Canvas.FillRect(pb.ClientRect);
end;

procedure TfrMain.pbADSRPaint(Sender: TObject);
var
  DrawRect: TRect;
  Quarter, Amp: Integer;
  C: TCanvas;
  X, Y: Integer;
begin
  DrawRect := GetControlDrawRect(pbADSR);
  Quarter := DrawRect.Width div 4;

  CleanUpPaintBox(pbADSR);

  C := pbADSR.Canvas;

  C.Pen.Color := clGray;
  C.MoveTo(DrawRect.Left, DrawRect.Top);
  C.LineTo(DrawRect.Left, DrawRect.Bottom);
  C.LineTo(DrawRect.Right, DrawRect.Bottom);

  C.Pen.Color := clBlue;

  X := DrawRect.Left;
  Y := DrawRect.Bottom;
  C.MoveTo(X, Y);

  X := X + Round(Quarter * GetTrackBarValue(tbAttack));
  Amp := Round(DrawRect.Height * GetTrackBarValue(tbAmplitude));
  Y := DrawRect.Bottom - Amp;
  C.LineTo(X, Y);

  X := X + Round(Quarter * GetTrackBarValue(tbDecay));
  Amp := Round(Amp * GetTrackBarValue(tbSustain));
  Y := DrawRect.Bottom - Amp;
  C.LineTo(X, Y);

  X := X + Quarter;
  C.LineTo(X, Y);

  X := X + Round(Quarter * GetTrackBarValue(tbRelease));
  Y := DrawRect.Bottom;
  C.LineTo(X, Y);
end;

function TfrMain.GetLastNoteTime(): Cardinal;
begin
  Result := MMSystem.timeGetTime - LastNoteTime;
end;

procedure TfrMain.OnControlMouseEnter(Sender: TObject);
var
  Value: Extended;
begin
  if Sender is TTrackBar then
    TWinControl(Sender).SetFocus();

  if not (Sender is TTrackBar) then
    Exit();

  Value := GetControlValue(TControl(Sender));
  eValue.Text := Format('%10.10f', [Value]);
end;

procedure TfrMain.InitKeyFrequencies();
  function Arr(const A: TArray<Cardinal>): TArray<Cardinal>;
  begin
    Result := A;
  end;
var
  I: Integer;
  Freq, NoteStep: Extended;
  vkCode: Cardinal;
begin
  for I := 0 to High(KeysAndFrequencies) do
    KeysAndFrequencies[I] := 0;

  NoteStep := Power(2, 1/12);

  Freq := 220;

  KeysAndFrequencies[vkA] := Freq / NoteStep;
  for vkCode in Arr([
    vkZ, vkS, vkX,
    vkC, vkF, vkV, vkG, vkB,
    vkN, vkJ, vkM, vkK, vkComma, vkL, vkPeriod,
    vkSlash, vkQuote
  ]) do
  begin
    KeysAndFrequencies[vkCode] := Freq;
    Freq := Freq * NoteStep;
  end;

  Freq := 440;
  KeysAndFrequencies[vk1] := Freq / NoteStep;
  for vkCode in Arr([
    vkQ, vk2, vkW,
    vkE, vk4, vkR, vk5, vkT,
    vkY, vk7, vkU, vk8, vkI, vk9, vkO,
    vkP, vkMinus, vkLeftBracket, vkEqual, vkRightBracket
  ]) do
  begin
    KeysAndFrequencies[vkCode] := Freq;
    Freq := Freq * NoteStep;
  end;
end;

procedure TfrMain.InitWaveFormGenerators();
begin
  WaveFormGenerators[wfSine] :=
  function(Period: Float): Float
  begin
    Result := Sin(2*Pi * Period);
  end;

  WaveFormGenerators[wfTriangle] :=
  function(Period: Float): Float
  begin
    Period := Frac(Period);
    if Period < 0.25 then
      Result := Period * 4
    else if Period < 0.75 then
      Result := 2 - Period * 4
    else
      Result := (-1 + Period) * 4;
  end;

  WaveFormGenerators[wfSaw] :=
  function(Period: Float): Float
  begin
    Result := -1 + Frac(Period) * 2;
  end;

  WaveFormGenerators[wfFlat] :=
  function(Period: Float): Float
  begin
    if Frac(Period) < 0.5 then
      Result := 1.0
    else
      Result := -1.0;
  end;

  WaveFormGenerators[wfCosine] :=
  function(Period: Float): Float
  begin
    Result := Cos(2*Pi * Period);
  end;
end;

procedure TfrMain.btnPresetAddClick(Sender: TObject);
begin
  if not Assigned(tvWaves.Selected) then
    tvWaves.Selected := tvWaves.Items.GetFirstNode();

  tvWaves.Items.AddChild(tvWaves.Selected, (tvWaves.Items.Count + 1).ToString());
  tvWaves.Selected.Expand(True);
end;

procedure TfrMain.btnPresetDeleteClick(Sender: TObject);
var
  N: TTreeNode;
begin
  N := tvWaves.Selected;

  tvWaves.Items.Delete(N);

//
end;
      {
procedure TfrMain.InitTreeView();
//var
//  N: TTreeNode;
begin
  tvWaves.Items.Clear();
//  N := tvWaves.Selected;
//
//  tvWaves.Items.Delete(N);

//
end;
     }
procedure TfrMain.tvWavesChange(Sender: TObject; Node: TTreeNode);
begin
  btnPresetDelete.Enabled := Node <> tvWaves.Items.GetFirstNode;
end;

{ TWave }

function TWave.GetAmplitudeEnvelope(Milliseconds: Float; ReleaseMilliseconds: Float): Float;
begin
  if Milliseconds < Preset.ADSR.Attack then
    Result := 0.0001 + Milliseconds / Preset.ADSR.Attack
  else if Milliseconds < Preset.ADSR.Attack + Preset.ADSR.Decay then
    Result := 1 - (1 - Preset.ADSR.Sustain) * (Milliseconds - Preset.ADSR.Attack) / Preset.ADSR.Decay
  else if ReleaseMilliseconds = 0 then
    Result := Preset.ADSR.Sustain
  else
    Result := Preset.ADSR.Sustain * (1 - Power((Milliseconds - ReleaseMilliseconds) / Preset.ADSR.Release, 2));

  if Result < 0 then
    Result := 0;
end;

function TWave.GetWaveGenerator(Frequency: Float;
  KeyIsReleasedFunc: TFunc<Boolean>): TWaveGenerator;
begin

end;

end.
