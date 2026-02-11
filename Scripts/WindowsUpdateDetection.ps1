# Define the path and value name reported by Autopatch
$registryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
$valueName = "NoAutoUpdate"

try {
    # Check if the registry path exists
    if (Test-Path $registryPath) {
        # Check if the specific value exists
        $registryValue = Get-ItemProperty -Path $registryPath -Name $valueName -ErrorAction SilentlyContinue
        
        if ($null -ne $registryValue.$valueName) {
            # The problematic key exists. Exit with 1 to trigger the fix.
            Write-Output "Found problematic registry key: $valueName"
            exit 1
        }
        else {
            # The path exists, but the specific 'NoAutoUpdate' value is missing.
            Write-Output "Path exists, but $valueName value is not present. Device is compliant."
            exit 0
        }
    }
    else {
        # The entire AU folder is missing, which means the block isn't there.
        Write-Output "Registry path not found. Device is compliant."
        exit 0
    }
}
catch {
    # If something goes wrong, exit with 1 to be safe and let remediation attempt a fix
    Write-Error "An error occurred during detection: $($_.Exception.Message)"
    exit 1
}