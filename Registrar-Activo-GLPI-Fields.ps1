#requires -Version 5.1
# SkanHawk - Registro de activo para GLPI
# Ejecutar PowerShell como Administrador.

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ==========================================================
# CONFIGURACIÓN
# ==========================================================
$EnvFile = Join-Path $env:TEMP 'SkanHawkGLPI\.env'
if (-not (Test-Path $EnvFile)) {
    throw "No se encontró el archivo de configuración: $EnvFile"
}

Get-Content $EnvFile | ForEach-Object {

    $linea = $_.Trim()

    if (
        $linea -and
        -not $linea.StartsWith('#') -and
        $linea.Contains('=')
    ) {
        $partes = $linea -split '=', 2

        $nombre = $partes[0].Trim()
        $valor = $partes[1].Trim()

        [Environment]::SetEnvironmentVariable(
            $nombre,
            $valor,
            'Process'
        )
    }
}
try {
    Remove-Item -LiteralPath $EnvFile -Force -ErrorAction SilentlyContinue
} catch {}

# Conexión GLPI
$Servidor = $env:GLPI_SERVER
$ApiBase = "$Servidor/apirest.php"

$AgentUser = $env:GLPI_AGENT_USER
$AgentPassword = $env:GLPI_AGENT_PASSWORD

$AppToken = $env:GLPI_APP_TOKEN
$UserToken = $env:GLPI_USER_TOKEN

# GLPI Agent
$AgentUrl = $env:GLPI_AGENT_URL
$AgentVersion = $env:GLPI_AGENT_VERSION

# Rutas locales
$Dir = Join-Path $env:ProgramData 'SkanHawk\GLPI\activo'
$XmlFile = Join-Path $Dir 'codigo-activo.xml'
$LogFile = 'C:\Users\Public\Documents\InstalarRegistrar-GLPI.log'

# Fields
$ContainerId = [int]$env:GLPI_CONTAINER_ID

$TipoPropiedad = @{
    'Rentado' = [int]$env:TIPO_PROPIEDAD_RENTADO
    'Propio'  = [int]$env:TIPO_PROPIEDAD_PROPIO
}

$Empresa = @{
    'RentaComputo' = [int]$env:EMPRESA_RENTACOMPUTO
    'SkanHawk'     = [int]$env:EMPRESA_SKANHAWK
}

$TipoDueno = @{
    'Torre/Rig' = [int]$env:TIPO_DUENO_TORRE
    'Persona'   = [int]$env:TIPO_DUENO_PERSONA
}

# ==========================================================
# INICIO Y REGISTRO
# ==========================================================

New-Item -ItemType Directory -Path $Dir -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force | Out-Null

function Write-Paso {
    param([string]$Texto)

    Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] $Texto" `
        -ForegroundColor Cyan
}

function Show-Msg {
    param(
        [string]$Texto,
        [string]$Titulo = 'SkanHawk - Registro de activo'
    )

    Add-Type -AssemblyName System.Windows.Forms

    [System.Windows.Forms.MessageBox]::Show(
        $Texto,
        $Titulo,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}

function Convert-SecureToPlain {
    param([Security.SecureString]$Secure)

    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)

    try {
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

# ==========================================================
# CONEXIÓN CON LA API DE GLPI
# ==========================================================

function Connect-GLPI {

    Write-Paso 'Autenticación con GLPI'

    # Usar los tokens definidos en la configuración inicial
    $script:AppToken = $AppToken
    $script:UserToken = $UserToken

    if (
        [string]::IsNullOrWhiteSpace($script:AppToken) -or
        [string]::IsNullOrWhiteSpace($script:UserToken)
    ) {
        throw 'Faltan el App-Token o el User-Token en la configuración inicial.'
    }

    $headersAuth = @{
        'App-Token' = $script:AppToken
        'Authorization' = "user_token $($script:UserToken)"
        'Accept' = 'application/json'
        'Content-Type' = 'application/json'
    }

    $session = Invoke-RestMethod `
        -Uri "$ApiBase/initSession" `
        -Method GET `
        -Headers $headersAuth

    if (-not $session.session_token) {
        throw 'GLPI no devolvió un Session-Token.'
    }

    $script:ApiHeaders = @{
        'App-Token' = $script:AppToken
        'Session-Token' = $session.session_token
        'Accept' = 'application/json'
        'Content-Type' = 'application/json'
    }

    # Seleccionar perfil Super-Admin ID 4
    $body = @{
        profiles_id = 4
    } | ConvertTo-Json

    try {
        Invoke-RestMethod `
            -Uri "$ApiBase/changeActiveProfile/" `
            -Method POST `
            -Headers $script:ApiHeaders `
            -Body $body | Out-Null

        Write-Host 'Perfil Super-Admin seleccionado.' -ForegroundColor Green
    }
    catch {
        throw "No fue posible activar el perfil Super-Admin: $($_.Exception.Message)"
    }

    Write-Host 'Conexión con GLPI establecida.' -ForegroundColor Green
}

function Disconnect-GLPI {

    if ($script:ApiHeaders) {
        try {
            Invoke-RestMethod `
                -Uri "$ApiBase/killSession" `
                -Method GET `
                -Headers $script:ApiHeaders | Out-Null
        }
        catch {}
    }

    $script:AppToken = $null
    $script:UserToken = $null
    $script:ApiHeaders = $null
}

