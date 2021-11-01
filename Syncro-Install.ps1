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
                IsRemainingInstallsComplete = $false;
                IsProfileSetUp = $false;
                IsOldDevPacksInstalled = $false;
                IsDotNet35Enabled = $false;
                IsWixInstalled = $false;
                IsNugetConfigured = $false;
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
    
    function Kill-Powershell{
        Syncro-Status "Powershell session needs to be restarted.  Closing this window, please rerun the install script."
        Write-Host "Press any key to continue."
        $k = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
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
    
    function Write-ProgressHelper (
	    [int]$stepNumber,
	    [string]$message
	)
    {
        Write-Progress -Id 1 -Activity 'Setting up Developer Environment' -Status "$Message - Step $stepNumber of $steps" -PercentComplete (($stepNumber / $steps) * 100)
    }
    
    function Write-GitRepositoryProgress(
	    [int]$stepNumber,
	    [string]$message
	)
    {
        Write-Progress -ParentId 1 -Id 2 -Activity 'Cloning Git repositories' -Status $Message -PercentComplete (($stepNumber / $gitSteps) * 100)
    }
    
    function Download-AndExtractZip($url, $destinationFolder)
    {
        $zipFile = Download-File $url
        $extractedFolderName = [io.path]::GetFileNameWithoutExtension($zipFile)
        $destination = Join-Path $destinationFolder $extractedFolderName
         
        $extractShell = New-Object -ComObject Shell.Application 
        $files = $extractShell.Namespace($zipFile).Items() 
        $extractShell.NameSpace($destination).CopyHere($files) 
    }

    function Download-File($url)
    {
        $downloadFolder = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path
        $filePath = Join-Path $downloadFolder $(Split-Path -Path $url -Leaf) 
        
        Invoke-WebRequest -Uri $url -OutFile $filePath 
        return $filePath
    }

    function Get-ObjectHasProperty($object, $propertyName)
    {
        return [bool]($object.PSobject.Properties.name -like $propertyName)
    }
    Set-Alias HasProperty Get-ObjectHasProperty -Scope Global

    # Based on http://nuts4.net/post/automated-download-and-installation-of-visual-studio-extensions-via-powershell
    function Install-Vsix([String] $PackageName)
    {
        $ErrorActionPreference = "Stop"
         
        $baseProtocol = "https:"
        $baseHostName = "marketplace.visualstudio.com"
         
        $Uri = "$($baseProtocol)//$($baseHostName)/items?itemName=$($PackageName)"
        $VsixLocation = "$($env:Temp)\$([guid]::NewGuid()).vsix"
         
        $VSInstallDir = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\resources\app\ServiceHub\Services\Microsoft.VisualStudio.Setup.Service"
         
        if (-Not $VSInstallDir) {
          Write-Error "Visual Studio InstallDir registry key missing"
          Exit 1
        }
         
        Write-Host "Grabbing VSIX extension at $($Uri)"
        $HTML = Invoke-WebRequest -Uri $Uri -UseBasicParsing -SessionVariable session
         
        Write-Host "Attempting to download $($PackageName)..."
        $anchor = $HTML.Links |
        Where-Object { (HasProperty $_ "class") -and $_.class -eq 'install-button-container' } |
        Select-Object -ExpandProperty href

        if (-Not $anchor) {
          Write-Error "Could not find download anchor tag on the Visual Studio Extensions page"
          Exit 1
        }
        Write-Host "Anchor is $($anchor)"
        $href = "$($baseProtocol)//$($baseHostName)$($anchor)"
        Write-Host "Href is $($href)"
        Invoke-WebRequest $href -OutFile $VsixLocation -WebSession $session
         
        if (-Not (Test-Path $VsixLocation)) {
          Write-Error "Downloaded VSIX file could not be located"
          Exit 1
        }
        Write-Host "VSInstallDir is $($VSInstallDir)"
        Write-Host "VsixLocation is $($VsixLocation)"
        Write-Host "Installing $($PackageName)..."
        Start-Process -Filepath "$($VSInstallDir)\VSIXInstaller" -ArgumentList "/q /a $($VsixLocation)" -Wait
         
        Write-Host "Cleanup..."
        rm $VsixLocation
        
        Write-Host "Installation of $($PackageName) complete!"
    }
    
    $steps = ([System.Management.Automation.PsParser]::Tokenize((gc "$PSScriptRoot\$($MyInvocation.MyCommand.Name)"), [ref]$null) | where { $_.Type -eq 'Command' -and $_.Content -eq 'Write-ProgressHelper' }).Count

    $gitSteps = ([System.Management.Automation.PsParser]::Tokenize((gc "$PSScriptRoot\$($MyInvocation.MyCommand.Name)"), [ref]$null) | where { $_.Type -eq 'Command' -and $_.Content -eq 'Write-GitRepositoryProgress' }).Count

    $stepCounter = 0
    $gitStepCounter = 0
    
    $state = Get-State
    
    $status = "Beginning Syncro Agent Team development machine setup"
    Syncro-Status $status
    $progressId = 1
    
    Write-ProgressHelper -Message $status -StepNumber ($stepCounter++)
    
    if(-not(Test-IsAdmin))
    {
        Restart-ScriptInAdmin
    }
    
    Write-ProgressHelper -Message "Verifying Chocolatey Install" -StepNumber ($stepCounter++)

    if(-not(Get-Command "choco" -ErrorAction SilentlyContinue))
    {
        Syncro-Status "Installing Chocolatey and required git packages"

        # install chocolatey
        Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    }
    
    Write-ProgressHelper -Message "Verifying sudo Install" -StepNumber ($stepCounter++)
    Syncro-Status "Checking for sudo"
    if (-not(Get-Command "sudo" -ErrorAction SilentlyContinue))
    {
        choco install sudo -y
    }

    Write-ProgressHelper -Message "Verifying Git Install" -StepNumber ($stepCounter++)
    Syncro-Status "Checking for git"
    if (-not(Get-Command "git" -ErrorAction SilentlyContinue))
    {
        choco install git -y
    }

    Write-ProgressHelper -Message "Verifying pageant Install" -StepNumber ($stepCounter++)
    Syncro-Status "Checking for pageant"
    if(-not(Get-Command "pageant" -ErrorAction SilentlyContinue))
    {
        choco install tortoisegit -y
    }

    Write-ProgressHelper -Message "Verifying plink Install" -StepNumber ($stepCounter++)
    Syncro-Status "Checking for plink"
    if(-not(Get-Command "plink" -ErrorAction SilentlyContinue))
    {
        choco install putty -y
    }

    #start a new admin powershell session
    if(-not(Get-Command "pageant" -ErrorAction SilentlyContinue) `
        -or -not(Get-Command "git" -ErrorAction SilentlyContinue) `
        -or -not(Get-Command "pageant" -ErrorAction SilentlyContinue) `
        -or -not(Get-Command "plink" -ErrorAction SilentlyContinue))
    {
        Kill-Powershell
    }

    Write-ProgressHelper -Message "Verifying SSH Setup" -StepNumber ($stepCounter++)
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
        
        Kill-Powershell
    }
    
    # create git workspace
    Write-ProgressHelper -Message "Verifying Git Workspace Setup" -StepNumber ($stepCounter++)
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
    Write-ProgressHelper -Message "Verifying Git Repositories" -StepNumber ($stepCounter++)
    if(!($state.IsRepositoriesCloned))
    {
        Syncro-Status "Fetching required repositories."

        cd $state.GitWorkspacePath
        if(Get-Command plink)
        {
            plink.exe -agent -v git@github.com
        }
        
        Write-GitRepositoryProgress -message "Cloning Main PS Profile Scripts" -stepNumber ($gitStepCounter++)
        git clone --recurse-submodules git@github.com:SyncroSam/Scripts.git --progress
        
        Write-GitRepositoryProgress -message "Cloning kabuto-app" -stepNumber ($gitStepCounter++)
        git clone --recurse-submodules git@github.com:repairtech/kabuto-app.git --progress

        Write-GitRepositoryProgress -message "Cloning kabuto-live-windows" -stepNumber ($gitStepCounter++)
        git clone --recurse-submodules git@github.com:repairtech/kabuto-live-windows.git --progress

        Write-GitRepositoryProgress -message "Cloning kabuto-live-client" -stepNumber ($gitStepCounter++)
        git clone --recurse-submodules git@github.com:repairtech/kabuto-live-client.git --progress      
        
        if($LASTEXITCODE -ne 0)
        {
            Write-Host "An error occured fetching main scripts git repository.  Exiting, please inspect the console for details."
            exit
        }
        
        $state.IsRepositoriesCloned = $true
        Save-State $state
    }
    
    cd (Join-Path $state.GitWorkspacePath "Scripts")

    # set up $profile
    Write-ProgressHelper -Message "Verifying Powershell Profile Setup" -StepNumber ($stepCounter++)
    if(!($state.IsProfileSetUp))
    {
        Syncro-Status "Setting up Powershell Profile."
        
        
        if (!(test-path $profile)) 
        {
            New-Item -path $profile -type file -force
        }

        # set up project settings
        $profilePath = Join-Path $state.GitWorkspacePath "\Scripts\PowerShellProfile\Microsoft.PowerShell_profile.ps1"
        
        $profileBody = @"
`$dotNetProjects = @(
    @{
        Name = "kabuto-app";
        MainDirectory ="$($state.GitWorkspacePath)";
        RepositoryPath ="$($state.GitWorkspacePath)\kabuto-app";
        BaseRemote = "origin";    # remote for the git repository fetch
        BaseBranch = "dev";        # the default branch to base new feature branches on
        PushRemote = "origin";      # default remote to push to
        SolutionPath = "$($state.GitWorkspacePath)\kabuto-app\Kabuto.sln";
        RepositoryUrl = "https://github.com/repairtech/kabuto-app"
        GitUserName = ""
    },
    @{
        Name = "kabuto-live-windows";
        MainDirectory ="$($state.GitWorkspacePath)";
        RepositoryPath ="$($state.GitWorkspacePath)\kabuto-live-windows";
        BaseRemote = "origin";    # remote for the git repository fetch
        BaseBranch = "dev";        # the default branch to base new feature branches on
        PushRemote = "origin";      # default remote to push to
        SolutionPath = "C:\Git Workspace\Syncro\kabuto-live-windows\kabuto-live-windows\KabutoLive.sln";
        RepositoryUrl = "https://github.com/repairtech/kabuto-live-windows"
        GitUserName = ""
    },
    @{
        Name = "kabuto-live-client";
        MainDirectory ="$($state.GitWorkspacePath)";
        RepositoryPath ="$($state.GitWorkspacePath)\kabuto-live-client";
        BaseRemote = "origin";    # remote for the git repository fetch
        BaseBranch = "dev";        # the default branch to base new feature branches on
        PushRemote = "origin";      # default remote to push to
        SolutionPath = "$($state.GitWorkspacePath)\kabuto-live-client";
        RepositoryUrl = "https://github.com/repairtech/kabuto-live-client"
        GitUserName = ""
    })
    
`$localModules = @(
    @{
        Path = "$($state.GitWorkspacePath)\Scripts\Apps\dotNetProject";
        Name = "dotNetProject";
        ArgumentList = @('c:', `$dotNetProjects);
    }
)

