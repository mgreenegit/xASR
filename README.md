[![Build status](https://ci.appveyor.com/api/projects/status/ /branch/master?svg=true)](https://ci.appveyor.com/project/PowerShell/xASR/branch/master)

# xASR

The **xASR** DSC module installs the ASR agent on a protected node and the provider on a SCVMM server. 

## Contributing
Please check out common DSC Resources [contributing guidelines](https://github.com/PowerShell/DscResource.Kit/blob/master/CONTRIBUTING.md).


## Resources

* **xMARSAgentSetup** installs the agent on a protected node.
* **xVMMASRProviderSetup** installs the provider on SCVMM server. 

### xMARSAgentSetup

* **Ensure**: An enumerated value that describes if the MASR provider is expected to be installed on the machine.
* **SourcePath**: UNC path to the root of the source files for installation. 
* **SourceFolder**: Folder within the source path containing the source files for installation.
* **SetupCredential**: Credential to be used to perform the installation.
* **SourceCredential**: Credential to be used to access SourcePath.
* **SuppressReboot**: Suppress reboot.
* **ForceReboot**: Force reboot.
* **ProxyServerAddress**: Address of Proxy server to be connected.
* **ProxyServerPort**: Port of proxy server to be connected.
* **ProxyServerCredential**: Credential to be used to Connect to proxy server.

### xVMMASRProviderSetup

* **Ensure**: An enumerated value that describes if the MASR provider is expected to be installed on the machine. 
* **SourcePath**: UNC path to the root of the source files for installation.
* **SourceFolder**: Folder within the source path containing the source files for installation.
* **SetupCredential**: Credential to be used to perform the installation.
* **SourceCredential**: Credential to be used to access SourcePath.
* **SuppressReboot**: Suppress reboot.
* **ForceReboot**: Force reboot.
* **ProxyServerAddress**: Address of Proxy server to be connected.
* **ProxyServerPort**: Port of proxy server to be connected.
* **ProxyServerCredential**: Credential to be used to Connect to proxy server.

## Versions

### Unreleased
* **New Module**: Completely new module
  * **TODO** Unit tests and tested examples

## Examples

### End-to-End Example

TODO

```powershell
# End to end sample for xASR
Configuration Sample_EndToEnd_xASR
{
    param
    (
        [Parameter(Mandatory)]
        [PSCredential]$SetupCredential
    )

    Import-DscResource -module xASR

    xMARSAgentSetup setup
    {
        Ensure = "Present"      
        SourcePath = "\\server\share\"
        SourceFolder = "MARSAgent"
        SetupCredential = $SetupCredential
    }
}
```