function Invoke-GLPIGet {
    param([string]$Ruta)

    Invoke-RestMethod `
        -Uri "$ApiBase/$Ruta" `
        -Method GET `
        -Headers $script:ApiHeaders
}

function Invoke-GLPIPut {
    param(
        [string]$Ruta,
        [hashtable]$Datos
    )

    $body = @{
        input = $Datos
    } | ConvertTo-Json -Depth 12

    Invoke-RestMethod `
        -Uri "$ApiBase/$Ruta" `
        -Method PUT `
        -Headers $script:ApiHeaders `
        -Body $body
}

function Invoke-GLPIPost {
    param(
        [string]$Ruta,
        [hashtable]$Datos
    )

    $body = @{ input = $Datos } | ConvertTo-Json -Depth 12

    Invoke-RestMethod `
        -Uri "$ApiBase/$Ruta" `
        -Method POST `
        -Headers $script:ApiHeaders `
        -Body $body
}

function Get-SerieFisica {
    $serie = (Get-CimInstance Win32_BIOS).SerialNumber.Trim()

    if ([string]::IsNullOrWhiteSpace($serie) -or
        $serie -match '^(To be filled|Default string|None|Unknown|System Serial Number)$') {
        throw "No se pudo obtener una serie física válida del BIOS."
    }

    return $serie
}

function Get-GLPIRows {
    param($Respuesta)

    if ($null -eq $Respuesta) {
        return @()
    }

    if ($Respuesta -is [System.Array]) {
        return @($Respuesta)
    }

    if ($Respuesta.PSObject.Properties.Name -contains 'data') {
        return @($Respuesta.data)
    }

    return @($Respuesta)
}

# ==========================================================
# CONSULTAR DESPLEGABLES DE GLPI
# ==========================================================

function Get-GLPIDropdown {
    param([string]$Endpoint)

    $respuesta = Invoke-GLPIGet "$Endpoint`?range=0-9999"

    return @(Get-GLPIRows $respuesta)
}

function Get-GLPITorres {
    return @(Get-GLPIDropdown 'PluginFieldsTorrefieldDropdown')
}

function Get-GLPIUsuarios {

    $respuesta = Invoke-GLPIGet 'User/?range=0-9999'

    return @(
        Get-GLPIRows $respuesta |
        Where-Object {
            $_.is_active -eq 1 -or $_.is_active -eq $true
        }
    )
}

function Get-GLPIUbicaciones {

    $respuesta = Invoke-GLPIGet 'Location/?range=0-9999'

    return @(
        Get-GLPIRows $respuesta |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace($_.completename)
        }
    )
}# ==========================================================
# FORMULARIO DE REGISTRO
# ==========================================================

