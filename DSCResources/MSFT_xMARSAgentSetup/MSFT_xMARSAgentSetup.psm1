$currentPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Debug -Message "CurrentPath: $currentPath"

# Load Common Code
Import-Module $currentPath\..\..\ASRHelper.psm1 -Verbose:$false -ErrorAction Stop

function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [parameter(Mandatory = $True)]
        [ValidateSet("Present","Absent")]
        [System.String]
        $Ensure = "Present",

        [System.String]
        $SourcePath = "$PSScriptRoot\..\..\",

        [System.String]
        $SourceFolder = "Source",

        [parameter(Mandatory = $True)]
        [System.Management.Automation.PSCredential]
        $SetupCredential,

        [System.Management.Automation.PSCredential]
        $SourceCredential,

        [System.Boolean]
        $SuppressReboot,

        [System.Boolean]
        $ForceReboot,

        [System.String]
        $ProxyServerAddress,

        [System.String]
        $ProxyServerPort="8080",

        [System.Management.Automation.PSCredential]
        $ProxyServerCredential,

        [System.Boolean]
        $UseNoUpdateFlag = $true
    )

    $Path = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $Script:MyInvocation.MyCommand.Path))
    Import-Module (Join-Path -Path $Path -ChildPath "xPDT.psm1")

    try
    {
        if($SourceCredential)
        {
            NetUse -SourcePath $SourcePath -Credential $SourceCredential -Ensure "Present"
        }
        $Path = Join-Path -Path (Join-Path -Path $SourcePath -ChildPath $SourceFolder) -ChildPath "MARSAgentInstaller.exe"
        $Path = ResolvePath $Path    
        $ExpectedVersion = (Get-Item -Path $Path).VersionInfo.FileVersion

        Write-Verbose "Path: $Path"
        Write-Verbose "Expected Version: $ExpectedVersion"
    }
    finally
    {
        if($SourceCredential)
        {
            NetUse -SourcePath $SourcePath -Credential $SourceCredential -Ensure "Absent"
        }
    }
    $Ensure = "Absent"

    if(Test-Path("HKLM:\SOFTWARE\Microsoft\Windows Azure Backup"))
    {
        Write-Verbose "MARS Agent is already installed. Checking version of installed MARS agent"
        try
        {
            $ExistingVersion = (Get-WmiObject -ns root\cimv2 -query "select * from win32_product where Name='Microsoft Azure Recovery Services Agent'").Version
            Write-Verbose "Version of installed MARS agent: $ExistingVersion"
        }
        catch
        {            
            Write-Verbose "Error in getting version of MARS agent which is already installed."
            $Ensure = "Absent"
        }

        if($ExistingVersion -eq $ExpectedVersion)
        {
            Write-Verbose "Version of installed MARS agent is same as MARS agent to be inastlled"
            $Ensure = "Present"
        }
    }

    Write-Verbose "MARS agent status : $Ensure"

    $returnValue = @{
        Ensure = $Ensure
        SourcePath = $SourcePath
        SourceFolder = $SourceFolder
    }

    $returnValue
}


