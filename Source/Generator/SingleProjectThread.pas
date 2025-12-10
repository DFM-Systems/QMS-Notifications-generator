unit SingleProjectThread;

interface

uses
  System.SysUtils, System.Variants, System.Classes, System.IniFiles, Data.DB,
  dbisamtb, System.DateUtils, System.StrUtils, Winapi.Windows, Vcl.SvcMgr, IdURI;

type
  TSingleProjectThread = class(TThread)

private
  _threadTimeOutSeconds: Integer;
  _processAttempts: Integer;
  _mailFilesCreated: Integer;
  _exceptionMessage,
  _completedStats: string;
  _transactionKey,
  _debugEmail,
  _mainDbPath,
  _appBasePath,
  _outputPath,
  _outputTable,
  _projectDbPath,
  _projectKey,
  _pdfOutputPath,
  _fullPdfOutputPath,
  _fullLinkToPDF,
  _projectFilesRootPath,
  _emailsFolderPath,
  _recordKey,
  _recordCode,
  _recordType,
  _projectType,
  _projectNo,
  _projectName,
  _siteURL,
  _messageTemplate,
  _ownerLogoPath,
  _secondaryEmail: string;
  _projectUseFirstGateKeeper,
  _projectRequireAcceptance: Boolean;
  _started: TDateTime;
  _finished: TDateTime;
  _timeOutCheck: TDateTime;
  _includeAttachmentforAllMails: Boolean;
  _includeAttachmentforSecondaryEmail: Boolean;
  _failed: Boolean;
  _done: Boolean;

  function BuildEmailBody(aFileName, aProjectNo, aProjectName, aFormCode,
      aFormCaption, aFormType, aFullLinkToPDF, aNotifyName: string;
      aDateCommenced: TDateTime): string;
  function CheckIfDone: Boolean;
  function GenerateFormPDF: Boolean;
  function ExtractFirstname(aFullName: string): string;
  function GetGUID32: string;
  function GetProcessTime: Integer;
  procedure BuildEmailsMessages;
  function GetFileSize(const FileName: string): Int64;
  function InsertToMailTable(aUserRef, aFullName, aEmail, aSubject,
      aBodyFileName: string; includeAttachment: Boolean): Boolean;
  procedure UpdateTimeoutDate;
public
  resultString: string;
  dbsSingleProjec: TDBISAMSession;
  qAction: TDBISAMQuery;
  qAction1: TDBISAMQuery;
  property RecordKey: string read _recordKey;
  property StartedOn: TDateTime read _started;
  property FinishedOn: TDateTime read _finished;
  property ProcessTime: Integer read GetProcessTime;
  property ExceptionMessage: string read _exceptionMessage;
  property CompletedStats: string read _completedStats;
  property ProcessAttempts: Integer read _processAttempts;
  property MailFilesCreated: Integer read _mailFilesCreated;
  property FullPdfOutputPath: string read _fullPdfOutputPath;
  property Failed: Boolean read _failed;
  property IsDone: Boolean read CheckIfDone;
  constructor Create(aMessageTemplate, aMessageFileStorePath, aDebugEmail, aKey,
      aProjectKey, aCode, aType, aDBPath, pdfOutputPath, aTransaction,
      anAppBasePath, aMainDb, aSiteURL, ownerLogoPath, secondaryEmail: string;
      aStarted: TDateTime; aThreadTimeOutSeconds: Integer;
      aIncludeAttachmentforAllMails, aIncludeAttachmentforSecondaryEmail:
      Boolean); overload;
protected
  procedure Execute; override;
  procedure BeforeDestruction; override;
end;

implementation

  //uses MainForm;

constructor TSingleProjectThread.Create(aMessageTemplate,
    aMessageFileStorePath, aDebugEmail, aKey, aProjectKey, aCode, aType,
    aDBPath, pdfOutputPath, aTransaction, anAppBasePath, aMainDb, aSiteURL,
    ownerLogoPath, secondaryEmail: string; aStarted: TDateTime;
    aThreadTimeOutSeconds: Integer; aIncludeAttachmentforAllMails,
    aIncludeAttachmentforSecondaryEmail: Boolean);
