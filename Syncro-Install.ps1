    $ScriptPath = Split-Path -parent $MyInvocation.MyCommand.Definition;
    $ScriptFile = $MyInvocation.MyCommand.Definition

    function Test-IsAdmin
    {
        $wid=[System.Security.Principal.WindowsIdentity]::GetCurrent()
        $prp=new-object System.Security.Principal.WindowsPrincipal($wid)
        $adm=[System.Security.Principal.WindowsBuiltInRole]::Administrator
        return $prp.IsInRole($adm)
    }
    
    function Set-PageantStartup($keyFiles, $keysDirectory)
    {
        if(!$keysDirectory)
        {
            Write-Host "Are all your keys in the same directory[y/n]?"
            $sameDirectory = $(Read-Host).Trim()

            if($sameDirectory.Trim() -eq "y")
            {
                Write-Host "Enter the path where your keys are stored:"
                $keysDirectory = $(Read-Host).Trim()
            }
        }
        
        if(!$keyFiles)
        {
            $keyFiles = @()

            Write-Host "Enter each key file path (or file name if using a shared directory):"
            $count = 1
            do{
                $path = $(Read-Host $count).Trim()

                $count = $count + 1
                if($path)
                {
                    $keyFiles += $path
                }
            } while ($path -ne "")
            
        }

        $pageant = Get-Command pageant
        $shortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) "pageant.lnk"  
        
        Set-Shortcut $pageant $shortcutPath $keysDirectory $keyFiles
        
        # now setup plink for git in console 
        $git_ssh = [System.Environment]::GetEnvironmentVariable("GIT_SSH")
        
        if(!$git_ssh)
        {
            $plink = Get-Command plink
            [Environment]::SetEnvironmentVariable("GIT_SSH", $plink.Source, "Machine")
        }
    }

    function New-PsSession([Parameter(Mandatory=$true)]$command, [switch]$admin)
    {
        $sb = @'
&{
    param([scriptblock]$command)

    Invoke-Command -ScriptBlock $command 4>&1
    
} -command { 
'@+$command+'}'

        if($admin)
        {
            Start-Process powershell -Verb RunAs -ArgumentList "-noexit -Command $sb"
        }
        else 
        {
            Start-Process powershell -ArgumentList "-noexit -Command $sb"
        }
    }
    
    function Restart-ScriptInAdmin
    {
        New-PsSession "& $ScriptFile" -admin        
        stop-process -Id $PID
    }
    
    function Syncro-Status ($status)
    {
        Write-Host "*******************************************************************************"
        Write-Host "                            Syncro Status"
        Write-Host "*******************************************************************************"
        Write-Host $status
        
    }
    
    function Set-Shortcut( [string]$SourceExe, [string]$DestinationPath, [string]$StartIn, $ArgumentList)
    {
        
        if( $ArgumentList -is [array])
        {
            $argumentsJoined = ""
            foreach ($argument in $ArgumentList)
            {
                $argumentsJoined += """$argument"" "
            }
            $ArgumentList = $argumentsJoined
        }
        
        $WshShell = New-Object -comObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut($DestinationPath)

        $Shortcut.TargetPath = $SourceExe
        $Shortcut.Arguments = $ArgumentList
        $Shortcut.WorkingDirectory = $StartIn
        
        $Shortcut.Save()
    }
    
    if(-not(Test-IsAdmin))
    {
        Restart-ScriptInAdmin
    }

    if(-not(Get-Command "choco" -ErrorAction SilentlyContinue))
    {
        # install chocolatey
        Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    }

    if (-not(Get-Command "git" -ErrorAction SilentlyContinue))
    {
        Syncro-Status "Checking for git"
        choco install git -y
    }
    if(-not(Get-Command "pageant" -ErrorAction SilentlyContinue))
    {
        Syncro-Status "Checking for pageant"
        choco install tortoisegit -y
    }

    if(-not(Get-Command "plink" -ErrorAction SilentlyContinue))
    {
        Syncro-Status "Checking for plink"
        choco install putty -y
    }

    #start a new admin powershell session
    if(-not(Get-Command "pageant" -ErrorAction SilentlyContinue) `
        -or -not(Get-Command "git" -ErrorAction SilentlyContinue) `
        -or -not(Get-Command "pageant" -ErrorAction SilentlyContinue) `
        -or -not(Get-Command "plink" -ErrorAction SilentlyContinue))
    {
        Syncro-Status "Powershell session needs to be restarted.  Closing this window, please rerun the install script."
        Write-Host "Press any key to continue."
        $k = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        stop-process -Id $PID
    }

    # important! Ensure the user has set up their SSH keys

    Write-Host "*******************************************************************************"
    Write-Host "Important!  Now that git has been installed, please make sure you generate"
    Write-Host "your ssh keys and save them or you will not be able to fetch the repositories."
    Write-Host "*******************************************************************************"

    Write-Host
    do{
        Write-Host "Would you like to go through Pageant key setup (including startup and PATH)?"
        $setupPageant = (Read-Host "(Type [n] if you would like to set up ssh manually) [y/n]").Trim()
    } while(-not ($setupPageant -match '^[yn]$'))
    
    if($setupPageant -ne "y")
    {
        Read-Host "Press enter after you have set up your ssh keys."
    }
    else{
        Set-PageantStartup
    }



