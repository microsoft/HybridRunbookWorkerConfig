
<#PSScriptInfo

.VERSION 0.2.6

.GUID a62fccd2-e507-43f9-b29b-1a1d6ef8c337

.AUTHOR Ben Gelens, Michael Greene

.COMPANYNAME Microsoft

.COPYRIGHT 

.TAGS DSCConfiguration

.LICENSEURI https://github.com/Microsoft/HybridRunbookWorkerConfig/blob/master/LICENSE

.PROJECTURI https://github.com/Microsoft/HybridRunbookWorkerConfig

.ICONURI https://raw.githubusercontent.com/Microsoft/HybridRunbookWorkerConfig/master/icon.png

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS 

.EXTERNALSCRIPTDEPENDENCIES 

.RELEASENOTES
https://github.com/Microsoft/HybridRunbookWorkerConfig/blob/master/README.md#releasenotes

.PRIVATEDATA 2016-Datacenter-Server-Core

#>

#Requires -Module @{ModuleName = 'HybridRunbookWorkerDSC'; ModuleVersion = '1.0.0.2'}
#Requires -Module @{ModuleName = 'xPSDesiredStateConfiguration'; ModuleVersion = '8.10.0.0'}

<# 

.DESCRIPTION 
 Automatically install Azure Automation hybrid runbook worker.
#> 

<#

.QUICKSTART

Required variables in Automation service:
  - OMS Workspace ID as Variable: WorkspaceID
  - OMS Workspace Key as Variable: WorkspaceKey(encrypted)
  - Automation Account Endpoint URL as Variable: AutomationEndpoint
  - Automation Account Primary or Secondary Key as Credential: AutomationCredential
    - Username can be any value. Key as password.


 Requires the following modules be imported from the PowerShell Gallery:
  - HybridRunbookerWorkerDSC
  - xPSDesiredStateConfiguration

 To compile using Azure PowerShell:
    Add-AzureRMAccount (Login)
    
    $ConfigurationData = @{
        AllNodes = @(
            @{
                NodeName = 'Localhost'
                PSDscAllowPlainTextPassword = $true
            }
        )
    }

    $CompileParams = @{
        ResourceGroupName     = <ResourceGroupName>
        AutomationAccountName = <AutomationAccountName>
        ConfigurationName     = HybridRunbookWorkerConfig
        ConfigurationData     = $ConfigurationData
    }

    Start-AzureRmAutomationDscCompilationJob @CompileParams

#>

configuration HybridRunbookWorkerConfig
{

Import-DscResource -ModuleName @{ModuleName='xPSDesiredStateConfiguration';ModuleVersion='8.10.0.0'}
Import-DscResource -ModuleName @{ModuleName='HybridRunbookWorkerDsc';ModuleVersion='1.0.0.2'}

$OmsWorkspaceId = Get-AutomationVariable WorkspaceID
$OmsWorkspaceKey = Get-AutomationVariable WorkspaceKey
$AutomationEndpoint = Get-AutomationVariable AutomationEndpoint
$AutomationKey = Get-AutomationPSCredential AutomationCredential

$OIPackageLocalPath = "C:\MMASetup-AMD64.exe"
    
    node localhost
    {
    
      # Download a package
      xRemoteFile OIPackage
      {
          Uri = 'http://download.microsoft.com/download/2/B/5/2B59B9A7-37CC-4FC5-BB4E-C7A69FE75DCF/MMASetup-AMD64.exe'
          DestinationPath = $OIPackageLocalPath
      }
  
      # Application, requires reboot. Allow reboot in meta config
      Package OI
      {
          Ensure = "Present"
          Path = $OIPackageLocalPath
          Name = "Microsoft Monitoring Agent"
          ProductId = "43176309-DADC-4C94-9719-DDB6BC1AFECA"
          Arguments = '/Q /C:"setup.exe /qn ADD_OPINSIGHTS_WORKSPACE=1 OPINSIGHTS_WORKSPACE_ID=' + 
              $OmsWorkspaceID + ' OPINSIGHTS_WORKSPACE_KEY=' + 
                  $OmsWorkspaceKey + ' AcceptEndUserLicenseAgreement=1"'
          DependsOn = "[xRemoteFile]OIPackage"
      }
      
      Service OIService
      {
          Name = "HealthService"
          State = "Running"
          DependsOn = "[Package]OI"
      }
  
      WaitForHybridRegistrationModule ModuleWait
      {
          IsSingleInstance = 'Yes'
          RetryIntervalSec = 3
          RetryCount = 40
          DependsOn = '[Package]OI'
      }
  
      HybridRunbookWorker Onboard
      {
          Ensure    = 'Present'
          Endpoint  = $AutomationEndpoint
          Token     = $AutomationKey
          GroupName = 'Managed'
          DependsOn = '[WaitForHybridRegistrationModule]ModuleWait'
      }
    }
}
  
