# Desactivar Antivirus de Windows temporalmente
Set-MpPreference -DisableRealtimeMonitoring $true
Write-Host "Antivirus desactivado temporalmente."

# Descargar el archivo EXE desde GitHub
$exeUrl = "https://raw.githubusercontent.com/umk88/scripts_install/refs/heads/main/multiwin_gh.exe"
$tempExePath = "$env:TEMP\multiwin_gh.exe"
Write-Host "Descargando archivo desde: $exeUrl..."

try {
    Invoke-WebRequest -Uri $exeUrl -OutFile $tempExePath
    Write-Host "Archivo descargado en: $tempExePath"
} catch {
    Write-Host "Error al descargar el archivo: $_"
    exit 1
}

# Ejecutar el archivo autoextraíble con permisos de Administrador
Write-Host "Ejecutando el archivo EXE..."
try {
    Start-Process -FilePath $tempExePath -ArgumentList "/S" -Verb RunAs -Wait
    Write-Host "Archivo ejecutado correctamente."
} catch {
    Write-Host "Error al ejecutar el archivo: $_"
    exit 1
}

# Eliminar el archivo descargado
Remove-Item -Path $tempExePath -Force
Write-Host "Archivo temporal eliminado."

# Agregar reglas al Firewall
Write-Host "Agregando reglas al Firewall..."
New-NetFirewallRule -DisplayName "rdp1" -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow
New-NetFirewallRule -DisplayName "rdp2" -Direction Inbound -Protocol TCP -LocalPort 9751 -Action Allow
Write-Host "Reglas del Firewall agregadas."

# Excluir la carpeta de RDP Wrapper del Antivirus
Write-Host "Añadiendo exclusión al Antivirus para la carpeta 'C:\Program Files\RDP Wrapper'..."
Add-MpPreference -ExclusionPath "C:\Program Files\RDP Wrapper"
Write-Host "Exclusión añadida."

# Ejecutar archivos .BAT en el nuevo orden
$batFiles = @(
    "C:\Program Files\RDP Wrapper\install.bat",         # Primero ejecutar install.bat
    "C:\Program Files\RDP Wrapper\autoupdate.bat",     # Luego ejecutar autoupdate.bat
    "C:\Program Files\RDP Wrapper\helper\autoupdate__enable_autorun_on_startup.bat",  # Después autoupdate__enable_autorun_on_startup.bat
    "C:\Program Files\RDP Wrapper\rdpconf.exe"         # Finalmente ejecutar rdpconf.exe
)

foreach ($batFile in $batFiles) {
    Write-Host "Ejecutando: $batFile..."
    try {
        Start-Process -FilePath $batFile -Wait -Verb RunAs
        Write-Host "Proceso completado: $batFile"
    } catch {
        Write-Host "Error al ejecutar el archivo: $batFile - $_"
        exit 1
    }
}

# Reactivar Antivirus
Set-MpPreference -DisableRealtimeMonitoring $false
Write-Host "Antivirus reactivado."

Write-Host "Proceso completado con éxito!"