. (Resolve-Path '$profilePath') "C:" `$localModules
"@
        Add-Content $profile $profileBody
        
        # install BurntToast so that we can get notifications from background services
        Write-Output "Installing BurntToast"
        Install-Module -Name BurntToast
        
        . $PROFILE
        
        $state.IsProfileSetUp = $true
        Save-State $state
    }
    
    # do remaining developer installs
    Write-ProgressHelper -Message "Verifying Development Tools Installed" -StepNumber ($stepCounter++)
    if(!($state.IsRemainingInstallsComplete))
    {
        Syncro-Status "Running Chocolatey Installs."

        Run-ChocolateyInstalls -y
        
        $state.IsRemainingInstallsComplete = $true
        Save-State $state
    }

    # dl and extract old .net developer packs
    Write-ProgressHelper -Message "Verifying Old .Net Developer Packs Installed" -StepNumber ($stepCounter++)
    if(!($state.IsOldDevPacksInstalled))
    {
        Syncro-Status "Downloading and extracting old dev pack zip files."

        $destinationFolder = "C:\Program Files (x86)\Reference Assemblies\Microsoft\Framework\.NETFramework\"
        Download-AndExtractZip "https://tc.aurelius.pw/redist/dotnet/v4.0.zip" $destinationFolder
        Download-AndExtractZip "https://tc.aurelius.pw/redist/dotnet/v4.5.zip" $destinationFolder   

        $dotNet462 = Download-File "https://tc.aurelius.pw/redist/dotnet/NDP462-KB3151800-x86-x64-AllOS-ENU.exe"
        Start-Process $dotNet462
        
        $state.IsOldDevPacksInstalled = $true
        Save-State $state
    }
    
    # enable .net 3.5
    Write-ProgressHelper -Message "Verifying .Net Framework 3.5 Enbled" -StepNumber ($stepCounter++)
    if(!($state.IsDotNet35Enabled))
    {
        $dotNet35Status = Get-WindowsOptionalFeature -Online | Where-Object -FilterScript {$_.featurename -Like "*netfx3*"}
        if($dotNet35Status.State -ne "Enabled")
        {
            Syncro-Status "Enabling .Net Framework 3.5"
            Enable-WindowsOptionalFeature -Online -FeatureName "NetFx3" -Source "SourcePath"
        }
        
        $state.IsDotNet35Enabled = $true
        Save-State $state
    }
    
    # ensure Nuget source exists
    Write-ProgressHelper -Message "Verifying Nuget Sources exist Installed" -StepNumber ($stepCounter++)
    if(!($state.IsNugetConfigured) -or -not(Is-Installed "wix"))
    {
        Syncro-Status "Setting up default nuget sources."
        
        $nugetBody = "<?xml version=`"1.0`" encoding=`"utf-8`"?>
