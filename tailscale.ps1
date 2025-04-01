<#
.SYNOPSIS
    Instala Tailscale con modo unattended habilitado permanentemente.
.DESCRIPTION
    Instala Tailscale y configura el modo unattended tanto en la instalación
    como en el servicio para operación completamente automatizada.
#>

# Configuración
$InstallerUrl = "https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe"
$InstallerPath = "$env:TEMP\tailscale-setup.exe"
$LogPath = "$env:TEMP\tailscale-install.log"

# Mostrar logo
function Show-UnamarkLogo {
    Write-Host @"
  _   _   _  _     _     __  __     _     ___   _  __
 | | | | | \| |   /_\   |  \/  |   /_\   | _ \ | |/ /
 | |_| | | .` |  / _ \  | |\/| |  / _ \  |   / | ' < 
  \___/  |_|\_| /_/ \_\ |_|  |_| /_/ \_\ |_|_\ |_|\_\
"@ -ForegroundColor White
    Write-Host "`nInstalando VPN (Modo Unattended)...`n" -ForegroundColor White
}

# Registrar eventos
function Write-Log {
    param ([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogPath -Value "[$timestamp] $message"
}

# Inicio
Clear-Host
Show-UnamarkLogo

try {
    # 1. Cerrar Tailscale si está en ejecución
    Get-Process -Name "tailscale*" -ErrorAction SilentlyContinue | Stop-Process -Force
    Write-Log "Procesos existentes cerrados"

    # 2. Descargar instalador
    Write-Log "Descargando instalador..."
    Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath -UseBasicParsing -ErrorAction Stop

    # 3. Instalar con parámetros unattended
    Write-Log "Instalando en modo unattended..."
    $installArgs = @(
        "/quiet",
        "/norestart",
        "EXE_OPTS=--unattended",
        "ACCEPT_EULA=1"
    )
    $process = Start-Process -FilePath $InstallerPath -ArgumentList $installArgs -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        throw "Error en instalación (Código $($process.ExitCode))"
    }

    # 4. Configuración adicional post-instalación
    Write-Log "Configurando servicio..."
    & "C:\Program Files\Tailscale\tailscale.exe" set --unattended | Out-Null
    Set-Service -Name "Tailscale" -StartupType Automatic -ErrorAction SilentlyContinue

    # 5. Verificación final
    $unattendedStatus = & "C:\Program Files\Tailscale\tailscale.exe" status --json | ConvertFrom-Json
    if (-not $unattendedStatus.UnattendedMode) {
        throw "El modo unattended no se activó correctamente"
    }

    Write-Log "Configuración unattended confirmada"
    Write-Host "✅ Tailscale instalado en modo unattended" -ForegroundColor Green

} catch {
    Write-Log "ERROR: $_"
    Write-Host "❌ Error en la instalación: $_" -ForegroundColor Red
    exit 1
} finally {
    if (Test-Path $InstallerPath) { Remove-Item $InstallerPath -Force }
}
