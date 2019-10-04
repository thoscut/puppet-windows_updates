[CmdletBinding()]
Param(
    [Parameter(Mandatory = $True)] [String]  $kb,
    [Parameter(Mandatory = $True)] [Boolean] $restart,
    [Parameter(Mandatory = $True)] [String]  $_installdir
)

$ProgressPreference = 'SilentlyContinue'
$ErrCodesFile = "$_installdir/windows_updates/lib/windows_updates/errorcodes.txt"
$all_error_codes = Get-Content -raw -Path $ErrCodesFile | ConvertFrom-StringData

Import-Module -Name "$_installdir/windows_updates/files/PSWindowsUpdate"
if (Get-WindowsUpdate -KBArticleID "$KB") {
    Write-Host "Update $KB is available on the update server, proceeding with installation..."
} Else {
    Write-Host "Update $KB is not provided by the update server!"; Exit 5
}

if ($PSSenderInfo){
    # We are running in a WinRM session, can't install Windows Updates directly
    $User = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Role = (New-Object Security.Principal.WindowsPrincipal $user).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    if (!$Role){
        Write-Host "To install updates, the account used to connect over WinRM must have administrative permissions."; Exit 1
    }
    Write-Host "Running via WinRM: Creating scheduled task to install update $kb"
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
        Write-Host "A PSWindowsUpdate scheduled task is already running, aborting creation of new scheduled task to install $KB"; Exit 1
    }
    $RootFolder.RegisterTaskDefinition($TaskName, $Task, 6, "SYSTEM", $Null, 1) | Out-Null
    $RunningTask = $RootFolder.GetTask($TaskName).Run(0)
    
    $timeout = 14400 # seconds
    $timer =  [Diagnostics.Stopwatch]::StartNew()
    while (($RunningTask.State -ne 3) -and ($timer.Elapsed.TotalSeconds -lt $timeout)) {    
        Write-Host "Waiting on PSWindowsUpdate scheduled task to complete..."
        Start-Sleep -Seconds 120
        $RunningTask.Refresh()
    }
    $timer.Stop()
    if ($RunningTask.State -eq 3) {
        Write-Host "Installation of $KB took $($timer.Elapsed.TotalSeconds) seconds"
    } Else {
        Write-Host "Timeout waiting for PSWindowsUpdate scheduled task to complete. The task will keep running in the background, please check it manually."; Exit 0
    }

} Else {
    # Not running in a WinRM session, we can install Windows Updates directly
    [void](Install-WindowsUpdate -KBArticleID "$KB" -AcceptAll -IgnoreReboot)
    Start-Sleep 10
}

$update = Get-WUHistory | Where-Object KB -eq $KB | Sort-Object Date -Descending | Select-Object -First 1
switch -regex ($update.Result) {
    'Succeeded' {
        Set-Content "C:\ProgramData\InstalledUpdates\$KB.flg" "Installed"
        if ($restart) {
            Write-Host "Restart parameter enabled, restarting node in 30 seconds"
            & shutdown -r -t 30
        }
    }
    'SucceededWithErrors|InProgress' {
        $HResult = [Convert]::ToString($update.HResult, 16)
        $Message = $all_error_codes["0x$HResult"]
        Write-Host "Update $KB was installed but reported (likely reboot needed): $Message"
        Set-Content "C:\ProgramData\InstalledUpdates\$KB.flg" "Installed"
        if ($restart) {
            Write-Host "Restart parameter enabled, restarting node in 30 seconds"
            & shutdown -r -t 30
        }
    }
    'Failed' {
        $HResult = [Convert]::ToString($update.HResult, 16)
        $Message = $all_error_codes["0x$HResult"]
        Write-Host "Update $KB failed to install, reporting: $Message"
        Exit 2
    }
    default { Write-Host "Could not find update $KB in the Windows Update History, it seems installation has not succeeded!"; Exit 5 }
}
