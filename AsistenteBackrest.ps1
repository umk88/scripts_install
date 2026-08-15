# ==============================================================================
# ASISTENTE DE CONFIGURACION SQL SERVER + BACKREST (MULTI-INSTANCIA)
# ==============================================================================
# Pasos 1 a 4: deteccion, analisis, prueba de dump y generacion de scripts.
# Paso 5 (nuevo): genera el config.json de Backrest (repo + plan + known host).
# ==============================================================================

# Variables globales de estado (Manejo de múltiples instancias)
$global:instanciasConfiguradas = @()

# Ruta del config.json de Backrest (corre como SYSTEM -> perfil de systemprofile)
$global:BackrestConfigPath = "C:\Windows\System32\config\systemprofile\AppData\Roaming\backrest\config.json"

# Credenciales de la web de Backrest (iguales para todos los clientes).
# passwordBcrypt = base64( bcrypt("Rosario.1988!Bkp-") ). Si cambias la contrasena,
# generá el hash nuevo desde la UI de Backrest (Settings -> Users) y pegalo aca.
$global:AuthUser   = "nomada"
$global:AuthBcrypt = "JDJhJDEwJEViM2NnNDV5dEdVTWs0M0ZTNzBkL3VONmlJaDFLNlpOL1preDRxWjR1QzRFRE43Y0N6RUNx"

# Contraseña web en texto plano (para copiar al portapapeles al abrir el navegador).
$global:AuthPassPlain = "Rosario.1988!Bkp-"

# Contraseña de encriptación por default de los repositorios (restic). Comilla incluida.
$global:RepoDefaultPass = '#enPpkZ{X"ut5+r%?pQP{dMVJn*WCJe*'

# --- Función Auxiliar para Ejecutar Consultas SQL ---
function Exec-SqlQuery {
    param (
        [string]$Server,
        [string]$AuthType,
        [string]$User,
        [string]$Password,
        [string]$Query
    )

    $sqlcmd = "sqlcmd.exe"
    if (-not (Get-Command $sqlcmd -ErrorAction SilentlyContinue)) {
        Write-Host "ERROR: No se encontró 'sqlcmd.exe' en el sistema." -ForegroundColor Red
        return $null
    }

    if ($AuthType -eq "2") {
        $result = & $sqlcmd -S "$Server" -U "$User" -P "$Password" -Q "$Query" -W -h -1 2>&1
    } else {
        $result = & $sqlcmd -S "$Server" -E -Q "$Query" -W -h -1 2>&1
    }

    return $result
}