begin
  Create;
  _failed := False;
  _done := False;
  _mailFilesCreated := 0;
  _processAttempts := 1;
  _messageTemplate := aMessageTemplate;
  _debugEmail := aDebugEmail;
  _recordKey := aKey;
  _projectKey := aProjectKey;
  _recordCode := aCode;
  _recordType := aType;
  _projectDbPath := aDBPath; //DBISAM4 database (tables converted from DB3 to DB4, required to generate emails)
  _pdfOutputPath := pdfOutputPath;
  _emailsFolderPath := aMessageFileStorePath;

  _transactionKey := aTransaction;
  _started := aStarted;
  _appBasePath := anAppBasePath;
  _outputPath := anAppBasePath + 'Results\';
  _outputTable := _outputPath + 'docOnlineActionLog_' + _recordKey;
  _mainDbPath := aMainDb;  //DBISAM3 Database (original QMS database used to generate PDFs)
  _siteURL := aSiteURL;
  _ownerLogoPath := ownerLogoPath;
  _secondaryEmail := secondaryEmail;
  _includeAttachmentforAllMails := aIncludeAttachmentforAllMails;
  _includeAttachmentforSecondaryEmail := aIncludeAttachmentforSecondaryEmail;

  _threadTimeOutSeconds := aThreadTimeOutSeconds;
  UpdateTimeoutDate;
end;

procedure TSingleProjectThread.Execute;
begin
  inherited;

  dbsSingleProjec := TDBISAMSession.Create(nil);
  dbsSingleProjec.PrivateDir := _appBasePath + 'Temp';
  qAction := TDBISAMQuery.Create(nil);
  qAction1 := TDBISAMQuery.Create(nil);
  dbsSingleProjec.SessionName := 'SingleTread_' + GetGUID32;
  qAction.SessionName := dbsSingleProjec.SessionName;
  qAction1.SessionName := dbsSingleProjec.SessionName;

  try
    if GenerateFormPDF then
      begin
        BuildEmailsMessages;
        _done := True;
        _finished := Now;
        resultString := 'T.ID: ' + Self.ThreadID.ToString + ' ' + _recordKey;
      end
    else
      begin
        _failed := True;
        _done := True;
        resultString := 'Failed - T.ID: ' + Self.ThreadID.ToString + ' ' +  _recordKey;
      end;
  except
    on e : Exception do
      begin
        _failed := True;
        _done := True;
        _exceptionMessage := 'Error on ' + _processAttempts.ToString + ' attempt: ' + E.Message;
        resultString := 'Failed - T.ID: ' + Self.ThreadID.ToString + ' ' +  _projectName;
      end;
  end;
end;

function TSingleProjectThread.GetGUID32: string;
var
  aGuid: TGUID;
  aGuid32: string;
begin
  System.SysUtils.CreateGUID(aGuid);
  aGuid32 := GUIDToString(aGuid);
  aGuid32 := StringReplace(aGuid32, '-', '', [rfReplaceAll]);
  aGuid32 := StringReplace(aGuid32, '{', '', [rfReplaceAll]);
  aGuid32 := StringReplace(aGuid32, '}', '', [rfReplaceAll]);
  Result := aGuid32;
end;

procedure TSingleProjectThread.BeforeDestruction;
var
  i: Integer;
begin
  inherited;
  qAction.Close;
  qAction1.Close;
  FreeAndNil(qAction);
  FreeAndNil(qAction1);
  FreeAndNil(dbsSingleProjec);
end;


function TSingleProjectThread.GetProcessTime: Integer;
begin
  Result := SecondsBetween(_finished, _started);
end;


function TSingleProjectThread.CheckIfDone: Boolean;
begin
  Result := False;

  if _done then
    begin
      Result := True;
    end
  else if SecondsBetween(Now, _timeOutCheck) > _threadTimeOutSeconds then
    begin
      _failed := True;

      _exceptionMessage := 'Thread timeout: Started on ' +
        FormatDateTime('yyyy-mm-dd HH:nn:ss', _started) +
        ' Terminates on: ' + FormatDateTime('yyyy-mm-dd HH:nn:ss', Now);

       Result := True;
    end;
