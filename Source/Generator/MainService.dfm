object srvMain: TsrvMain
  OnCreate = ServiceCreate
  DisplayName = 'srvMain'
  OnStart = ServiceStart
  Height = 545
  Width = 654
  object tmrRun: TTimer
    Enabled = False
    Interval = 60000
    OnTimer = tmrRunTimer
    Left = 400
    Top = 248
  end
end