function Show-RegistroForm {

    param(
        $Torres,
        $Usuarios,
        $Ubicaciones
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    [System.Windows.Forms.Application]::EnableVisualStyles()

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'SkanHawk - Registro de activo'
    $form.Size = New-Object System.Drawing.Size(570, 650)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false

    function Add-Label {
        param($Texto, $X, $Y)

        $label = New-Object System.Windows.Forms.Label
        $label.Text = $Texto
        $label.Location = New-Object System.Drawing.Point($X, $Y)
        $label.Size = New-Object System.Drawing.Size(190, 25)

        $form.Controls.Add($label)
    }

   
function Add-Combo {
    param($X, $Y, $Ancho = 320)

    $combo = New-Object System.Windows.Forms.ComboBox
    $combo.Location = New-Object System.Drawing.Point($X, $Y)
    $combo.Size = New-Object System.Drawing.Size($Ancho, 25)

    # Permitir escribir para buscar opciones
    $combo.DropDownStyle = 'DropDown'
    $combo.AutoCompleteMode = 'SuggestAppend'
    $combo.AutoCompleteSource = 'ListItems'

    $form.Controls.Add($combo)

    return $combo
}


    # Código de inventario
    Add-Label 'Código de inventario' 20 25

    $txtSticker = New-Object System.Windows.Forms.TextBox
    $txtSticker.Location = New-Object System.Drawing.Point(220, 22)
    $txtSticker.Size = New-Object System.Drawing.Size(300, 25)

    $form.Controls.Add($txtSticker)

    # Tipo de propiedad
    Add-Label 'Tipo de propiedad' 20 70

    $cbPropiedad = Add-Combo 220 67

    [void]$cbPropiedad.Items.Add('Rentado')
    [void]$cbPropiedad.Items.Add('Propio')

    $cbPropiedad.SelectedIndex = 0

    # Empresa
    Add-Label 'Empresa' 20 110

    $cbEmpresa = Add-Combo 220 107

    [void]$cbEmpresa.Items.Add('RentaComputo')
    [void]$cbEmpresa.Items.Add('SkanHawk')

    $cbEmpresa.SelectedIndex = 0

    # Tipo de dueño
    Add-Label 'Tipo de dueño' 20 150

    $cbDueno = Add-Combo 220 147

    [void]$cbDueno.Items.Add('Torre/Rig')
    [void]$cbDueno.Items.Add('Persona')

    $cbDueno.SelectedIndex = 0

    # Torres
    Add-Label 'Torre / Rig' 20 190

    $cbTorre = Add-Combo 220 187

    $cbTorre.DisplayMember = 'Text'
    $cbTorre.ValueMember = 'Id'

    foreach ($torre in ($Torres | Sort-Object name)) {

        [void]$cbTorre.Items.Add(
            [PSCustomObject]@{
                Text = [string]$torre.name
                Id   = [int]$torre.id
            }
        )
    }

    if ($cbTorre.Items.Count -gt 0) {
        $cbTorre.SelectedIndex = 0
    }

    # Actualizar torres
    $btnActualizar = New-Object System.Windows.Forms.Button
    $btnActualizar.Text = 'Actualizar torres'
    $btnActualizar.Location = New-Object System.Drawing.Point(220, 220)
    $btnActualizar.Size = New-Object System.Drawing.Size(140, 28)

    $form.Controls.Add($btnActualizar)

    $btnActualizar.Add_Click({

        try {

            $nuevasTorres = @(Get-GLPITorres)

            if ($nuevasTorres.Count -eq 0) {
                Show-Msg 'GLPI no devolvió torres.'
                return
            }

            $cbTorre.Items.Clear()

            foreach ($torre in ($nuevasTorres | Sort-Object name)) {

                [void]$cbTorre.Items.Add(
                    [PSCustomObject]@{
                        Text = [string]$torre.name
                        Id   = [int]$torre.id
                    }
                )
            }

            $cbTorre.SelectedIndex = 0

            Show-Msg 'Las torres se actualizaron desde GLPI.'
        }
        catch {
            Show-Msg "Error actualizando torres:`n$($_.Exception.Message)"
        }
    })

    # Usuarios
    Add-Label 'Persona / Usuario GLPI' 20 270

    $cbUsuario = Add-Combo 220 267
    $cbUsuario.DisplayMember = 'Text'
    $cbUsuario.ValueMember = 'Id'

    foreach ($usuario in ($Usuarios | Sort-Object name)) {

        $nombre = (
            "$($usuario.firstname) $($usuario.realname)"
        ).Trim()

        if ([string]::IsNullOrWhiteSpace($nombre)) {
            $nombre = [string]$usuario.name
        }
        else {
            $nombre = "$nombre ($($usuario.name))"
        }

        [void]$cbUsuario.Items.Add(
            [PSCustomObject]@{
                Text = $nombre
                Id   = [int]$usuario.id
            }
        )
    }

    if ($cbUsuario.Items.Count -gt 0) {
        $cbUsuario.SelectedIndex = 0
    }

    # Ubicaciones
    Add-Label 'Ubicación GLPI' 20 310

    $cbUbicacion = Add-Combo 220 307 320

    foreach ($ubicacion in ($Ubicaciones | Sort-Object completename)) {

        [void]$cbUbicacion.Items.Add(
            [PSCustomObject]@{
                Text = [string]$ubicacion.completename
                Id   = [int]$ubicacion.id
            }
        )
    }

    $cbUbicacion.DisplayMember = 'Text'
    $cbUbicacion.ValueMember = 'Id'

    if ($cbUbicacion.Items.Count -gt 0) {
        $cbUbicacion.SelectedIndex = 0
    }

    # Activación según tipo de dueño
    $cbDueno.Add_SelectedIndexChanged({

        $esTorre = ($cbDueno.SelectedItem -eq 'Torre/Rig')

        $cbTorre.Enabled = $esTorre
        $btnActualizar.Enabled = $esTorre
        $cbUsuario.Enabled = -not $esTorre
    })

    $cbDueno.SelectedIndex = 0

    # Información
    $info = New-Object System.Windows.Forms.Label
    $info.Text = 'Seleccione los datos del activo. La torre y el usuario se consultan en GLPI.'
    $info.Location = New-Object System.Drawing.Point(20, 355)
    $info.Size = New-Object System.Drawing.Size(520, 40)

    $form.Controls.Add($info)

    # Botones
    $btnGuardar = New-Object System.Windows.Forms.Button
    $btnGuardar.Text = 'Guardar y enviar'
    $btnGuardar.Location = New-Object System.Drawing.Point(220, 420)
    $btnGuardar.Size = New-Object System.Drawing.Size(140, 35)

    $btnCancelar = New-Object System.Windows.Forms.Button
    $btnCancelar.Text = 'Cancelar'
    $btnCancelar.Location = New-Object System.Drawing.Point(370, 420)
    $btnCancelar.Size = New-Object System.Drawing.Size(100, 35)

    $form.Controls.AddRange(@($btnGuardar, $btnCancelar))

    $script:RegistroSeleccionado = $null

    $btnGuardar.Add_Click({

        $sticker = $txtSticker.Text.Trim()

        if ($sticker -notmatch '^\d{4,8}$') {
            Show-Msg 'El código debe tener entre 4 y 8 dígitos.'
            return
        }

        if ($cbUbicacion.SelectedItem -eq $null) {
            Show-Msg 'Seleccione una ubicación.'
            return
        }

        if (
            $cbDueno.SelectedItem -eq 'Torre/Rig' -and
            $cbTorre.SelectedItem -eq $null
        ) {
            Show-Msg 'Seleccione una torre.'
            return
        }

        if (
            $cbDueno.SelectedItem -eq 'Persona' -and
            $cbUsuario.SelectedItem -eq $null
        ) {
            Show-Msg 'Seleccione un usuario.'
            return
        }

        $script:RegistroSeleccionado = [PSCustomObject]@{

            Sticker       = $sticker
            TipoPropiedad = [string]$cbPropiedad.SelectedItem
            Empresa       = [string]$cbEmpresa.SelectedItem
            TipoDueno     = [string]$cbDueno.SelectedItem

            Torre         = $cbTorre.SelectedItem
            Usuario       = $cbUsuario.SelectedItem

            Ubicacion     = $cbUbicacion.SelectedItem
        }

        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })

    $btnCancelar.Add_Click({

        $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $form.Close()
    })

    $form.AcceptButton = $btnGuardar
    $form.CancelButton = $btnCancelar

    $resultado = $form.ShowDialog()

    if ($resultado -eq [System.Windows.Forms.DialogResult]::OK) {
        return $script:RegistroSeleccionado
    }

    return $null
}

# ==========================================================
# GENERAR XML DEL ACTIVO
# ==========================================================

function Save-ActivoXML {

    param($Datos)

    $nombre = if ($Datos.TipoDueno -eq 'Torre/Rig') {
        $Datos.Torre.Text
    }
    else {
        $Datos.Usuario.Text
    }

    $comentario = "UBICACION=$($Datos.Ubicacion.Text) | TIPO=$($Datos.TipoDueno) | NOMBRE=$nombre"

    $comentarioXML = [System.Security.SecurityElement]::Escape($comentario)

    $xml = @"
<?xml version="1.0" encoding="UTF-8"?>
<REQUEST>
  <CONTENT>
    <BIOS>
      <ASSETTAG>$($Datos.Sticker)</ASSETTAG>
    </BIOS>
    <HARDWARE>
      <OSCOMMENTS>$comentarioXML</OSCOMMENTS>
    </HARDWARE>
  </CONTENT>
</REQUEST>
"@

    Set-Content -Path $XmlFile -Value $xml -Encoding UTF8

    Write-Host "XML guardado: $XmlFile" -ForegroundColor Green
}# ==========================================================
# VERIFICAR E INSTALAR GLPI AGENT
# ========================================================== 

function Install-GLPIAgent {
    Write-Paso "Verificando GLPI Agent"

    $msiUrl = 'https://github.com/glpi-project/glpi-agent/releases/download/1.21/GLPI-Agent-1.21-x64.msi'
    $expectedHash = '152BD777ABC5A6D0E8A1F163AF25C6B8C166F47895D115076B480863A5F0DE6C'
    $msiPath = Join-Path $env:TEMP 'GLPI-Agent-1.21-x64.msi'

    $regPath = 'HKLM:\SOFTWARE\GLPI-Agent'

    $agentUser = $AgentUser
    $plainPassword = $AgentPassword

    $uninstallPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    try {
        # 1. Verificar si GLPI Agent ya está instalado
        $installedApps = Get-ItemProperty -Path $uninstallPaths `
            -ErrorAction SilentlyContinue

        $agent = $installedApps |
            Where-Object { $_.DisplayName -like 'GLPI Agent*' } |
            Select-Object -First 1

        $version = if ($agent) {
            [string]$agent.DisplayVersion
        } else {
            $null
        }

        if ($version -like '1.21*') {
            Write-Host "GLPI Agent $version ya está instalado." -ForegroundColor Green
        }
        else {
            # 2. Descargar e instalar GLPI Agent 1.21
            Write-Host "Descargando GLPI Agent 1.21..." -ForegroundColor Cyan

            Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath `
                -UseBasicParsing -ErrorAction Stop

            Write-Host "Verificando SHA256..."

            $actualHash = (Get-FileHash -Path $msiPath -Algorithm SHA256).Hash

            if ($actualHash -ne $expectedHash) {
                throw "El SHA256 no coincide. Se canceló la instalación."
            }

            Write-Host "SHA256 correcto." -ForegroundColor Green

            $arguments = "/i `"$msiPath`" /qn SERVER=`"$Servidor`" RUNNOW=1"

            $process = Start-Process -FilePath 'msiexec.exe' `
                -ArgumentList $arguments -Wait -PassThru

            if ($process.ExitCode -notin @(0, 3010, 1641)) {
                throw "Falló la instalación. Código MSI: $($process.ExitCode)"
            }

            Start-Sleep -Seconds 3

            $installedApps = Get-ItemProperty -Path $uninstallPaths `
                -ErrorAction SilentlyContinue

            $agent = $installedApps |
                Where-Object { $_.DisplayName -like 'GLPI Agent*' } |
                Select-Object -First 1

            if (-not $agent -or $agent.DisplayVersion -notlike '1.21*') {
                throw "No se pudo confirmar la instalación de GLPI Agent 1.21."
            }

            Write-Host "GLPI Agent instalado correctamente." -ForegroundColor Green

            if ($process.ExitCode -in @(3010, 1641)) {
                Write-Warning "Windows indicó que se requiere reiniciar el equipo."
            }
        }

        # 3. Validar credenciales
        if ([string]::IsNullOrWhiteSpace($Servidor)) {
            throw "La dirección del servidor GLPI está vacía."
        }

        if ([string]::IsNullOrWhiteSpace($agentUser)) {
            throw "El usuario del agente está vacío."
        }

        if ([string]::IsNullOrWhiteSpace($plainPassword)) {
            throw "La contraseña del agente está vacía."
        }

        # 4. Configurar servidor y autenticación en el Registro
        Write-Host "Configurando conexión con GLPI..." -ForegroundColor Cyan

        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }

        New-ItemProperty -Path $regPath -Name 'server' `
            -Value $Servidor -PropertyType String -Force | Out-Null

        New-ItemProperty -Path $regPath -Name 'user' `
            -Value $agentUser -PropertyType String -Force | Out-Null

        New-ItemProperty -Path $regPath -Name 'password' `
            -Value $plainPassword -PropertyType String -Force | Out-Null

        Write-Host "Configuración del servidor y credenciales guardada." -ForegroundColor Green

        # 5. Reiniciar el servicio
        Write-Host "Reiniciando GLPI Agent..." -ForegroundColor Cyan

        $service = Get-Service -Name 'glpi-agent' -ErrorAction Stop

        if ($service.Status -eq 'Running') {
            Restart-Service -Name 'glpi-agent' -ErrorAction Stop
        }
        else {
            Start-Service -Name 'glpi-agent' -ErrorAction Stop
        }

        (Get-Service -Name 'glpi-agent').WaitForStatus(
            'Running',
            [TimeSpan]::FromSeconds(30)
        )

        Write-Host "GLPI Agent está ejecutándose correctamente." -ForegroundColor Green
    }
    finally {
        $plainPassword = $null

        if (Test-Path $msiPath) {
            Remove-Item $msiPath -Force -ErrorAction SilentlyContinue
        }
    }
}

# ==========================================================
# VALIDAR SERVIDOR
# ==========================================================

function Test-Servidor {

    try {

        $respuesta = Invoke-WebRequest `
            -Uri $Servidor `
            -UseBasicParsing `
            -TimeoutSec 20

        return ($respuesta.StatusCode -ge 200 -and $respuesta.StatusCode -lt 400)
    }
    catch {

        Write-Warning "No fue posible validar el servidor: $($_.Exception.Message)"
        return $false
    }
}

