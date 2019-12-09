program Synth;

uses
  Vcl.Forms,
  uMain in 'uMain.pas' {frMain},
  uWaveApi in 'uWaveApi.pas',
  uWaveApiTest in 'uWaveApiTest.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TfrMain, frMain);
  Application.Run;
end.
