object frmMain: TfrmMain
  Left = 0
  Top = 0
  Caption = 'frmMain'
  ClientHeight = 517
  ClientWidth = 518
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  OnCreate = FormCreate
  TextHeight = 15
  object lblNextRun: TLabel
    Left = 384
    Top = 176
    Width = 44
    Height = 15
    Caption = 'next run'
  end
  object btnRun: TButton
    Left = 392
    Top = 24
    Width = 75
    Height = 25
    Caption = 'Start'
    TabOrder = 0
    OnClick = btnRunClick
  end
  object btnTerminate: TButton
    Left = 392
    Top = 72
    Width = 75
    Height = 25
    Caption = 'Terminate'
    TabOrder = 1
    OnClick = btnTerminateClick
  end
  object mmoResult: TMemo
    Left = 8
    Top = 8
    Width = 345
    Height = 505
    Lines.Strings = (
      'mmoResult')
    ScrollBars = ssVertical
    TabOrder = 2
  end
  object btnNextTime: TButton
    Left = 392
    Top = 128
    Width = 75
    Height = 25
    Caption = 'Next Run'
    TabOrder = 3
    OnClick = btnNextTimeClick
  end
  object tmrRun: TTimer
    Enabled = False
    Interval = 60000
    OnTimer = tmrRunTimer
    Left = 416
    Top = 336
  end
end
