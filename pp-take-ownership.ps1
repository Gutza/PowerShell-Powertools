param (
    [string]$FolderPath,
    [switch]$Headless,
    [switch]$ElevatedInstance,
    [switch]$V,
    [switch]$Help,
    [string]$UserName = $env:USERNAME
)

if ($Help) {
    Write-Host "Usage: pp-take-ownership.ps1 <path> [-UserName <username>] [-Headless] [-V] [-Help]"
    Write-Host "  <path>: The path to the folder to take ownership of. Required."
    Write-Host "  -UserName: The username to grant full access permissions to. Defaults to the current user."
    Write-Host "  -Headless: Run the script in non-interactive mode. If the script requires administrative privileges, it will fail."
    Write-Host "  -V: Verbose mode. Displays the commands being executed."
    Write-Host "  -Help: Display this help message. If this parameter is present, all other parameters are ignored; the script displays the help message and exits."
    Write-Host ""
    Write-Host "Notes:"
    Write-Host "- The names of the parameters are case-insensitive."
    Write-Host "- The script will prompt for administrative privileges if needed."
    Write-Host "- The path can be passed as a positional parameter (as shown above), or as -FolderPath <path>."
    exit
}

if (-not $FolderPath) {
    Write-Error "The -FolderPath parameter is required. Use -Help for more information."
    exit
}

# Resolve relative path to absolute path immediately
$absoluteFolderPath = Resolve-Path -Path $FolderPath -ErrorAction Stop

$currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = new-object System.Security.Principal.WindowsPrincipal($currentIdentity)
$adminRole = [System.Security.Principal.WindowsBuiltInRole]::Administrator

function TakeOwnershipAndPermissions {
    param (
        [string]$FolderPath,
        [string]$UserName
    )
    
    $takeownCommand = "takeown /f `"$FolderPath`" /r /d y"
    if ($V) {
        Write-Host "Executing takeown command: $takeownCommand"
    }
    Invoke-Expression $takeownCommand | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to take ownership of the folder."
        return 1
    }

    $icaclsCommand = "icacls `"$FolderPath`" /grant `"$UserName`:F`" /t /q"
    if ($V) {
        Write-Host "Executing icacls command: $icaclsCommand"
    }

    Invoke-Expression $icaclsCommand
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to grant full access permissions to the user $UserName."
        return
    }
}

if ($principal.IsInRole($adminRole)) {
    TakeOwnershipAndPermissions -FolderPath $absoluteFolderPath.Path -UserName $UserName
    
    if ($ElevatedInstance) {
        Write-Host "Operation completed. Press any key to exit..."
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    }
} elseif (-not $Headless) {
    # Relaunch the script with administrative privileges and ensure it stays open for input if needed
    $script = $MyInvocation.MyCommand.Definition
    $argList = "-FolderPath `"$($absoluteFolderPath.Path)`" -UserName `"$UserName`" -Headless -ElevatedInstance"
    if ($V) {
        $argList += " -V"
    }
    Start-Process PowerShell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$script`" $argList" -Verb RunAs
}
else {
    Write-Error "Script requires administrative privileges. Please rerun with elevated permissions."
}