# ==========================================================
# BUSCAR COMPUTADOR EN GLPI
# ==========================================================

function Find-ComputerGLPI {

    param(
        [string]$NumeroInventario,
        [string]$NumeroSerie
    )

   Write-Paso "Buscando computador en GLPI"

Write-Host ""
Write-Host "El inventario se está enviando a GLPI." -ForegroundColor Cyan
Write-Host "Por favor, espere hasta 5 minutos mientras se registra el computador." -ForegroundColor Yellow
Write-Host "No cierre esta ventana ni apague el equipo." -ForegroundColor Yellow
Write-Host ""

    $respuesta = Invoke-GLPIGet 'Computer/?range=0-9999'
    $computadores = @(Get-GLPIRows $respuesta)

    $coincidencias = @(
        $computadores | Where-Object {
            (
                -not [string]::IsNullOrWhiteSpace($NumeroInventario) -and
                [string]$_.otherserial -eq $NumeroInventario
            ) -or (
                -not [string]::IsNullOrWhiteSpace($NumeroSerie) -and
                [string]$_.serial -eq $NumeroSerie
            )
        }
    )

    $ids = @($coincidencias | ForEach-Object { [int]$_.id } | Select-Object -Unique)

    if ($ids.Count -gt 1) {
        throw "El inventario y la serie coinciden con computadores diferentes. No se modificará ninguno."
    }

    if ($ids.Count -eq 1) {
        return $coincidencias | Where-Object { [int]$_.id -eq $ids[0] } | Select-Object -First 1
    }

    return $null
}

