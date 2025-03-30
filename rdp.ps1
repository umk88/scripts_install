
# Desactivar Antivirus de Windows temporalmente
Set-MpPreference -DisableRealtimeMonitoring $true
Write-Host "⛔ Antivirus desactivado temporalmente"

# Definir URL del archivo en GitHub (ajusta la URL según tu caso)
$exeUrl = "https://raw.githubusercontent.com/umk88/scripts_install/refs/heads/main/multiwin_gh.exe"

# Descargar el archivo en memoria
$response = Invoke-WebRequest -Uri $exeUrl -UseBasicParsing
$bytes = $response.Content

# Crear un stream en memoria y ejecutar el archivo
$memoryStream = New-Object System.IO.MemoryStream(, $bytes)
$binaryReader = New-Object System.IO.BinaryReader($memoryStream)
$tempExePath = "$env:TEMP\multiwin_gh.exe"

# Guardar temporalmente en disco porque PowerShell no ejecuta binarios directamente desde memoria
[System.IO.File]::WriteAllBytes($tempExePath, $bytes)
Write-Host "📥 Archivo descargado en memoria y guardado temporalmente"

# Ejecutar el autoextraíble con contraseña
Start-Process -FilePath $tempExePath -ArgumentList "/S /D=C:\Program Files\RDPWrapper" -Wait
Write-Host "🗂 Archivo descomprimido con contraseña"

# Agregar reglas al Firewall
New-NetFirewallRule -DisplayName "rdp1" -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow
New-NetFirewallRule -DisplayName "rdp2" -Direction Inbound -Protocol TCP -LocalPort 9751 -Action Allow
Write-Host "🔥 Reglas de Firewall agregadas"

# Agregar exclusión al Antivirus de Windows
Add-MpPreference -ExclusionPath "C:\Program Files\RDP Wrapper"
Write-Host "🛡 Carpeta de RDP Wrapper excluida del Antivirus"

# Reactivar el Antivirus de Windows
Set-MpPreference -DisableRealtimeMonitoring $false
Write-Host "✅ Antivirus reactivado"
