    $ScriptPath = Split-Path -parent $MyInvocation.MyCommand.Definition;
    $ScriptFile = $MyInvocation.MyCommand.Definition

    $statePath = Join-Path $ScriptPath "Syncro-Install.state"

    function Test-IsAdmin
    {
        $wid=[System.Security.Principal.WindowsIdentity]::GetCurrent()
        $prp=new-object System.Security.Principal.WindowsPrincipal($wid)
        $adm=[System.Security.Principal.WindowsBuiltInRole]::Administrator
        return $prp.IsInRole($adm)
    }
    
    function Save-State($state)
    {
        $body = ConvertTo-Json $state -Depth 10
        $output = New-Item -ItemType File -Force -Path $statePath -Value $body
    }
    
    function Get-State()
    {
        $state = Get-JsonFromFile $statePath
        
        if(!$state)
        {
            $state = @{
                IsSshSet = $false;
                IsGitWorkspacePathSet = $false;
                GitWorkspacePath = "C:\Git Workspace";
                IsRepositoriesCloned = $false;
            }
        }
        
        return $state
    }
    
    function Get-JsonFromFile([Parameter(Mandatory)][string]$storePath){
        if (-not (Test-Path $storePath))
        {
            $output = New-Item -ItemType File -Force -Path $storePath 
        }
        
        $content = Get-Content $storePath -Raw
        
        if(!$content){
            return
        }
        
        $results = ConvertFrom-Json $content 
        
        try{
            if($results -is [array] -and $results.Count -le 1)
            {
                return ,({$results}.Invoke())
            }
            else
            {
                return {$results}.Invoke()
            }
        }
        catch
        {
            Write-Error "Failed trying to invoke file $storePath"
            throw
        }
    }
    
    
    function Set-PageantStartup($keyFiles, $keysDirectory)
    {
        if(!$keysDirectory)
        {
            $sameDirectory = $(Read-Host "Are all your keys in the same directory[y/n]?").Trim()

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
        Write-Host
        Write-Host "*******************************************************************************"
        Write-Host "    Syncro Status: $status"
        Write-Host "*******************************************************************************"
        Write-Host
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
    
    $state = Get-State
    
    Syncro-Status "Beginning Syncro Agent Team development machine setup"
    
    if(-not(Test-IsAdmin))
    {
        Restart-ScriptInAdmin
    }
    
    if(-not(Get-Command "choco" -ErrorAction SilentlyContinue))
    {
        Syncro-Status "Installing Chocolatey and required git packages"

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

    if(!($state.IsSshSet))
    {
        Syncro-Status "Setting up SSH keys for git."

        # important! Ensure the user has set up their SSH keys

        Write-Host "*******************************************************************************"
        Write-Host "Important!  Now that git has been installed, please make sure you generate"
        Write-Host "your ssh keys and save them or you will not be able to fetch the repositories."
        Write-Host "*******************************************************************************"

        Write-Host
        do{
            Write-Host "Would you like to go through Pageant key setup (including startup and PATH)?"
            $setupPageant = (Read-Host "(If you would like to set up ssh manually, type [n]) [y/n]").Trim()
        } while(-not($setupPageant -match '^[yn]$'))
        
        if($setupPageant -ne "y")
        {
            Read-Host "Press enter after you have set up your ssh keys."
        }
        else{
            Set-PageantStartup
            $pageantLink = Join-Path ([Environment]::GetFolderPath('Startup')) "pageant.lnk"
            
            do{
                invoke-item $pageantLink
                Write-Host "Waiting for pageant to load.  If your key requires a passphrase, enter it when the prompt pops up."
                $ready = (Read-Host "Check your task tray for the icon and verify that your key is loaded. Did Pageant load properly?[y/n]").Trim()
            } while ($ready -ne 'y')
        }
        
        if($LASTEXITCODE)
        {
            Write-Host "An error occured setting up ssh.  Exiting, please inspect the console for details."
            exit
        }
        
        $state.IsSshSet = $true
        Save-State $state
    }
    
    # create git workspace
    if(!($state.IsGitWorkspacePathSet))
    {
        Syncro-Status "Setting up git workspace."

        Write-Host
        do{
            $useDefaultGitFolder = (Read-Host "Use the default workspace directory for git repositories? ($($state.GitWorkspacePath))? [y/n]").Trim()
        } while(-not ($useDefaultGitFolder -match '^[yn]$'))
        
        if($useDefaultGitFolder -eq "n")
        {
            do{
                $state.GitWorkspacePath = (Read-Host "Enter the default git workspace directory you would like to use").Trim()
                $isPathValid = Test-Path $state.GitWorkspacePath -IsValid
                
                if(!$isPathValid)
                {
                    Write-Host "Path: '$gitFolder' is not valid."
                }
            } while (!$isPathValid)
        }
        
        if (-not (Test-Path $state.GitWorkspacePath))
        {
            $output = New-Item -ItemType Directory -Force -Path $state.GitWorkspacePath
        }
                
        if($LASTEXITCODE)
        {
            Write-Host "An error occured setting up the git workspace.  Exiting, please inspect the console for details."
            exit
        }
        
        $state.IsGitWorkspacePathSet = $true
        Save-State $state
    }
    
    # clone the repositories
    if(!($state.IsRepositoriesCloned))
    {
        Syncro-Status "Fetching required repositories."

        cd $state.GitWorkspacePath
        plink.exe -agent -v git@github.com
        git clone --recurse-submodules git@github.com:SyncroSam/Scripts.git --progress
        git clone --recurse-submodules git@github.com:repairtech/kabuto-app.git --progress
        git clone --recurse-submodules git@github.com:repairtech/kabuto-live-windows.git --progress
        git clone --recurse-submodules git@github.com:repairtech/kabuto-live-client.git --progress        
        
        if($LASTEXITCODE -ne 0)
        {
            Write-Host "An error occured fetching main scripts git repository.  Exiting, please inspect the console for details."
            exit
        }
        
        $state.IsRepositoriesCloned = $true
        Save-State $state
    }
    
    # set up $profile
    if(!($state.IsProfileSetUp))
    {
        Syncro-Status "Setting up Powershell Profile."

        cd (Join-Path $state.GitWorkspacePath "Scripts")
        
        
        
#        . Install-DeveloperEnvironment.ps1
        
    }
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    


