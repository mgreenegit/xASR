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
        $ProxyServerCredential
    )

    $Path = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $Script:MyInvocation.MyCommand.Path))
    Import-Module (Join-Path -Path $Path -ChildPath "xPDT.psm1")    
    try
    {
        if($SourceCredential)
        {
            NetUse -SourcePath $SourcePath -Credential $SourceCredential -Ensure "Present"
        }
        $Path = Join-Path -Path (Join-Path -Path $SourcePath -ChildPath $SourceFolder) -ChildPath "VMMASRProvider_x64.exe"    
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

    if(Test-Path("HKLM:\SOFTWARE\Microsoft\Azure Site Recovery"))
    {
        Write-Verbose "MASR provider is already installed. Checking version of installed MASR provider"
        $ExistingVersion=Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Azure Site Recovery" -Name Version
        Write-Verbose "Version of installed MASR provider: $ExistingVersion"

        if($ExistingVersion.Version -eq $ExpectedVersion)
        {
            Write-Verbose "Version of installed MASR Provider is same as MASR Provider to be inastlled"
            $Ensure = "Present"
        }
    }

    Write-Verbose "MASR provider status : $Ensure"

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
        $ProxyServerCredential
    )

    $Path = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $Script:MyInvocation.MyCommand.Path))
    Import-Module (Join-Path -Path $Path -ChildPath "xPDT.psm1")    
    try
    {
        if($SourceCredential)
        {
            NetUse -SourcePath $SourcePath -Credential $SourceCredential -Ensure "Present"
        }
        $TempFolder = [IO.Path]::GetTempPath()

        $ExtractionPath = (Join-Path -Path $TempFolder -ChildPath $SourceFolder)    

        $SourcePath=(Join-Path -Path $SourcePath -ChildPath $SourceFolder)    
        $Path=Join-Path -Path $SourcePath -ChildPath "VMMASRProvider_x64.exe"
        $Arguments = "/x:$ExtractionPath /q"
    
        $Path = ResolvePath $Path    
    
        Write-Verbose "Path: $Path"
        Write-Verbose "Arguments: $Arguments"
    
        $Process = StartWin32Process -Path $Path -Arguments $Arguments
        Write-Verbose $Process
        WaitForWin32ProcessEnd -Path $Path -Arguments $Arguments
    }
    finally
    {
        if($SourceCredential)
        {
            NetUse -SourcePath $SourcePath -Credential $SourceCredential -Ensure "Absent"
        }
    }
    $SourcePath = $ExtractionPath

    $Path = Join-Path -Path $SourcePath -ChildPath "SETUPDR.EXE"

    $Path = ResolvePath $Path    

    switch($Ensure)
    {
        "Present"
        {
            $Arguments = "/i"
        }
        "Absent"
        {
            try
            {
                $UninstallCmd = Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall,HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall |
                Get-ItemProperty |
                Where-Object {$_.DisplayName -match ("Microsoft Azure Site Recovery Provider")} |
                Select-Object -Property UninstallString
            }
            catch
            {
                throw New-TerminatingError -ErrorType MASRprovider_FailedToGetIdentifyingNum -ErrorCategory ObjectNotFound
            }

            if($UninstallCmds -ne $null)
            {
                $IdentifyingNumber = $UninstallCmd.UninstallString.Substring($UninstallCmd.UninstallString.IndexOf("{"))
                $Arguments="/X$IdentifyingNumber /q"
                $Path = "MsiExec.exe"
                $Path = ResolvePath $Path
            }
            else
            {
                throw New-TerminatingError -ErrorType MASRprovider_FailedToGetIdentifyingNum -ErrorCategory ObjectNotFound
            }
        }
    }

    Write-Verbose "Path: $Path"
    Write-Verbose "Arguments: $Arguments"

    try
    {
        if((Get-Service SCVMMService).Status -eq "Running")
        {
            Write-Verbose "Stopping SCVMM service"
            Stop-Service scvmmservice
        }

        $Process = StartWin32Process -Path $Path -Arguments $Arguments -Credential $SetupCredential
        Write-Verbose $Process
        WaitForWin32ProcessEnd -Path $Path -Arguments $Arguments -Credential $SetupCredential
    }
    finally
    {
        if((Get-Service SCVMMService).Status -eq "Stopped")
        {
            Write-Verbose "Starting SCVMM service"
            Start-Service scvmmservice
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
        if(($Ensure -eq "Present") -and $ProxyServerAddress)
        {
            Write-Verbose "Configuring Proxy settings of MASR Provider"
            $BinPath = Join-Path -Path "$env:SystemDrive" -ChildPath "Program Files\Microsoft System Center 2012 R2\Virtual Machine Manager\bin"

            $Path = Join-Path -Path $BinPath -ChildPath "DRConfigurator.exe"
            $Arguments = "/configure /proxyaddress $ProxyServerAddress /proxyport $ProxyServerPort"

            Write-Verbose "Path: $Path"
            Write-Verbose "Arguments: $Arguments"

            if($ProxyServerCredential)
            {
                Write-Verbose "Retreiving Proxy Credentials"
                $ProxyServerUserName = $ProxyServerCredential.UserName 
                $ProxyServerPassword = $ProxyServerCredential.GetNetworkCredential().Password
                $Arguments+=" /ProxyUserName $ProxyServerUserName /proxypassword $ProxyServerPassword"
                Write-Verbose "Retreived Proxy Credentials"
            }

            $Process = StartWin32Process -Path $Path -Arguments $Arguments -Credential $SetupCredential
            Write-Verbose $Process
            WaitForWin32ProcessEnd -Path $Path -Arguments $Arguments -Credential $SetupCredential
            
            Write-Verbose "ReStarting SCVMM service"
            Restart-Service scvmmservice
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
        $ProxyServerCredential
    )

    $result = ((Get-TargetResource @PSBoundParameters).Ensure -eq $Ensure)

    $result
}

Export-ModuleMember -Function *-TargetResource