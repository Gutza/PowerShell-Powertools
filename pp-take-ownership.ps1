param (
    [Parameter(Mandatory=$true)]
    [string]$FolderPath,
    [switch]$Headless,
    [switch]$ElevatedInstance,
    [string]$UserName = $env:USERNAME # Default to the current user if not specified
)

# Resolve relative path to absolute path immediately
$absoluteFolderPath = Resolve-Path -Path $FolderPath -ErrorAction Stop

function Request-PermissionAndRun {
    param (
        [string]$path,
        [string]$username,
        [switch]$headless
    )

    # Ensure username is in the correct format for icacls
    if (-not $username.Contains('\')) {
        $username = "$env:COMPUTERNAME\$username"
    }

    # Check if running as Administrator
    if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        if (-NOT $headless) {
            # Attempt to relaunch script with administrative privileges, passing the resolved absolute path and formatted username
            Start-Process PowerShell.exe -ArgumentList "-File", "`"$PSCommandPath`"", "-FolderPath", "`"$path`"", "-UserName", "`"$username`"", "-Headless", "-ElevatedInstance" -Verb RunAs
            exit
        } else {
            Write-Error "Script requires administrative privileges. Please rerun with elevated permissions."
            exit
        }
    }
}

function TakeOwnershipAndGrantPermissions {
    param (
        [string]$path,
        [string]$username
    )

    # Check for and ensure username format
    if (-not $username.Contains('\')) {
        $username = "$env:COMPUTERNAME\$username"
    }

    # Ensure the path is not targeting system32
    $system32Path = [System.Environment]::ExpandEnvironmentVariables('%windir%\system32')
    if ($path -ieq $system32Path) {
        Write-Error "Modifying the system32 directory is not allowed."
        return
    }

    # Check if the folder path exists
    if (-Not (Test-Path -Path $path -PathType Container)) {
        Write-Error "The folder path '$path' does not exist."
        return
    }

    # Taking ownership
    takeown /f $path /r /d y | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to take ownership of the folder."
        return
    }

    # Correctly formatting the icacls command with quotes around the username and path
    $icaclsCommand = "icacls `"$path`" /grant `"$username`:F`" /t /q"
    Write-Host "Executing icacls command: $icaclsCommand" # Diagnostic output
    Invoke-Expression $icaclsCommand
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to grant full access permissions to the user $username."
        return
    }

    Write-Host "Ownership taken and permissions updated successfully for: $path"
}

try {
    # Check for elevation and potentially restart the script with elevated privileges, passing the original username
    Request-PermissionAndRun -path $absoluteFolderPath.Path -username $UserName -headless:$Headless

    # If already elevated, or running headless, proceed to take ownership and grant permissions, using the original username
    TakeOwnershipAndGrantPermissions -path $absoluteFolderPath.Path -username $UserName
} catch {
    Write-Error "An error occurred: $_"
}

if ($ElevatedInstance) {
    Write-Host "Press any key to continue . . ."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}    