function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $True)]
        [ValidateSet("Present","Absent")]
        [System.String]
        $Ensure = "Present",

        [System.String]
        $SourcePath = "$PSScriptRoot\..\..\",

        [System.String]
        $SourceFolder = "Source",

        [parameter(Mandatory = $True)]
        [System.Management.Automation.PSCredential]
        $SetupCredential,

        [System.Management.Automation.PSCredential]
        $SourceCredential,

        [System.Boolean]
        $SuppressReboot,

        [System.Boolean]
        $ForceReboot,

        [System.String]
        $ProxyServerAddress,

        [System.String]
        $ProxyServerPort="8080",

        [System.Management.Automation.PSCredential]
        $ProxyServerCredential,

        [System.Boolean]
        $UseNoUpdateFlag = $true
    )

    $Path = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $Script:MyInvocation.MyCommand.Path))
    Import-Module (Join-Path -Path $Path -ChildPath "xPDT.psm1")

    if($SourceCredential)
    {
        try
        {
            NetUse -SourcePath $SourcePath -Credential $SourceCredential -Ensure "Present"
            $TempFolder = [IO.Path]::GetTempPath()
            & robocopy.exe (Join-Path -Path $SourcePath -ChildPath $SourceFolder) (Join-Path -Path $TempFolder -ChildPath $SourceFolder) /e    
            $SourcePath = $TempFolder
        }
        finally
        {
            NetUse -SourcePath $SourcePath -Credential $SourceCredential -Ensure "Absent"
        }
    }

    $Path = Join-Path -Path (Join-Path -Path $SourcePath -ChildPath $SourceFolder) -ChildPath "MARSAgentInstaller.exe"
    
    $Path = ResolvePath $Path    

    switch($Ensure)
    {
        "Present"
        {
            $Arguments = ""
            if($UseNoUpdateFlag)
            {
                $Arguments = "/q /nu"
            }
            else
            {
                $Arguments = "/q"
            }
            
        }
        "Absent"
        {
            try
            {
                $UninstallCmds = Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall,HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall |
                Get-ItemProperty |
                Where-Object {$_.DisplayName -match ("Microsoft Azure Recovery Services Agent")} |
                Select-Object -Property UninstallString
            }
            catch
            {
                throw New-TerminatingError -ErrorType MARSAgent_FailedToGetIdentifyingNum -ErrorCategory ObjectNotFound
            }
            
            if($UninstallCmds -ne $null)
            {
                foreach($cmd in $UninstallCmds)
                {
                    if($cmd.UninstallString -match "MsiExec.exe")
                    {
                        $UninstallCmd = $cmd
                        break
                    }
                }
                $IdentifyingNumber = $UninstallCmd.UninstallString.Substring($UninstallCmd.UninstallString.IndexOf("{"))
                $Arguments="/X$IdentifyingNumber /q"
                $Path = "MsiExec.exe"
                $Path = ResolvePath $Path
            }
            else
            {
                throw New-TerminatingError -ErrorType MARSAgent_FailedToGetIdentifyingNum -ErrorCategory ObjectNotFound
            }
        }
    }

    Write-Verbose "Path: $Path"
    Write-Verbose "Arguments: $Arguments"
    
    $StartService = $false

    try
    {
        if((Test-Path("HKLM:\SOFTWARE\Microsoft\Windows Azure Backup")) -and ($Ensure -eq "Present"))
        {
            Write-Verbose "Stopping OBENGINE service"
            if((Get-Service obengine).Status -eq "Running")
            {
                Stop-Service obengine
            }
            $StartService = $True
        }

        $Process = StartWin32Process -Path $Path -Arguments $Arguments -Credential $SetupCredential
        Write-Verbose $Process
        WaitForWin32ProcessEnd -Path $Path -Arguments $Arguments -Credential $SetupCredential
    }
    finally
    {
        if($StartService)
        {
            Write-Verbose "Starting OBENGINE service"
            Set-Service obengine -StartupType Manual
            if((Get-Service obengine).Status -eq "Stopped")
            {
                Start-Service obengine
            }
        }
    }
    if($ForceReboot -or ((Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue) -ne $null))
    {
        if(!($SuppressReboot))
        {
            $global:DSCMachineStatus = 1
        }
        else
        {
            Write-Verbose "Suppressing reboot"
        }
    }

    if((Test-TargetResource @PSBoundParameters))
    {
        if($ProxyServerAddress -and ($Ensure -eq "Present"))
        {
            Write-Verbose "Configuring Proxy settings of MARS Agent"
            try
            {
                $InstallPath = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Azure Backup\Setup" -Name InstallPath
                $ModulePath = Join-Path -Path $InstallPath.InstallPath -ChildPath "bin\Modules\MSOnlineBackup"

                Import-module $ModulePath
                if($ProxyServerCredential)
                {
                    Set-OBMachineSetting -ProxyServer $ProxyServerAddress -ProxyPort $ProxyServerPort -ProxyUserName $ProxyServerCredential.UserName -ProxyPassword $sProxyServerPassword.Password
                }
                else
                {
                    Set-OBMachineSetting -ProxyServer $ProxyServerAddress -ProxyPort $ProxyServerPort
                }
            }
            catch
            {
                throw New-TerminatingError -ErrorType MARSAgent_FailedConfigureProxy
            }
        }
    }
    else
    {
        throw New-TerminatingError -ErrorType TestFailedAfterSet -ErrorCategory InvalidResult
    }
}


function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [parameter(Mandatory = $True)]
        [ValidateSet("Present","Absent")]
        [System.String]
        $Ensure = "Present",

        [System.String]
        $SourcePath = "$PSScriptRoot\..\..\",

        [System.String]
        $SourceFolder = "Source",

        [parameter(Mandatory = $True)]
        [System.Management.Automation.PSCredential]
        $SetupCredential,

        [System.Management.Automation.PSCredential]
        $SourceCredential,

        [System.Boolean]
        $SuppressReboot,

        [System.Boolean]
        $ForceReboot,

        [System.String]
        $ProxyServerAddress,

        [System.String]
        $ProxyServerPort="8080",

        [System.Management.Automation.PSCredential]
        $ProxyServerCredential,

        [System.Boolean]
        $UseNoUpdateFlag = $true

    )

    $result = ((Get-TargetResource @PSBoundParameters).Ensure -eq $Ensure)

    $result
}


Export-ModuleMember -Function *-TargetResource