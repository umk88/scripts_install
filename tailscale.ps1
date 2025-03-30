<#
.SYNOPSIS
    Instala Tailscale de manera silenciosa con mensajes visuales personalizados.
.DESCRIPTION
    Descarga e instala Tailscale, muestra el logo "UMK" durante la instalación,
    y notifica claramente si fue exitosa o falló.
#>

# Configuración
$InstallerUrl = "https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe"
$InstallerPath = "$env:TEMP\tailscale-setup.exe"
$LogPath = "$env:TEMP\tailscale-install.log"

# Función para mostrar el logo "UMK"
function Show-UMKLogo {
    Write-Host @"
  _   _ __  __ _    
 | | | |  \/  | |   
 | | | | |\/| | |   
 | |_| | |  | | |___
  \___/|_|  |_|_____|
"@ -ForegroundColor Cyan
    Write-Host "`nInstalando Tailscale, por favor espere...`n" -ForegroundColor White
}

# Función para registrar eventos
function Write-Log {
    param ([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogPath -Value "[$timestamp] $message"
}

# Mostrar logo al inicio
Clear-Host
Show-UMKLogo

try {
    # 1. Cerrar Tailscale si está en ejecución
    $tailscaleProcess = Get-Process -Name "tailscale*" -ErrorAction SilentlyContinue
    if ($tailscaleProcess) {
        Write-Log "Cerrando procesos existentes de Tailscale..."
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
        Write-Log "Instalación exitosa."
        Clear-Host
        Write-Host @"
  _   _ __  __ _      ✅ TAILSCALE INSTALADO CORRECTAMENTE
 | | | |  \/  | |     ----------------------------------
 | | | | |\/| | |     Ahora puedes configurar Tailscale con:
 | |_| | |  | | |___    tailscale up
  \___/|_|  |_|_____|   
"@ -ForegroundColor Green
    } else {
        throw "Error en la instalación (Código: $($process.ExitCode)). Ver $env:TEMP\tailscale-setup.log"
    }

} catch {
    Write-Log "ERROR: $_"
    Clear-Host
    Write-Host @"
  _   _ __  __ _      ❌ ERROR EN LA INSTALACIÓN
 | | | |  \/  | |     -------------------------
 | | | | |\/| | |     $_ 
 | |_| | |  | | |___   Consulta el log en $LogPath
  \___/|_|  |_|_____|  
"@ -ForegroundColor Red
    exit 1
} finally {
    # Limpieza opcional
    if (Test-Path $InstallerPath) { Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue }
}
