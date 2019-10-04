[CmdletBinding()]
Param(
  [Parameter(Mandatory = $True)] [String] $kb,
  [Parameter(Mandatory = $True)] [String] $_installdir
)

#Write-Host $_installdir
#Get-ChildItem "$_installdir/windows_updates/files/"
Import-Module -Name "$_installdir/windows_updates/files/PSWindowsUpdate"
Get-WindowsUpdate