<configuration>
  <packageSources>
    <add key=`"nuget.org`" value=`"https://api.nuget.org/v3/index.json`" protocolVersion=`"3`" />
  </packageSources>
</configuration>"
        
        $nugetPath = Join-Path $env:APPDATA "\NuGet\NuGet.Config"        
        $output = New-Item -ItemType File -Force -Path $nugetPath -Value $nugetBody
        
        $state.IsNugetConfigured = $true
        Save-State $state
    }
    
    # install wix
    Write-ProgressHelper -Message "Verifying Wix Installed" -StepNumber ($stepCounter++)
    if(!($state.IsWixInstalled) -or -not(Is-Installed "wix"))
    {
        Syncro-Status "Installing Wix"
            
        $wixExe = Download-File "https://github.com/wixtoolset/wix3/releases/download/wix3112rtm/wix311.exe"
        Start-Process $wixExe
        
        Write-Host "Wix Installer executed.  Please note that you will need to install the VS 2019 plugin next (scripted)."
        Write-Host "You can find the installer in your Downloads folder, upon any failure."
                    
        Read-Host "Press enter after you have installed Wix."

        Install-Vsix "WixToolset.WixToolsetVisualStudio2019Extension"
                
        $state.IsWixInstalled = $true
        Save-State $state
    }   
            Syncro-Status @"
            
        Congratulations! Dev machine setup complete!  
        Next steps:
         - Run Visual Studio
         - Enter Telerik nuget credentials
         - Build project.
"@

    