end;

procedure TSingleProjectThread.UpdateTimeoutDate;
begin
  _timeOutCheck := Now;
end;


function TSingleProjectThread.GenerateFormPDF: Boolean;
var
  StartupInfo: TStartupInfo;
  ProcessInfo: TProcessInformation;
  CmdLine: string;
  ExitCode: DWORD;
  fs: TFormatSettings;
  startTime: TDateTime;
  outpurFolder, subFolder: string;
  fileName: string;
begin
  try
    Result := False;
    startTime := Now;

    // Prepare command line
    subFolder := _projectKey + '\OBS\' + _recordKey + FloatToStr(Now) + '\';
    outpurFolder := _pdfOutputPath + subFolder;
    fileName := _recordCode + ' ' + _recordType + ' ' + FormatDateTime('dd-mm-yyyy HH_nn_ss', Now) + '.pdf';

    if ForceDirectories(outpurFolder) then
      begin
        _fullPdfOutputPath := outpurFolder + fileName;
        _fullLinkToPDF := TIdURI.URLEncode(_siteURL + subFolder + fileName);
      end
    else
      begin
        raise Exception.Create('Cant create output forlder: ' + outpurFolder);
      end;

    CmdLine := Format('"%s" "%s" "%s" "%s"', [_appBasePath + '\Modules\ExportFormToPDF.exe',
                                               _recordKey,
                                               _mainDbPath,
                                               _fullPdfOutputPath]);

    // Initialize StartupInfo
    FillChar(StartupInfo, SizeOf(StartupInfo), 0);
    StartupInfo.cb := SizeOf(StartupInfo);
    StartupInfo.dwFlags := STARTF_USESHOWWINDOW; // Use wShowWindow setting
    StartupInfo.wShowWindow := SW_HIDE; // Hide the window


    if CreateProcess(nil, PChar(CmdLine), nil, nil, False, 0, nil, nil, StartupInfo, ProcessInfo) then
    try
      WaitForSingleObject(ProcessInfo.hProcess, INFINITE);
      GetExitCodeProcess(ProcessInfo.hProcess, ExitCode);

      if (ExitCode = 0) or (ExitCode = 216) then
        begin
          if FileExists(_fullPdfOutputPath) then
            begin
              _completedStats := 'PDF generated successfully in ' + System.DateUtils.SecondsBetween(startTime, Now).ToString + 's';
              Result := True;
            end
          else
            begin
              _completedStats := 'PDF generation failed, file was not created';
            end;
        end
      else
        _completedStats := 'PDF generation failed, exit code: ' + IntToStr(ExitCode);

    finally
      CloseHandle(ProcessInfo.hProcess);
      CloseHandle(ProcessInfo.hThread);
    end
    else
      _completedStats := 'Failed to start PDFGenerator.exe: ' + SysErrorMessage(GetLastError);

  except
    on E: Exception do
      begin
        raise Exception.Create('Generate PDF Error: ' + #10#13 + E.Message);
      end;
  end;
end;


procedure TSingleProjectThread.BuildEmailsMessages;
var
  aMemo: TStringList;
  i, aUserRecordCount: Integer;
  templatePath, aBody: string;
  aEmailInserted: Boolean;
  aFullName, aEmail,  aUserRef, aRef: string;
  aUpdateKeys: string;
  aBodyFileName, aEmailsTable: string;
  aProjectRef, aFormCode, aFormType, aFormCaption, aNotify,
  aProjectName, aProjectNo: string;
  aFormDate: TDateTime;
  secondaryEmailNotifyNameText, notifyNameText, companyName: string;
begin
  aUserRecordCount := 0;
  try
    if ForceDirectories(_emailsFolderPath) then
      begin
        aEmailsTable := 'Memory/memEmails_' + GetGUID32;

        with qAction do
          begin
            Close;
            SQL.Clear;
            SQL.Add('SELECT F.*, P.Name, P.ProjectNo FROM "'+_projectDbPath+'insp_Forms" F');
            SQL.Add('LEFT OUTER JOIN "'+_projectDbPath+'Projects" P on P.Key = F.ProjectRef');
            SQL.Add('WHERE Key = :Key');
            ParamByName('Key').AsString := _recordKey;
            Open;

            aProjectRef := FieldByName('ProjectRef').AsString;
            aFormCode := FieldByName('Code').AsString;
            aFormCaption := FieldByName('Caption').AsString;
            aFormType := FieldByName('Type').AsString;
            aFormDate := FieldByName('Date').AsDateTime;
            aNotify := FieldByName('Notify').AsString;
            aProjectNo := FieldByName('ProjectNo').AsString;
            aProjectName := FieldByName('Name').AsString;

            if aFormType.ToUpper = 'DIARY' then
              aFormType := 'Site Observation';

            Close;
            SQL.Clear;
            SQL.Add('SELECT Key, Ref, UserRef, CompanyRef, Contact, CompanyEmail, CompanyName FROM "'+_projectDbPath+'insp_ProjectTeam"');
            SQL.Add('WHERE Ref = :Ref and ProjectRef = :ProjectRef and Deleted <> True and Notifications = True');
            ParamByName('Ref').AsString := aNotify;
            ParamByName('ProjectRef').AsString := aProjectRef;
            Open;

            if RecordCount > 0 then
              begin
                if FieldByName('UserRef').AsString <> '' then
                  begin
                    companyName := FieldByName('CompanyName').AsString;
                    //Get Single User Details
                    Close;
                    SQL.Clear;
                    SQL.Add('SELECT Key, FullName, Email FROM "'+_projectDbPath+'Users"');
                    SQL.Add('WHERE Key = :Key and Deleted <> True and Active = True');
                    ParamByName('Key').AsString := aNotify;
                    Open;

                    if (FieldByName('Key').AsString <> '') and (FieldByName('Email').AsString <> '') then
                      begin
                        aBodyFileName := BuildEmailBody(
                          aNotify + '_' + FormatDateTime('yyyy-mm-dd HH_nn_ss', Now) + '.html',  //file name
                          aProjectNo,
                          aProjectName,
                          aFormCode,
                          aFormCaption,
                          aFormType,
                          _fullLinkToPDF,
                          companyName + ' (' +FieldByName('FullName').AsString+ ')',
                          aFormDate
                        );

                        aEmailInserted := InsertToMailTable(
                          FieldByName('Key').AsString,
                          FieldByName('FullName').AsString,
                          FieldByName('Email').AsString,
                          '(' + aFormCode + ') ' + aProjectNo + ' - ' + aProjectName + ' ' + aFormCaption,  //subject
                          aBodyFileName,
                          _includeAttachmentforAllMails
                        );

                        secondaryEmailNotifyNameText := companyName + ' (' +FieldByName('FullName').AsString+ ')';
                      end;
                  end
                else if FieldByName('CompanyRef').AsString <> '' then
                  begin
                    //Get Contact Details
                    if FieldByName('CompanyRef').AsString = FieldByName('Key').AsString then
                      begin
                        if FieldByName('CompanyEmail').AsString <> '' then
                          begin
                            if FieldByName('Contact').AsString <> '' then
                              notifyNameText := FieldByName('Contact').AsString
                            else
                              notifyNameText := FieldByName('CompanyEmail').AsString;

                            aBodyFileName := BuildEmailBody(
                              aNotify + '_' + FormatDateTime('yyyy-mm-dd HH_nn_ss', Now) + '.html',  //file name
                              aProjectNo,
                              aProjectName,
                              aFormCode,
                              aFormCaption,
                              aFormType,
                              _fullLinkToPDF,
                              FieldByName('CompanyName').AsString + ' (' +notifyNameText+ ')',
                              aFormDate
                            );

                            aEmailInserted := InsertToMailTable(
                              FieldByName('Key').AsString,
                              FieldByName('Contact').AsString,
                              FieldByName('CompanyEmail').AsString,
                              '(' + aFormCode + ') ' + aProjectNo + ' - ' + aProjectName + ' ' + aFormCaption,  //subject
                              aBodyFileName,
                              _includeAttachmentforAllMails
                            );

                            secondaryEmailNotifyNameText := FieldByName('CompanyName').AsString + ' (' +notifyNameText+ ')';
                          end;
                      end
                    else
                      begin
                        Close;
                        SQL.Clear;
                        SQL.Add('SELECT Key, Name, Contact, Email FROM "'+_projectDbPath+'AllContacts"');
                        SQL.Add('WHERE Key = :Key and Deleted <> True');
                        ParamByName('Key').AsString := aNotify;
                        Open;

                        if (FieldByName('Key').AsString <> '') and (FieldByName('Email').AsString <> '') then
                          begin
                            aBodyFileName := BuildEmailBody(
                              aNotify + '_' + FormatDateTime('yyyy-mm-dd HH_nn_ss', Now) + '.html',  //file name
                              aProjectNo,
                              aProjectName,
                              aFormCode,
                              aFormCaption,
                              aFormType,
                              _fullLinkToPDF,
                              FieldByName('Name').AsString + ' (' +FieldByName('Contact').AsString+ ')',
                              aFormDate
                            );

                            aEmailInserted := InsertToMailTable(
                              FieldByName('Key').AsString,
                              FieldByName('Name').AsString,
                              FieldByName('Email').AsString,
                              '(' + aFormCode + ') ' + aProjectNo + ' - ' + aProjectName + ' ' + aFormCaption,  //subject
                              aBodyFileName,
                              _includeAttachmentforAllMails
                            );

                            secondaryEmailNotifyNameText := FieldByName('Name').AsString + ' (' +FieldByName('Contact').AsString+ ')';
                          end;
                      end;
                  end
                else
                  begin
                    secondaryEmailNotifyNameText := FieldByName('CompanyName').AsString;

                    //Get Details for Group of Users (If UserRef and CompanyRef is empty, then it is a Group)
                    Close;
                    SQL.Clear;
                    //SQL.Add('SELECT G.UserRef, U.FullName, U.Email FROM "'+_projectDbPath+'ProjectGroups" G');

                    SQL.Add('SELECT G.UserRef, IF(U.FullName <> null then U.FullName else IF(PT.Contact <> null then PT.Contact else AR.Contact)) as FullName,');
                    SQL.Add('IF(U.Email <> null then U.Email else IF(PT.CompanyEmail <> null then PT.CompanyEmail else AR.Email)) as Email FROM "'+_projectDbPath+'ProjectGroups" G');

                    SQL.Add('LEFT OUTER JOIN "'+_projectDbPath+'Users" U on U.Key = G.UserRef AND U.Deleted <> True AND U.Active = True ');
                    SQL.Add('LEFT OUTER JOIN "'+_projectDbPath+'insp_ProjectTeam" PT on PT.Key = G.UserRef AND PT.Deleted <> True');
                    SQL.Add('LEFT OUTER JOIN "'+_projectDbPath+'AllContacts" AR on AR.Key = G.UserRef AND AR.Deleted <> True');

                    SQL.Add('WHERE G.GroupRef = :GroupRef AND G.ProjectRef = :ProjectRef AND G.Deleted <> True');
//                    SQL.Add('AND (U.Deleted <> True and U.Active = True)');
                    ParamByName('GroupRef').AsString := aNotify;
                    ParamByName('ProjectRef').AsString := aProjectRef;
                    Open;
                    First;

                    while not Eof do
                      begin
                        UpdateTimeoutDate;

                        if FieldByName('Email').AsString <> '' then
                          begin
                            aBodyFileName := BuildEmailBody(
                              FieldByName('UserRef').AsString + '_' + FormatDateTime('yyyy-mm-dd HH_nn_ss', Now) + '.html',  //file name
                              aProjectNo,
                              aProjectName,
                              aFormCode,
                              aFormCaption,
                              aFormType,
                              _fullLinkToPDF,
                              secondaryEmailNotifyNameText + ' (' +FieldByName('FullName').AsString+ ')',
                              aFormDate
                            );

                            aEmailInserted := InsertToMailTable(
                              FieldByName('UserRef').AsString,
                              FieldByName('FullName').AsString,
                              FieldByName('Email').AsString,
                              '(' + aFormCode + ') ' + aProjectNo + ' - ' + aProjectName + ' ' + aFormCaption,  //subject
                              aBodyFileName,
                              _includeAttachmentforAllMails
                            );
                          end;

                        Next;
                      end;
                  end;

                //additional email will be sent about any generated notification
                if (_secondaryEmail <> '') and (_recordType <> 'Diary') then
                  begin
                    aBodyFileName := BuildEmailBody(
                      'additionalEmail_' + FormatDateTime('yyyy-mm-dd HH_nn_ss', Now) + '.html',  //file name
                      aProjectNo,
                      aProjectName,
                      aFormCode,
                      aFormCaption,
                      aFormType,
                      _fullLinkToPDF,
                      'Secondary Email - ' + secondaryEmailNotifyNameText,
                      aFormDate
                    );

                    aEmailInserted := InsertToMailTable(
                      'secondaryEmail',
                      _secondaryEmail,
                      _secondaryEmail,
                      '(' + aFormCode + ') ' + aProjectNo + ' - ' + aProjectName + ' ' + aFormCaption,  //subject
                      aBodyFileName,
                      _includeAttachmentforSecondaryEmail
                    );
                  end;

                _completedStats := _completedStats + '  Mail files created: ' + _mailFilesCreated.ToString;
              end
            else
              _completedStats := _completedStats + '  Mail files created: 0';
          end;
      end;
  except
    on E: Exception do
      begin
        raise Exception.Create('Create email files Error: ' + E.ClassName + #10#13 + E.Message);
      end;
  end;
end;

function TSingleProjectThread.BuildEmailBody(aFileName, aProjectNo,
    aProjectName, aFormCode, aFormCaption, aFormType, aFullLinkToPDF,
    aNotifyName: string; aDateCommenced: TDateTime): string;
var
  aHTMLTemplate : string;
  aPlainTextTemplate : string;
  aMemo : TStringList;
  outputEmailFile: string;
  subFolder: string;
begin
  aMemo := TStringList.Create;
  try
    subFolder := _emailsFolderPath + _projectKey + '\' + _recordKey + '\';

    if not ForceDirectories(subFolder) then
      raise Exception.Create('Failed to create message folder');

    outputEmailFile := subFolder + aFileName;
    aMemo.Text := _messageTemplate;
    aMemo.Text := StringReplace(aMemo.Text, '&lt;IMG&gt;', _ownerLogoPath, [rfReplaceAll, rfIgnoreCase]);
    aMemo.Text := StringReplace(aMemo.Text, '&lt;PROJECTNAME&gt;', aProjectNo + ' - ' + aProjectName, [rfReplaceAll, rfIgnoreCase]);
    aMemo.Text := StringReplace(aMemo.Text, '&lt;OBS&gt;', aFormCode + ' - ' + aFormCaption, [rfReplaceAll, rfIgnoreCase]);
    aMemo.Text := StringReplace(aMemo.Text, '&lt;LINK&gt;', aFullLinkToPDF, [rfReplaceAll, rfIgnoreCase]);
    aMemo.Text := StringReplace(aMemo.Text, '&lt;NOTIFY&gt;', aNotifyName, [rfReplaceAll, rfIgnoreCase]);
    aMemo.Text := StringReplace(aMemo.Text, '&lt;TEXTCOLOR&gt;', 'white', [rfReplaceAll, rfIgnoreCase]);
    aMemo.Text := StringReplace(aMemo.Text, '&lt;BUTTONCOLOR&gt;', '#5c6d89', [rfReplaceAll, rfIgnoreCase]);
    aMemo.Text := StringReplace(aMemo.Text, '&lt;FORMTYPE&gt;', aFormType, [rfReplaceAll, rfIgnoreCase]);
    aMemo.Text := StringReplace(aMemo.Text, '&lt;Date Commenced:&gt;', 'Date Commenced: ' + FormatDateTime('dd/mm/yyyy', aDateCommenced) , [rfReplaceAll, rfIgnoreCase]);


    aMemo.SaveToFile(outputEmailFile);

    if FileExists(outputEmailFile) then
      Result := outputEmailFile;

  finally
    aMemo.Free;
  end;
end;

function TSingleProjectThread.InsertToMailTable(aUserRef, aFullName, aEmail,
    aSubject, aBodyFileName: string; includeAttachment: Boolean): Boolean;
var
  aKey: string;
  MAX_FILE_SIZE: Int64;
begin
  try
    if aBodyFileName = '' then
      raise Exception.Create('Failed to create message file');

    Inc(_mailFilesCreated);
    aKey := GetGUID32;

    if _debugEmail <> '' then
      aEmail := _debugEmail;

    with qAction1 do
      begin
        Close;
        SQL.Clear;
        SQL.Add('INSERT INTO "'+_mainDbPath+'NotificationLog" (Key, UserRef, UserContact, UserEmail, Type, EmailTitle, TransactionRef, RecordRef)');
        SQL.Add('VALUES (:Key, :UserRef, :UserContact, :UserEmail, :Type, :EmailTitle, :TransactionRef, :RecordRef)');
        ParamByName('Key').AsString := aKey;
        ParamByName('UserRef').AsString := aUserRef;
        ParamByName('UserContact').AsString := aFullName;
        ParamByName('UserEmail').AsString := aEmail;
        ParamByName('Type').AsString := 'QMS';
        ParamByName('EmailTitle').AsString := aSubject;
        ParamByName('TransactionRef').AsString := _transactionKey;
        ParamByName('RecordRef').AsString := _recordKey;
        ExecSQL;

        SQL.Clear;
        SQL.Add('INSERT INTO "'+_mainDbPath+'NotificationAttachments" (Key, MailRef, FilePath, Type)');
        SQL.Add('VALUES (:Key, :MailRef, :FilePath, :Type)');
        ParamByName('Key').AsString := GetGUID32;
        ParamByName('MailRef').AsString := aKey;
        ParamByName('FilePath').AsString := aBodyFileName;
        ParamByName('Type').AsString := 'BODY';
        ExecSQL;

        if includeAttachment then
          begin
            MAX_FILE_SIZE := 25 * 1024 * 1024;

            if GetFileSize(_fullPdfOutputPath) < MAX_FILE_SIZE then
              begin
                SQL.Clear;
                SQL.Add('INSERT INTO "'+_mainDbPath+'NotificationAttachments" (Key, MailRef, FilePath, Type)');
                SQL.Add('VALUES (:Key, :MailRef, :FilePath, :Type)');
                ParamByName('Key').AsString := GetGUID32;
                ParamByName('MailRef').AsString := aKey;
                ParamByName('FilePath').AsString := _fullPdfOutputPath;
                ParamByName('Type').AsString := 'ATTACHMENT';
                ExecSQL;
              end;
          end;

        Close;
      end;
  except
    on E: Exception do
      begin
        raise Exception.Create('InsertToMailTable Error: ' + E.ClassName + #10#13 + E.Message);
      end;
  end;
end;

function TSingleProjectThread.ExtractFirstname(aFullName: string): string;
begin
  if aFullName <> '' then
    begin
      Result := Trim(Copy(aFullName, 1, Pos(' ', aFullName)));

      if Result = '' then
        Result := aFullName;
    end;
end;

function TSingleProjectThread.GetFileSize(const FileName: string): Int64;
var
  SearchRec: TSearchRec;
begin
  if FindFirst(FileName, faAnyFile, SearchRec) = 0 then
    Result := Int64(SearchRec.Size)
  else
    Result := -1; // Error if file not found
end;

end.