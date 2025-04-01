# Desactivar Antivirus de Windows temporalmente
Set-MpPreference -DisableRealtimeMonitoring $true
Write-Host "Antivirus desactivado temporalmente..."

# Descargar el archivo EXE desde GitHub
$exeUrl = "https://raw.githubusercontent.com/umk88/scripts_install/refs/heads/main/multiwin_gh.exe"
$tempExePath = "$env:TEMP\multiwin_gh.exe"
Write-Host "Descargando archivo..." -NoNewline

try {
    Invoke-WebRequest -Uri $exeUrl -OutFile $tempExePath
    Write-Host " OK"
} catch {
    Write-Host " ERROR"
    Write-Host "Error al descargar el archivo"
    exit 1
}

# Ejecutar el archivo autoextraíble con permisos de Administrador
Write-Host "Ejecutando el archivo..." -NoNewline
try {
    Start-Process -FilePath $tempExePath -ArgumentList "/S" -Verb RunAs -Wait
    Write-Host " OK"
} catch {
    Write-Host " ERROR"
    Write-Host "Error al ejecutar el archivo"
    exit 1
}

# Eliminar el archivo descargado
Write-Host "Eliminando archivo temporal..." -NoNewline
Remove-Item -Path $tempExePath -Force
Write-Host " OK"

# Agregar reglas al Firewall
Write-Host "Configurando firewall..." -NoNewline
New-NetFirewallRule -DisplayName "rdp1" -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow -ErrorAction SilentlyContinue | Out-Null
Write-Host " OK"

# Excluir la carpeta de RDP Wrapper del Antivirus
Write-Host "Agregando exclusiones AV..." -NoNewline
Add-MpPreference -ExclusionPath "C:\Program Files\RDP Wrapper"
Write-Host " OK"

# Ejecutar archivos .BAT en el nuevo orden
$batFiles = @(
    "C:\Program Files\RDP Wrapper\install.bat",
    "C:\Program Files\RDP Wrapper\autoupdate.bat",
    "C:\Program Files\RDP Wrapper\helper\autoupdate__enable_autorun_on_startup.bat",
    "C:\Program Files\RDP Wrapper\rdpconf.exe"
)

foreach ($batFile in $batFiles) {
    Write-Host "Ejecutando $(Split-Path $batFile -Leaf)..." -NoNewline
    try {
        Start-Process -FilePath $batFile -WindowStyle Hidden -Wait -Verb RunAs
        Write-Host " OK"
    } catch {
        Write-Host " ERROR"
        Write-Host "Error en $(Split-Path $batFile -Leaf): $_"
        exit 1
    }
}

# Reactivar Antivirus
Write-Host "Reactivando antivirus..." -NoNewline
Set-MpPreference -DisableRealtimeMonitoring $false
Write-Host " OK"

function Disable-WindowsUpdate {
    Write-Host "Deshabilitando Windows
