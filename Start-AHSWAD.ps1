[CmdletBinding()]
param(
    [switch]$ShowOutput = $false
)

# Enable strict mode for better error detection
Set-StrictMode -Version Latest

###############################################################################
# Force TLS 1.2 and bypass SSL certificate validation (use with caution)
###############################################################################
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::ServerCertificateValidationCallback = {
    param($sender, $certificate, $chain, $sslPolicyErrors)
    if ($ShowOutput) { Write-Host "Bypassing SSL certificate error: $sslPolicyErrors" }
    return $true
}

###############################################################################
# User-defined variables
###############################################################################
$Customer         = 1981
$Country          = 4
$User             = "filip.johansson@atea.se"
$GroupTag         = "ARP_ENROLLMENT"
$AuthKey          = "nCTgRtsk7FX71XKIhQD9dEfER6hC0HucmjUMUJZ4"

###############################################################################
# Script-level (script:) variables for progress tracking
###############################################################################
$script:totalSteps  = 4
$script:currentStep = 0

###############################################################################
# Helper Functions
###############################################################################
function Show-Progress {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Activity,
        [Parameter(Mandatory=$true)]
        [string]$Status,
        [int]$PercentComplete
    )
    if ($ShowOutput) { Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete }
}

# Increments the script-level progress counter and displays the progress bar
function Update-Progress {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Status
    )
    $script:currentStep++
    $percent = [int](($script:currentStep / $script:totalSteps) * 100)
    Show-Progress -Activity "Autopilot Enrollment" -Status $Status -PercentComplete $percent
}

function Get-HardwareHash {
    param(
        [string]$ScriptRoot
    )
    
    # Define the writable temporary folder
    $TempDir = "X:\Temp"
    if (-not (Test-Path $TempDir)) {
        New-Item -Path $TempDir -ItemType Directory | Out-Null
    }
    $env:TEMP = $TempDir
    $env:TMP  = $TempDir
    
    # Set paths for the XML output, tool executable, and config file in both locations
    $xmlPath      = Join-Path $TempDir 'OA3.xml'
    $oa3ToolExe   = Join-Path $ScriptRoot 'oa3tool.exe'
    $oa3ToolTemp  = Join-Path $TempDir 'oa3tool.exe'
    $cfgPath      = Join-Path $ScriptRoot 'OA3.cfg'
    
    # Copy the tool and configuration file to the temporary folder
    try {
        Copy-Item -Path $oa3ToolExe -Destination $TempDir -Force
        Copy-Item -Path $cfgPath -Destination $TempDir -Force
    }
    catch {
        if ($ShowOutput) { Write-Host "Error copying files to temp folder: $($_.Exception.Message)" }
        return $null
    }
    
    # Remove any existing OA3.xml in the temp folder
    if (Test-Path $xmlPath) {
        Remove-Item $xmlPath -Force
    }
    
    # Verify that the copied tool exists
    if (-not (Test-Path $oa3ToolTemp)) {
        if ($ShowOutput) { Write-Host "oa3tool.exe not found in temp folder." }
        return $null
    }
    
    # Change working directory to TempDir before running the tool
    Push-Location $TempDir
    try {
        & $oa3ToolTemp /Report /ConfigFile:"$TempDir\OA3.cfg" /NoKeyCheck > $null 2>&1
    }
    catch {
        if ($ShowOutput) { Write-Host "Error running oa3tool.exe: $($_.Exception.Message)" }
        Pop-Location
        return $null
    }
    finally {
        Pop-Location
    }
    
    # Increase wait time to ensure file generation
    Start-Sleep -Seconds 5
    
    # Debug: list files in the temp folder
    if ($ShowOutput) {
        Write-Host "Files in $TempDir"
        Get-ChildItem -Path $TempDir | ForEach-Object { Write-Host $_.FullName }
    }
    
    if (-not (Test-Path $xmlPath)) {
        if ($ShowOutput) { Write-Host "OA3.xml not found in temp folder." }
        return $null
    }
    
    try {
        $rawContent = Get-Content -Path $xmlPath -Raw
        $firstTagIndex = $rawContent.IndexOf("<")
        if ($firstTagIndex -lt 0) { return $null }
        $xmlText = $rawContent.Substring($firstTagIndex)
        try {
            [xml]$xmlDoc = $xmlText
            $hashNode = $xmlDoc.SelectSingleNode("//*[contains(translate(local-name(), 'abcdefghijklmnopqrstuvwxyz', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'), 'HARDWAREHASH')]")
            if ($hashNode -and $hashNode.InnerText.Trim().Length -gt 0) {
                $hash = $hashNode.InnerText.Trim()
                if ($hash.StartsWith("T0") -and $hash.EndsWith("A")) {
                    return $hash
                }
                else {
                    $t0Index = $hash.IndexOf("T0")
                    if ($t0Index -ge 0 -and $hash.Length -ge ($t0Index + 4000)) {
                        $hashCandidate = $hash.Substring($t0Index, 4000)
                        if ($hashCandidate.StartsWith("T0") -and $hashCandidate.EndsWith("A")) {
                            return $hashCandidate
                        }
                    }
                }
            }
        }
        catch {
            # Fallback to regex extraction
        }
        $matches = [regex]::Matches($xmlText, '(?<!\S)[A-Za-z0-9+/=]{50,}(?!\S)')
        if ($matches.Count -gt 0) {
            $hash = $matches[0].Value.Trim()
            if ($hash.StartsWith("T0") -and $hash.EndsWith("A")) {
                return $hash
            }
            else {
                $t0Index = $hash.IndexOf("T0")
                if ($t0Index -ge 0 -and $hash.Length -ge ($t0Index + 4000)) {
                    $hashCandidate = $hash.Substring($t0Index, 4000)
                    if ($hashCandidate.StartsWith("T0") -and $hashCandidate.EndsWith("A")) {
                        return $hashCandidate
                    }
                }
            }
        }
    }
    catch {
        return $null
    }
    finally {
        Remove-Item $xmlPath -Force
    }
    
    return $null
}

