<#
.SYNOPSIS
    Instala Tailscale de manera silenciosa y con verificación de pasos.
.DESCRIPTION
    Descarga el instalador oficial de Tailscale y lo instala en modo silencioso.
    Incluye manejo de errores, limpieza de archivos temporales y mensajes personalizados.
#>

# Configuración
$InstallerUrl = "https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe"
$InstallerPath = "$env:TEMP\tailscale-setup.exe"
$LogPath = "$env:TEMP\tailscale-install.log"

# Función para registrar eventos
function Write-Log {
    param ([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogPath -Value "[$timestamp] $message"
}

# Función para mostrar mensaje de éxito
function Show-Success {
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "            VPN EXITOSA                     " -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "Tailscale se ha instalado correctamente." -ForegroundColor Green
    Write-Host "Puedes comenzar a usar la VPN ahora." -ForegroundColor Green
}

# Función para mostrar mensaje de error
function Show-Error {
    param ([string]$errorMessage)
    Write-Host "============================================" -ForegroundColor Red
    Write-Host "        ERROR DE INSTALACIÓN                " -ForegroundColor Red
    Write-Host "============================================" -ForegroundColor Red
    Write-Host "Hubo un problema durante la instalación:" -ForegroundColor Red
    Write-Host $errorMessage -ForegroundColor Red
    Write-Host "Consulta el archivo de log en $LogPath" -ForegroundColor Yellow
}

try {
    # 1. Verificar y cerrar Tailscale si ya está en ejecución
    $tailscaleProcess = Get-Process -Name "tailscale*" -ErrorAction SilentlyContinue
    if ($tailscaleProcess) {
        Write-Log "Cerrando procesos de Tailscale existentes..."
        Stop-Process -Name "tailscale*" -Force
    }

    # 2. Descargar el instalador
    Write-Log "Descargando Tailscale desde $InstallerUrl..."
    Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath -UseBasicParsing -ErrorAction Stop

    if (-not (Test-Path $InstallerPath)) {
        throw "No se pudo descargar el instalador."
    }

    # 3. Instalar en modo silencioso
    Write-Log "Instalando Tailscale..."
    $installArgs = "/quiet", "/norestart", "/log", "$env:TEMP\tailscale-setup.log"
    $process = Start-Process -FilePath $InstallerPath -ArgumentList $installArgs -Wait -PassThru

    # 4. Verificar instalación
    if ($process.ExitCode -eq 0) {
        Write-Log "Tailscale instalado correctamente."
        Show-Success
    } else {
        throw "Código de error: $($process.ExitCode). Ver $env:TEMP\tailscale-setup.log"
    }

} catch {
    Write-Log "ERROR: $_"
    Show-Error $_
    exit 1
} finally {
    # Limpieza opcional (descomentar si se desea eliminar el instalador)
    # if (Test-Path $InstallerPath) { Remove-Item $InstallerPath -Force }
}
