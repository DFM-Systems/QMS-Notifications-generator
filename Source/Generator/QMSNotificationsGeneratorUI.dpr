program QMSNotificationsGeneratorUI;

uses
  Vcl.Forms,
  MainForm in 'MainForm.pas' {frmMain},
  ThreadController in 'ThreadController.pas',
  SingleProjectThread in 'SingleProjectThread.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TfrmMain, frmMain);
  //Application.ShowMainForm := False;
  Application.Run;
end.