function Get-CurrentSerialNumber {
    if ($ShowOutput) { Write-Host "Retrieving the device serial number..." }
    try {
        $serial = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber
        if ($ShowOutput) { Write-Host "Device Serial Number: $serial" }
        return $serial
    }
    catch {
        if ($ShowOutput) { Write-Host "Error retrieving Serial Number: $($_.Exception.Message)" }
        return $null
    }
}

function Get-Manufacturer {
    if ($ShowOutput) { Write-Host "Retrieving the device manufacturer..." }
    try {
        $manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer
        if ($ShowOutput) { Write-Host "Manufacturer reported as: $manufacturer" }
        switch -Wildcard ($manufacturer) {
            "Acer"                             { return 27 }
            "Dell Inc."                        { return 28 }
            "HP"                               { return 29 }
            "LENOVO"                           { return 30 }
            "Microsoft Corporation"            { return 31 }
            "ASUSTeK COMPUTER INC."            { return 32 }
            "Dynabook Inc."                    { return 33 }
            "Fujitsu"                          { return 34 }
            "FUJITSU CLIENT COMPUTING LIMITED" { return 34 }
            "FUJITSU"                          { return 34 }
            "GETAC"                            { return 35 }
            "Panasonic Corporation"            { return 36 }
            "SAMSUNG ELECTRONICS CO., LTD."    { return 51 }
            "SAMSUNG"                          { return 51 }


            default {
                if ($ShowOutput) { Write-Host "Unknown manufacturer: $manufacturer" }
                return 0
            }
        }
    }
    catch {
        if ($ShowOutput) { Write-Host "Error retrieving manufacturer: $($_.Exception.Message)" }
        return $null
    }
}

