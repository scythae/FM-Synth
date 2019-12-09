unit uWaveApiTest;

interface

uses
  SysUtils, Dialogs, MMSystem, Math;

type
  TWaveApiTest = class
  private
    class function GetAudioData(): TBytes;
  public
    class procedure Play();
  end;

implementation

var
  Finished: Boolean;

procedure TestWaveOutProc(wo: HWaveOut; uMsg: NativeUInt; dwInstance, dwParam1, dwParam2: Cardinal);
begin
  if uMsg = WOM_DONE then
    Finished := True;
end;

class procedure TWaveApiTest.Play();
var
  ErrorMessage: string;

  procedure Ensure(waveOutResult: Cardinal);
  begin
    if waveOutResult = MMSYSERR_NOERROR then
      Exit;

    SetLength(ErrorMessage, MAXERRORLENGTH);
    if waveOutGetErrorText(waveOutResult, PChar(ErrorMessage), MAXERRORLENGTH) <> MMSYSERR_NOERROR then
      ErrorMessage := 'Unknown waveOut error';

    Abort();
  end;

  function woOpen(): HWaveOut;
  var
    WFormat: TWaveFormatEx;
  begin
    WFormat.wFormatTag := WAVE_FORMAT_PCM;
    WFormat.nChannels := 1;
    WFormat.wBitsPerSample := 8;
    WFormat.nSamplesPerSec := 8000;
    WFormat.nBlockAlign := WFormat.nChannels * WFormat.wBitsPerSample div 8;
    WFormat.nAvgBytesPerSec := WFormat.nSamplesPerSec * WFormat.nBlockAlign;
    WFormat.cbSize := 0;

    Ensure(waveOutOpen(@Result, WAVE_MAPPER, @WFormat, NativeUInt(@TestWaveOutProc), 0, CALLBACK_FUNCTION));
  end;

  procedure LimitInt(var I: Integer; const MinValue, MaxValue: Integer);
  begin
    if I < MinValue then
      I := MinValue
    else if I > MaxValue then
      I := MaxValue;
  end;

  function EncodeChannelsVolumePercentage(Left: Integer; Right: Integer = -1): Cardinal;
  begin
    if Right = -1 then
      Right := Left;

    LimitInt(Left, 0, 100);
    LimitInt(Right, 0, 100);

    Result := ($FFFF * Right div 100) shl 32 + $FFFF * Left div 100;
  end;
var
  wo: HWaveOut;
  Header: TWaveHdr;
  AudioData: TBytes;
//  Position: TMMTime;
begin
  try
    wo := woOpen();

    AudioData := GetAudioData();

    Header.lpData := Pointer(AudioData);
    Header.dwBufferLength := Length(AudioData);
//    Header.dwLoops := 1;
    Header.dwFlags := 0;
    Ensure(waveOutPrepareHeader(wo, @Header, SizeOf(TWaveHdr)));

    Finished := False;
    Ensure(waveOutWrite(wo, @Header, SizeOf(TWaveHdr)));

//    Position.wType := TIME_SAMPLES;
    repeat
//      Ensure(waveOutGetPosition(wo, @Position, SizeOf(Position)));
//
//      Ensure(waveOutSetVolume(wo, EncodeChannelsVolumePercentage(
//        50 + Round(20 * Sin(Position.Sample div 2000))
//      )));
    until Finished;

    Ensure(waveOutUnprepareHeader(wo, @Header, SizeOf(TWaveHdr)));

    Ensure(waveOutClose(wo));
  except
    ShowMessage(ErrorMessage);
    Exit();
  end;
end;

class function TWaveApiTest.GetAudioData(): TBytes;
var
  I: Integer;
begin
  SetLength(Result, 4000);
  for I := 0 to High(Result) do
    if Odd(I div 25) then
      Result[I] := 0
    else
      Result[I] := 255;

//    Result[I] := 127 - Round(Sin(I / 500) * 80) + Round(Sin(I / 5) * 30);
end;

end.

