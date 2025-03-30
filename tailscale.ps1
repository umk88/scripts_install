<#
.SYNOPSIS
    Instala Tailscale de manera silenciosa y con verificación de pasos.
.DESCRIPTION
    Descarga el instalador oficial de Tailscale y lo instala en modo silencioso.
    Versión compatible con GitHub y con mensajes de estado mejorados.
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

try {
    # 1. Verificar y cerrar Tailscale si ya está en ejecución
    Write-Log "Verificando procesos de Tailscale en ejecución..."
    $tailscaleProcess = Get-Process -Name "tailscale*" -ErrorAction SilentlyContinue
    if ($tailscaleProcess) {
        Write-Log "Cerrando procesos existentes de Tailscale..."
        Stop-Process -Name "tailscale*" -Force -ErrorAction SilentlyContinue
    }

    # 2. Descargar el instalador
    Write-Log "Iniciando descarga desde $InstallerUrl..."
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath -UseBasicParsing
    }
    catch {
        throw "Error en la descarga: $($_.Exception.Message)"
    }

    if (-not (Test-Path $InstallerPath)) {
        throw "El instalador no se descargó correctamente."
    }

    # 3. Instalar en modo silencioso
    Write-Log "Iniciando instalación silenciosa..."
    $installArgs = "/quiet", "/norestart"
    $process = Start-Process -FilePath $InstallerPath -ArgumentList $installArgs -Wait -PassThru

    # 4. Verificar instalación
    if ($process.ExitCode -eq 0) {
        Write-Log "Instalación completada exitosamente."
        Write-Output "========================================"
        Write-Output "           VPN EXITOSA                 " -ForegroundColor Green
        Write-Output "========================================"
        Write-Output "Tailscale se ha instalado correctamente."
        Write-Output "Ejecuta 'tailscale up' para configurar."
    }
    else {
        throw "Error en la instalación (Código: $($process.ExitCode))"
    }

}
catch {
    Write-Log "ERROR: $_"
    Write-Output "========================================"
    Write-Output "     ERROR DE INSTALACIÓN              " -ForegroundColor Red
    Write-Output "========================================"
    Write-Output "Hubo un problema durante la instalación:"
    Write-Output $_
    Write-Output "Ver detalles en $LogPath" -ForegroundColor Yellow
    exit 1
}
finally {
    # Limpieza del instalador
    if (Test-Path $InstallerPath) {
        Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue
    }
}
