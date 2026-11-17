unit MainService;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  System.DateUtils, System.IniFiles, Vcl.Graphics, Vcl.Controls, Vcl.SvcMgr,
  Vcl.Dialogs, Vcl.ExtCtrls, ThreadController, VCL.Forms;

type
  TsrvMain = class(TService)
    tmrRun: TTimer;
    procedure ServiceCreate(Sender: TObject);
    procedure ServiceStart(Sender: TService; var Started: Boolean);
    procedure tmrRunTimer(Sender: TObject);
  private
    procedure GetNextRunTime;
    procedure RunControllerThread;
    { Private declarations }
  public
    nextTime: TDateTime;
    mainThreadController: TThreadController;
    function GetServiceController: TServiceController; override;
    { Public declarations }
  end;

var
  srvMain: TsrvMain;

implementation

{$R *.dfm}

procedure ServiceController(CtrlCode: DWord); stdcall;
begin
  srvMain.Controller(CtrlCode);
end;

procedure TsrvMain.ServiceCreate(Sender: TObject);
begin
  Self.Name := ChangeFileExt(ExtractFileName(Application.ExeName), '');
  Self.DisplayName := Self.Name;
end;

function TsrvMain.GetServiceController: TServiceController;
begin
  Result := ServiceController;
end;

procedure TsrvMain.tmrRunTimer(Sender: TObject);
begin
  if mainThreadController <> nil then
    begin
      if mainThreadController.Finished then
        begin
          Sleep(1000);
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

procedure TsrvMain.GetNextRunTime;
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

              Exit;
            end;
        end
      else if DayOfTheWeek(Now) = 6 then
        begin
          aTimeString := aIni.ReadString('SCHEDULE', 'RUN1', '');
          nextTime := IncDay(Date, 2) + StrToTime(aTimeString);
          Exit;
        end
      else if DayOfTheWeek(Now) = 7 then
        begin
          aTimeString := aIni.ReadString('SCHEDULE', 'RUN1', '');
          nextTime := IncDay(Date, 1) + StrToTime(aTimeString);
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

procedure TsrvMain.RunControllerThread;
begin
  mainThreadController := TThreadController.Create;
end;

procedure TsrvMain.ServiceStart(Sender: TService; var Started: Boolean);
begin
  GetNextRunTime;
  tmrRun.Enabled := True;
end;

end.
