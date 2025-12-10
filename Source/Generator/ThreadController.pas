unit ThreadController;

interface

uses
  System.SysUtils, System.Variants, System.Classes, System.IniFiles, Data.DB,
  dbisamtb, Vcl.Forms, System.Generics.Collections, SingleProjectThread,
  System.DateUtils, System.IOUtils, System.Types;

type
  TThreadController = class(TThread)

private
  nextTime: TDateTime;
  startTime: TDateTime;
  transactionKey,
  mainDbPath,
  resultsDbPath,
  projectFilesRootPath,
  appBasePath,
  tempPath,
  pdfOutputPath,
  messagesStorePath,
  blankTablesPath,
  projectsKeyList,
  siteURL,
  notificationType,
  debugEmail,
  messageTemplate,
  ownerLogoPath,
  secondaryEmail: string;
  includeAttachmentforAllMails,
  includeAttachmentforSecondaryEmail: Boolean;
  maxThreadsCount: Integer;
  selectRecordsOlderThanDays: Integer;
  threadTimeOutSeconds: Integer;
  totalMailFilesCreated: Integer;
  activeThreads: TObjectList<TSingleProjectThread>;
  function CheckResult(aResult: Pointer): Boolean;
  function ChekIfMaxThreadsRuning: Boolean;
  function CreateNewThread: Boolean;
  procedure FinishCompletedThreads;
  function GetGUID32: string;
  procedure InsertControllerError(aErrorMessage: string);
  procedure InsertControllerFinishTime;
  procedure InsertThreadError(aKey, aErrorMessage: string; aProcessTime,
      aMailFilesCreated: Integer);
  procedure InsertThreadFinishTime(aKey: string; aFinished: TDateTime;
      aProcessTime, aMailFilesCreated: Integer; aStats, aFullPdfOutputPath:
      string);
  procedure InsertThreadStartTime(aKey: string; aStarted: TDateTime);
  procedure LoadParameters;
  procedure ColectRecordsToNotifyAbout;
  function ConvertTablesFromDB3toDB4: Boolean;
  procedure CopyFolder(const SourceDir, DestDir: string);
  function ImportCsvToDB4Table(aTable: string): Boolean;
  procedure StartGeneration;

public
  resultString: string;
  dbsController: TDBISAMSession;
  qAction,
  qAction1: TDBISAMQuery;
  function CheckIfNotificationRequired(aRecordRef, aRecordType, aRecordStatus:
      string): Boolean;

protected
  procedure Execute; override;
  procedure BeforeDestruction; override;

end;

  //function ExportTableToCSV(aProjectDbPath, aTable, outputFolder, typesList: PAnsiChar): Pointer; stdcall; external 'DBISAM3_lib.dll';
  function ExportTableToCSV(aProjectDbPath, aTable, outputFolder, typesList: AnsiString): Pointer; stdcall; external 'DBISAM3_lib.dll';
  function ExportFormsToCSV(aProjectDbPath, aTable, outputFolder, filterString, olderRecordsThanDays: AnsiString): Pointer; stdcall; external 'DBISAM3_lib.dll';

implementation

  uses MainService; //For Service
  //uses MainForm;     //For UI App

procedure TThreadController.Execute;
var
  aList: TStringList;
begin
  inherited;
  aList := TStringList.Create;
  try
    try
      totalMailFilesCreated := 0;
      nextTime := srvMain.nextTime;  //For Service
      //nextTime := frmMain.nextTime;  //For UI App

      Self.FreeOnTerminate := True;

      startTime := Now;
      transactionKey := GetGUID32;

      activeThreads := TObjectList<TSingleProjectThread>.Create(True);
      dbsController := TDBISAMSession.Create(nil);
      qAction := TDBISAMQuery.Create(nil);
      qAction1 := TDBISAMQuery.Create(nil);

      dbsController.SessionName := 'Controller_' + GetGUID32;
      qAction.SessionName := dbsController.SessionName;
      qAction1.SessionName := dbsController.SessionName;

      LoadParameters;

      if not ConvertTablesFromDB3toDB4 then
        Exit;

      ColectRecordsToNotifyAbout;
      StartGeneration;
    except
      on e : Exception do
        begin
          aList.Text := E.ClassName + '  ' + E.Message;
          aList.SaveToFile('exception.txt');
          InsertControllerError(E.ClassName + '  ' + E.Message);
          Self.Terminate;
        end;
    end;
  finally
    aList.Free;
  end;
