# Define la URL de descarga (verifica que sea la versión más actualizada)
$rdpUrl = "https://github.com/stascorp/rdpwrap/releases/latest/download/rdpwrap.zip"
$downloadPath = "$env:TEMP\rdpwrap.zip"
$extractPath = "$env:TEMP\rdpwrap"

# Descargar el archivo ZIP
Invoke-WebRequest -Uri $rdpUrl -OutFile $downloadPath

# Crear carpeta temporal y extraer
Expand-Archive -Path $downloadPath -DestinationPath $extractPath -Force

# Cambiar a la carpeta extraída
Set-Location -Path $extractPath

# Instalar RDP Wrapper
Start-Process -FilePath "install.bat" -Verb RunAs -Wait

# Iniciar el servicio RDP si no está corriendo
Restart-Service TermService -Force

Write-Host "✅ Instalación completada. Ejecuta 'RDPConf.exe' para verificar el estado."
