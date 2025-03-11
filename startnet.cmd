$server = "VAXRECWDS01"
$share = "\\$server\ahswad"
$username = "VAXRECYCLING\arpprod"
$password = "Skirt9-Multitude-Blinker"
$retryInterval = 5  # Seconds to wait before retrying
$retryLimit = 10    # Maximum number of retries

# Function to map network drive
function MapNetworkDrive {
    $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential ($username, $securePassword)
    New-PSDrive -Name Z -PSProvider FileSystem -Root $share -Credential $credential -Persist
}

# Retry logic
$retryCount = 0
do {
    if (Test-Connection -ComputerName $server -Count 1 -Quiet) {
        try {
            MapNetworkDrive
            Write-Host "Drive mapped successfully."
            break
        } catch {
            Write-Host "Failed to map drive. Retrying in $retryInterval seconds..."
            Start-Sleep -Seconds $retryInterval
        }
    } else {
        Write-Host "$server is not reachable. Retrying in $retryInterval seconds..."
        Start-Sleep -Seconds $retryInterval
    }
    $retryCount++
} while ($retryCount -lt $retryLimit)

if ($retryCount -ge $retryLimit) {
    Write-Host "Failed to connect after $retryLimit attempts. Please check your network connection and server status."
}



Start-Process -FilePath "X:\Windows\System32\BlanccoPreInstall.exe" -ArgumentList '--image="X:\Windows\System32\LOG_BDE_7.14_bmp.iso"', '--reboot', '--force' -NoNewWindow
