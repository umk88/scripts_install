# 1. Verificar si se ejecuta como Administrador
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Por favor, ejecuta este script como Administrador."
    Read-Host "Presiona Enter para salir..."
    exit
}

# Configurar el título de la ventana y la codificación
$host.UI.RawUI.WindowTitle = "Reset AnyDesk"
[Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(437)

# Definir funciones de parada y arranque
function Stop-AnyDesk {
    Write-Host "Deteniendo servicio y procesos de AnyDesk..."
    Stop-Service -Name "AnyDesk" -Force -ErrorAction SilentlyContinue
    Stop-Process -Name "AnyDesk" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}

function Start-AnyDesk {
    Write-Host "Iniciando servicio de AnyDesk..."
    Start-Service -Name "AnyDesk" -ErrorAction SilentlyContinue
    
    # Buscar el ejecutable e iniciarlo
    $paths = @(
        "${env:SystemDrive}\Program Files (x86)\AnyDesk\AnyDesk.exe",
        "${env:SystemDrive}\Program Files\AnyDesk\AnyDesk.exe"
    )
    foreach ($path in $paths) {
        if (Test-Path $path) {
            Start-Process $path
            break
        }
    }
}

# --- PROCESO PRINCIPAL ---

# 2. Detener AnyDesk
Stop-AnyDesk

# 3. Guardar configuraciones de usuario temporales
$anydeskAppData = "${env:APPDATA}\AnyDesk"
$anydeskProgramData = "${env:ProgramData}\AnyDesk" # Equivalente a %ALLUSERSPROFILE%
$tempDir = [System.IO.Path]::GetTempPath()

if (Test-Path "$anydeskAppData\user.conf") {
    Copy-Item -Path "$anydeskAppData\user.conf" -Destination $tempDir -Force
}

if (Test-Path "$anydeskAppData\thumbnails") {
    $tempThumbnails = Join-Path $tempDir "thumbnails"
    Remove-Item -Path $tempThumbnails -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item -Path "$anydeskAppData\thumbnails" -Destination $tempThumbnails -Recurse -Force
}

# 4. Limpiar carpetas de AnyDesk (Borrando IDs y licencias viejas)
if (Test-Path $anydeskProgramData) {
    Get-ChildItem -Path $anydeskProgramData -Recurse | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
}
if (Test-Path $anydeskAppData) {
    Get-ChildItem -Path $anydeskAppData -Recurse | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
}

# 5. Iniciar AnyDesk para que genere el nuevo ID del sistema
Start-AnyDesk

# 6. Esperar a que AnyDesk genere el archivo 'system.conf' con el nuevo ID (Reemplaza al bucle :lic)
$systemConfPath = "$anydeskProgramData\system.conf"
Write-Host "Esperando a que AnyDesk genere el nuevo ID..."
while (-not (Test-Path $systemConfPath)) { Start-Sleep -Milliseconds 500 }

# Esperar a que el archivo tenga contenido real con el ID asignado
while (-not (Select-String -Path $systemConfPath -Pattern "ad.anynet.id=")) { Start-Sleep -Milliseconds 500 }

# 7. Volver a apagar para restaurar tus datos de usuario (direcciones recientes, etc.)
Stop-AnyDesk

# Restaurar user.conf y miniaturas
if (Test-Path "$tempDir\user.conf") {
    if (-not (Test-Path $anydeskAppData)) { New-Item -ItemType Directory -Path $anydeskAppData -Force > $null }
    Move-Item -Path "$tempDir\user.conf" -Destination "$anydeskAppData\user.conf" -Force
}

if (Test-Path "$tempDir\thumbnails") {
    Copy-Item -Path "$tempDir\thumbnails" -Destination "$anydeskAppData\thumbnails" -Recurse -Force
    Remove-Item -Path "$tempDir\thumbnails" -Recurse -Force -ErrorAction SilentlyContinue
}

# 8. Encender AnyDesk de forma definitiva con el ID reseteado
Start-AnyDesk

Write-Host "*********" -ForegroundColor Green
Write-Host "Completed." -ForegroundColor Green
Write-Host ""
