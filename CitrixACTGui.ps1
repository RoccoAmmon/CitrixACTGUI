<#
.SYNOPSIS
    Helle, resizebare WPF-GUI für Backup & Restore einer Citrix CVAD/DaaS-Umgebung
    über das Automated Configuration Tool (ACT) – für OnPrem UND Cloud.

.DESCRIPTION
    - Backup / Restore wählbar, optionaler Trockenlauf (CheckMode)
    - Umgebung: OnPrem oder Cloud (Citrix DaaS)
    - Cloud: Eingabe von Customer ID, Client ID, Secret über GUI-Felder
    - Cloud: Automatische Generierung der CustomerInfo.yml
    - Cloud: Validierung der Anmeldedaten vor Ausführung
    - Ordnerbasiertes .yml-Konzept des ACT
    - DisplayLog=$false -> kein blockierendes Notepad
    - SYNCHRONE Ausführung mit Stream-Capture -> ACT-Ausgabe landet im GUI-Log
    - Auswertung von Overall_Success
    - Logging nach C:\ScriptLog

.NOTES
    Autor   : Rocco Ammon
    Version : 1.1.0 (Cloud-Anmeldung + Credentials-Validierung)
    Stand   : 01.07.2026
#>

#region === ZENTRALE VARIABLEN =================================================
$Global:LogVerzeichnis       = 'C:\ScriptLog'
$Global:LogDatei             = Join-Path $LogVerzeichnis ("CVAD-ACT-GUI_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
$Global:StandardBackupOrdner = 'C:\CvadBackups'

$Global:CvadKomponenten = @(
    'Zones','Tags','AdminRoles','AdminScopes','HostConnections',
    'MachineCatalogs','PolicySets','Storefronts','DeliveryGroups','ApplicationGroups',
    'ApplicationFolders','Applications','AppLibPackageDiscovery','AdminAdministrators','AdminFolders',
    'GroupPolicies','SiteData','UserZonePreferences','AppVIsolationGroups','BackupSchedules'
)
#endregion =====================================================================


#region === HILFSFUNKTIONEN ====================================================

function Write-Log {
    param(
        [Parameter(Mandatory)] [string] $Nachricht,
        [ValidateSet('INFO','WARN','ERROR')] [string] $Stufe = 'INFO'
    )
    try {
        if (-not (Test-Path $Global:LogVerzeichnis)) {
            New-Item -Path $Global:LogVerzeichnis -ItemType Directory -Force | Out-Null
        }
        $zeile = "[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}" -f (Get-Date), $Stufe, $Nachricht
        Add-Content -Path $Global:LogDatei -Value $zeile -Encoding UTF8

        if ($Global:txtLog) {
            $Global:txtLog.Dispatcher.Invoke([action]{
                $Global:txtLog.AppendText("$zeile`r`n")
                $Global:txtLog.ScrollToEnd()
            }, [System.Windows.Threading.DispatcherPriority]::Send)
        }
    }
    catch {
        Write-Warning "Logging fehlgeschlagen: $($_.Exception.Message)"
    }
}

function Initialize-ActModul {
    try {
        $cmd = Get-Command -Name 'Export-CvadAcToFile' -ErrorAction SilentlyContinue
        if ($cmd) {
            Write-Log "ACT-Cmdlets sind bereits geladen (Modul/SnapIn aktiv)." 'INFO'
            return $true
        }

        Write-Log "ACT-Cmdlets nicht gefunden – versuche zu laden ..." 'WARN'

        # a) Als SnapIn registriert?
        $snapins = @('Citrix.AutoConfig.Commands','Citrix.Common.Commands')
        foreach ($s in $snapins) {
            if (Get-PSSnapin -Registered -Name $s -ErrorAction SilentlyContinue) {
                Add-PSSnapin $s -ErrorAction Stop
                Write-Log "ACT-SnapIn hinzugefügt: $s" 'INFO'
                return $true
            }
        }
        # b) Als Modul?
        foreach ($m in @('Citrix.AutoConfig.Commands','Citrix.AutoConfig')) {
            if (Get-Module -ListAvailable -Name $m -ErrorAction SilentlyContinue) {
                Import-Module $m -ErrorAction Stop
                Write-Log "ACT-Modul geladen: $m" 'INFO'
                return $true
            }
        }

        Write-Log "ACT-Cmdlets konnten nicht geladen werden." 'ERROR'
        return $false
    }
    catch {
        Write-Log "Fehler beim Laden der ACT-Cmdlets: $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

function Test-OverallSuccess {
    param([Parameter(Mandatory=$false)] $Ergebnis, [string] $Aktion = 'Aktion')

    if ($null -ne $Ergebnis -and ($Ergebnis | Get-Member -Name 'Overall_Success' -ErrorAction SilentlyContinue)) {
        if ($Ergebnis.Overall_Success) {
            Write-Log "$Aktion meldet Overall_Success = TRUE." 'INFO'
            return $true
        }
        Write-Log "$Aktion meldet Overall_Success = FALSE (Teil-/Gesamtfehler!)." 'ERROR'
        Write-Log "⚠️ Fehlerdetails in der ACT History.log prüfen! Diese befindet sich im Backup-Ordner." 'WARN'
        return $false
    }
    Write-Log "$Aktion lieferte kein Overall_Success-Feld – als erfolgreich gewertet." 'WARN'
    return $true
}

function Get-CvadBackupOrdner {
    param([Parameter(Mandatory)] [string] $Basisordner)
    if (-not (Test-Path $Basisordner -PathType Container)) { return @() }
    return @(
        Get-ChildItem -Path $Basisordner -Directory -ErrorAction SilentlyContinue |
        Where-Object { Get-ChildItem -Path $_.FullName -Filter '*.yml' -File -ErrorAction SilentlyContinue } |
        Sort-Object LastWriteTime -Descending
    )
}

function Invoke-CvadOperation {
    <#
    .SYNOPSIS
        Führt ein ACT-Cmdlet SYNCHRON aus und leitet dessen Konsolenausgabe
        (Information/Verbose/Warning/Error) ins GUI-Log um.
        Gibt das ActionResult-Objekt zurück.
    #>
    param(
        [Parameter(Mandatory)] [string]    $CmdName,
        [Parameter(Mandatory)] [hashtable] $Parameter
    )

    Write-Log "Starte $CmdName ..." 'INFO'
    $btnStart.IsEnabled = $false
    $btnStart.Content   = '⏳ Läuft ...'
    # GUI einmal zeichnen lassen, bevor der UI-Thread blockiert
    $Fenster.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Render)

    $actionResult = $null
    try {
        # ACT-Bestätigungen automatisch bestätigen (ohne Confirm-Parameter, da nicht alle Cmdlets ihn unterstützen)
        $prevConfirmPreference = $ConfirmPreference
        $ConfirmPreference = 'None'
        
        # Alle Nebenstreams einfangen, Ergebnisobjekt durchreichen
        $alle = & $CmdName @Parameter 2>&1 3>&1 4>&1 5>&1 6>&1
        foreach ($item in $alle) {
            if     ($item -is [System.Management.Automation.InformationRecord]) { Write-Log ([string]$item.MessageData) 'INFO' }
            elseif ($item -is [System.Management.Automation.VerboseRecord])     { Write-Log $item.Message 'INFO' }
            elseif ($item -is [System.Management.Automation.WarningRecord])     { Write-Log $item.Message 'WARN' }
            elseif ($item -is [System.Management.Automation.ErrorRecord])       { Write-Log $item.Exception.Message 'ERROR' }
            elseif ($item -is [string])                                         { if ($item.Trim()) { Write-Log $item.Trim() 'INFO' } }
            else                                                                { $actionResult = $item }
        }
    }
    finally {
        $ConfirmPreference = $prevConfirmPreference
        $btnStart.IsEnabled = $true
        $btnStart.Content   = '▶ Ausführen'
    }
    return $actionResult
}
#endregion =====================================================================


#region === GUI (XAML, helles Theme, resizebar) ================================
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

[xml]$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="CVAD ACT Backup &amp; Restore Manager"
    Height="700" Width="900" MinHeight="520" MinWidth="700"
    WindowStartupLocation="CenterScreen" Background="#FFF5F7FA"
    ResizeMode="CanResizeWithGrip" SizeToContent="Manual">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#FF2563EB"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Height" Value="38"/>
            <Setter Property="Margin" Value="5"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border CornerRadius="8" Background="{TemplateBinding Background}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="Label"><Setter Property="Foreground" Value="#FF1F2937"/><Setter Property="FontSize" Value="12"/></Style>
        <Style TargetType="GroupBox"><Setter Property="Foreground" Value="#FF1D4ED8"/><Setter Property="BorderBrush" Value="#FFCBD5E1"/><Setter Property="Margin" Value="8,3"/><Setter Property="Padding" Value="6"/><Setter Property="FontWeight" Value="SemiBold"/></Style>
        <Style TargetType="RadioButton"><Setter Property="Foreground" Value="#FF1F2937"/><Setter Property="Margin" Value="4"/></Style>
        <Style TargetType="CheckBox"><Setter Property="Foreground" Value="#FF1F2937"/><Setter Property="Margin" Value="4"/></Style>
        <Style TargetType="TextBox"><Setter Property="Background" Value="White"/><Setter Property="Foreground" Value="#FF111827"/><Setter Property="BorderBrush" Value="#FFCBD5E1"/></Style>
    </Window.Resources>
    <Grid Margin="12">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <TextBlock Grid.Row="0" Margin="0,0,0,6">
            <Run Text="CVAD ACT – Backup &amp; Restore" Foreground="#FF1D4ED8" FontSize="18" FontWeight="Bold"/>
            <Run Text="   v1.1.0" Foreground="#FF6B7280" FontSize="12" FontWeight="Normal" BaselineAlignment="Bottom"/>
        </TextBlock>

        <Grid Grid.Row="1">
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <GroupBox Grid.Column="0" Header="1) Aktion">
                <StackPanel>
                    <RadioButton x:Name="rbBackup"  Content="Backup erstellen" IsChecked="True"/>
                    <RadioButton x:Name="rbRestore" Content="Restore durchführen"/>
                    <CheckBox x:Name="chkCheckMode" Content="Trockenlauf (CheckMode)"/>
                </StackPanel>
            </GroupBox>
            <GroupBox Grid.Column="1" Header="2) Umgebung">
                <StackPanel>
                    <RadioButton x:Name="rbOnPrem" Content="OnPrem" IsChecked="True"/>
                    <RadioButton x:Name="rbCloud"  Content="Cloud"/>
                </StackPanel>
            </GroupBox>
        </Grid>

        <GroupBox Grid.Row="2" Header="Cloud-Anmeldung" x:Name="grpCloudCreds" Visibility="Collapsed">
            <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <TextBlock Grid.Row="0" Grid.Column="0" Grid.ColumnSpan="2" Foreground="#FF666666" FontSize="11" Margin="0,0,0,6" TextWrapping="Wrap">
                    Geben Sie Ihre echten Citrix Cloud-Anmeldedaten ein. Diese werden automatisch in C:\Users\[Username]\Documents\Citrix\AutoConfig\CustomerInfo.yml gespeichert.
                </TextBlock>
                <Label Content="Customer ID:" Grid.Row="1" Grid.Column="0" VerticalAlignment="Center"/>
                <TextBox x:Name="txtCustomerId" Grid.Row="1" Grid.Column="1" Height="24" VerticalContentAlignment="Center" Margin="4" ToolTip="z.B. markhof123 oder eine längere Kundennummer"/>
                <Label Content="Client ID:" Grid.Row="2" Grid.Column="0" VerticalAlignment="Center"/>
                <TextBox x:Name="txtClientId" Grid.Row="2" Grid.Column="1" Height="24" VerticalContentAlignment="Center" Margin="4" ToolTip="Format: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX (UUID)"/>
                <Label Content="Secret:" Grid.Row="3" Grid.Column="0" VerticalAlignment="Center"/>
                <PasswordBox x:Name="pwdSecret" Grid.Row="3" Grid.Column="1" Height="24" Margin="4" ToolTip="Verschlüsselter String (20+ Zeichen)"/>
                <TextBlock Grid.Row="4" Grid.Column="0" Grid.ColumnSpan="2" Foreground="#FF1D4ED8" FontSize="10" Margin="0,4,0,0" TextWrapping="Wrap">
                    💡 Tipp: Validierung überprüft die Daten vor dem Senden. Ungültige Credentials führen zu Authentifizierungsfehlern.
                </TextBlock>
                <TextBlock Grid.Row="5" Grid.Column="0" Grid.ColumnSpan="2" Foreground="#FFDC2626" FontSize="10" Margin="0,4,0,0" TextWrapping="Wrap">
                    ⚠️ Häufige Fehlerursachen:
                    • Credentials sind Test-Daten (zu kurz, zu einfach)
                    • Firewall blockiert Zugriff auf *.xendesktop.net und *.cloud.com
                    • Customer ID, Client ID oder Secret kopiert falsch
                </TextBlock>
            </Grid>
        </GroupBox>

        <GroupBox Grid.Row="3" Header="3) Backup-Ordner &amp; Komponenten">
            <StackPanel>
                <Grid Margin="0,0,0,4">
                    <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                    <Label Content="Ordner:" Grid.Column="0" Margin="0,0,4,0" VerticalAlignment="Center"/>
                    <TextBox x:Name="txtPfad" Grid.Column="1" Height="24" VerticalContentAlignment="Center" Margin="0,0,4,0"/>
                    <Button x:Name="btnBrowse" Grid.Column="2" Content="..." Width="30" Height="24"/>
                </Grid>
                <Label Content="Verfügbare Backups:" Margin="0,0,0,2"/>
                <ListBox x:Name="lstBackups" Height="90" SelectionMode="Single" Margin="0,0,0,4"
                         Background="White" Foreground="#FF111827" BorderBrush="#FFCBD5E1"/>
                <CheckBox x:Name="chkVollstaendig" Content="Backup: Komplette Site | Restore: nur angehakte Komponenten" IsChecked="True" Margin="0,0,0,4"/>
                <Grid Margin="0,0,0,2">
                    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                    <Label Content="Komponenten (anhaken/abhaken):" Grid.Column="0"/>
                    <Button x:Name="btnSelectAll" Grid.Column="1" Content="✓ Alle" Width="60" Height="24" Margin="4,0,0,0" IsEnabled="False"/>
                    <Button x:Name="btnSelectNone" Grid.Column="2" Content="✗ Keine" Width="60" Height="24" Margin="4,0,0,0" IsEnabled="False"/>
                    <Button x:Name="btnZoneMapping" Grid.Column="3" Content="🗺️ Zone Mapping" Width="160" Height="24" Margin="4,0,0,0" IsEnabled="False"/>
                </Grid>
                <Border BorderBrush="#FFCBD5E1" BorderThickness="1" Height="130" Margin="0,0,0,0" CornerRadius="4">
                    <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                        <UniformGrid x:Name="pnlKomponenten" Columns="5" Margin="4,2,4,2"/>
                    </ScrollViewer>
                </Border>
            </StackPanel>
        </GroupBox>

        <GroupBox Grid.Row="4" Header="Protokoll" MinHeight="120">
            <TextBox x:Name="txtLog" IsReadOnly="True" VerticalScrollBarVisibility="Auto"
                     Background="#FFF8FAFC" Foreground="#FF065F46" FontFamily="Consolas"
                     FontSize="12" TextWrapping="Wrap"/>
        </GroupBox>

        <Grid Grid.Row="5" Margin="0,6,0,0">
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <Button x:Name="btnStart" Grid.Column="0" Content="▶ Ausführen"/>
            <Button x:Name="btnSchliessen" Grid.Column="1" Content="✖ Schließen" Background="#FFDC2626"/>
        </Grid>
    </Grid>
</Window>
'@
#endregion =====================================================================


#region === GUI INITIALISIEREN =================================================
try {
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $Global:Fenster = [Windows.Markup.XamlReader]::Load($reader)
}
catch {
    Write-Error "Die GUI konnte nicht geladen werden: $($_.Exception.Message)"
    return
}

$rbBackup        = $Fenster.FindName('rbBackup')
$rbRestore       = $Fenster.FindName('rbRestore')
$chkCheckMode    = $Fenster.FindName('chkCheckMode')
$rbOnPrem        = $Fenster.FindName('rbOnPrem')
$rbCloud         = $Fenster.FindName('rbCloud')
$txtPfad         = $Fenster.FindName('txtPfad')
$lstBackups      = $Fenster.FindName('lstBackups')
$btnBrowse       = $Fenster.FindName('btnBrowse')
$chkVollstaendig = $Fenster.FindName('chkVollstaendig')
$btnSelectAll    = $Fenster.FindName('btnSelectAll')
$btnSelectNone   = $Fenster.FindName('btnSelectNone')
$btnZoneMapping  = $Fenster.FindName('btnZoneMapping')
$pnlKomponenten  = $Fenster.FindName('pnlKomponenten')
$Global:txtLog   = $Fenster.FindName('txtLog')
$btnStart        = $Fenster.FindName('btnStart')
$btnSchliessen   = $Fenster.FindName('btnSchliessen')
$grpCloudCreds   = $Fenster.FindName('grpCloudCreds')
$txtCustomerId   = $Fenster.FindName('txtCustomerId')
$txtClientId     = $Fenster.FindName('txtClientId')
$pwdSecret       = $Fenster.FindName('pwdSecret')

$txtPfad.Text = $Global:StandardBackupOrdner

# CheckBoxen für Komponenten dynamisch erstellen
foreach ($komp in $Global:CvadKomponenten) {
    $chk = New-Object System.Windows.Controls.CheckBox
    $chk.Content = $komp
    $chk.Margin = "8,2,8,2"
    $chk.Foreground = "#FF1F2937"
    $chk.IsChecked = $false
    $pnlKomponenten.Children.Add($chk) | Out-Null
}

function Select-ComponentsFromBackup {
    param([string] $BackupOrdner)
    try {
        $ymlFiles = @(Get-ChildItem -Path $BackupOrdner -Filter '*.yml' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty BaseName)
        
        if ($ymlFiles.Count -eq 0) {
            Write-Log "Keine YAML-Dateien in: $BackupOrdner" 'WARN'
            return
        }
        
        Write-Log "Verfügbare YAML-Dateien: $($ymlFiles -join ', ')" 'INFO'
        
        # Alle CheckBoxen im Panel durchlaufen und abhaken, wenn sie im Backup vorhanden sind
        foreach ($chk in $pnlKomponenten.Children) {
            if ($chk -is [System.Windows.Controls.CheckBox]) {
                $component = $chk.Content
                # Versuche zu matchen mit verschiedenen Varianten (z.B. "GroupPolicies" mit "GroupPolicy.yml")
                $found = $false
                foreach ($yml in $ymlFiles) {
                    # Entferne Plurale und Singular-Formen für Matching
                    $ymlSingular = $yml -replace 's$', ''
                    $ymlPlural = "$yml`s"
                    $compSingular = $component -replace 's$', ''
                    $compPlural = "$component`s"
                    
                    if ($yml -eq $component -or $yml -eq "$component.yml" -or 
                        $yml -match "^$component" -or 
                        $ymlSingular -match "^$compSingular" -or
                        $yml -match $compSingular) {
                        $found = $true
                        break
                    }
                }
                
                $chk.IsChecked = $found
                if ($chk.IsChecked) {
                    Write-Log "  ✓ Komponente angehakt: $component (YAML: $yml)" 'INFO'
                }
            }
        }
    }
    catch {
        Write-Log "Fehler beim Auslesen der Backup-Komponenten: $($_.Exception.Message)" 'WARN'
    }
}


function Get-CustomerInfoPath {
    <# Standardpfad für CustomerInfo.yml #>
    return Join-Path $env:USERPROFILE 'Documents\Citrix\AutoConfig\CustomerInfo.yml'
}

function Test-CustomerInfoValidity {
    param(
        [string] $CustomerId,
        [string] $ClientId,
        [string] $Secret
    )
    
    $warnings = @()
    
    # Customer ID Validierung
    if ($CustomerId.Length -lt 5) {
        $warnings += "⚠️ Customer ID ist sehr kurz ($($CustomerId.Length) Zeichen). Sollte mind. eine Kundennummer oder UUID sein."
    }
    
    # Client ID Validierung (sollte UUID sein)
    if ($ClientId -notmatch '^[a-fA-F0-9\-]{36}$' -and $ClientId.Length -lt 10) {
        $warnings += "⚠️ Client ID sieht nicht wie eine gültige UUID aus. Format sollte: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"
    }
    
    # Secret Validierung (sollte länger und Base64-ähnlich sein)
    if ($Secret.Length -lt 15) {
        $warnings += "⚠️ Secret ist sehr kurz ($($Secret.Length) Zeichen). Sollte mind. 20+ Zeichen sein (verschlüsselter String)."
    }
    
    if ($warnings.Count -gt 0) {
        Write-Log "⚠️ WARNUNG: Die eingegebenen Cloud-Anmeldedaten sehen ungültig aus!" 'WARN'
        foreach ($w in $warnings) {
            Write-Log $w 'WARN'
        }
        Write-Log "⚠️ Bitte überprüfen Sie Ihre Citrix Cloud-Anmeldedaten!" 'WARN'
        return $false
    }
    
    return $true
}

function Write-CustomerInfoYml {
    param(
        [string] $CustomerId,
        [string] $ClientId,
        [string] $Secret
    )
    try {
        # Validierung: Keine Leerzeichen am Anfang/Ende
        $CustomerId = $CustomerId.Trim()
        $ClientId   = $ClientId.Trim()
        $Secret     = $Secret.Trim()
        
        if (-not $CustomerId -or -not $ClientId -or -not $Secret) {
            Write-Log "Cloud-Anmeldedaten unvollständig! Alle Felder sind erforderlich." 'ERROR'
            return $false
        }
        
        # Verzeichnis erstellen, falls nicht vorhanden
        $dir = Join-Path $env:USERPROFILE 'Documents\Citrix\AutoConfig'
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Log "Verzeichnis erstellt: $dir" 'INFO'
        }
        
        # YAML-Datei mit vollständiger Struktur schreiben
        $filePath = Join-Path $dir 'CustomerInfo.yml'
        $timestamp = Get-Date -Format 'yyyy.MM.dd  HH:mm:ss'
        
        $lines = @(
            '---'
            "# Created/Updated on $timestamp"
            '# Be sure to single-quote all strings when manually updating'
            '# Be sure to include a space between the colon : and the value'
            "CustomerId: '$CustomerId'"
            "ClientId: '$ClientId'"
            "Secret: '$Secret'"
            '# Environment: Production, ProductionJP, ProductionGov'
            "Environment: Production"
            "LogTransactions: True"
            "Locale: 'de-DE'"
            "Editor: 'notepad.exe'"
            "DisplayLog: False"
            '# OnErrorAction: Continue, Pause, StopCompEnd, StopImmediately'
            "OnErrorAction: StopCompEnd"
            "Confirm: False"
        )
        $content = $lines -join "`n" + "`n"
        
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($filePath, $content, $utf8NoBom)
        
        Write-Log "CustomerInfo.yml geschrieben: $filePath" 'INFO'
        Write-Log "✓ Datei enthält alle erforderlichen Felder:" 'INFO'
        Write-Log "  ✓ CustomerId: $('*' * 8)...$(($CustomerId -replace '^(.{4}).*(.{4})$','$1...$2'))" 'INFO'
        Write-Log "  ✓ ClientId: $('*' * 8)...$(($ClientId -replace '^(.{4}).*(.{4})$','$1...$2'))" 'INFO'
        Write-Log "  ✓ Secret: [REDACTED]" 'INFO'
        Write-Log "  ✓ Environment: Production" 'INFO'
        
        # Vergewissern, dass die Datei geschrieben wurde
        if (-not (Test-Path $filePath)) {
            Write-Log "FEHLER: CustomerInfo.yml konnte nicht verifiziert werden!" 'ERROR'
            return $false
        }
        
        Write-Log "✓ CustomerInfo.yml erfolgreich verifiziert" 'INFO'
        return $true
    }
    catch {
        Write-Log "Fehler beim Schreiben von CustomerInfo.yml: $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

function Generate-ZoneMapping {
    param([string] $BackupOrdner)
    try {
        $zonePath = Join-Path $BackupOrdner 'Zone.yml'
        if (-not (Test-Path $zonePath)) {
            Write-Log "Zone.yml nicht gefunden in: $BackupOrdner" 'WARN'
            [System.Windows.MessageBox]::Show("Zone.yml nicht gefunden!`nKannst du das Zone Mapping manuell bearbeiten.","Fehler",'OK','Warning') | Out-Null
            return
        }

        # Zone.yml mit UTF8 einlesen
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        $content = [System.IO.File]::ReadAllText($zonePath, $utf8NoBom)
        $zones = @()
        
        # Extrahiere Zonennamen aus "- Name: 'ZoneName'"
        $matches = [regex]::Matches($content, "- Name:\s*'([^']+)'")
        foreach ($match in $matches) {
            $zoneName = $match.Groups[1].Value
            $zones += $zoneName
            Write-Log "  Zone gefunden: $zoneName" 'INFO'
        }

        if ($zones.Count -eq 0) {
            Write-Log "Keine Zonen in Zone.yml gefunden" 'WARN'
            return
        }

        # Generiere ZoneMapping.yml (1:1-Mapping: Source = Target)
        $mappingContent = "---`n"
        foreach ($zone in $zones) {
            $mappingContent += "$zone`: $zone`n"
        }

        # Speichere ZoneMapping.yml (UTF8 ohne BOM)
        $mappingPath = Join-Path $BackupOrdner 'ZoneMapping.yml'
        [System.IO.File]::WriteAllText($mappingPath, $mappingContent, $utf8NoBom)
        Write-Log "ZoneMapping.yml generiert: $mappingPath" 'INFO'
        [System.Windows.MessageBox]::Show("Zone Mapping für $($zones.Count) Zone(n) generiert!`nDatei: $mappingPath","Erfolg",'OK','Information') | Out-Null
    }
    catch {
        Write-Log "Fehler beim Generieren von ZoneMapping.yml: $($_.Exception.Message)" 'ERROR'
        [System.Windows.MessageBox]::Show("Fehler: $($_.Exception.Message)","Fehler",'OK','Error') | Out-Null
    }
}

#endregion =====================================================================


#region === BACKUP-ORDNER-FUNKTION =============================================
function Update-BackupsList {
    param([string] $Basisordner)
    try {
        $lstBackups.Items.Clear()
        $backups = Get-CvadBackupOrdner -Basisordner $Basisordner
        if ($backups.Count -gt 0) {
            foreach ($b in $backups) {
                [void]$lstBackups.Items.Add(("{0} ({1:yyyy-MM-dd HH:mm:ss})" -f $b.Name, $b.LastWriteTime))
            }
            $lstBackups.SelectedIndex = 0
            Write-Log "$($backups.Count) Backup-Ordner gefunden in: $Basisordner" 'INFO'
        }
        else {
            [void]$lstBackups.Items.Add('Keine Backups gefunden')
            Write-Log "Keine gültigen .yml-Backup-Ordner in: $Basisordner" 'WARN'
        }
    }
    catch {
        Write-Log "Fehler beim Laden der Backups: $($_.Exception.Message)" 'ERROR'
    }
}
#endregion =====================================================================


#region === EVENT-HANDLER ======================================================

$chkVollstaendig.Add_Click({ $pnlKomponenten.IsEnabled = -not $chkVollstaendig.IsChecked })

$rbBackup.Add_Checked({
    $chkVollstaendig.IsChecked = $true
    $pnlKomponenten.IsEnabled = $false
    $btnSelectAll.IsEnabled = $false
    $btnSelectNone.IsEnabled = $false
    $btnZoneMapping.IsEnabled = $false
    Write-Log "Backup-Modus: Komponenten-Auswahl deaktiviert (wird ignoriert)" 'INFO'
})

$rbRestore.Add_Checked({
    $chkVollstaendig.IsChecked = $false
    $pnlKomponenten.IsEnabled = $true
    $btnSelectAll.IsEnabled = $true
    $btnSelectNone.IsEnabled = $true
    $btnZoneMapping.IsEnabled = $true
    Write-Log "Restore-Modus: Komponenten-Auswahl aktiviert (Vollsicherung deaktiviert)" 'INFO'
    # Komponenten basierend auf Backup-Ordner automatisch laden
    if ($lstBackups.SelectedIndex -ge 0) {
        $auswahl = [string]$lstBackups.Items[$lstBackups.SelectedIndex]
        $ordnerName = ($auswahl -split ' \(')[0]
        $backupOrdner = Join-Path $txtPfad.Text $ordnerName
        if (Test-Path $backupOrdner) {
            Select-ComponentsFromBackup -BackupOrdner $backupOrdner
        }
    }
})

$rbOnPrem.Add_Checked({
    $grpCloudCreds.Visibility = 'Collapsed'
    Write-Log "Umgebung: OnPrem" 'INFO'
})

$rbCloud.Add_Checked({
    $grpCloudCreds.Visibility = 'Visible'
    Write-Log "Umgebung: Cloud – Bitte Anmeldedaten eingeben" 'INFO'
})

$btnSelectAll.Add_Click({
    foreach ($chk in $pnlKomponenten.Children) {
        if ($chk -is [System.Windows.Controls.CheckBox]) {
            $chk.IsChecked = $true
        }
    }
    Write-Log "Alle Komponenten ausgewählt" 'INFO'
})

$btnSelectNone.Add_Click({
    foreach ($chk in $pnlKomponenten.Children) {
        if ($chk -is [System.Windows.Controls.CheckBox]) {
            $chk.IsChecked = $false
        }
    }
    Write-Log "Alle Komponenten abgewählt" 'INFO'
})

$btnZoneMapping.Add_Click({
    if ($lstBackups.SelectedIndex -ge 0) {
        $auswahl = [string]$lstBackups.Items[$lstBackups.SelectedIndex]
        $ordnerName = ($auswahl -split ' \(')[0]
        $backupOrdner = Join-Path $txtPfad.Text $ordnerName
        if (Test-Path $backupOrdner) {
            Generate-ZoneMapping -BackupOrdner $backupOrdner
        }
        else {
            [System.Windows.MessageBox]::Show("Backup-Ordner nicht gefunden: $backupOrdner","Fehler",'OK','Error') | Out-Null
        }
    }
    else {
        [System.Windows.MessageBox]::Show("Bitte ein Backup auswählen!","Hinweis",'OK','Warning') | Out-Null
    }
})

$lstBackups.Add_SelectionChanged({
    if ($rbRestore.IsChecked -and $lstBackups.SelectedIndex -ge 0) {
        $auswahl = [string]$lstBackups.Items[$lstBackups.SelectedIndex]
        $ordnerName = ($auswahl -split ' \(')[0]
        $backupOrdner = Join-Path $txtPfad.Text $ordnerName
        if (Test-Path $backupOrdner) {
            Select-ComponentsFromBackup -BackupOrdner $backupOrdner
        }
    }
})

$btnBrowse.Add_Click({
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.SelectedPath = $txtPfad.Text
        if ($dlg.ShowDialog() -eq 'OK') {
            $txtPfad.Text = $dlg.SelectedPath
            Update-BackupsList $dlg.SelectedPath
        }
    }
    catch { Write-Log "Ordnerauswahl fehlgeschlagen: $($_.Exception.Message)" 'ERROR' }
})

$btnSchliessen.Add_Click({ $Fenster.Close() })

$btnStart.Add_Click({
    try {
        $istBackup    = $rbBackup.IsChecked
        $umgebung     = if ($rbCloud.IsChecked) { 'Cloud' } else { 'OnPrem' }
        $basisordner  = $txtPfad.Text
        $vollstaendig = $chkVollstaendig.IsChecked
        $checkMode    = $chkCheckMode.IsChecked

        Write-Log "=== Aktion: $(if($istBackup){'BACKUP'}else{'RESTORE'}) | Umgebung: $umgebung ===" 'INFO'

        if ([string]::IsNullOrWhiteSpace($basisordner)) { throw "Backup-Ordner erforderlich." }

        if ($umgebung -eq 'Cloud') {
            # Cloud: CustomerInfo.yml aus Eingabefeldern schreiben
            Write-Log "Cloud-Anmeldedaten werden konfiguriert ..." 'INFO'
            $customerId = $txtCustomerId.Text.Trim()
            $clientId   = $txtClientId.Text.Trim()
            $secret     = $pwdSecret.Password  # PasswordBox hat .Password Property
            
            # Validiere Credentials BEVOR sie geschrieben werden
            if (-not (Test-CustomerInfoValidity -CustomerId $customerId -ClientId $clientId -Secret $secret)) {
                $result = [System.Windows.MessageBox]::Show(
                    "Die eingegebenen Anmeldedaten sehen ungültig aus.`n`nTrotzdem fortfahren?`n`n(Überprüfen Sie Ihre Citrix Cloud-Zugangsdaten)",
                    "Warnung: Ungültige Credentials", 
                    'YesNo', 
                    'Warning'
                )
                if ($result -ne 'Yes') {
                    Write-Log "Benutzer hat Abbruch wegen ungültiger Credentials gewählt." 'WARN'
                    return
                }
            }
            
            if (-not (Write-CustomerInfoYml -CustomerId $customerId -ClientId $clientId -Secret $secret)) {
                throw "CustomerInfo.yml konnte nicht geschrieben werden!"
            }
        }
        
        $komponenten = @()
        if (-not $vollstaendig) {
            # Nur angehakte CheckBoxen auswählen
            foreach ($chk in $pnlKomponenten.Children) {
                if ($chk -is [System.Windows.Controls.CheckBox] -and $chk.IsChecked) {
                    $komponenten += [string]$chk.Content
                }
            }
            if ($komponenten.Count -eq 0) { throw "Keine Komponente ausgewählt (Vollsicherung deaktiviert)." }
            Write-Log "Komponenten: $($komponenten -join ', ')" 'INFO'
        }
        else {
            Write-Log "Vollsicherung: Alle Komponenten" 'INFO'
        }

        # ---------------- BACKUP ----------------
        if ($istBackup) {
            $zielOrdner = Join-Path $basisordner ("CVAD-ACT_{0:yyyyMMdd_HHmmss}" -f (Get-Date))
            New-Item -Path $zielOrdner -ItemType Directory -Force | Out-Null
            Write-Log "Ziel-Ordner: $zielOrdner" 'INFO'

            $cmdName = if ($umgebung -eq 'Cloud') { 'Backup-CvadAcToFile' } else { 'Export-CvadAcToFile' }
            $pNames  = (Get-Command $cmdName).Parameters.Keys
            $p = @{ TargetFolder = $zielOrdner }
            if ($pNames -contains 'Environment') { $p['Environment'] = $umgebung }
            if ($pNames -contains 'DisplayLog')  { $p['DisplayLog']  = $false }
            if ($umgebung -eq 'Cloud' -and $pNames -contains 'CustomerInfoFileSpec') {
                $custInfoPath = Get-CustomerInfoPath
                if (Test-Path $custInfoPath) {
                    $p['CustomerInfoFileSpec'] = $custInfoPath
                    Write-Log "✓ CustomerInfo.yml wird verwendet: $custInfoPath" 'INFO'
                } else {
                    Write-Log "⚠️ CustomerInfo.yml nicht gefunden unter: $custInfoPath" 'WARN'
                    Write-Log "   Bitte füllen Sie die Cloud-Anmeldedaten aus und versuchen es erneut." 'WARN'
                }
            }
            
            # Komponenten als Switch-Parameter übergeben (nur wenn nicht Vollsicherung)
            if (-not $vollstaendig -and $komponenten.Count -gt 0) {
                Write-Log "Komponenten-Filter: $($komponenten -join ', ')" 'INFO'
                foreach ($komp in $komponenten) {
                    if ($pNames -contains $komp) {
                        $p[$komp] = $true
                        Write-Log "  ✓ Parameter -$komp = true" 'INFO'
                    }
                }
            }
            elseif ($vollstaendig) {
                Write-Log "Vollsicherung: -All wird verwendet" 'INFO'
                if ($pNames -contains 'All') {
                    $p['All'] = $true
                }
            }
            
            # Confirm-Parameter hinzufügen, um Bestätigungsabfragen zu unterdrücken
            if ($pNames -contains 'Confirm') {
                $p['Confirm'] = $false
            }
            
            # Confirm-Parameter hinzufügen, um Bestätigungsabfragen zu unterdrücken
            if ($pNames -contains 'Confirm') {
                $p['Confirm'] = $false
            }

            $ergebnis = Invoke-CvadOperation -CmdName $cmdName -Parameter $p

            if (Test-OverallSuccess -Ergebnis $ergebnis -Aktion 'Backup') {
                Write-Log "Backup erfolgreich: $zielOrdner" 'INFO'
                Update-BackupsList $basisordner
                [System.Windows.MessageBox]::Show("Backup erfolgreich abgeschlossen!`n$zielOrdner","Erfolg",'OK','Information') | Out-Null
            }
            else {
                [System.Windows.MessageBox]::Show("Backup mit Fehlern beendet. Log prüfen:`n$Global:LogDatei","Warnung",'OK','Warning') | Out-Null
            }
            return
        }
        # ---------------- RESTORE ----------------
        else {
            if ($lstBackups.SelectedIndex -lt 0 -or $lstBackups.Items[$lstBackups.SelectedIndex] -eq 'Keine Backups gefunden') {
                throw "Kein gültiger Backup-Ordner ausgewählt."
            }

            $auswahl     = [string]$lstBackups.Items[$lstBackups.SelectedIndex]
            $ordnerName  = ($auswahl -split ' \(')[0]
            $quellOrdner = Join-Path $basisordner $ordnerName
            if (-not (Test-Path $quellOrdner -PathType Container)) {
                throw "Backup-Ordner nicht gefunden: $quellOrdner"
            }

            if ($checkMode) {
                $hinweis = "TROCKENLAUF (CheckMode): Es werden KEINE Änderungen geschrieben.`nFortfahren?"
            }
            else {
                $hinweis = "ACHTUNG: Ein Restore überschreibt bestehende Konfigurationen!`nOrdner: $ordnerName`nUmgebung: $umgebung`nFortfahren?"
            }
            if ([System.Windows.MessageBox]::Show($hinweis,"Bestätigung",'YesNo','Warning') -ne 'Yes') {
                Write-Log "Restore vom Benutzer abgebrochen." 'WARN'
                return
            }

            Write-Log "DEBUG: vollstaendig=$vollstaendig | Angehakte Komponenten=$($pnlKomponenten.Children | Where-Object {$_ -is [System.Windows.Controls.CheckBox] -and $_.IsChecked} | ForEach-Object {$_.Content})" 'INFO'

            $cmdName = if ($umgebung -eq 'Cloud') { 'Restore-CvadAcToSite' } else { 'Import-CvadAcToSite' }
            $pNames  = (Get-Command $cmdName).Parameters.Keys
            Write-Log "DEBUG: Verfügbare Parameter für $cmdName : $($pNames -join ', ')" 'INFO'
            $p = @{}
            if     ($pNames -contains 'RestoreFolder') { $p['RestoreFolder'] = $quellOrdner }
            elseif ($pNames -contains 'SourceFolder')  { $p['SourceFolder']  = $quellOrdner }
            elseif ($pNames -contains 'Folder')        { $p['Folder']        = $quellOrdner }
            if ($pNames -contains 'Environment') { $p['Environment'] = $umgebung }
            if ($pNames -contains 'DisplayLog')  { $p['DisplayLog']  = $false }
            if ($umgebung -eq 'Cloud' -and $pNames -contains 'CustomerInfoFileSpec') {
                $custInfoPath = Get-CustomerInfoPath
                if (Test-Path $custInfoPath) {
                    $p['CustomerInfoFileSpec'] = $custInfoPath
                    Write-Log "✓ CustomerInfo.yml wird verwendet: $custInfoPath" 'INFO'
                } else {
                    Write-Log "⚠️ CustomerInfo.yml nicht gefunden unter: $custInfoPath" 'WARN'
                    Write-Log "   Bitte füllen Sie die Cloud-Anmeldedaten aus und versuchen es erneut." 'WARN'
                }
            }
            
            # Komponenten als Switch-Parameter übergeben (nur wenn nicht Vollsicherung)
            if (-not $vollstaendig -and $komponenten.Count -gt 0) {
                Write-Log "Komponenten-Filter: $($komponenten -join ', ')" 'INFO'
                foreach ($komp in $komponenten) {
                    if ($pNames -contains $komp) {
                        $p[$komp] = $true
                        Write-Log "  ✓ Parameter -$komp = true" 'INFO'
                    }
                }
            }
            elseif ($vollstaendig) {
                Write-Log "Vollsicherung: -All wird verwendet" 'INFO'
                if ($pNames -contains 'All') {
                    $p['All'] = $true
                }
            }
            if ($checkMode -and $pNames -contains 'CheckMode') {
                $p['CheckMode'] = $true
            }
            
            # Confirm-Parameter hinzufügen, um Bestätigungsabfragen zu unterdrücken
            if ($pNames -contains 'Confirm') {
                $p['Confirm'] = $false
            }

            $ergebnis = Invoke-CvadOperation -CmdName $cmdName -Parameter $p

            if (Test-OverallSuccess -Ergebnis $ergebnis -Aktion 'Restore') {
                if ($checkMode) {
                    $txt = "Trockenlauf abgeschlossen (keine Änderungen geschrieben)."
                }
                else {
                    $txt = "Restore erfolgreich abgeschlossen!"
                }
                Write-Log $txt 'INFO'
                [System.Windows.MessageBox]::Show($txt,"Erfolg",'OK','Information') | Out-Null
            }
            else {
                [System.Windows.MessageBox]::Show("Restore mit Fehlern beendet. Log prüfen:`n$Global:LogDatei","Warnung",'OK','Warning') | Out-Null
            }
            return
        }
    }
    catch {
        $fehler = $_.Exception.Message
        Write-Log "FEHLER: $fehler" 'ERROR'
        [System.Windows.MessageBox]::Show("Fehler:`n$fehler","Fehler",'OK','Error') | Out-Null
        $btnStart.IsEnabled = $true
        $btnStart.Content   = '▶ Ausführen'
    }
})
#endregion =====================================================================


#region === START ==============================================================
Write-Log "GUI gestartet. Logdatei: $Global:LogDatei" 'INFO'

if (-not (Initialize-ActModul)) {
    $btnStart.IsEnabled = $false
    Write-Log "Start-Button deaktiviert – ACT-Cmdlets fehlen." 'ERROR'
    [System.Windows.MessageBox]::Show("ACT-Cmdlets nicht gefunden.`nBitte ACT-Konsole zuerst starten oder installieren.","ACT fehlt",'OK','Warning') | Out-Null
}

Update-BackupsList $Global:StandardBackupOrdner

# GUI-Größe auf 90% der Bildschirmhöhe setzen
$screenHeight = [System.Windows.SystemParameters]::PrimaryScreenHeight
$screenWidth = [System.Windows.SystemParameters]::PrimaryScreenWidth
$Fenster.Height = $screenHeight * 0.9
$Fenster.Width = $screenWidth * 0.85
$Fenster.Top = $screenHeight * 0.05
$Fenster.Left = $screenWidth * 0.075

$Fenster.Add_Closed({ Write-Log "GUI beendet." 'INFO' })
$Fenster.ShowDialog() | Out-Null
#endregion =====================================================================
