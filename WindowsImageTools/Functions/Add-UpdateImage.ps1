﻿<#
        .Synopsis
        Add a Windows Image to the Windows Image Tools Update Directory
        .DESCRIPTION
        convert a .ISO or .WIM into a VHD populated with an unattend and scripts/modules from the Resources folder locaed in -Path
        .EXAMPLE
        Add-WitUpdateImage -Path c:\WitTools
        .EXAMPLE
        Another example of how to use this cmdlet
        .INPUTS
        System.IO.DirectoryInfo
        .OUTPUTS
        Custom object containing String -Path and String -Name
#>
function Add-UpdateImage
{
    [CmdletBinding(SupportsShouldProcess = $true)]
    #[OutputType([String])]
    Param
    (
        # Path to the Windows Image Tools Update Folders (created via New-WindowsImageToolsExample)
        [Parameter(Mandatory = $true, 
        ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
                    if (Test-Path $_) 
                    {
                        $true
                    }
                    else 
                    {
                        throw "Path $_ does not exist"
                    }
        })]
        [Alias('FullName')] 
        $Path,
 
        # Administrator Password for Base VHD (Default = P@ssw0rd)
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string]
        $FriendlyName,

        # Administrator Password for Base VHD (Default = P@ssw0rd)
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string]
        $AdminPassword = 'P@ssw0rd',

        # Product Key for sorce image (Not required for volume licence media) 
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
                    if ($_ -imatch '^[a-z0-9]{5}-[a-z0-9]{5}-[a-z0-9]{5}-[a-z0-9]{5}-[a-z0-9]{5}$') 
                    {
                        $true
                    } 
                    else 
                    {
                        throw "$_ not a valid key format"
                    }
        })]
        [String]
        $ProductKey,

        # Size in Bytes (Default 40B)
        [ValidateRange(25GB,64TB)]
        [uint64]$Size = 40GB,
        
        # Create Dynamic disk
        [switch]$Dynamic,

        # Specifies whether to build the image for BIOS (MBR), UEFI (GPT), or WindowsToGo (MBR).
        # Generation 1 VMs require BIOS (MBR) images.  Generation 2 VMs require UEFI (GPT) images.
        # Windows To Go images will boot in UEFI or BIOS
        [Parameter(Mandatory = $true)]
        [Alias('Layout')]
        [string]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('BIOS', 'UEFI', 'WindowsToGo')]
        $DiskLayout,
        
        # Path to WIM or ISO used to populate VHDX
        [parameter(Position = 1,Mandatory = $true,
        HelpMessage = 'Enter the path to the WIM/ISO file')]
        [ValidateScript({
                    Test-Path -Path (get-FullFilePath -Path $_ )
        })]
        [string]$SourcePath,
        
        # Index of image inside of WIM (Default 1)
        [int]$Index = 1,
        
        # Native Boot does not have the boot code inside the VHD(x) it must exist on the physical disk. 
        [switch]$NativeBoot,

        # Features to turn on (in DISM format)
        [ValidateNotNullOrEmpty()]
        [string[]]$Feature,

        # Path to drivers to inject
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
                    Test-Path -Path $(Resolve-Path $_)
        })]
        [string[]]$Driver,

        # Path of packages to install via DSIM
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
                    Test-Path -Path $(Resolve-Path $_)
        })]
        [string[]]$Package,

        # Files/Folders to copy to root of Winodws Drive (to place files in directories mimic the direcotry structure off of C:\)
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
                    foreach ($Path in $_) 
                    {
                        Test-Path -Path $(Resolve-Path $Path)
                    }
        })]
        [string[]]$filesToInject

    )

    $target = "$Path\BaseImage\$($FriendlyName)_base.vhdx"

    if ($pscmdlet.ShouldProcess("$target", 'Add Windows Image Tools Update Image'))
    {
        $ParametersToPass = @{}
        foreach ($key in ('Whatif', 'Verbose', 'Debug'))
        {
            if ($PSBoundParameters.ContainsKey($key)) 
            {
                $ParametersToPass[$key] = $PSBoundParameters[$key]
            }
        }

        #region Validate Input
        try 
        {
            $null = Test-Path -Path "$Path\BaseImage" -ErrorAction Stop
            $null = Test-Path -Path "$Path\Resource" -ErrorAction Stop
        }
        catch
        {
            Throw "$Path missing required folder structure use New-WindowsImagetoolsExample to create example"
        }
        #if (Test-Path -Path "$Path\BaseImage\$($FriendlyName)_Base.vhdx")
        #{
        #    Throw "BaseImage for $FriendlyName allready exists. use Remove-WindowsImageToolsUpdateImage -Name $FriendlyName first"
        #}
        
        #if (-not (Get-Command Save-Module))
        #{
        #    Write-Warning -Message 'PowerShellGet missing. you will need to doanload required modules from the Galary manualy'
        #}
        #endregion

        #region Update Resource Folder
        # PowerShell Modules
       # Write-Verbose -Message "[$($MyInvocation.MyCommand)] : Geting latest PSWindowsUpdate"
       # try 
       # {
       #     Save-Module -Name PSWindowsUpdate -Path $Path\Resource -Force -ErrorAction Stop
       # }
       # catch 
       # {
       #     if (Test-Path -Path $Path\Resource\PSWindowsUpdate)
       #     {
       #         Write-Warning -Message "[$($MyInvocation.MyCommand)] : PSwindowsUpdate present, but unable to download latest"
       #     }
       #     else 
       #     {
       #         throw "unable to download PSWindowsUpdate from PowerShellGalary.com, download manualy and place in $Path\Resource "
       #     }
       # }
        
     
        #endregion

        #region Unattend
        
        $unattentParam = @{
            LogonCount = 1
            ScriptPath = 'c:\pstemp\FirstBoot.ps1'
        }
        if ($AdminPassword) 
        {
            $unattentParam.add('AdminPassword',$AdminPassword) 
        }
        if ($ProductKey) 
        {
            $unattentParam.add('ProductKey',$ProductKey) 
        }
        
        $UnattendPath = New-UnattendXml @unattentParam @ParametersToPass

        #endregion 

                
        #region Create Base VHD

        $convertParm = @{
            DiskLayout = $DiskLayout
            SourcePath = $SourcePath
            Index      = $Index
            Unattend   = $UnattendPath
            Path       = $target
        }
        if ($NativeBoot) 
        {
            $convertParm.add('NativeBoot',$NativeBoot) 
        }
        if ($Feature) 
        {
            $convertParm.add('Feature',$Feature)
        }
        if ($Driver) 
        {
            $convertParm.add('Driver',$Driver)
        }
        if ($Package) 
        {
            $convertParm.add('Package',$Package)
        }
        if ($filesToInject) 
        {
            $convertParm.add('filesToInject',$filesToInject)
        }
        
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] : $target : Creating "
        Convert-Wim2VHD @convertParm  @ParametersToPass
        #endregion

        $FirstBootContent = {
            Start-Transcript -Path $PSScriptRoot\FirstBoot.log

            $Paramaters = @{
                Action   = New-ScheduledTaskAction -Execute '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\PsTemp\AtStartup.ps1'
                Trigger  = New-ScheduledTaskTrigger -AtStartup
                Settings = New-ScheduledTaskSettingsSet
            }
            $TaskObject = New-ScheduledTask @Paramaters
            Register-ScheduledTask AtStartup -InputObject $TaskObject -User 'nt authority\system' -Verbose 

            Start-Sleep -Seconds 20
            Restart-Computer -Verbose -Force 
            Stop-Transcript
        }
       
        $AddScriptFilesBlock = {
            if (-not (Test-Path "$($driveLetter):\PsTemp"))
            { $null = mkdir "$($driveLetter):\PsTemp" }
            $null = New-Item -Path "$($driveLetter):\PsTemp" -Name FirstBoot.ps1 -ItemType 'file' -Value $FirstBootContent  
        }

        Write-Verbose -Message "[$($MyInvocation.MyCommand)] : $target : Adding First Boot Script "
        MountVHDandRunBlock -vhd $target -block $AddScriptFilesBlock @ParametersToPass
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] : $target : Finished "
    }
}