unit uWaveApi;

interface

uses
  SysUtils, Windows, Dialogs, MMSystem, Math, Classes;

const
  Format_nChannels = 1;
  Format_wBitsPerSample = 8;
  Format_nSamplesPerSec = 8000;
//  Format_wBitsPerSample = 16;
//  Format_nSamplesPerSec = 44100;
  BufferSizeInMillis = 50;
  SamplesPerBuffer = Format_nSamplesPerSec * BufferSizeInMillis div 1000 div Format_wBitsPerSample * Format_wBitsPerSample;
//  SamplesPerBuffer = Format_nSamplesPerSec * BufferSizeInMillis div 1000;


{$IF Format_wBitsPerSample = 8}
  SemiAmplitude = 127;
{$ELSEIF Format_wBitsPerSample = 16}
  SemiAmplitude = 32760;
{$ELSE}
  SemiAmplitude = 0;
{$IFEND}

type
  Float = Single;
  TGetWaveVal = reference to function(Millisecond: Float): Float;
  TWaveGenerator = reference to function(Millisecond: Float): TGetWaveVal;

type
  TWaveApi = class
  public
    class function Play(WaveGenerator: TWaveGenerator): Cardinal;
    class procedure Stop(PlayId: Cardinal);
    class procedure TestPlay();
  end;

{$IF Format_wBitsPerSample = 8}
  TBuffer = array of Byte;
{$ELSEIF Format_wBitsPerSample = 16}
  TBuffer = array of SmallInt;
{$ELSE}
  {$MESSAGE ERROR 'Only 8 and 16 bits per sample are supported'}
{$IFEND}

  TPlayerThread = class(TThread)
  private
    WaveGenerator: TWaveGenerator;
    WaveOut: HWaveOut;
    PlayFinishEvent: THandle;
    procedure FillWaveForm(var Buffer: TBuffer; var SampleNo: Cardinal;
      Freq: Cardinal = 880);
    procedure OpenWaveOut();
    procedure PlaySound();
    procedure FadeoutBuffer(var Buffer: TBuffer);
  protected
    procedure Execute(); override;
  end;

implementation

uses
  uWaveApiTest;

class procedure TWaveApi.TestPlay();
begin
  TWaveApiTest.Play();
end;

procedure Ensure(waveOutResult: Cardinal);
var
  ErrorMessage: string;
begin
  if waveOutResult = MMSYSERR_NOERROR then
    Exit;

  SetLength(ErrorMessage, MAXERRORLENGTH);
  if waveOutGetErrorText(waveOutResult, PChar(ErrorMessage), MAXERRORLENGTH) <> MMSYSERR_NOERROR then
    ErrorMessage := 'Unknown waveOut error';

  ShowMessage(ErrorMessage);
  Abort();
end;

class function TWaveApi.Play(WaveGenerator: TWaveGenerator): Cardinal;
var
  Player: TPlayerThread;
begin
  if not Assigned(WaveGenerator) then
    Exit(0);

  Player := TPlayerThread.Create(True);
  Player.FreeOnTerminate := True;
  Player.Priority := tpHigher;
  Player.WaveGenerator := WaveGenerator;
  Player.Start();

  Result := Cardinal(Player);

end;

class procedure TWaveApi.Stop(PlayId: Cardinal);
begin
  TPlayerThread(PlayId).Terminate();
end;

{ TPlayerThread }

procedure TPlayerThread.OpenWaveOut();
var
  WFormat: TWaveFormatEx;
begin
  WFormat.wFormatTag := WAVE_FORMAT_PCM;
  WFormat.nChannels := Format_nChannels;
  WFormat.wBitsPerSample := Format_wBitsPerSample;
  WFormat.nSamplesPerSec := Format_nSamplesPerSec;
  WFormat.nBlockAlign := WFormat.nChannels * WFormat.wBitsPerSample div 8;
  WFormat.nAvgBytesPerSec := WFormat.nSamplesPerSec * WFormat.nBlockAlign;
  WFormat.cbSize := 0;

  PlayFinishEvent := CreateEvent(nil, False, False, nil);
  Ensure(waveOutOpen(@WaveOut, WAVE_MAPPER, @WFormat, PlayFinishEvent, Cardinal(Self), CALLBACK_EVENT));
