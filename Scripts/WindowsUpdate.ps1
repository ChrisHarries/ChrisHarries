$path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
$name = "NoAutoUpdate"

if (Test-Path $path) {
    $val = Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
    if ($val) {
        Remove-ItemProperty -Path $path -Name $name -Force
        Write-Host "Successfully removed NoAutoUpdate registry key."
    } else {
        Write-Host "Key exists but value '$name' was not found."
    }
} else {
    Write-Host "Path does not exist. Nothing to do."
}