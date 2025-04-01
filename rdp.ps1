# Desactivar Antivirus de Windows temporalmente
Set-MpPreference -DisableRealtimeMonitoring $true
Write-Host "Antivirus desactivado temporalmente."

# Descargar el archivo EXE desde GitHub
$exeUrl = "https://raw.githubusercontent.com/umk88/scripts_install/refs/heads/main/multiwin_gh.exe"
$tempExePath = "$env:TEMP\multiwin_gh.exe"
Write-Host "Descargando archivo..."

try {
    Invoke-WebRequest -Uri $exeUrl -OutFile $tempExePath
    Write-Host "Archivo descargado"
} catch {
    Write-Host "Error al descargar el archivo"
    exit 1
}

# Ejecutar el archivo autoextraíble con permisos de Administrador
Write-Host "Ejecutando el archivo..."
try {
    Start-Process -FilePath $tempExePath -ArgumentList "/S" -Verb RunAs -Wait
    Write-Host "OK."
} catch {
    Write-Host "Error al ejecutar el archivo: "
    exit 1
}

# Eliminar el archivo descargado
Remove-Item -Path $tempExePath -Force
Write-Host "Archivo temporal eliminado."

# Agregar reglas al Firewall
Write-Host "Firewall..." -NoNewline
New-NetFirewallRule -DisplayName "rdp1" -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow -ErrorAction SilentlyContinue | Out-Null
Write-Host " OK"

# Excluir la carpeta de RDP Wrapper del Antivirus
Write-Host "Exclusiones AV..."
Add-MpPreference -ExclusionPath "C:\Program Files\RDP Wrapper"
Write-Host "OK"

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
Write-Host "Antivirus reactivado OK."

function Disable-WindowsUpdate {
    Write-Host "Deshabilitando Windows Update..."
    
    # Detiene el servicio Windows Update
    Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
    
    # Cambia el tipo de inicio a 'Deshabilitado'
    Set-Service -Name wuauserv -StartupType Disabled
    
    # Configura la recuperación para que no intente reiniciarse
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\wuauserv"
    Set-ItemProperty -Path $regPath -Name "FailureActions" -Value ([byte[]](60,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
    
    Write-Host "OK."
}

# Llamar a la función
Disable-WindowsUpdate

Write-Host "---Proceso terminado---"