function Get-Model {
    if ($ShowOutput) { Write-Host "Retrieving the device model..." }
    try {
        $model = (Get-CimInstance -ClassName Win32_ComputerSystem).Model
        if ($ShowOutput) { Write-Host "Device Model: $model" }
        return $model
    }
    catch {
        if ($ShowOutput) { Write-Host "Error retrieving model name: $($_.Exception.Message)" }
        return $null
    }
}

###############################################################################
# Main Script Logic
###############################################################################

# Step 1: Gathering Data
Update-Progress "Gathering data..."

# Determine the script root
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if ($ShowOutput) { Write-Host "STEP 1.1: Getting SerialNumber." }
$SerialNumber = Get-CurrentSerialNumber

if ($ShowOutput) { Write-Host "STEP 1.2: Getting Manufacturer." }
$Manufacturer = Get-Manufacturer

if ($ShowOutput) { Write-Host "STEP 1.3: Getting Model." }
$Model = Get-Model

if ($ShowOutput) { Write-Host "STEP 1.4: Getting Hardware Hash." }
$HardwareHash = Get-HardwareHash -ScriptRoot $ScriptRoot

# Step 2: Building JSON
Update-Progress "Building JSON..."
$CurrentDate = (Get-Date -Format "yyyy-MM-dd")

# Prepare the API request header
$Headers = @{
    Authkey = $AuthKey
}
if ($ShowOutput) {
    Write-Host "Prepared request headers:"
    Write-Host ($Headers | Out-String)
}

# Build the request body based on available data.
# If a valid hardware hash is present, it is used; otherwise, the device serial,
# manufacturer, and model are posted.
if (-not $SerialNumber -or -not $HardwareHash) {
    if ($ShowOutput) { Write-Host "Mandatory data missing. Posting without hardware hash." }
    $Device = @{
        DeviceId      = $SerialNumber
        ManufactureId = $Manufacturer
        ModelName     = $Model
    }
}
else {
    if ($ShowOutput) { Write-Host "All mandatory data present. Posting with hardware hash." }
    $Device = @{
        DeviceId      = $SerialNumber
        ManufactureId = $Manufacturer
        HardwareHash  = $HardwareHash
    }
}

$Body = [ordered]@{
    CustomerId          = $Customer
    CountryId           = $Country
    UserEmail           = $User
    Devices             = @($Device)
    EnrollmentReference = $GroupTag
} | ConvertTo-Json -Depth 10

if ($ShowOutput) {
    Write-Host "Request body (JSON):"
    Write-Host $Body
}

# Step 3: Sending the request
Update-Progress "Sending POST request..."
$Uri = "https://ateadep.atea.com/Api/Enroll/WAP"

if ($ShowOutput) {
    Write-Host "POST URL: $Uri"
    Write-Host "POST payload: $Body"
}

# Attempt the POST request using multiple methods
$Response = $null
$success = $false

# Method 1: Invoke-RestMethod
try {
    if ($ShowOutput) { Write-Host "Method 1: Invoke-RestMethod" }
    $Response = Invoke-RestMethod -Uri $Uri -Method POST -Headers $Headers -Body $Body -ContentType "application/json"
    if ($ShowOutput) { Write-Host "Method 1 succeeded." }
    $success = $true
}
catch {
    if ($ShowOutput) { 
        Write-Host "Method 1 failed: $($_.Exception.Message)"
        Write-Host "Detailed error: $($_.Exception.ToString())"
    }
}

# Method 2: Invoke-WebRequest
if (-not $success) {
    try {
        if ($ShowOutput) { Write-Host "Method 2: Invoke-WebRequest" }
        $webResponse = Invoke-WebRequest -Uri $Uri -Method POST -Headers $Headers -Body $Body -ContentType "application/json"
        $Response = $webResponse.Content | ConvertFrom-Json
        if ($ShowOutput) { Write-Host "Method 2 succeeded." }
        $success = $true
    }
    catch {
        if ($ShowOutput) { 
            Write-Host "Method 2 failed: $($_.Exception.Message)"
            Write-Host "Detailed error: $($_.Exception.ToString())"
        }
    }
}

