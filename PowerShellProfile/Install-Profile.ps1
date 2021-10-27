$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition

if (!(test-path $profile)) 
{
    New-Item -path $profile -type file -force
}

if(!(Find-TextInFiles -fullPath $profile -textToFind ". (Resolve-Path '$ScriptPath\Microsoft.PowerShell_profile.ps1')" -first))
{
    Add-Content $profile ". (Resolve-Path '$ScriptPath\Microsoft.PowerShell_profile.ps1')"
}