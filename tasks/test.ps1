[CmdletBinding()]
Param(
  [Parameter(Mandatory = $True)] [String] $kb,
  [Parameter(Mandatory = $True)] [String] $_installdir
)

#Write-Host $_installdir
#Get-ChildItem "$_installdir/windows_updates/files/"
if ($PSSenderInfo){
  # We are running in a WinRM session, can't install Windows Updates directly
  $User = [Security.Principal.WindowsIdentity]::GetCurrent()
  $Role = (New-Object Security.Principal.WindowsPrincipal $user).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
  if (!$Role){
    Write-Warning "To install updates, the account used to connect over WinRM must have administrative permissions."	
  }
  Write-Verbose "Running via WinRM: Creating scheduled task to install update $kb"
  [String]$TaskName = "PSWindowsUpdate"
  [ScriptBlock]$Script = {Import-Module -Name "$_installdir/windows_updates/files/PSWindowsUpdate"; [void](Install-WindowsUpdate -KBArticleID "$KB" -AcceptAll -IgnoreReboot)}

  $Scheduler = New-Object -ComObject Schedule.Service
  $Task = $Scheduler.NewTask(0)

  $RegistrationInfo = $Task.RegistrationInfo
  $RegistrationInfo.Description = $TaskName
  $RegistrationInfo.Author = $User.Name

  $Settings = $Task.Settings
  $Settings.Enabled = $True
  $Settings.StartWhenAvailable = $True
  $Settings.Hidden = $False

  $Action = $Task.Actions.Create(0)
  $Action.Path = "powershell"
  $Action.Arguments = "-Command $Script"
  
  $Task.Principal.RunLevel = 1

  $Scheduler.Connect('localhost')
  $RootFolder = $Scheduler.GetFolder("\")
  if ($Scheduler.GetRunningTasks(0) | Where-Object {$_.Name -eq $TaskName}) {
    Write-Error "A PSWindowsUpdate scheduled task is already running, aborting creation of new scheduled task to install $KB" -ErrorAction Stop
  }
  $RootFolder.RegisterTaskDefinition($TaskName, $Task, 6, "SYSTEM", $Null, 1) | Out-Null
  $RunningTask = $RootFolder.GetTask($TaskName).Run(0)
  
  $timeout = 14400 # seconds
  $timer =  [Diagnostics.Stopwatch]::StartNew()
  while (($RunningTask.State -ne 'Ready') -and ($timer.Elapsed.TotalSeconds -lt $timeout)) {    
    Write-Host -Message "Waiting on PSWindowsUpdate scheduled task to complete..."
    Start-Sleep -Seconds 120
    $RunningTask.Refresh()
  }
  $timer.Stop()
  if ($RunningTask.State -ne 'Ready') {
    Write-Error -Message "Timeout waiting for PSWindowsUpdate scheduled task to complete. The task will keep running in the background, please check it manually." -ErrorAction Stop
  }
  Write-Host -Message "Installation of $KB took $($timer.Elapsed.TotalSeconds) seconds"

}