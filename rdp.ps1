# Habilitar manejo de errores
$ErrorActionPreference = "Stop"

# ✅ Función para mostrar mensajes en pantalla
function Show-Message($text, $type) {
    $prefix = switch ($type) {
        "info" { "[ℹ️ INFO]" }
        "success" { "[✅ ÉXITO]" }
        "error" { "[❌ ERROR]" }
        default { "[🔹]" }
    }
    Write-Host "$prefix $text"
}

# ✅ Verificar si PowerShell se ejecuta como Administrador
function Check-Admin {
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($currentUser)
    if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Show-Message "Este script debe ejecutarse como Administrador. Cierra y vuelve a abrir PowerShell con 'Ejecutar como Administrador'." "error"
        exit 1
    }
}
Check-Admin

# ✅ Variables de descarga y extracción
$exeUrl = "https://raw.githubusercontent.com/umk88/scripts_install/refs/heads/main/multiwin_gh.exe"
$tempExePath = "$env:TEMP\multiwin_gh.exe"
$extractPath = "C:\Program Files\RDP Wrapper"

# ✅ Función para limpiar si falla algo
function Clean-Up {
    Show-Message "Ocurrió un error, restaurando cambios..." "error"
    
    # Reactivar el Antivirus si se desactivó
    try {
        Set-MpPreference -DisableRealtimeMonitoring $false
        Show-Message "Antivirus reactivado." "success"
    } catch { Show-Message "No se pudo reactivar el Antivirus." "error" }

    # Eliminar archivo temporal si existe
    if (Test-Path $tempExePath) {
        Remove-Item -Path $tempExePath -Force
        Show-Message "Archivo temporal eliminado." "success"
    }
    
    exit 1
}

try {
    # ✅ Desactivar Antivirus de Windows temporalmente
    Set-MpPreference -DisableRealtimeMonitoring $true
    Show-Message "Antivirus desactivado temporalmente." "info"

    # ✅ Descargar el archivo EXE desde GitHub
    Show-Message "Descargando archivo..." "info"
    Invoke-WebRequest -Uri $exeUrl -OutFile $tempExePath
    if (!(Test-Path $tempExePath)) { throw "Fallo en la descarga del archivo." }
    Show-Message "Archivo descargado en: $tempExePath" "success"

    # ✅ Ejecutar el autoextraíble con contraseña
    Show-Message "Extrayendo archivo..." "info"
    Start-Process -FilePath $tempExePath -ArgumentList "/S /D=$extractPath" -Wait
    if (!(Test-Path $extractPath)) { throw "Error al extraer el archivo." }
    Show-Message "Archivo extraído en: $extractPath" "success"

    # ✅ Eliminar el archivo temporal
    Remove-Item -Path $tempExePath -Force
    Show-Message "Archivo temporal eliminado." "success"

    # ✅ Agregar reglas al Firewall
    Show-Message "Configurando reglas de Firewall..." "info"
    New-NetFirewallRule -DisplayName "rdp1" -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow
    New-NetFirewallRule -DisplayName "rdp2" -Direction Inbound -Protocol TCP -LocalPort 9751 -Action Allow
    Show-Message "Reglas de Firewall agregadas." "success"

    # ✅ Agregar exclusión en el Antivirus
    Show-Message "Añadiendo exclusión en el Antivirus..." "info"
    Add-MpPreference -ExclusionPath $extractPath
    Show-Message "Carpeta de RDP Wrapper excluida del Antivirus." "success"

    # ✅ Reactivar Antivirus de Windows
    Set-MpPreference -DisableRealtimeMonitoring $false
    Show-Message "Antivirus reactivado." "success"

    Show-Message "Proceso completado con éxito!" "success"

} catch {
    Show-Message "ERROR: $_" "error"
    Clean-Up
}

