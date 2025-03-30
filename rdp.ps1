# ✅ 1. Desactivar Windows Defender temporalmente
Set-MpPreference -DisableRealtimeMonitoring $true
Write-Host "⛔ Antivirus desactivado temporalmente"

# ✅ 2. Definir URL y rutas de trabajo
$exeUrl = "https://raw.githubusercontent.com/umk88/scripts_install/refs/heads/main/multiwin_gh.exe"
$tempExePath = "$env:TEMP\multiwin_gh.exe"
$extractPath = "C:\Program Files\RDP Wrapper"

# ✅ 3. Descargar el archivo EXE desde GitHub
Invoke-WebRequest -Uri $exeUrl -OutFile $tempExePath
Write-Host "📥 Archivo descargado en: $tempExePath"

# ✅ 4. Ejecutar el autoextraíble con contraseña (ajustar si es necesario)
Start-Process -FilePath $tempExePath -ArgumentList "/S /D=$extractPath" -Wait
Write-Host "🗂 Archivo extraído en: $extractPath"

# ✅ 5. Eliminar el archivo temporal
Remove-Item -Path $tempExePath -Force
Write-Host "🗑 Archivo temporal eliminado"

# ✅ 6. Agregar reglas al Firewall
New-NetFirewallRule -DisplayName "rdp1" -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow
New-NetFirewallRule -DisplayName "rdp2" -Direction Inbound -Protocol TCP -LocalPort 9751 -Action Allow
Write-Host "🔥 Reglas de Firewall agregadas"

# ✅ 7. Agregar exclusión de antivirus para la carpeta de RDP Wrapper
Add-MpPreference -ExclusionPath $extractPath
Write-Host "🛡 Carpeta de RDP Wrapper excluida del Antivirus"

# ✅ 8. Reactivar Windows Defender
Set-MpPreference -DisableRealtimeMonitoring $false
Write-Host "✅ Antivirus reactivado"