# --- ¿Corremos como administrador? (necesario para tocar el config.json y la tarea) ---
function Test-Admin {
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object System.Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

# --- Lee una contraseña OCULTA y la devuelve en texto plano (para pasarla a sqlcmd) ---
function Read-PasswordPlain {
    param([string]$Prompt)
    $sec = Read-Host $Prompt -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

# --- Credenciales EFECTIVAS para operaciones que necesitan sysadmin de SQL ---
# Si la instancia es Windows auth pero se ingresaron credenciales elevadas (sa),
# usa esas; si no, usa las credenciales normales de la instancia.
function Get-EffectiveAuth {
    param($InstObj)
    if ($InstObj.AuthOpcion -eq "1" -and -not [string]::IsNullOrWhiteSpace($InstObj.ElevatedPass)) {
        return @{ Auth = "2"; User = $InstObj.ElevatedUser; Pass = $InstObj.ElevatedPass }
    }
    return @{ Auth = $InstObj.AuthOpcion; User = $InstObj.User; Pass = $InstObj.Pass }
}

# --- Nombre de la cuenta de servicio de Windows de una instancia SQL ---
# SQL escribe los .bak con SU cuenta de servicio (NT SERVICE\MSSQL$<instancia>),
# no con la tuya ni con SYSTEM. Derivamos ese nombre desde cualquier formato de
# server: ".\WYNGES", "SERVER-EPAQ\WYNGES", ".\MSSQLSERVER", "localhost", etc.
function Get-SqlServiceName {
    param([string]$Server)
    $inst = "$Server".Trim()
    if ($inst -match '\\') {
        # host\instancia  ->  me quedo con la instancia (lo que va despues del ultimo \)
        $inst = $inst.Substring($inst.LastIndexOf('\') + 1)
    } else {
        # sin "\" es una instancia default (solo host/alias)
        $inst = 'MSSQLSERVER'
    }
    if ([string]::IsNullOrWhiteSpace($inst) -or $inst -ieq 'MSSQLSERVER') {
        return 'MSSQLSERVER'
    }
    return 'MSSQL$' + $inst
}

# --- Extraer el campo "id" (guid) de la salida JSON de restic ---
# Robusto: aisla el objeto { ... } aunque haya lineas de warning alrededor.
function Get-GuidFromResticOutput {
    param($Salida)
    $joined = ($Salida | Out-String)
    $s = $joined.IndexOf('{')
    $e = $joined.LastIndexOf('}')
    if ($s -lt 0 -or $e -le $s) { return $null }
    try { return ($joined.Substring($s, $e - $s + 1) | ConvertFrom-Json).id } catch { return $null }
}

# --- Escapar un valor para meterlo dentro de un string JSON ---
function Esc-Json {
    param([string]$s)
    if ($null -eq $s) { return "" }
    return $s.Replace('\', '\\').Replace('"', '\"')
}

# --- Reiniciar Backrest (tarea programada, corre como SYSTEM) ---
function Restart-Backrest {
    Write-Host "Deteniendo Backrest..." -ForegroundColor Yellow
    try { Stop-ScheduledTask -TaskName "Backrest" -ErrorAction Stop } catch { Write-Host "  (no se pudo detener la tarea: $($_.Exception.Message))" -ForegroundColor DarkYellow }
    Start-Sleep -Seconds 3
    Get-Process backrest -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Host "Arrancando Backrest..." -ForegroundColor Yellow
    try { Start-ScheduledTask -TaskName "Backrest" -ErrorAction Stop } catch { Write-Host "  (no se pudo arrancar la tarea: $($_.Exception.Message))" -ForegroundColor Red }
    Start-Sleep -Seconds 3
    $estado = (Get-ScheduledTask -TaskName "Backrest" -ErrorAction SilentlyContinue).State
    Write-Host "Estado de la tarea Backrest: $estado" -ForegroundColor Cyan
}

# ==============================================================================
# HELPERS DE CONSTRUCCION (bloques de repo y plan, e init de repo con restic)
# ==============================================================================
# Renderiza un array de strings como array JSON. Vacio -> []. No vacio -> multilinea.
function Format-JsonStrArray {
    param([string[]]$Items, [int]$Indent)
    if (-not $Items -or $Items.Count -eq 0) { return "[]" }
    $pad = ' ' * ($Indent + 2)
    $inner = ($Items | ForEach-Object { $pad + '"' + (Esc-Json $_) + '"' }) -join ",`n"
    $padClose = ' ' * $Indent
    return "[`n$inner`n$padClose]"
}

# Bloque JSON de UN repo (identico para sql o files, solo cambian id/uri/guid).
function New-RepoBlock {
    param([string]$Id, [string]$Uri, [string]$RepoPass, [string]$AwsId, [string]$AwsSecret, [string]$Guid)
    return @"
    {
      "id": "$(Esc-Json $Id)",
      "uri": "$(Esc-Json $Uri)",
      "password": "$(Esc-Json $RepoPass)",
      "env": [
        "AWS_ACCESS_KEY_ID=$(Esc-Json $AwsId)",
        "AWS_SECRET_ACCESS_KEY=$(Esc-Json $AwsSecret)"
      ],
      "guid": "$(Esc-Json $Guid)",
      "autoUnlock": true,
      "prunePolicy": {
        "schedule": { "cron": "0 0 1 * *", "clock": "CLOCK_LAST_RUN_TIME" },
        "maxUnusedPercent": 10
      },
      "checkPolicy": {
        "schedule": { "cron": "0 0 1 * *", "clock": "CLOCK_LAST_RUN_TIME" }
      },
      "commandPrefix": {},
      "shared": true,
      "forgetPolicy": {
        "schedule": { "disabled": true, "clock": "CLOCK_LAST_RUN_TIME" },
        "retention": { "policyTimeBucketed": { "hourly": 24, "daily": 30, "monthly": 12 } }
      }
    }
"@
}

# Bloque JSON de UN plan. Excludes y HookCommand son opcionales.
function New-PlanBlock {
    param([string]$Id, [string]$Repo, [string[]]$Paths, [string[]]$Excludes, [string]$Cron, [string]$HookCommand)
    $pathsVal = Format-JsonStrArray $Paths 6
    $excludesVal = Format-JsonStrArray $Excludes 6
    if (-not [string]::IsNullOrWhiteSpace($HookCommand)) {
        $hooksVal = @"
[
        {
          "conditions": [ "CONDITION_SNAPSHOT_START" ],
          "onError": "ON_ERROR_FATAL",
          "actionCommand": {
            "command": "$(Esc-Json $HookCommand)"
          }
        }
      ]
"@
    } else {
        $hooksVal = "[]"
    }
    return @"
    {
      "id": "$(Esc-Json $Id)",
      "repo": "$(Esc-Json $Repo)",
      "paths": $pathsVal,
      "excludes": $excludesVal,
      "schedule": { "cron": "$(Esc-Json $Cron)", "clock": "CLOCK_LOCAL" },
      "retention": { "policyKeepLastN": 60 },
      "hooks": $hooksVal
    }
"@
}

# Inicializa/verifica un repo en B2 con restic y devuelve su guid (64 hex) o $null.
function Get-RepoGuid {
    param([string]$ResticExe, [string]$Uri, [string]$RepoPass, [string]$AwsId, [string]$AwsSecret)
    $env:AWS_ACCESS_KEY_ID = $AwsId
    $env:AWS_SECRET_ACCESS_KEY = $AwsSecret
    $env:RESTIC_PASSWORD = $RepoPass
    $catOut = & $ResticExe -r $Uri cat config --json 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Repo ya existe en B2, se usa tal cual." -ForegroundColor Green
        return Get-GuidFromResticOutput $catOut
    }
    Write-Host "  Repo no existe, inicializando en B2..." -ForegroundColor Yellow
    $initOut = & $ResticExe -r $Uri init --json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ERROR inicializando el repo:" -ForegroundColor Red
        Write-Host ($initOut | Out-String) -ForegroundColor DarkYellow
        return $null
    }
    $catOut = & $ResticExe -r $Uri cat config --json 2>&1
    return Get-GuidFromResticOutput $catOut
}

# ==============================================================================
# CONSTRUCTOR DEL config.json  (aislado y testeable)
# ==============================================================================
# Devuelve el TEXTO JSON completo, listo para escribir. NO escribe nada.
# Preserva la identidad y el auth existentes (se pasan como texto JSON o $null).
# RepoBlocks / PlanBlocks: arrays con los bloques JSON ya formateados (1 o 2 c/u).
function Build-BackrestConfig {
    param(
        [int]$Modno,
        [int]$Version,
        [string]$Instance,
        [string[]]$RepoBlocks,
        [string[]]$PlanBlocks,
        [string]$KhInstanceId,
        [string]$KhKeyId,
        [string]$KhSecret,
        [string]$KhUrl,
        [string]$IdentityJson,   # texto JSON del objeto identity, o $null/"" si no hay
        [string]$AuthUser,       # usuario para la web; si vacio -> auth deshabilitada
        [string]$AuthBcrypt      # base64(bcrypt(pass))
    )

    # Bloque de auth: si hay usuario+hash, se habilita login; si no, queda deshabilitada.
    if (-not [string]::IsNullOrWhiteSpace($AuthUser) -and -not [string]::IsNullOrWhiteSpace($AuthBcrypt)) {
        $AuthJson = @"
{
    "users": [
      {
        "name": "$(Esc-Json $AuthUser)",
        "passwordBcrypt": "$(Esc-Json $AuthBcrypt)"
      }
    ]
  }
"@
    } else {
        $AuthJson = '{ "disabled": true }'
    }

    # Linea opcional de identity dentro de "sync". Si no hay, Backrest la genera al arrancar.
    $identityLine = ""
    if (-not [string]::IsNullOrWhiteSpace($IdentityJson)) {
        $identityLine = "    `"identity`": $IdentityJson,`r`n"
    }

    $reposText = $RepoBlocks -join ",`n"
    $plansText = $PlanBlocks -join ",`n"

    $cfgText = @"
{
  "modno": $Modno,
  "version": $Version,
  "instance": "$(Esc-Json $Instance)",
  "repos": [
$reposText
  ],
  "plans": [
$plansText
  ],
  "auth": $AuthJson,
  "sync": {
$identityLine    "knownHosts": [
      {
        "instanceId": "$(Esc-Json $KhInstanceId)",
        "keyId": "$(Esc-Json $KhKeyId)",
        "instanceUrl": "$(Esc-Json $KhUrl)",
        "initialPairingSecret": "$(Esc-Json $KhSecret)",
        "permissions": [
          { "type": "PERMISSION_READ_OPERATIONS", "scopes": [ "*" ] },
          { "type": "PERMISSION_RECEIVE_SHARED_REPOS" },
          { "type": "PERMISSION_READ_WRITE_CONFIG", "scopes": [ "*" ] }
        ]
      }
    ]
  }
}
"@
    return $cfgText
}

# ==============================================================================
# INSTALADOR DESATENDIDO (descarga binarios + crea la tarea SYSTEM)
# ==============================================================================
function Install-Backrest {
    Clear-Host
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host " INSTALAR BACKREST (desatendido, como SYSTEM)                     " -ForegroundColor Yellow
    Write-Host "==================================================================" -ForegroundColor Cyan

    if (-not (Test-Admin)) {
        Write-Host "Necesita Administrador (escribe en Program Files y crea la tarea)." -ForegroundColor Red
        Pause
        return
    }

    $appDir = "C:\Program Files\Backrest"
    $exe = Join-Path $appDir "backrest.exe"
    if (Test-Path $exe) {
        Write-Host "Backrest ya esta instalado en: $exe" -ForegroundColor Yellow
        $re = Read-Host "Reinstalar / actualizar a la ultima version igual? (s/N)"
        if ($re -ne 's' -and $re -ne 'S') { return }
    }

    Write-Host "`nSe va a:" -ForegroundColor White
    Write-Host "  1. Descargar Backrest (ultima version) y restic 0.19.1" -ForegroundColor White
    Write-Host "  2. Ponerlos en $appDir" -ForegroundColor White
    Write-Host "  3. Crear la tarea 'Backrest' como SYSTEM (al arranque, puerto 9897)" -ForegroundColor White
    $ok = Read-Host "Continuar? (s/N)"
    if ($ok -ne 's' -and $ok -ne 'S') { return }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $tmp = Join-Path $env:TEMP ("backrest-inst-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    if (-not (Test-Path $appDir)) { New-Item -ItemType Directory -Path $appDir -Force | Out-Null }

    try {
        Write-Host "`nDescargando Backrest (ultima version)..." -ForegroundColor Cyan
        $bzip = Join-Path $tmp "backrest.zip"
        Invoke-WebRequest -Uri "https://github.com/garethgeorge/backrest/releases/latest/download/backrest_Windows_x86_64.zip" -OutFile $bzip -UseBasicParsing
        Expand-Archive -Path $bzip -DestinationPath (Join-Path $tmp "b") -Force
        $bexe = Get-ChildItem (Join-Path $tmp "b") -Recurse -Filter "backrest.exe" | Select-Object -First 1
        if (-not $bexe) { throw "no se encontro backrest.exe en el zip" }
        Copy-Item $bexe.FullName $exe -Force
        Write-Host "  backrest.exe listo" -ForegroundColor Green

        Write-Host "Descargando restic 0.19.1..." -ForegroundColor Cyan
        $rzip = Join-Path $tmp "restic.zip"
        Invoke-WebRequest -Uri "https://github.com/restic/restic/releases/download/v0.19.1/restic_0.19.1_windows_amd64.zip" -OutFile $rzip -UseBasicParsing
        Expand-Archive -Path $rzip -DestinationPath (Join-Path $tmp "r") -Force
        $rexe = Get-ChildItem (Join-Path $tmp "r") -Recurse -Filter "restic*.exe" | Select-Object -First 1
        if (-not $rexe) { throw "no se encontro restic.exe en el zip" }
        Copy-Item $rexe.FullName (Join-Path $appDir "restic.exe") -Force
        Write-Host "  restic.exe listo" -ForegroundColor Green
    } catch {
        Write-Host "ERROR en descarga/extraccion: $($_.Exception.Message)" -ForegroundColor Red
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        Pause
        return
    }
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "Creando la tarea 'Backrest' como SYSTEM (mismo esquema que el instalador oficial)..." -ForegroundColor Cyan
    try {
        $s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries
        $s.ExecutionTimeLimit = 'PT0S'
        $action = New-ScheduledTaskAction -Execute $exe -Argument '--bind-address 127.0.0.1:9897' -WorkingDirectory $appDir
        $trigger = New-ScheduledTaskTrigger -AtStartup
        Register-ScheduledTask -Force -TaskName 'Backrest' -RunLevel Highest -User 'SYSTEM' -Trigger $trigger -Action $action -Settings $s | Out-Null
        Start-ScheduledTask -TaskName 'Backrest'
        Write-Host "Tarea creada y arrancada." -ForegroundColor Green
    } catch {
        Write-Host "ERROR creando la tarea: $($_.Exception.Message)" -ForegroundColor Red
        Pause
        return
    }

    Write-Host "Esperando a que Backrest genere su config..." -ForegroundColor Cyan
    $deadline = (Get-Date).AddSeconds(45)
    do { Start-Sleep -Seconds 2; $ready = Test-Path $global:BackrestConfigPath } until ($ready -or (Get-Date) -gt $deadline)
    if ($ready) {
        Write-Host "`nLISTO. Backrest corriendo como SYSTEM en 127.0.0.1:9897." -ForegroundColor Green
        Write-Host "Segui con la opcion 1 (instancias) y despues la 5 (config)." -ForegroundColor Cyan
    } else {
        Write-Host "`nInstalado, pero el config todavia no aparecio. Revisa la tarea 'Backrest'." -ForegroundColor Yellow
    }
    Pause
}

# ==============================================================================
# MENU PRINCIPAL
# ==============================================================================
do {
    Clear-Host
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host "      ASISTENTE SQL SERVER + BACKREST (MULTI-INSTANCIA)            " -ForegroundColor Yellow
    Write-Host "==================================================================" -ForegroundColor Cyan

    if (-not (Test-Admin)) {
        Write-Host "  AVISO: no estas como Administrador. Los pasos 4 y 5 (config y" -ForegroundColor Red
        Write-Host "  reinicio de Backrest) necesitan permisos de administrador." -ForegroundColor Red
        Write-Host "------------------------------------------------------------------" -ForegroundColor DarkCyan
    }

    if ($global:instanciasConfiguradas.Count -gt 0) {
        Write-Host "  Instancias Activas Configuradas ($($global:instanciasConfiguradas.Count)):" -ForegroundColor Green
        foreach ($inst in $global:instanciasConfiguradas) {
            $metodo = if ($inst.AuthOpcion -eq "2") { "SQL Auth ($($inst.User))" } else { "Windows Auth" }
            Write-Host "   * $($inst.Server) -> Mode: $metodo" -ForegroundColor White
        }
    } else {
        Write-Host "  Instancias Activas : (Ninguna configurada aún)" -ForegroundColor Red
    }

    Write-Host "------------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host " [0] Instalar Backrest en esta PC (desatendido, como SYSTEM)" -ForegroundColor Green
    Write-Host "------------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host " [1] Configurar Autenticación e Instancias (Individual o TODAS)" -ForegroundColor White
    Write-Host " [2] Analizar Bases de Datos, Tamaños y Permisos" -ForegroundColor White
    Write-Host " [3] Hacer Prueba Real de Dump" -ForegroundColor White
    Write-Host " [4] Generar Scripts de Dump y Estructura de Carpetas" -ForegroundColor White
    Write-Host "------------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host " [5] GENERAR config.json DE BACKREST (Repo + Plan + Server)" -ForegroundColor Green
    Write-Host "------------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host " [R] Reiniciar servicio Backrest" -ForegroundColor Cyan
    Write-Host "------------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host " [6] Salir" -ForegroundColor Red
    Write-Host "==================================================================" -ForegroundColor Cyan

    $opcion = Read-Host "`nElegi una opcion"

    switch ($opcion.ToUpper()) {
        '0' { Install-Backrest }
        '1' {
            # ==============================================================================
            # PASO 1 - Detección y Configuración de Instancias (Individual o Todas)
            # ==============================================================================
            Clear-Host
            Write-Host "==================================================================" -ForegroundColor Cyan
            Write-Host " PASO 1 - Detección de Instancias y Configuración de Credenciales " -ForegroundColor Yellow
            Write-Host "==================================================================" -ForegroundColor Cyan

            $Equipo = $env:COMPUTERNAME
            $UsuarioWin = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

            Write-Host "  Equipo          : $Equipo" -ForegroundColor White
            Write-Host "  Usuario Windows : $UsuarioWin`n" -ForegroundColor White

            Write-Host "Buscando instancias de SQL Server localmente..." -ForegroundColor Yellow

            $serviciosSql = Get-Service | Where-Object { $_.Name -like "MSSQL$*" -or $_.Name -eq "MSSQLSERVER" }
            $instanciasDetectadas = @()

            foreach ($serv in $serviciosSql) {
                if ($serv.Name -eq "MSSQLSERVER") {
                    $instanciasDetectadas += ".\MSSQLSERVER"
                } else {
                    $instanciasDetectadas += ".\$($serv.Name.Replace('MSSQL$', ''))"
                }
            }

            if ($instanciasDetectadas.Count -eq 0) {
                Write-Host "No se encontraron instancias de SQL Server automáticas." -ForegroundColor Red
                $manual = Read-Host "Ingresá manualmente el nombre de la instancia (ej: .\SQLEXPRESS)"
                if ($manual) { $instanciasDetectadas += $manual }
            }

            Write-Host "`nSe encontraron $($instanciasDetectadas.Count) instancias de SQL Server:" -ForegroundColor Green
            for ($i = 0; $i -lt $instanciasDetectadas.Count; $i++) {
                Write-Host "  [$($i + 1)] $($instanciasDetectadas[$i])" -ForegroundColor White
            }
            if ($instanciasDetectadas.Count -gt 1) {
                Write-Host "  [0] CONFIGURAR TODAS LAS INSTANCIAS DETECTADAS" -ForegroundColor Yellow
            }

            $opcInstancia = Read-Host "`nSeleccioná la opción (Default: 1)"
            if ([string]::IsNullOrWhiteSpace($opcInstancia)) { $opcInstancia = "1" }

            $instanciasAProcesar = @()

            if ($opcInstancia -eq "0" -and $instanciasDetectadas.Count -gt 1) {
                $instanciasAProcesar = $instanciasDetectadas
            } else {
                $idx = [int]$opcInstancia - 1
                if ($idx -ge 0 -and $idx -lt $instanciasDetectadas.Count) {
                    $instanciasAProcesar += $instanciasDetectadas[$idx]
                } else {
                    $instanciasAProcesar += $instanciasDetectadas[0]
                }
            }

            # Reiniciar lista configurada para la selección actual
            $global:instanciasConfiguradas = @()

            foreach ($instName in $instanciasAProcesar) {
                Write-Host "`n==================================================================" -ForegroundColor DarkCyan
                Write-Host "Configurando Credenciales para Instancia: $instName" -ForegroundColor Yellow
                Write-Host "==================================================================" -ForegroundColor DarkCyan

                Write-Host "Seleccioná el método de Autenticación para ${instName}:" -ForegroundColor White
                Write-Host "  [1] Autenticación de Windows (Integrated Security)" -ForegroundColor White
                Write-Host "  [2] Autenticación de SQL Server (Usuario / Contraseña)" -ForegroundColor White
                $authOpcion = Read-Host "Opción (Default: 1)"
                if ([string]::IsNullOrWhiteSpace($authOpcion)) { $authOpcion = "1" }

                $sqlUser = "sa"
                $sqlPassPlainText = ""
                $elevUser = ""       # login sysadmin elevado (si el usuario Windows no es sysadmin)
                $elevPass = ""

                if ($authOpcion -eq "2") {
                    $sqlUser = Read-Host "Usuario de SQL Server para $instName (Default: sa)"
                    if ([string]::IsNullOrWhiteSpace($sqlUser)) { $sqlUser = "sa" }
                    $sqlPassPlainText = Read-Host "Contraseña para $sqlUser"
                } else {
                    Write-Host "Usando credenciales de Windows ($UsuarioWin)" -ForegroundColor Gray

                    # ¿El usuario actual es sysadmin de SQL? Hace falta para asignar permisos.
                    # Solo si NO lo es, se pide un login sysadmin (ej. sa) para continuar.
                    $chkSa = Exec-SqlQuery -Server $instName -AuthType "1" -User "" -Password "" -Query "SET NOCOUNT ON; SELECT IS_SRVROLEMEMBER('sysadmin');"
                    $grantAuth = "1"; $grantUser = ""; $grantPass = ""
                    if ($chkSa -notlike "*1*") {
                        Write-Host "El usuario actual ($UsuarioWin) NO es sysadmin de SQL (hace falta para asignar permisos a SYSTEM)." -ForegroundColor Yellow
                        $respSa = Read-Host "¿Ingresar un login sysadmin de SQL (ej. sa) para continuar? (s/n)"
                        if ($respSa -eq 's' -or $respSa -eq 'S') {
                            $elevUser = Read-Host "Login sysadmin (Default: sa)"
                            if ([string]::IsNullOrWhiteSpace($elevUser)) { $elevUser = "sa" }
                            $elevPass = Read-PasswordPlain "Contraseña de $elevUser"
                            $grantAuth = "2"; $grantUser = $elevUser; $grantPass = $elevPass
                        } else {
                            Write-Host "Sin sysadmin no se pueden asignar los permisos a SYSTEM; el backup puede fallar." -ForegroundColor Red
                        }
                    }

                    # Permisos para NT AUTHORITY\SYSTEM en ejecuciones de servicio
                    Write-Host "Configurando permisos para NT AUTHORITY\SYSTEM en ${instName}..." -ForegroundColor Yellow
                    $queryGrantSystem = @"
SET NOCOUNT ON;
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'NT AUTHORITY\SYSTEM')
BEGIN
    CREATE LOGIN [NT AUTHORITY\SYSTEM] FROM WINDOWS;
END
IF IS_SRVROLEMEMBER('sysadmin', 'NT AUTHORITY\SYSTEM') = 0
    EXEC sp_addsrvrolemember @loginame = N'NT AUTHORITY\SYSTEM', @rolename = N'sysadmin';
"@
                    $resGrant = Exec-SqlQuery -Server $instName -AuthType $grantAuth -User $grantUser -Password $grantPass -Query $queryGrantSystem
                    if ("$resGrant" -match 'Msg \d+|denied|denegad|permiso|permission') {
                        Write-Host "OJO: el GRANT pudo NO aplicarse:" -ForegroundColor Red
                        Write-Host $resGrant -ForegroundColor DarkYellow
                    } else {
                        Write-Host "Permisos 'sysadmin' asignados a NT AUTHORITY\SYSTEM." -ForegroundColor Green
                    }
                }

                # Probando conexión
                Write-Host "Probando conexión a $instName..." -ForegroundColor Yellow
                $testQuery = "SET NOCOUNT ON; SELECT @@VERSION;"
                $res = Exec-SqlQuery -Server $instName -AuthType $authOpcion -User $sqlUser -Password $sqlPassPlainText -Query $testQuery

                if ($res -like "*Microsoft SQL Server*") {
                    Write-Host "¡Conexión EXITOSA a $instName!" -ForegroundColor Green

                    $serverClean = ($instName -replace '^[.\\/]+', '' -replace '[\\/]', '_').ToLower()
                    if ([string]::IsNullOrWhiteSpace($serverClean)) { $serverClean = "sql" }

                    $global:instanciasConfiguradas += [PSCustomObject]@{
                        Server       = $instName
                        ServerClean  = $serverClean
                        AuthOpcion   = $authOpcion
                        User         = $sqlUser
                        Pass         = $sqlPassPlainText
                        ElevatedUser = $elevUser
                        ElevatedPass = $elevPass
                    }
                } else {
                    Write-Host "Error al conectar con la instancia ${instName}:" -ForegroundColor Red
                    Write-Host $res -ForegroundColor Red
                }
            }

            Write-Host "`nProceso de configuración finalizado." -ForegroundColor Green
            Pause
        }

        '2' {
            # ==============================================================================
            # PASO 2 - Analizar Bases de Datos, Tamaños y Permisos
            # ==============================================================================
            Clear-Host
            Write-Host "==================================================================" -ForegroundColor Cyan
            Write-Host " PASO 2 - Analizar Bases de Datos y Permisos por Instancia       " -ForegroundColor Yellow
            Write-Host "==================================================================" -ForegroundColor Cyan

            if ($global:instanciasConfiguradas.Count -eq 0) {
                Write-Host "Primero debés configurar al menos una instancia en la Opción 1." -ForegroundColor Red
                Pause
                continue
            }

            foreach ($instObj in $global:instanciasConfiguradas) {
                Write-Host "`n------------------------------------------------------------------" -ForegroundColor DarkCyan
                Write-Host "INSTANCIA: $($instObj.Server)" -ForegroundColor Yellow
                Write-Host "------------------------------------------------------------------" -ForegroundColor DarkCyan

                $queryDbSize = "SET NOCOUNT ON; SELECT d.name + ' | ' + CAST(CAST(SUM(f.size * 8.0 / 1024) AS DECIMAL(10,2)) AS VARCHAR) + ' MB' FROM sys.databases d JOIN sys.master_files f ON d.database_id = f.database_id WHERE d.name NOT IN ('master','tempdb','model','msdb') AND d.state_desc = 'ONLINE' GROUP BY d.name;"
                $rawDbs = Exec-SqlQuery -Server $instObj.Server -AuthType $instObj.AuthOpcion -User $instObj.User -Password $instObj.Pass -Query $queryDbSize

                $listaDbsFormatted = @($rawDbs | Where-Object { $_ -and $_.Trim() -ne "" -and $_ -notlike "*rows affected*" -and $_ -notlike "*filas afectadas*" } | ForEach-Object { $_.Trim() })

                Write-Host "Bases de datos detectadas y tamaño estimado:" -ForegroundColor Green
                if ($listaDbsFormatted.Count -gt 0) {
                    foreach ($line in $listaDbsFormatted) {
                        Write-Host "  * $line" -ForegroundColor White
                    }
                } else {
                    Write-Host "  (No se encontraron bases de datos de usuario activas)" -ForegroundColor Yellow
                }

                # Verificación Sysadmin
                $queryRole = "SET NOCOUNT ON; SELECT IS_SRVROLEMEMBER('sysadmin');"
                $isSysadmin = Exec-SqlQuery -Server $instObj.Server -AuthType $instObj.AuthOpcion -User $instObj.User -Password $instObj.Pass -Query $queryRole

                if ($isSysadmin -like "*1*") {
                    Write-Host "`nRol 'sysadmin': OK" -ForegroundColor Green
                } else {
                    Write-Host "`nRol 'sysadmin': ADVERTENCIA - No tiene permisos suficientes." -ForegroundColor Red
                }
            }

            Pause
        }

        '3' {
            # ==============================================================================
            # PASO 3 - Prueba Real de Dump (Con Estructura de Subcarpetas)
            # ==============================================================================
            Clear-Host
            Write-Host "==================================================================" -ForegroundColor Cyan
            Write-Host " PASO 3 - Prueba Real de Backup (Dump)                           " -ForegroundColor Yellow
            Write-Host "==================================================================" -ForegroundColor Cyan

            if ($global:instanciasConfiguradas.Count -eq 0) {
                Write-Host "Primero debés configurar al menos una instancia en la Opción 1." -ForegroundColor Red
                Pause
                continue
            }

            $baseTempFolder = "C:\Program Files\Backrest\backup"

            foreach ($instObj in $global:instanciasConfiguradas) {
                Write-Host "`n==================================================================" -ForegroundColor DarkCyan
                Write-Host "PROBANDO INSTANCIA: $($instObj.Server)" -ForegroundColor Yellow
                Write-Host "==================================================================" -ForegroundColor DarkCyan

                # Carpeta específica por instancia
                $instFolder = "$baseTempFolder\$($instObj.ServerClean)"
                if (-not (Test-Path $instFolder)) {
                    New-Item -ItemType Directory -Path $instFolder -Force | Out-Null
                }

                # SQL escribe el .bak con SU cuenta de servicio (no con la tuya ni con
                # SYSTEM). Como la carpeta cuelga de "Program Files" (protegida), hay que
                # darle permiso ANTES de la prueba o falla con "error 5 (Access denied)".
                # Requiere correr como admin; si no, icacls no aplica y el backup fallará.
                $svcName = Get-SqlServiceName $instObj.Server
                & icacls $instFolder /grant ("NT SERVICE\" + $svcName + ":(OI)(CI)M") /C | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "Permiso de escritura otorgado a NT SERVICE\$svcName" -ForegroundColor DarkGray
                } else {
                    Write-Host "OJO: no se pudo dar permiso a NT SERVICE\$svcName (¿corriendo como admin?). El backup puede fallar con 'Access denied'." -ForegroundColor Yellow
                }

                # Detección de compresión
                $queryComp = "SET NOCOUNT ON; DECLARE @v INT = CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(64)),4) AS INT)*100 + CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(64)),3) AS INT); DECLARE @e INT = CAST(SERVERPROPERTY('EngineEdition') AS INT); SELECT CASE WHEN (@e=3 AND @v>=1000) OR (@e=2 AND @v>=1050) THEN 1 ELSE 0 END;"
                $resComp = Exec-SqlQuery -Server $instObj.Server -AuthType $instObj.AuthOpcion -User $instObj.User -Password $instObj.Pass -Query $queryComp

                $sqlCompressionClause = ""
                if ($resComp -like "*1*") {
                    $sqlCompressionClause = ", COMPRESSION"
                    Write-Host "Soporte para COMPRESIÓN nativa: HABILITADO" -ForegroundColor Green
                } else {
                    Write-Host "Soporte para COMPRESIÓN nativa: DESHABILITADO (Express/Limitada)" -ForegroundColor Yellow
                }

                $queryDb = "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE name NOT IN ('master','tempdb','model','msdb') AND state_desc = 'ONLINE';"
                $rawDbs = Exec-SqlQuery -Server $instObj.Server -AuthType $instObj.AuthOpcion -User $instObj.User -Password $instObj.Pass -Query $queryDb
                $listaDbs = @($rawDbs | Where-Object { $_ -and $_.Trim() -ne "" -and $_ -notlike "*rows affected*" -and $_ -notlike "*filas afectadas*" } | ForEach-Object { $_.Trim() })

                if ($listaDbs.Count -eq 0) {
                    Write-Host "Sin bases de datos para respaldar." -ForegroundColor Yellow
                    continue
                }

                foreach ($dbName in $listaDbs) {
                    Write-Host "`nRespaldando [$dbName] en carpeta [$instFolder]..." -ForegroundColor Yellow

                    $bakFile = "$instFolder\TestBackup_$dbName.bak"
                    $queryBackup = "BACKUP DATABASE [$dbName] TO DISK = N'$bakFile' WITH FORMAT, INIT, CHECKSUM$sqlCompressionClause, STATS = 25;"
                    $eaB = Get-EffectiveAuth $instObj
                    $resBackup = Exec-SqlQuery -Server $instObj.Server -AuthType $eaB.Auth -User $eaB.User -Password $eaB.Pass -Query $queryBackup

                    Write-Host $resBackup -ForegroundColor White

                    if (Test-Path $bakFile) {
                        $tamano = (Get-Item $bakFile).Length / 1MB
                        Write-Host " Backup Exitoso. Tamaño: $([math]::Round($tamano, 2)) MB" -ForegroundColor Green
                        Remove-Item $bakFile -Force
                        Write-Host " Archivo de prueba eliminado." -ForegroundColor Gray
                    } else {
                        Write-Host " Falló el backup para $dbName." -ForegroundColor Red
                        if ("$resBackup" -match 'error 5|Access is denied|Acceso denegado|3201') {
                            Write-Host "   Causa: SQL no pudo ESCRIBIR el .bak (permiso de carpeta). Corré este asistente como administrador." -ForegroundColor DarkYellow
                        }
                    }
                }
            }

            Pause
        }

        '4' {
            # ==============================================================================
            # PASO 4 - Generar Scripts y Estructura de Carpetas para Backrest
            # ==============================================================================
            Clear-Host
            Write-Host "==================================================================" -ForegroundColor Cyan
            Write-Host " PASO 4 - Generar Scripts y Carpetas para Backrest               " -ForegroundColor Yellow
            Write-Host "==================================================================" -ForegroundColor Cyan

            if ($global:instanciasConfiguradas.Count -eq 0) {
                Write-Host "Primero debés configurar al menos una instancia en la Opción 1." -ForegroundColor Red
                Pause
                continue
            }

            $targetDir = Read-Host "Ruta raíz donde Backrest guardará los backups (Default: C:\Program Files\Backrest\backup)"
            if ([string]::IsNullOrWhiteSpace($targetDir)) { $targetDir = "C:\Program Files\Backrest\backup" }

            if (-not (Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }

            # Crear subcarpetas por instancia
            foreach ($instObj in $global:instanciasConfiguradas) {
                $subFolder = "$targetDir\$($instObj.ServerClean)"
                if (-not (Test-Path $subFolder)) {
                    New-Item -ItemType Directory -Path $subFolder -Force | Out-Null
                    Write-Host "Subcarpeta de instancia creada: $subFolder" -ForegroundColor Green
                }
            }

            # --- GENERAR SCRIPTS INDIVIDUALES POR INSTANCIA ---
            foreach ($instObj in $global:instanciasConfiguradas) {
                $scriptFileName = "sql_dump_$($instObj.ServerClean).ps1"
                $scriptPath = "$targetDir\$scriptFileName"

                $authFlag = if ($instObj.AuthOpcion -eq "2") { "-U `"$($instObj.User)`" -P `"$($instObj.Pass)`"" } else { "-E" }
                $instServer = $instObj.Server
                $instSubFolder = "$targetDir\$($instObj.ServerClean)"

                $singleScriptContent = @"
# Script generado automáticamente para la instancia: $instServer
`$ErrorActionPreference = "Stop"
`$TargetDir = "$instSubFolder"

if (-not (Test-Path `$TargetDir)) { New-Item -ItemType Directory -Path `$TargetDir -Force }

`$queryComp = "SET NOCOUNT ON; DECLARE @v INT = CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(64)),4) AS INT)*100 + CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(64)),3) AS INT); DECLARE @e INT = CAST(SERVERPROPERTY('EngineEdition') AS INT); SELECT CASE WHEN (@e=3 AND @v>=1000) OR (@e=2 AND @v>=1050) THEN 1 ELSE 0 END;"
`$supportsComp = sqlcmd.exe -b -S "$instServer" $authFlag -Q "`$queryComp" -W -h -1
`$compFlag = ""

if (`$supportsComp -like "*1*") {
    `$compFlag = ", COMPRESSION"
    Write-Host "Soporte de compresión nativa: HABILITADO"
} else {
    Write-Host "Soporte de compresión nativa: DESHABILITADO (Express/Limitada)"
}

`$dbs = sqlcmd.exe -b -S "$instServer" $authFlag -Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE name NOT IN ('master','tempdb','model','msdb') AND state_desc = 'ONLINE';" -W -h -1

foreach (`$db in `$dbs) {
    `$dbClean = `$db.Trim()
    if (`$dbClean -and `$dbClean -notlike "*rows affected*" -and `$dbClean -notlike "*filas afectadas*") {
        `$outFile = "`$TargetDir\`$dbClean.bak"
        Write-Host "Respaldando [$dbClean] de $instServer en `$outFile..."
        sqlcmd.exe -b -S "$instServer" $authFlag -Q "BACKUP DATABASE [`$dbClean] TO DISK = N'`$outFile' WITH FORMAT, INIT, CHECKSUM`$compFlag;"
        if (`$LASTEXITCODE -ne 0) {
            Write-Error "Error grave ejecutando dump de `$dbClean en $instServer"
            exit 1
        }
    }
}
"@
                Set-Content -Path $scriptPath -Value $singleScriptContent -Encoding UTF8
                Write-Host "Script individual generado: $scriptPath" -ForegroundColor Yellow
            }

            # --- GENERAR SCRIPT MAESTRO UNIFICADO (solo si hay MAS de una instancia) ---
            if ($global:instanciasConfiguradas.Count -gt 1) {
                $masterScriptPath = "$targetDir\sql_dump_todas_las_instancias.ps1"
                $masterContent = @"
# Script Maestro - Respalda TODAS las instancias configuradas.
`$ErrorActionPreference = "Stop"
"@
                foreach ($instObj in $global:instanciasConfiguradas) {
                    $masterContent += "`nWrite-Host '=================================================='"
                    $masterContent += "`nWrite-Host 'Iniciando respaldo de instancia: $($instObj.Server)'"
                    $masterContent += "`n& '$targetDir\sql_dump_$($instObj.ServerClean).ps1'"
                }
                Set-Content -Path $masterScriptPath -Value $masterContent -Encoding UTF8
                Write-Host "`nScript Maestro UNIFICADO generado:" -ForegroundColor Green
                Write-Host " -> $masterScriptPath" -ForegroundColor Yellow
            }

            Write-Host "`n¡Proceso completado!" -ForegroundColor White
            Write-Host "NOTA: los .ps1 llevan la clave SQL en texto plano; por eso el plan del" -ForegroundColor DarkYellow
            Write-Host "Paso 5 los EXCLUYE del backup (excludes: *.ps1) y no se suben a B2." -ForegroundColor DarkYellow
            Pause
        }

        '5' {
            # ==============================================================================
            # PASO 5 - Generar config.json de Backrest (Repo + Plan + Known Host)
            # ==============================================================================
            Clear-Host
            Write-Host "==================================================================" -ForegroundColor Cyan
            Write-Host " PASO 5 - Generar config.json de Backrest                        " -ForegroundColor Yellow
            Write-Host "==================================================================" -ForegroundColor Cyan

            if (-not (Test-Admin)) {
                Write-Host "Este paso necesita permisos de ADMINISTRADOR para leer/escribir:" -ForegroundColor Red
                Write-Host "  $global:BackrestConfigPath" -ForegroundColor Red
                Write-Host "Cerrá y volvé a abrir el asistente como administrador." -ForegroundColor Yellow
                Pause
                continue
            }

            # -------- ENTRADA DE DATOS con reintento y "k" para volver atras --------
            # Cada campo: si te equivocas, re-pregunta (no sale al menu). "k" vuelve al
            # campo anterior. En el primer campo, "k" cancela y vuelve al menu.
            $step = 0
            $cancelar = $false
            while ($step -le 8) {

                if ($step -eq 0) {
                    Write-Host "`n¿Qué querés configurar en este cliente?" -ForegroundColor Cyan
                    Write-Host "  [1] Solo SQL    [2] Solo Files    [3] Ambos" -ForegroundColor White
                    Write-Host "  (k = cancelar y volver al menú)" -ForegroundColor DarkGray
                    $tipoOpt = Read-Host "Opción [1]"
                    if ($tipoOpt -eq 'k' -or $tipoOpt -eq 'K') { $cancelar = $true; break }
                    if ([string]::IsNullOrWhiteSpace($tipoOpt)) { $tipoOpt = "1" }
                    if ($tipoOpt -eq "1") { $tipo = "SQL" }
                    elseif ($tipoOpt -eq "2") { $tipo = "FILES" }
                    elseif ($tipoOpt -eq "3") { $tipo = "AMBOS" }
                    else { Write-Host "  Opción inválida (1/2/3)." -ForegroundColor Red; continue }
                    $incluyeSql = ($tipo -eq "SQL" -or $tipo -eq "AMBOS")
                    $incluyeFiles = ($tipo -eq "FILES" -or $tipo -eq "AMBOS")
                    if ($incluyeSql -and $global:instanciasConfiguradas.Count -eq 0) {
                        Write-Host "  Para SQL primero configurá las instancias en el Paso 1." -ForegroundColor Red
                        Pause
                        $cancelar = $true; break
                    }
                    $step = 1
                }

                elseif ($step -eq 1) {
                    Write-Host "`n--- Nombre de la instancia (este cliente)   (k = volver atras) ---" -ForegroundColor Cyan
                    $instanceName = (Read-Host "Nombre de la instancia (ej: cabimetal)").Trim()
                    if ($instanceName -eq 'k') { $step = 0; continue }
                    if ([string]::IsNullOrWhiteSpace($instanceName)) { Write-Host "  Obligatorio." -ForegroundColor Red; continue }
                    $step = 2
                }

                elseif ($step -eq 2) {
                    Write-Host "`n--- Pairing token del server   (k = volver atras) ---" -ForegroundColor Cyan
                    Write-Host "Formato:  <keyId>:<secret>#<instanceId>" -ForegroundColor DarkGray
                    $pairToken = (Read-Host "Pairing token").Trim()
                    if ($pairToken -eq 'k') { $step = 1; continue }
                    $hashIdx = $pairToken.IndexOf('#'); $colonIdx = $pairToken.IndexOf(':')
                    if ($hashIdx -lt 0 -or $colonIdx -lt 0 -or $colonIdx -gt $hashIdx) { Write-Host "  Token inválido (falta : o #)." -ForegroundColor Red; continue }
                    $khKeyId = $pairToken.Substring(0, $colonIdx)
                    $khSecret = $pairToken.Substring($colonIdx + 1, $hashIdx - $colonIdx - 1)
                    $khInstanceId = $pairToken.Substring($hashIdx + 1)
                    if ([string]::IsNullOrWhiteSpace($khKeyId) -or [string]::IsNullOrWhiteSpace($khSecret) -or [string]::IsNullOrWhiteSpace($khInstanceId)) { Write-Host "  El token no tiene las 3 partes." -ForegroundColor Red; continue }
                    Write-Host "  Token OK -> server: $khInstanceId" -ForegroundColor Green
                    $step = 3
                }

                elseif ($step -eq 3) {
                    Write-Host "`n  (k = volver atras)" -ForegroundColor DarkGray
                    $khUrl = Read-Host "URL de la instancia [http://bkp.unamark.com:49374]"
                    if ($khUrl -eq 'k') { $step = 2; continue }
                    if ([string]::IsNullOrWhiteSpace($khUrl)) { $khUrl = "http://bkp.unamark.com:49374" }
                    $khUrl = $khUrl.Trim()
                    $step = 4
                }

                elseif ($step -eq 4) {
                    Write-Host "`n--- Repositorio en B2   (k = volver atras) ---" -ForegroundColor Cyan
                    $bucket = (Read-Host "Nombre del bucket de B2 (ej: 013-bucket)").Trim()
                    if ($bucket -eq 'k') { $step = 3; continue }
                    if ([string]::IsNullOrWhiteSpace($bucket)) { Write-Host "  El bucket es obligatorio." -ForegroundColor Red; continue }
                    $step = 5
                }

                elseif ($step -eq 5) {
                    Write-Host "`n  (k = volver atras)" -ForegroundColor DarkGray
                    $usarDef = Read-Host "¿Aplicar contraseña por default? (s/n)"
                    if ($usarDef -eq 'k' -or $usarDef -eq 'K') { $step = 4; continue }
                    if ($usarDef -eq 's' -or $usarDef -eq 'S') {
                        $repoPass = $global:RepoDefaultPass
                        Write-Host "  Contraseña por default aplicada." -ForegroundColor Green
                        $step = 6
                    }
                    elseif ($usarDef -eq 'n' -or $usarDef -eq 'N') {
                        $p = Read-Host "Ingresá la contraseña del repositorio"
                        if ($p -eq 'k') { continue }
                        if ([string]::IsNullOrWhiteSpace($p)) { Write-Host "  No puede estar vacía." -ForegroundColor Red; continue }
                        $repoPass = $p
                        $step = 6
                    }
                    else { Write-Host "  Respondé s o n." -ForegroundColor Red }
                }

                elseif ($step -eq 6) {
                    Write-Host "`n  (k = volver atras)" -ForegroundColor DarkGray
                    $awsId = (Read-Host "AWS_ACCESS_KEY_ID").Trim()
                    if ($awsId -eq 'k') { $step = 5; continue }
                    if ([string]::IsNullOrWhiteSpace($awsId)) { Write-Host "  Obligatorio." -ForegroundColor Red; continue }
                    $step = 7
                }

                elseif ($step -eq 7) {
                    Write-Host "  (k = volver atras)" -ForegroundColor DarkGray
                    $awsSecret = (Read-Host "AWS_SECRET_ACCESS_KEY").Trim()
                    if ($awsSecret -eq 'k') { $step = 6; continue }
                    if ([string]::IsNullOrWhiteSpace($awsSecret)) { Write-Host "  Obligatorio." -ForegroundColor Red; continue }
                    $step = 8
                }

                elseif ($step -eq 8) {
                    Write-Host "`n  (k = volver atras)" -ForegroundColor DarkGray
                    $horaStr = (Read-Host "Hora de la copia diaria (2000 = 20:00 ; 1730 = 17:30) [2000]").Trim()
                    if ($horaStr -eq 'k') { $step = 7; continue }
                    if ([string]::IsNullOrWhiteSpace($horaStr)) { $horaStr = "2000" }
                    if ($horaStr -notmatch '^\d{4}$') { Write-Host "  Formato HHMM (ej 2000, 0930)." -ForegroundColor Red; continue }
                    $hh = [int]$horaStr.Substring(0, 2); $mm = [int]$horaStr.Substring(2, 2)
                    if ($hh -gt 23 -or $mm -gt 59) { Write-Host "  Hora fuera de rango (00-23 / 00-59)." -ForegroundColor Red; continue }
                    $planCron = "$mm $hh * * *"
                    Write-Host "  Horario: todos los dias a las $($horaStr.Substring(0,2)):$($horaStr.Substring(2,2))  (cron: $planCron)" -ForegroundColor Green
                    $step = 9
                }
            }
            if ($cancelar) { continue }

            $resticExe = "C:\Program Files\Backrest\restic.exe"
            if (-not (Test-Path $resticExe)) {
                Write-Host "No se encontro restic.exe en: $resticExe" -ForegroundColor Red
                Pause
                continue
            }

            # -------- 4) CONSTRUIR repos/planes segun el tipo (init de cada repo con restic) --------
            $repoBlocks = @()
            $planBlocks = @()

            if ($incluyeSql) {
                $sqlRepoId = "$($instanceName)_sql"
                $sqlUri = "s3:https://s3.us-east-005.backblazeb2.com/$bucket/sql"
                Write-Host "`n[SQL] " -ForegroundColor Cyan -NoNewline
                Write-Host "$sqlRepoId" -ForegroundColor Green -NoNewline
                Write-Host "  ->  $sqlUri" -ForegroundColor DarkGray
                $sqlGuid = Get-RepoGuid -ResticExe $resticExe -Uri $sqlUri -RepoPass $repoPass -AwsId $awsId -AwsSecret $awsSecret
                if ([string]::IsNullOrWhiteSpace($sqlGuid) -or $sqlGuid.Length -ne 64) {
                    Write-Host "ERROR: no se obtuvo el guid del repo SQL. NO se escribio nada." -ForegroundColor Red
                    Pause
                    continue
                }
                # hook: usa el nombre REAL que genera el Paso 4 (1 instancia o maestro)
                if ($global:instanciasConfiguradas.Count -eq 1) {
                    $hookScript = "sql_dump_$($global:instanciasConfiguradas[0].ServerClean).ps1"
                } else {
                    $hookScript = "sql_dump_todas_las_instancias.ps1"
                }
                $sqlHook = "powershell.exe -ExecutionPolicy Bypass -File `"C:\Program Files\Backrest\backup\$hookScript`""
                $repoBlocks += New-RepoBlock -Id $sqlRepoId -Uri $sqlUri -RepoPass $repoPass -AwsId $awsId -AwsSecret $awsSecret -Guid $sqlGuid
                $planBlocks += New-PlanBlock -Id $sqlRepoId -Repo $sqlRepoId -Paths @("C:\Program Files\Backrest\backup") -Excludes @("*.ps1") -Cron $planCron -HookCommand $sqlHook
                Write-Host "[SQL] OK (hook -> $hookScript)" -ForegroundColor Green
            }

            if ($incluyeFiles) {
                $filesRepoId = "$($instanceName)_files"
                $filesUri = "s3:https://s3.us-east-005.backblazeb2.com/$bucket/files"
                Write-Host "`n[FILES] " -ForegroundColor Cyan -NoNewline
                Write-Host "$filesRepoId" -ForegroundColor Green -NoNewline
                Write-Host "  ->  $filesUri" -ForegroundColor DarkGray
                $filesGuid = Get-RepoGuid -ResticExe $resticExe -Uri $filesUri -RepoPass $repoPass -AwsId $awsId -AwsSecret $awsSecret
                if ([string]::IsNullOrWhiteSpace($filesGuid) -or $filesGuid.Length -ne 64) {
                    Write-Host "ERROR: no se obtuvo el guid del repo FILES. NO se escribio nada." -ForegroundColor Red
                    Pause
                    continue
                }
                $repoBlocks += New-RepoBlock -Id $filesRepoId -Uri $filesUri -RepoPass $repoPass -AwsId $awsId -AwsSecret $awsSecret -Guid $filesGuid
                # paths = C:\ por default (Backrest necesita al menos una ruta); SIN hook, SIN excludes
                $planBlocks += New-PlanBlock -Id $filesRepoId -Repo $filesRepoId -Paths @("C:\") -Excludes @() -Cron $planCron -HookCommand ""
                Write-Host ""
                Write-Host "  ****************************************************************" -ForegroundColor Yellow
                Write-Host "  *  DEBE SELECCIONAR QUE CARPETAS GUARDAR EN LA UI DE BACKREST   *" -ForegroundColor Yellow
                Write-Host "  *  Y ELIMINAR ``C:\``                                             *" -ForegroundColor Yellow
                Write-Host "  *  (se deja C:\ por default solo para que Backrest no de error) *" -ForegroundColor Yellow
                Write-Host "  ****************************************************************" -ForegroundColor Yellow
            }

            # -------- 4) LEER config.json EXISTENTE (preservar identidad, auth, modno, version) --------
            $identityJson = $null
            $authJson = $null
            $modno = 1
            $version = 6
            $cfgExiste = Test-Path $global:BackrestConfigPath

            if ($cfgExiste) {
                try {
                    $rawCfg = [System.IO.File]::ReadAllText($global:BackrestConfigPath)
                    $rawCfg = $rawCfg.TrimStart([char]0xFEFF)  # sacar BOM si lo tiene
                    $cfgObj = $rawCfg | ConvertFrom-Json
                    if ($cfgObj.PSObject.Properties.Name -contains 'modno' -and $cfgObj.modno) { $modno = [int]$cfgObj.modno + 1 }
                    if ($cfgObj.PSObject.Properties.Name -contains 'version' -and $cfgObj.version) { $version = [int]$cfgObj.version }
                    if ($cfgObj.PSObject.Properties.Name -contains 'auth' -and $cfgObj.auth) { $authJson = ($cfgObj.auth | ConvertTo-Json -Depth 20 -Compress) }
                    if (($cfgObj.PSObject.Properties.Name -contains 'sync') -and $cfgObj.sync -and $cfgObj.sync.identity) {
                        $identityJson = ($cfgObj.sync.identity | ConvertTo-Json -Depth 20 -Compress)
                        Write-Host "`nIdentidad existente PRESERVADA (no se toca)." -ForegroundColor Green
                    } else {
                        Write-Host "`nNo hay identidad previa: Backrest la generará al arrancar." -ForegroundColor Yellow
                    }
                    # Avisar si hay repos/planes que se van a reemplazar
                    $nRepos = @($cfgObj.repos).Count
                    $nPlans = @($cfgObj.plans).Count
                    if ($nRepos -gt 0 -or $nPlans -gt 0) {
                        Write-Host "AVISO: el config actual tiene $nRepos repo(s) y $nPlans plan(es)." -ForegroundColor Yellow
                        Write-Host "Este asistente REEMPLAZA el config (va a generar $($repoBlocks.Count) repo/s + $($planBlocks.Count) plan/es)." -ForegroundColor Yellow
                        Write-Host "Se hará un backup del config actual antes de reemplazarlo." -ForegroundColor Yellow
                    }
                } catch {
                    Write-Host "No se pudo leer/parsear el config actual: $($_.Exception.Message)" -ForegroundColor Red
                    Write-Host "Abortando para no romper nada." -ForegroundColor Red
                    Pause
                    continue
                }
            } else {
                Write-Host "`nNo existe config.json todavía. Se creará uno nuevo." -ForegroundColor Yellow
                Write-Host "Backrest generará la identidad al arrancar." -ForegroundColor Yellow
            }

            # -------- 6) CONSTRUIR el JSON y VALIDARLO --------
            $nuevoJson = Build-BackrestConfig -Modno $modno -Version $version -Instance $instanceName `
                -RepoBlocks $repoBlocks -PlanBlocks $planBlocks `
                -KhInstanceId $khInstanceId -KhKeyId $khKeyId -KhSecret $khSecret `
                -KhUrl $khUrl -IdentityJson $identityJson -AuthUser $global:AuthUser -AuthBcrypt $global:AuthBcrypt

            try {
                $null = $nuevoJson | ConvertFrom-Json
            } catch {
                Write-Host "ERROR: el JSON generado no es válido. NO se escribió nada." -ForegroundColor Red
                Write-Host $_.Exception.Message -ForegroundColor Red
                Pause
                continue
            }

            # -------- 6) PREVIEW y CONFIRMACION --------
            Write-Host "`n============== VISTA PREVIA DEL config.json ==============" -ForegroundColor Cyan
            Write-Host $nuevoJson -ForegroundColor Gray
            Write-Host "==========================================================" -ForegroundColor Cyan
            Write-Host "Destino: $global:BackrestConfigPath" -ForegroundColor White
            $conf = Read-Host "`n¿Aplicar? Esto DETIENE Backrest, respalda el config y lo reemplaza (s/N)"
            if ($conf -ne 's' -and $conf -ne 'S') {
                Write-Host "Cancelado. No se tocó nada." -ForegroundColor Yellow
                Pause
                continue
            }

            # -------- 7) DETENER, RESPALDAR, ESCRIBIR, ARRANCAR --------
            Write-Host "`nDeteniendo Backrest antes de escribir el config..." -ForegroundColor Yellow
            try { Stop-ScheduledTask -TaskName "Backrest" -ErrorAction SilentlyContinue } catch {}
            Start-Sleep -Seconds 3
            Get-Process backrest -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2

            $cfgDir = Split-Path $global:BackrestConfigPath -Parent
            if (-not (Test-Path $cfgDir)) { New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null }

            if ($cfgExiste) {
                $backupPath = "$global:BackrestConfigPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                Copy-Item -Path $global:BackrestConfigPath -Destination $backupPath -Force
                Write-Host "Backup del config anterior: $backupPath" -ForegroundColor Green
            }

            # Escribir SIN BOM (Go rechaza JSON con BOM)
            [System.IO.File]::WriteAllText($global:BackrestConfigPath, $nuevoJson, (New-Object System.Text.UTF8Encoding($false)))
            Write-Host "config.json escrito correctamente." -ForegroundColor Green

            # Endurecer permisos: SYSTEM (S-1-5-18) + Administradores (S-1-5-32-544)
            # en el config; y en la carpeta de backup ADEMAS la cuenta de servicio de
            # cada SQL Server, porque SQL escribe los .bak con SU cuenta (no con SYSTEM).
            # SIDs para el idioma; el usuario normal queda afuera igual.
            Write-Host "Restringiendo permisos (SYSTEM, Administradores y las cuentas de SQL)..." -ForegroundColor Cyan
            & icacls $global:BackrestConfigPath /inheritance:r /grant:r "*S-1-5-18:F" "*S-1-5-32-544:F" | Out-Null
            $backupDir = "C:\Program Files\Backrest\backup"
            if ($incluyeSql -and (Test-Path $backupDir)) {
                & icacls $backupDir /inheritance:r /grant:r "*S-1-5-18:F" "*S-1-5-32-544:F" /T /C | Out-Null
                foreach ($instObj in $global:instanciasConfiguradas) {
                    $svcName = Get-SqlServiceName $instObj.Server
                    & icacls $backupDir /grant ("NT SERVICE\" + $svcName + ":(OI)(CI)M") /T /C | Out-Null
                    Write-Host "  + escritura de .bak para NT SERVICE\$svcName" -ForegroundColor DarkGray
                }
            }
            Write-Host "Permisos OK: usuario normal afuera; SQL puede escribir los .bak." -ForegroundColor Green

            Write-Host "`nArrancando Backrest..." -ForegroundColor Yellow
            try { Start-ScheduledTask -TaskName "Backrest" -ErrorAction SilentlyContinue } catch {}
            Start-Sleep -Seconds 4
            $estado = (Get-ScheduledTask -TaskName "Backrest" -ErrorAction SilentlyContinue).State
            Write-Host "Estado de Backrest: $estado" -ForegroundColor Cyan
            Write-Host "`nListo. Revisá en la consola del server que el cliente '$instanceName'" -ForegroundColor Green
            Write-Host "aparezca conectado, y que los repos inicialicen en B2." -ForegroundColor Green

            # -------- Abrir la web de Backrest + copiar la contraseña al portapapeles --------
            try {
                Set-Clipboard -Value $global:AuthPassPlain
                Write-Host "`nContraseña de '$($global:AuthUser)' copiada al portapapeles (usuario a mano, pass con Ctrl+V)." -ForegroundColor Cyan
            } catch {
                Write-Host "`n(No se pudo copiar al portapapeles: $($_.Exception.Message))" -ForegroundColor DarkYellow
            }
            Write-Host "Abriendo la web de Backrest en localhost:9897..." -ForegroundColor Cyan
            Start-Process "http://localhost:9897"
            Pause
        }

        'R' { Restart-Backrest; Pause }
        '6' { exit }
        'S' { exit }
    }
} until ($opcion -eq '6' -or $opcion.ToUpper() -eq 'S')