end;

procedure TThreadController.StartGeneration;
var
  i: Integer;
begin
  try
    i := 0;

    while not Self.Terminated do
      begin
        Inc(i);

        if not ChekIfMaxThreadsRuning then
          begin
            if not CreateNewThread then
              begin
                while activeThreads.Count > 0 do
                  begin
                    FinishCompletedThreads;
                    Sleep(1000);
                  end;

                InsertControllerFinishTime;
                Self.Terminate;
              end
            else
              Sleep(50);
          end
        else
          begin
            Sleep(1000);
          end;
      end;
  except
    on e : Exception do
      begin
        raise Exception.Create('StartGeneration Error: ' + E.ClassName + #10#13 + E.Message);
      end;
  end;
end;


function TThreadController.ChekIfMaxThreadsRuning: Boolean;
begin
  try
    if activeThreads.Count = maxThreadsCount then
      begin
        FinishCompletedThreads;
        Result := (activeThreads.Count <= maxThreadsCount);
      end
    else
      begin
        Result := False;
      end;
  except
    on e : Exception do
      begin
        raise Exception.Create('ChekIfMaxThreadsRuning Error: ' + E.ClassName + #10#13 + E.Message);
      end;
  end;
end;

procedure TThreadController.FinishCompletedThreads;
var
  aActiveThread: TSingleProjectThread;
  finishedThread: TSingleProjectThread;
  finishedThreads: TObjectList<TSingleProjectThread>;
  //for logging
  threadsCount, aRecordKey, aStep: string;
begin
  try
    aStep := '0';
    finishedThreads := TObjectList<TSingleProjectThread>.Create(False);
    try
      for aActiveThread in activeThreads do
        begin
          aStep := '1';
          if aActiveThread <> nil then
            begin
              aStep := '2';
              //check if  completed or time out
              if aActiveThread.IsDone then
                begin
                  aStep := '3';
                  resultString := aActiveThread.resultString;
                  aStep := '4';
                  finishedThreads.Add(aActiveThread);
                  //Synchronize(frmMain.UpdateLabel);      //For UI app
                end;
            end;
        end;

      aStep := '5';
      //Removed finished threads from active threads list
      threadsCount := finishedThreads.Count.ToString;
      if finishedThreads.Count > 0 then
        begin
          aStep := '6';
          for finishedThread in finishedThreads do
            begin
              aStep := '7';
              if finishedThread <> nil then
                begin
                  aStep := '8';
                  aRecordKey := finishedThread.RecordKey;
                  if not finishedThread.Failed then
                    begin
                      aStep := '9';
                      InsertThreadFinishTime(
                          finishedThread.RecordKey,
                          finishedThread.FinishedOn,
                          finishedThread.ProcessTime,
                          finishedThread.MailFilesCreated,
                          finishedThread.CompletedStats,
                          finishedThread.FullPdfOutputPath
                        );
                    end
                  else
                    begin
                      aStep := '10';
                      InsertThreadError(
                        finishedThread.RecordKey,
                        finishedThread.ExceptionMessage,
                        finishedThread.ProcessTime,
                        finishedThread.MailFilesCreated
                        );
                    end;
                  aStep := '11';
                  totalMailFilesCreated := totalMailFilesCreated + finishedThread.MailFilesCreated;
                  aStep := '12';
                  finishedThread.Terminate;
                  aStep := '13';
                  activeThreads.Remove(finishedThread);
                  aStep := '14';
                end;
            end;
        end;
    finally
      finishedThreads.Clear;
      finishedThreads.Free;
    end;
  except
    on e : Exception do
      begin
        raise Exception.Create('FinishCompletedThreads Error: ' + E.ClassName + #10#13 + E.Message + #10#13 +
           'Place: ' + aStep +  #10#13 + 'Finished Threads count:' + threadsCount +  #10#13 + 'RecordKey:' + aRecordKey);
      end;
  end;
end;

procedure TThreadController.ColectRecordsToNotifyAbout;
var
  aType, keysList: string;
begin
  keysList := '''''';
  try
    with qAction do
      begin
//        Close;
//        SQL.Clear;
//        SQL.Add('Select Key, if(SavedTime <> null then SavedTime else Modified) as SavedTime from insp_Forms');
//        SQL.Add('where type = ' + QuotedStr(aFormType) + ' and if(SavedTime <> null then SavedTime else Modified) >= :ModFrom');
//        //SQL.Add('where type = ' + QuotedStr(aFormType) + ' and (if(SavedTime <> null then SavedTime else Modified) > :ModFrom and Modified < :ModifiedEnd)');        //and SavedTime >= :ModFrom
//
//        SQL.Add('and Notify <> "" and Status = ' + QuotedStr('Completed') + '');
//        SQL.Add('and Template <> null and JSON <> "" and Deleted <> True ');
//
//        ParamByName('ModFrom').AsDate := dmMain.OBSModifiedWithinDate;

        Close;
        SQL.Clear;
        SQL.Add('SELECT F.Key, F.Code, F.Type, F.ProjectRef, F.Status, F.Notify, F.SourceRef');
        SQL.Add('FROM "' + tempPath + 'insp_Forms" F');
        SQL.Add('WHERE F.Deleted <> True and F.Notify <> null');

        //Select Site Diary records
        SQL.Add('AND ((F.Type = ''Site Diary'' and F.Status = ''Completed'')');

        //Select Site Observations records
        SQL.Add('OR (F.Type = ''Diary'' and F.Status = ''Completed'')');

        //Select CAR type forms, based on SourceRef
        SQL.Add('OR (F.SourceRef = ''9CA23B711D8B4FE79E168BC1EB026249'' and (F.Status = ''In Progress'' or F.Status = ''Completed'')))');

//        SQL.Add('WHERE Key in (''270C16838DE34628959DF3423E86C929'',''76808711447744C5BC2E2D212EFC1313'',''87FD28E0E97E497FAE6A29488F9957D9'',''9A92B8FF4B5F4282984D666D67810081'',''ADD74E3DDAFB4DEBB6A6904BF3528B82'',''B6A0ECC505924E4E953D1A1EF10B8A90'',''B85393B40BDE4C0995747B0BBAF72DBE'',''E3D74BF95A9A432686D7C955F39A4286'')');
//        SQL.Add('and Key in (''9D9CA666736249EFB949755CCCC22026'', ''233780715C914A51AD371A54008F8844'', ''54E4C8B35B9146E4825DF512CF11DE2A'', ''C77C28849CE744388A18A3037A63F1AC'')');

        Open;
        First;

        while not Eof do
          begin
            if FieldByName('SourceRef').AsString = '9CA23B711D8B4FE79E168BC1EB026249' then
              aType := 'CAR_FORM'
            else
              aType := FieldByName('Type').AsString;

            if CheckIfNotificationRequired(FieldByName('Key').AsString, aType, FieldByName('Status').AsString) then
              begin
                if keysList = '''''' then
                  keysList := '''' + FieldByName('Key').AsString + ''''
                else
                  keysList := keysList +  ',''' + FieldByName('Key').AsString + '''';
              end;

            Next;
          end;

        SQL.Clear;
        SQL.Add('SELECT F.Key, F.Code, F.Type, F.ProjectRef, F.Status, F.Notify');
        SQL.Add('INTO "Memory/SelectedRecords" FROM "' + tempPath + 'insp_Forms" F');
        SQL.Add('WHERE Key in ('+keysList+')');
        ExecSQL;

        SQL.Clear;
        SQL.Add('INSERT INTO "' + resultsDbPath + 'GenerateResults" (TransactionKey, RecordRef, Code, Type, ProjectRef, Status, Notify)');
        SQL.Add('SELECT ' + QuotedStr(transactionKey) + ', Key, Code, Type, ProjectRef, Status, Notify FROM "Memory/SelectedRecords";');
        ExecSQL;

        SQL.Clear;
        SQL.Add('SELECT * FROM "Memory/SelectedRecords";');
        Open;
        First;
      end;
  except
    on e : Exception do
      begin
        raise Exception.Create('ColectRecordsToNotifyAbout Error: ' + E.ClassName + #10#13 + E.Message + #10#13 + qAction.SQL.Text);
      end;
  end;
end;


function TThreadController.GetGUID32: string;
var
  aGuid: TGUID;
  aGuid32: string;
begin
  try
    System.SysUtils.CreateGUID(aGuid);
    aGuid32 := GUIDToString(aGuid);
    aGuid32 := StringReplace(aGuid32, '-', '', [rfReplaceAll]);
    aGuid32 := StringReplace(aGuid32, '{', '', [rfReplaceAll]);
    aGuid32 := StringReplace(aGuid32, '}', '', [rfReplaceAll]);
    Result := aGuid32;
  except
    on e : Exception do
      begin
        raise Exception.Create('GetGUID32 Error: ' + E.ClassName + #10#13 + E.Message);
      end;
  end;
end;

procedure TThreadController.LoadParameters;
var
  aIni: TIniFile;
  aList: TStringList;
  i: Integer;
begin
  try
    aList := TStringList.Create;
    aIni := TiniFile.Create(ExtractFilePath(Application.ExeName) + 'Settings.ini');

    try
      appBasePath := ExtractFilePath(Application.ExeName);
      tempPath := appBasePath + 'Temp\';
      blankTablesPath := appBasePath + 'Blank Tables\';
      resultsDbPath := ExtractFilePath(Application.ExeName) + 'Data\';
      mainDbPath := aIni.ReadString('CONFIG', 'MAIN_DB_PATH', '');
      projectsKeyList := aIni.ReadString('CONFIG', 'PROJECTS_LIST', '');
      maxThreadsCount := aIni.ReadInteger('CONFIG', 'MAX_THREADS_COUNT', 32);
      siteURL := aIni.ReadString('CONFIG', 'SITE_URL', 'https://share.onlinedfm.com/dfmdocs2.dll');
      threadTimeOutSeconds := aIni.ReadInteger('CONFIG', 'THREAD_TIMEOUT_SECONDS', 60);
      notificationType := aIni.ReadString('CONFIG', 'NOTIFICATION_TYPE', 'CDE_ACTIVITY');
      debugEmail := aIni.ReadString('CONFIG', 'DEBUG_EMAIL', '');
      projectFilesRootPath := aIni.ReadString('CONFIG', 'PROJECT_FILES_ROOT_PATH', '');
      pdfOutputPath := aIni.ReadString('CONFIG', 'PDF_OUTPUT_PATH', '');
      messagesStorePath := aIni.ReadString('CONFIG', 'MESSAGES_STORE_PATH', '');
      ownerLogoPath := aIni.ReadString('CONFIG', 'OWNER_LOGO_PATH', '');
      secondaryEmail := aIni.ReadString('CONFIG', 'SECONDARY_EMAIL', '');
      includeAttachmentforAllMails := aIni.ReadBool('CONFIG', 'INCLUDE_ATTACHMENT_FOR_ALL_EMAILS', False);
      includeAttachmentforSecondaryEmail := aIni.ReadBool('CONFIG', 'INCLUDE_ATTACHMENT_FOR_SECONDARY_EMAIL', True);
      selectRecordsOlderThanDays := aIni.ReadInteger('CONFIG', 'SELECT_RECORDS_OLDER_THAN_DAYS', -10);

      aList.LoadFromFile(appBasePath + 'templates\OBSPDFLINK.htm');
      messageTemplate := aList.Text;

      if projectsKeyList <> '' then
        begin
          aList.CommaText := projectsKeyList;
          projectsKeyList := '';

          for i := 0 to aList.Count-1 do
            begin
              if projectsKeyList = '' then
                projectsKeyList := QuotedStr(aList[i])
              else
                projectsKeyList := projectsKeyList + ', ' + QuotedStr(aList[i]);
            end;
        end;
    finally
      aList.Free;
      aIni.Free;
    end;
  except
    on e : Exception do
      begin
        raise Exception.Create('LoadParameters Error: ' + E.ClassName + #10#13 + E.Message);
      end;
  end;
end;


function TThreadController.CreateNewThread: Boolean;
var
  aStarted: TDateTime;
begin
  try
    with qAction do
      begin
        if not Eof then
          begin
            aStarted := Now;

            InsertThreadStartTime(
              FieldByName('Key').AsString,
              aStarted
            );

            activeThreads.Add(
              TSingleProjectThread.Create(
                messageTemplate,
                messagesStorePath,
                debugEmail,
                FieldByName('Key').AsString, //Forms record Key
                FieldByName('ProjectRef').AsString, //Forms record ProjectRef
                FieldByName('Code').AsString,
                FieldByName('Type').AsString,
                tempPath,       //Path to DB4 insp_Forms table
                pdfOutputPath, //Path to folder where Generated PDF is stored
                transactionKey,
                appBasePath,
                mainDbPath,
                siteURL,
                ownerLogoPath,
                secondaryEmail, //additional email to which email will be sent about any generated notification
                aStarted,
                threadTimeOutSeconds,
                includeAttachmentforAllMails,
                includeAttachmentforSecondaryEmail
                )
              );

            Next;
            Result := True;
          end
        else
          begin
            Close;
            Result := False;
          end;
      end;
  except
    on e : Exception do
      begin
        raise Exception.Create('CreateNewThread Error: ' + E.ClassName + #10#13 + E.Message);
      end;
  end;
end;

procedure TThreadController.InsertThreadStartTime(aKey: string; aStarted:
    TDateTime);
begin
  try
    with qAction1 do
      begin
        Close;
        SQL.Clear;
        SQL.Add('UPDATE "' + resultsDbPath + 'GenerateResults"');
        SQL.Add('SET Started = :Started');
        SQL.Add('WHERE TransactionKey = :TransactionKey and RecordRef = :RecordRef');
        ParamByName('Started').AsDateTime := aStarted;
        ParamByName('TransactionKey').AsString := transactionKey;
        ParamByName('RecordRef').AsString := aKey;

        ExecSQL;
        Close;
      end;
  except
    on e : Exception do
      begin
        raise Exception.Create('CreateNewThread Error: ' + E.ClassName + #10#13 + E.Message);
      end;
  end;
end;

procedure TThreadController.InsertThreadFinishTime(aKey: string; aFinished:
    TDateTime; aProcessTime, aMailFilesCreated: Integer; aStats,
    aFullPdfOutputPath: string);
begin
  with qAction1 do
    begin
      Close;
      SQL.Clear;
      SQL.Add('UPDATE "' + resultsDbPath + 'GenerateResults"');
      SQL.Add('SET Finished = :Finished, ProcessSeconds = :ProcessSeconds, Stats = :Stats, MailFilesCreated = :MailFilesCreated, Success = :Success, GeneratedPDF = :GeneratedPDF');
      SQL.Add('WHERE TransactionKey = :TransactionKey and RecordRef = :RecordRef');
      ParamByName('Finished').AsDateTime := aFinished;
      ParamByName('ProcessSeconds').AsInteger := aProcessTime;
      ParamByName('Stats').AsString := aStats;
      ParamByName('MailFilesCreated').AsInteger := aMailFilesCreated;
      ParamByName('Success').AsBoolean := aMailFilesCreated > 0;
      ParamByName('GeneratedPDF').AsString := aFullPdfOutputPath;
      ParamByName('TransactionKey').AsString := transactionKey;
      ParamByName('RecordRef').AsString := aKey;

      ExecSQL;
      Close;
    end;
end;

procedure TThreadController.InsertThreadError(aKey, aErrorMessage: string;
    aProcessTime, aMailFilesCreated: Integer);
begin
  with qAction1 do
    begin
      Close;
      SQL.Clear;
      SQL.Add('UPDATE "' + resultsDbPath + 'GenerateResults"');
      SQL.Add('SET Notes = :Notes, ProcessSeconds = :ProcessSeconds, MailFilesCreated = :MailFilesCreated');
      SQL.Add('WHERE TransactionKey = :TransactionKey and RecordRef = :RecordRef');
      ParamByName('TransactionKey').AsString := transactionKey;
      ParamByName('RecordRef').AsString := aKey;
      ParamByName('Notes').AsString := aErrorMessage;
      ParamByName('ProcessSeconds').AsInteger := aProcessTime;
      ParamByName('MailFilesCreated').AsInteger := aMailFilesCreated;

      ExecSQL;
      Close;
    end;
end;

procedure TThreadController.InsertControllerFinishTime;
begin
  with qAction1 do
    begin
      Close;
      SQL.Clear;
      SQL.Add('INSERT INTO "' + resultsDbPath + 'GenerateResults" (TransactionKey, Started, Finished, ProcessSeconds, RecordRef, Stats, MailFilesCreated, Success)');
      SQL.Add('VALUES (:TransactionKey, :Started, :Finished, :ProcessSeconds, :RecordRef, :Stats, :MailFilesCreated, :Success);');
      ParamByName('TransactionKey').AsString := transactionKey;
      ParamByName('Started').AsDateTime := startTime;
      ParamByName('Finished').AsDateTime := Now;
      ParamByName('ProcessSeconds').AsInteger := SecondsBetween(Now, startTime);
      ParamByName('RecordRef').AsString := 'Completed';
      ParamByName('Success').AsBoolean := True;
      ParamByName('Stats').AsString := 'Next Run: ' + FormatDateTime('yyyy-mm-dd HH:nn', nextTime);
      ParamByName('MailFilesCreated').AsInteger := totalMailFilesCreated;

      ExecSQL;
      Close;
    end;
end;

procedure TThreadController.InsertControllerError(aErrorMessage: string);
begin
  with qAction1 do
    begin
      Close;
      SQL.Clear;
      SQL.Add('INSERT INTO "' + resultsDbPath + 'GenerateResults" (TransactionKey, Started, Finished, ProcessSeconds, RecordRef, Notes, Stats, MailFilesCreated)');
      SQL.Add('VALUES (:TransactionKey, :Started, :Finished, :ProcessSeconds, :RecordRef, :Notes, :Stats, :MailFilesCreated);');
      ParamByName('TransactionKey').AsString := transactionKey;
      ParamByName('Started').AsDateTime := startTime;
      ParamByName('Finished').AsDateTime := Now;
      ParamByName('ProcessSeconds').AsInteger := SecondsBetween(Now, startTime);
      ParamByName('RecordRef').AsString := 'Error Stop';
      ParamByName('Notes').AsString := aErrorMessage;
      ParamByName('Stats').AsString := 'Next Run: ' + FormatDateTime('yyyy-mm-dd HH:nn', nextTime);
      ParamByName('MailFilesCreated').AsInteger := totalMailFilesCreated;

      ExecSQL;
      Close;
    end;
end;

procedure TThreadController.BeforeDestruction;
var
  i: Integer;
begin
  inherited;

  with qAction do
    begin
      Close;
      SQL.Clear;
      SQL.Add('DROP TABLE IF EXISTS "Memory/SelectedProjects"');;
      ExecSQL;
    end;

  qAction.Close;
  qAction1.Close;
  FreeAndNil(qAction);
  FreeAndNil(qAction1);
  FreeAndNil(dbsController);
end;

function TThreadController.CheckIfNotificationRequired(aRecordRef, aRecordType,
    aRecordStatus: string): Boolean;
begin
  Result := True;

  with qAction1 do
    begin
      Close;
      SQL.Clear;
      SQL.Add('SELECT RecordRef, Success, Status, Started from "' + resultsDbPath + 'GenerateResults"');
      SQL.Add('WHERE RecordRef = :RecordRef and Success = True');
      SQL.Add('ORDER BY Started');

      ParamByName('RecordRef').AsString := aRecordRef;
      Open;
      First;

      if FieldByName('RecordRef').AsString <> '' then
        begin
          while not Eof do
            begin
              if (aRecordType = 'CAR_FORM') then
                begin
                  //Checks if notification for Status = Completed was already sent. Will skip if true
                  if FieldByName('Status').AsString = 'Completed' then
                    begin
                      Result := False;
                      Break;
                    end
                  //Checks if In Progress notification was already sent. Will skip if true
                  else if FieldByName('Status').AsString = aRecordStatus then
                    Result := False;
                end
              else
                Result := False;

              Next;
            end;
        end;

      Close;
    end;
end;

function TThreadController.ConvertTablesFromDB3toDB4: Boolean;
var
  aResult: Pointer;
  aResultString: string;
begin
  Result := True;
  CopyFolder(blankTablesPath, tempPath);

  if not (CheckResult(ExportFormsToCSV(
                        AnsiString(mainDbPath),
                        AnsiString('insp_Forms'),
                        AnsiString(tempPath),
                        AnsiString('and (Type in (''Site Diary'', ''Diary'') or SourceRef = ''9CA23B711D8B4FE79E168BC1EB026249'')'),
                        AnsiString(selectRecordsOlderThanDays.ToString)
              ))) then
    begin
      InsertControllerError('Failed to export insp_Forms from DBISAM3 Table');
      Result := False;
      Exit;
    end
  else
    begin
      ImportCsvToDB4Table('insp_Forms');
    end;

  if not (CheckResult(ExportTableToCSV(
                AnsiString(mainDbPath),
                AnsiString('insp_ProjectTeam'),
                AnsiString(tempPath),
                AnsiString('')
              ))) then
    begin
      InsertControllerError('Failed to export insp_ProjectTeam from DBISAM3 Table');
      Result := False;
      Exit;
    end
  else
    begin
      ImportCsvToDB4Table('insp_ProjectTeam');
    end;

  if not (CheckResult(ExportTableToCSV(
                AnsiString(mainDbPath),
                AnsiString('Users'),
                AnsiString(tempPath),
                AnsiString('')
              ))) then
    begin
      InsertControllerError('Failed to export Users from DBISAM3 Table');
      Result := False;
      Exit;
    end
  else
    begin
      ImportCsvToDB4Table('Users');
    end;

  if not (CheckResult(ExportTableToCSV(
                AnsiString(mainDbPath),
                AnsiString('ProjectGroups'),
                AnsiString(tempPath),
                AnsiString('')
              ))) then
    begin
      InsertControllerError('Failed to export ProjectGroups from DBISAM3 Table');
      Result := False;
      Exit;
    end
  else
    begin
      ImportCsvToDB4Table('ProjectGroups');
    end;

  if not (CheckResult(ExportTableToCSV(
                AnsiString(mainDbPath),
                AnsiString('Projects'),
                AnsiString(tempPath),
                AnsiString('')
              ))) then
    begin
      InsertControllerError('Failed to export Projects from DBISAM3 Table');
      Result := False;
      Exit;
    end
  else
    begin
      ImportCsvToDB4Table('Projects');
    end;

  if not (CheckResult(ExportTableToCSV(
                AnsiString(mainDbPath),
                AnsiString('AllContacts'),
                AnsiString(tempPath),
                AnsiString('')
              ))) then
    begin
      InsertControllerError('Failed to export AllContacts from DBISAM3 Table');
      Result := False;
      Exit;
    end
  else
    begin
      ImportCsvToDB4Table('AllContacts');
    end;
end;

function TThreadController.CheckResult(aResult: Pointer): Boolean;
var
  aResultString: string;
begin
  if aResult <> nil then
    aResultString := string(PAnsiChar(aResult)); // Convert Pointer to ANSI string

  Result := aResultString = 'OK';
end;

function TThreadController.ImportCsvToDB4Table(aTable: string): Boolean;
var
  aResultString: string;
  aCSVFile: string;
begin
  Result := False;
  qAction.RequestLive := True;
  with qAction do
    begin
      Close;
      SQL.Clear;
      SQL.Add('SELECT * FROM "' + tempPath + aTable + '"');
      Open;

      aCSVFile := tempPath + aTable + '.csv';

      if FileExists(aCSVFile) then
        begin
          ImportTable(
            aCSVFile,
            ',',
            True
          );

          Result := True;
        end;
    end;
end;

procedure TThreadController.CopyFolder(const SourceDir, DestDir: string);
var
  SourceFiles: TStringDynArray;
  SourceFile, DestFile: string;
  SubDir: string;
begin
  try
    // Check if source directory exists
    if not TDirectory.Exists(SourceDir) then
      raise EDirectoryNotFoundException.Create('Source directory does not exist: ' + SourceDir);

    // Create destination directory if it doesn't exist
    TDirectory.CreateDirectory(DestDir);

    // Get all files in the source directory (non-recursive)
    SourceFiles := TDirectory.GetFiles(SourceDir);
    for SourceFile in SourceFiles do
    begin
      DestFile := TPath.Combine(DestDir, TPath.GetFileName(SourceFile));
      // Copy file with overwrite
      TFile.Copy(SourceFile, DestFile, True);
    end;

    // Recursively copy subdirectories
    for SubDir in TDirectory.GetDirectories(SourceDir) do
    begin
      CopyFolder(SubDir, TPath.Combine(DestDir, TPath.GetFileName(SubDir)));
    end;
  except
    on E: Exception do
    begin
      //ShowMessage('Error copying folder: ' + E.Message);
      raise;
    end;
  end;
end;



end.