end;

procedure TPlayerThread.Execute();
begin
  OpenWaveOut();
  try
    PlaySound();
  except
    waveOutClose(WaveOut);
  end;
end;

procedure TPlayerThread.PlaySound();
type
  TWave = record
    Header: TWaveHdr;
    AudioData: TBuffer;
  end;
const
  BuffersCount = 2;

  function WaveDone(const Wave: TWave): Boolean; inline;
  begin
    Result := Wave.Header.dwFlags and WHDR_DONE = WHDR_DONE;
  end;

  function NextId(const CurrentId: Byte): Byte; inline;
  begin
    if CurrentId = BuffersCount - 1 then
      Result := 0
    else
      Result := CurrentId + 1;
  end;
var
  W: array [0..BuffersCount-1] of TWave;
  Id: Byte;
  SampleNo: Cardinal;
begin
  SampleNo := 0;

  for Id := 0 to BuffersCount - 1 do
  begin
    SetLength(W[Id].AudioData, SamplesPerBuffer);
    W[Id].Header.lpData := Pointer(W[Id].AudioData);
    W[Id].Header.dwBufferLength := SamplesPerBuffer;
    W[Id].Header.dwBytesRecorded := SamplesPerBuffer;
    W[Id].Header.dwFlags := 0;
    W[Id].Header.dwLoops := 0;
    Ensure(waveOutPrepareHeader(WaveOut, @(W[Id].Header), SizeOf(TWaveHdr)));

    FillWaveForm(W[Id].AudioData, SampleNo);
    Ensure(waveOutWrite(WaveOut, @(W[Id].Header), SizeOf(TWaveHdr)));
  end;

  repeat
    WaitForSingleObject(PlayFinishEvent, INFINITE);
    for Id := 0 to BuffersCount - 1 do
      if WaveDone(W[Id]) then
      begin
        FillWaveForm(W[Id].AudioData, SampleNo);
        if Terminated then
          FadeoutBuffer(W[Id].AudioData);

        Ensure(waveOutWrite(WaveOut, @(W[Id].Header), SizeOf(TWaveHdr)));
      end;
  until Terminated;

  for Id := 0 to BuffersCount - 1 do
  begin
    repeat until WaveDone(W[Id]);
    Ensure(waveOutUnprepareHeader(WaveOut, @(W[Id].Header), SizeOf(TWaveHdr)));
  end;
end;

procedure TPlayerThread.FillWaveForm(var Buffer: TBuffer; var SampleNo: Cardinal;
  Freq: Cardinal);
var
  I: Cardinal;
  CurrentMillisecond: Float;
  SampleValue: Float;
  GetWaveValFunc: TGetWaveVal;
begin
  for I := 0 to SamplesPerBuffer - 1 do
  begin
    if Terminated then
      SampleValue := 0
    else
    begin
      CurrentMillisecond := 1000 * (SampleNo + I) / Format_nSamplesPerSec;
      GetWaveValFunc := WaveGenerator(CurrentMillisecond);

      if Assigned(GetWaveValFunc) then
        SampleValue := GetWaveValFunc(CurrentMillisecond)
      else
      begin
        SampleValue := 0;
        Terminate();
      end;
    end;

    Buffer[I] := Round(SemiAmplitude * SampleValue) {$IF Format_wBitsPerSample = 8} + SemiAmplitude {$IFEND};
  end;

  Inc(SampleNo, SamplesPerBuffer);
end;

procedure TPlayerThread.FadeoutBuffer(var Buffer: TBuffer);
var
  I, MaxI: Integer;
begin
  MaxI := High(Buffer);
  for I := 0 to MaxI do
    Buffer[I] := (Buffer[I] {$IF Format_wBitsPerSample = 8} - SemiAmplitude {$IFEND}) * (MaxI - I) div MaxI
      {$IF Format_wBitsPerSample = 8} + SemiAmplitude {$IFEND};
end;

end.