# Method 3: .NET HttpWebRequest
if (-not $success) {
    try {
        if ($ShowOutput) { Write-Host "Method 3: .NET HttpWebRequest" }
        $req = [System.Net.HttpWebRequest]::Create($Uri)
        $req.Method = "POST"
        $req.ContentType = "application/json"
        foreach ($key in $Headers.Keys) {
            $req.Headers.Add($key, $Headers[$key])
        }
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
        $req.ContentLength = $bodyBytes.Length
        $reqStream = $req.GetRequestStream()
        $reqStream.Write($bodyBytes, 0, $bodyBytes.Length)
        $reqStream.Close()
        $resp = $req.GetResponse()
        $streamReader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $respContent = $streamReader.ReadToEnd()
        $Response = $respContent | ConvertFrom-Json
        if ($ShowOutput) { Write-Host "Method 3 succeeded." }
        $success = $true
    }
    catch {
        if ($ShowOutput) { 
            Write-Host "Method 3 failed: $($_.Exception.Message)"
            Write-Host "Detailed error: $($_.Exception.ToString())"
        }
    }
}

# Method 4: System.Net.WebClient
if (-not $success) {
    try {
        if ($ShowOutput) { Write-Host "Method 4: System.Net.WebClient" }
        $wc = New-Object System.Net.WebClient
        $wc.Headers["Content-Type"] = "application/json"
        foreach ($key in $Headers.Keys) {
            $wc.Headers.Add($key, $Headers[$key])
        }
        $respContent = $wc.UploadString($Uri, "POST", $Body)
        $Response = $respContent | ConvertFrom-Json
        if ($ShowOutput) { Write-Host "Method 4 succeeded." }
        $success = $true
    }
    catch {
        if ($ShowOutput) { 
            Write-Host "Method 4 failed: $($_.Exception.Message)"
            Write-Host "Detailed error: $($_.Exception.ToString())"
        }
    }
}

# Method 5: System.Net.Http.HttpClient
if (-not $success) {
    try {
        if ($ShowOutput) { Write-Host "Method 5: System.Net.Http.HttpClient" }
        $client = New-Object System.Net.Http.HttpClient
        foreach ($key in $Headers.Keys) {
            $client.DefaultRequestHeaders.Add($key, $Headers[$key])
        }
        $content = New-Object System.Net.Http.StringContent($Body, [System.Text.Encoding]::UTF8, "application/json")
        $resultTask = $client.PostAsync($Uri, $content)
        $resultTask.Wait()
        $result = $resultTask.Result
        $readTask = $result.Content.ReadAsStringAsync()
        $readTask.Wait()
        $resultContent = $readTask.Result
        $Response = $resultContent | ConvertFrom-Json
        if ($ShowOutput) { Write-Host "Method 5 succeeded." }
        $success = $true
    }
    catch {
        if ($ShowOutput) { 
            Write-Host "Method 5 failed: $($_.Exception.Message)"
            Write-Host "Detailed error: $($_.Exception.ToString())"
        }
    }
}

if (-not $success) {
    Write-Error "All methods failed for enrollment POST request."
}
else {
    if ($ShowOutput) {
        Write-Host "Response received:"
        Write-Host ($Response | ConvertTo-Json -Depth 10)
    }
}


$dirPath = "C:\temp"
$path = "C:\temp\flag.txt"

if (!(Test-Path $dirPath)){
	New-Item -Path $dirPath -ItemType Directory -Force | Out-Null
}

if (!(Test-Path $path)){
	New-Item -Path $path -ItemType File -Force | Out-Null
	"Boot marker created on $(Get-Date)" | Out-File $path 

} else {
	Write-Host "Flag already exists"
}

# Step 4: Finish up
Update-Progress "Complete."
if ($ShowOutput) { Write-Host "Script finished." }
