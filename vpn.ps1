<#
.SYNOPSIS
    Instala Tailscale de manera silenciosa y con verificación de pasos.
.DESCRIPTION
    Descarga el instalador oficial de Tailscale y lo instala en modo silencioso.
    Incluye manejo de errores y limpieza de archivos temporales.
    Configura el modo "unattended" para operación sin supervisión.
#>

# Configuración
$InstallerUrl = "https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe"
$InstallerPath = "$env:TEMP\tailscale-setup.exe"
$LogPath = "$env:TEMP\tailscale-install.log"

# Función para mostrar el nuevo logo
function Show-UnamarkLogo {
    Write-Host @"
  _   _   _  _     _     __  __     _     ___   _  __
 | | | | | \| |   /_\   |  \/  |   /_\   | _ \ | |/ /
 | |_| | | .` |  / _ \  | |\/| |  / _ \  |   / | ' < 
  \___/  |_|\_| /_/ \_\ |_|  |_| /_/ \_\ |_|_\ |_|\_\
"@ -ForegroundColor White
    Write-Host "`nInstalando VPN, por favor espere...`n" -ForegroundColor White
}

# Función para registrar eventos
function Write-Log {
    param ([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogPath -Value "[$timestamp] $message"
}

# Mostrar logo al inicio
Clear-Host
Show-UnamarkLogo

try {
    # 1. Verificar y cerrar Tailscale si ya está en ejecución
    $vpnProcess = Get-Process -Name "tailscale*" -ErrorAction SilentlyContinue
    if ($vpnProcess) {
        Write-Log "Cerrando procesos de VPN existentes..."
        Stop-Process -Name "tailscale*" -Force
    }

    # 2. Descargar el instalador
    Write-Log "Descargando VPN desde $InstallerUrl..."
    Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath -UseBasicParsing -ErrorAction Stop

    if (-not (Test-Path $InstallerPath)) {
        throw "Error: No se pudo descargar el instalador."
    }

    # 3. Instalar en modo silencioso con unattended
    Write-Log "VPN unattended..."
    $installArgs = "/quiet", "/norestart", "/log", "$env:TEMP\tailscale-setup.log", "UNATTENDED=1", "EXE_OPTS=--unattended"
    $process = Start-Process -FilePath $InstallerPath -ArgumentList $installArgs -Wait -PassThru

    # 4. Verificar instalación
    if ($process.ExitCode -eq 0) {
        Write-Log "VPN unattended OK."
        Clear-Host
        Show-UnamarkLogo
        Write-Host "✅ VPN Exitosa" -ForegroundColor Green
    } else {
        throw "Error durante la instalación (Código: $($process.ExitCode)). Ver $env:TEMP\tailscale-setup.log"
    }

} catch {
    Write-Log "ERROR: $_"
    Clear-Host
    Show-UnamarkLogo
    Write-Host "❌ Hubo un error en la instalación" -ForegroundColor Red
    Write-Host "Detalles: $_" -ForegroundColor Yellow
    exit 1
} finally {
    # Limpieza opcional (descomentar si se desea eliminar el instalador)
    # if (Test-Path $InstallerPath) { Remove-Item $InstallerPath -Force }
}
