<#
.SYNOPSIS
    Descarga e instala SyncBack Touch silenciosamente, configurando el puerto 36369.
.DESCRIPTION
    Automatiza la instalación de SyncBack Touch con parámetros personalizados.
    Requiere permisos de administrador.
#>

# Configuración
$downloadUrl = "https://www.2brightsparks.com/assets/software/SyncBackTouch_Setup.exe"
$installerPath = "$env:TEMP\SyncBackTouch_Setup.exe"
$port = "36369"  # Puerto personalizado

# Descargar el instalador
try {
    Write-Host "Descargando SB Touch..."
    Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -ErrorAction Stop
    Write-Host "Descarga completada!" -ForegroundColor Green
}
catch {
    Write-Host "Error al descargar: $_" -ForegroundColor Red
    exit 1
}

# Instalar con parámetros silenciosos y cambiar el puerto
try {
    Write-Host "Instalando SB Touch (puerto $port)..."
    $arguments = "/verysilent /SBFS_Port=`"$port`""
    Start-Process -FilePath $installerPath -ArgumentList $arguments -Wait -NoNewWindow

    # Verificar instalación (opcional)
    $service = Get-Service -Name "SyncBackTouch" -ErrorAction SilentlyContinue
    if ($service) {
        Write-Host "SB Touch instalado. Puerto: $port" -ForegroundColor Green
    }
    else {
        Write-Host "SB Touch se instaló, pero el servicio no se detectó." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "Error durante la instalación: $_" -ForegroundColor Red
    exit 1
}

# Limpiar instalador (opcional)
Remove-Item -Path $installerPath -Force