# ==========================================================
# ACTUALIZAR CAMPOS FIELDS Y DATOS NATIVOS
# ==========================================================


function Update-ComputerGLPI {

    param(
        $Computer,
        $Datos,
        [string]$NumeroSerie,
        [string]$NumeroInventario
    )

    $computerId = [int]$Computer.id

    Write-Paso "Preparando actualización del computador ID $computerId"

    # Campos Fields del contenedor Datos PC (ID 6).
    $fieldsInput = @{
        id = $computerId
        c_id = $ContainerId

        plugin_fields_tipodepropiedadfielddropdowns_id =
            [int]$TipoPropiedad[$Datos.TipoPropiedad]

        plugin_fields_empresafielddropdowns_id =
            [int]$Empresa[$Datos.Empresa]

        plugin_fields_tipodedueofielddropdowns_id =
            [int]$TipoDueno[$Datos.TipoDueno]
    }

    if ($Datos.TipoDueno -eq 'Torre/Rig') {
        $fieldsInput.plugin_fields_torrefielddropdowns_id =
            [int]$Datos.Torre.Id
    }
    else {
        $fieldsInput.plugin_fields_torrefielddropdowns_id = 0
    }

    # Campos nativos de GLPI.
    $computerInput = @{
        id           = $computerId
        serial       = $NumeroSerie
        otherserial  = $NumeroInventario
        locations_id = [int]$Datos.Ubicacion.Id
    }

    if ($Datos.TipoDueno -eq 'Persona') {
        $computerInput.users_id = [int]$Datos.Usuario.Id
    }

    Write-Paso 'Enviando campos Fields a GLPI'

    $resultadoFields = Invoke-GLPIPut `
        -Ruta "Computer/$computerId" `
        -Datos $fieldsInput

    if ($null -eq $resultadoFields) {
        throw 'GLPI no devolvió confirmación de la actualización Fields.'
    }

    Write-Paso 'Actualizando serie, inventario, ubicación y usuario'

    $resultadoComputer = Invoke-GLPIPut `
        -Ruta "Computer/$computerId" `
        -Datos $computerInput

    if ($null -eq $resultadoComputer) {
        throw 'GLPI no devolvió confirmación de la actualización del computador.'
    }

    Write-Paso 'Verificando actualización en GLPI'

    $verificacion = Invoke-GLPIGet "Computer/$computerId"

    if ([int]$verificacion.id -ne $computerId) {
        throw 'No fue posible verificar el computador.'
    }

    if ([string]$verificacion.serial -ne $NumeroSerie) {
        throw 'La serie física no coincide con el valor enviado a GLPI.'
    }

    if ([string]$verificacion.otherserial -ne $NumeroInventario) {
        throw 'El número de inventario no coincide con el valor enviado a GLPI.'
    }

    if ([int]$verificacion.locations_id -ne [int]$Datos.Ubicacion.Id) {
        throw 'La ubicación no coincide con el valor enviado a GLPI.'
    }

    if ($Datos.TipoDueno -eq 'Persona') {
        if ([int]$verificacion.users_id -ne [int]$Datos.Usuario.Id) {
            throw 'El usuario asociado no coincide con el valor enviado a GLPI.'
        }
    }

    Write-Host 'Los datos nativos del computador fueron verificados.' `
        -ForegroundColor Green

    return $true
}

# ==========================================================
# EJECUCIÓN PRINCIPAL
# ==========================================================

$transcripcionActiva = $false

try {

    # Evitar que los tokens ingresados queden registrados.
    try {
        Start-Transcript -Path $LogFile -Append | Out-Null
        $transcripcionActiva = $true
    }
    catch {}

    Write-Paso 'Comprobando permisos de administrador'

    $principal = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )

    if (-not $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )) {
        throw 'Ejecute PowerShell como Administrador.'
    }

    Write-Paso 'Validando servidor GLPI'

    if (-not (Test-Servidor)) {
        throw "No fue posible conectar con $Servidor."
    }

    Write-Paso 'Verificando GLPI Agent'

    Install-GLPIAgent

    # Detener transcripción antes de pedir los tokens.
    if ($transcripcionActiva) {
        Stop-Transcript | Out-Null
        $transcripcionActiva = $false
    }

    Connect-GLPI

    # Volver a iniciar registro después de autenticarse.
    try {
        Start-Transcript -Path $LogFile -Append | Out-Null
        $transcripcionActiva = $true
    }
    catch {}

    Write-Paso 'Consultando torres, usuarios y ubicaciones'

    $torres = @(Get-GLPITorres)
    $usuarios = @(Get-GLPIUsuarios)
    $ubicaciones = @(Get-GLPIUbicaciones)

    if ($torres.Count -eq 0) {
        throw 'No se encontraron torres en el desplegable torrefield.'
    }

    if ($usuarios.Count -eq 0) {
        throw 'No se encontraron usuarios activos en GLPI.'
    }

    if ($ubicaciones.Count -eq 0) {
        throw 'No se encontraron ubicaciones en GLPI.'
    }

    Write-Paso 'Abriendo formulario de registro'

    $datos = Show-RegistroForm `
        -Torres $torres `
        -Usuarios $usuarios `
        -Ubicaciones $ubicaciones

    if ($null -eq $datos) {
        Write-Host 'Registro cancelado por el usuario.'
        return
    }

    # Guardar XML local.
    Write-Paso 'Guardando información local'

    Save-ActivoXML -Datos $datos

    # Solicitar inventario inmediato.
    Write-Paso 'Solicitando inventario al agente'

    try {

        $respuestaAgente = Invoke-WebRequest `
            -Uri $AgentUrl `
            -Method GET `
            -UseBasicParsing `
            -TimeoutSec 20

        Write-Host 'El agente recibió la solicitud local.' `
            -ForegroundColor Green
    }
    catch {

        Write-Warning "No se confirmó la solicitud local del agente: $($_.Exception.Message)"
    }

    # Buscar equipo ya registrado.
    
    # Obtener serie física y número de inventario.
    Write-Paso 'Obteniendo serie física del equipo'

    $NumeroInventario = ([string]$datos.Sticker).Trim()
    $NumeroSerie = Get-SerieFisica

    if ([string]::IsNullOrWhiteSpace($NumeroInventario)) {
        throw 'El número de inventario está vacío.'
    }

    # Buscar por serie física o número de inventario.
    Write-Paso 'Buscando computador en GLPI'

    $computer = Find-ComputerGLPI `
        -NumeroInventario $NumeroInventario `
        -NumeroSerie $NumeroSerie

    if ($null -ne $computer) {

        Write-Host "Computador existente. ID: $($computer.id)" `
            -ForegroundColor Yellow

    }
else {

    Write-Host 'Computador aún no aparece en GLPI. Esperando sincronización del agente...' `
        -ForegroundColor Cyan

    $computer = $null

    for ($intento = 1; $intento -le 60; $intento++) {

        Start-Sleep -Seconds 5

        Write-Host "Consulta $intento de 24..." -ForegroundColor Gray

        $computer = Find-ComputerGLPI `
            -NumeroInventario $NumeroInventario `
            -NumeroSerie $NumeroSerie

        if ($null -ne $computer) {
            Write-Host "Computador encontrado. ID: $($computer.id)" `
                -ForegroundColor Green
            break
        }
    }

    if ($null -eq $computer) {
        throw 'El GLPI Agent no registró el computador en GLPI después de 2 minutos. No se actualizaron los campos manuales.'
    }
}

    
    # Actualizar campos Fields y datos nativos.
    $actualizado = Update-ComputerGLPI `
        -Computer $computer `
        -Datos $datos `
        -NumeroSerie $NumeroSerie `
        -NumeroInventario $NumeroInventario

    if ($actualizado) {

        Show-Msg @"
Registro enviado a GLPI correctamente.

Computador: $($computer.name)
ID GLPI: $($computer.id)
Serie física: $NumeroSerie
Número de inventario: $NumeroInventario
Ubicación: $($datos.Ubicacion.Text)

XML local:
$XmlFile
"@
    }

}
catch {

    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red

    try {
        Show-Msg `
            -Texto "No se pudo completar el registro:`n`n$($_.Exception.Message)" `
            -Titulo 'Error - SkanHawk GLPI'
    }
    catch {}
}
finally {

    Disconnect-GLPI

    $script:AppToken = $null
    $script:UserToken = $null
    $script:ApiHeaders = $null

    if ($transcripcionActiva) {
        try {
            Stop-Transcript | Out-Null
        }
        catch {}
    }
}
