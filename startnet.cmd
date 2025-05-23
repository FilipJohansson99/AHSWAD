@echo off
setlocal

set "iso1=X:\Windows\System32\LOG_BDE_7.14_bmp.iso"
set "iso2=X:\Windows\System32\BDE 7.15.0.iso"

if exist "%iso1%" (
    set "iso=%iso1%"
) else if exist "%iso2%" (
    set "iso=%iso2%"
) else (
    echo No ISO file found.
    exit /b 1
)

:: Uncomment to run PowerShell script
:: powershell.exe -NoProfile -ExecutionPolicy Bypass -File "Z\Invoke-AEPWAD.ps1"

Start-Process -FilePath "X:\Windows\System32\BlanccoPreInstall.exe" -ArgumentList "--image=""%iso%""", "--reboot", "--force" -NoNewWindow

echo OK
endlocal
