unit MainForm;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, ThreadController, Vcl.StdCtrls, System.IniFiles, System.DateUtils,
  Vcl.ExtCtrls;

type
  TfrmMain = class(TForm)
    btnRun: TButton;
    btnTerminate: TButton;
    mmoResult: TMemo;
    btnNextTime: TButton;
    lblNextRun: TLabel;
    tmrRun: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure btnNextTimeClick(Sender: TObject);
    procedure btnRunClick(Sender: TObject);
    procedure btnTerminateClick(Sender: TObject);
    procedure tmrRunTimer(Sender: TObject);
  private
    procedure GetNextRunTime;
    procedure RunControllerThread;
    { Private declarations }
  public
    nextTime: TDateTime;
    mainThreadController: TThreadController;
    procedure UpdateLabel;

    { Public declarations }
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.dfm}

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  GetNextRunTime;
 // tmrRun.Enabled := True;
end;

procedure TfrmMain.btnNextTimeClick(Sender: TObject);
begin
  GetNextRunTime;
end;

procedure TfrmMain.btnRunClick(Sender: TObject);
begin
  RunControllerThread;
end;

procedure TfrmMain.btnTerminateClick(Sender: TObject);
begin
  if mainThreadController <> nil then
    mainThreadController.Terminate;


//    if mainThreadController.Finished then
//      mainThreadController := nil;
end;

procedure TfrmMain.GetNextRunTime;
var
  aIni: TIniFile;
  i: Integer;
  aCount: Integer;
  aTimeString: string;
  aDateTime: TDateTime;
  timeBias: Integer;
begin
  try
    aIni := TiniFile.Create(ExtractFilePath(Application.ExeName) + 'Settings.ini');

    try
      aCount := aIni.ReadInteger('SCHEDULE', 'COUNT', 0);
      timeBias := aIni.ReadInteger('SCHEDULE', 'TIME_BIAS', 0);

      if DayOfTheWeek(Now) in [1..5] then
        begin
          aTimeString := aIni.ReadString('SCHEDULE', 'RUN' + aCount.ToString, '');
          aDateTime := Date + StrToTime(aTimeString);

          if Now > aDateTime then
            begin
              aTimeString := aIni.ReadString('SCHEDULE', 'RUN1', '');

              if DayOfTheWeek(Now) = 5 then
                nextTime := IncDay(Date, 3) + StrToTime(aTimeString)
              else
                nextTime := IncDay(Date, 1) + StrToTime(aTimeString);

              lblNextRun.Caption := FormatDateTime('yyyy-mm-dd HH:nn:ss', nextTime);
              Exit;
            end;
        end
      else if DayOfTheWeek(Now) = 6 then
        begin
          aTimeString := aIni.ReadString('SCHEDULE', 'RUN1', '');
          nextTime := IncDay(Date, 2) + StrToTime(aTimeString);
          lblNextRun.Caption := FormatDateTime('yyyy-mm-dd HH:nn:ss', nextTime);
          Exit;
        end
      else if DayOfTheWeek(Now) = 7 then
        begin
          aTimeString := aIni.ReadString('SCHEDULE', 'RUN1', '');
          nextTime := IncDay(Date, 1) + StrToTime(aTimeString);
          lblNextRun.Caption := FormatDateTime('yyyy-mm-dd HH:nn:ss', nextTime);
          Exit;
        end;


      for i := 1 to aCount do
        begin
          aTimeString := aIni.ReadString('SCHEDULE', 'RUN' + i.ToString, '');
          aDateTime := Date + StrToTime(aTimeString);

          if aDateTime > Now then
            begin
              nextTime := IncMinute(aDateTime, timeBias);
              Break;
            end;
        end;

       lblNextRun.Caption := FormatDateTime('yyyy-mm-dd HH:nn:ss', nextTime);
    finally
      aIni.Free;
    end;
  except
    on e : Exception do
      begin
        raise Exception.Create('Get Next Run Time Error: ' + E.ClassName + #10#13 + E.Message);
      end;
  end;
end;

procedure TfrmMain.RunControllerThread;
begin
  mmoResult.Clear;
  mainThreadController := TThreadController.Create;
end;

procedure TfrmMain.tmrRunTimer(Sender: TObject);
begin
  if mainThreadController <> nil then
    begin
      if mainThreadController.Finished then
        begin
          mainThreadController := nil;

          if Now >= nextTime then
            begin
              GetNextRunTime;
              RunControllerThread;
            end;
        end;
    end
  else
    begin
      if Now >= nextTime then
        begin
          GetNextRunTime;
          RunControllerThread;
        end;
    end;
end;

procedure TfrmMain.UpdateLabel;
begin
  mmoResult.Lines.Add(mainThreadController.resultString);
end;


end.
