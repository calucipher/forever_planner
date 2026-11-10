<#
.SYNOPSIS
    Instala ou atualiza o Forever Planner no WoW: Forever.

.DESCRIPTION
    Confere a versao instalada com a release mais nova de
    https://github.com/calucipher/forever_planner/releases e, se houver versao nova, baixa o
    ForeverPlanner-<versao>.zip e troca a pasta Interface\AddOns\ForeverPlanner inteira.
    Outros addons e as suas configuracoes (pasta WTF) nao sao tocados.

    Dois jeitos de rodar, numa janela do PowerShell:
        irm https://raw.githubusercontent.com/calucipher/forever_planner/main/install.ps1 | iex
        powershell -ExecutionPolicy Bypass -File install.ps1

    Este arquivo e so ASCII e sem BOM, de proposito: no Windows PowerShell 5.1 o 'irm' mantem
    o BOM e quebra o 'iex', e o '-File' sem BOM le acentos errado. Por isso as mensagens nao
    tem acento.

.PARAMETER WowPath
    Pasta do WoW (ex.: "E:\World of Warcraft") ou direto a do Forever (ex.: "E:\World of Warcraft\_forever_").
    Sem ele, usa $env:FOREVER_WOW; sem os dois, procura no registro da Blizzard e nas pastas comuns.

.PARAMETER Zip
    Usa um zip ja baixado, sem acessar a internet.

.PARAMETER Force
    Instala mesmo que a versao instalada seja igual ou mais nova.

.EXAMPLE
    .\install.ps1
    .\install.ps1 -WowPath "E:\World of Warcraft"
    .\install.ps1 -Zip "$HOME\Downloads\ForeverPlanner-0.7.0.zip"
#>
param(
    [string]$WowPath,
    [string]$Zip,
    [switch]$Force
)

function Install-ForeverPlanner([string]$WowPath, [string]$Zip, [switch]$Force) {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue' # a barra de progresso deixa o download do PS 5.1 lento
    $AddonName = 'ForeverPlanner'
    $FlavorDirs = '_forever_', '_camelot_'
    $ReleaseApi = 'https://api.github.com/repos/calucipher/forever_planner/releases/latest'
    $Headers = @{ 'User-Agent' = 'ForeverPlanner-install' }
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

    function Find-FlavorDir([string]$path) {
        if (-not $path -or -not (Test-Path -LiteralPath $path)) { return $null }
        if ($FlavorDirs -contains (Split-Path $path -Leaf)) { return (Resolve-Path -LiteralPath $path).Path }
        foreach ($f in $FlavorDirs) {
            $c = Join-Path $path $f
            if (Test-Path -LiteralPath $c) { return (Resolve-Path -LiteralPath $c).Path }
        }
        return $null
    }

    function Get-WowRoots {
        $roots = @()
        foreach ($key in 'HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft',
                         'HKLM:\SOFTWARE\Blizzard Entertainment\World of Warcraft') {
            try {
                $p = (Get-ItemProperty $key -ErrorAction Stop).InstallPath
                if ($p) { $roots += (Split-Path $p.TrimEnd('\') -Parent); $roots += $p }
            } catch {}
        }
        foreach ($drive in 'C:', 'D:', 'E:', 'F:', 'G:') {
            $roots += "$drive\World of Warcraft", "$drive\Games\World of Warcraft",
                      "$drive\Program Files (x86)\World of Warcraft", "$drive\Program Files\World of Warcraft"
        }
        return $roots | Select-Object -Unique
    }

    function Get-TocVersion([string]$text) {
        $m = [regex]::Match($text, '(?m)^##\s*Version:\s*(\S+)')
        if ($m.Success) { return $m.Groups[1].Value } else { return $null }
    }

    # -1, 0 ou 1. Por partes numericas, parte que falta vale 0 (0.7 = 0.7.0, 0.10.0 > 0.9.0).
    # Parte que nao e numero (ex.: 1.0-beta) faz a comparacao virar texto.
    function Compare-Version([string]$a, [string]$b) {
        $pa = $a -split '\.'; $pb = $b -split '\.'
        if (@($pa + $pb | Where-Object { $_ -notmatch '^\d+$' }).Count -gt 0) {
            return [Math]::Sign([string]::CompareOrdinal($a, $b))
        }
        for ($i = 0; $i -lt [Math]::Max($pa.Count, $pb.Count); $i++) {
            $x = if ($i -lt $pa.Count) { [long]$pa[$i] } else { 0 }
            $y = if ($i -lt $pb.Count) { [long]$pb[$i] } else { 0 }
            if ($x -ne $y) { return [Math]::Sign($x - $y) }
        }
        return 0
    }

    # Decide se instala (R5): igual ou mais nova instalada, so com -Force.
    function Test-ShouldInstall([string]$installed, [string]$offered) {
        if (-not $installed -or $Force) { return $true }
        $c = Compare-Version $installed $offered
        if ($c -eq 0) {
            Write-Host "O Forever Planner $installed ja esta instalado e atualizado. Use -Force para reinstalar." -ForegroundColor Green
            return $false
        }
        if ($c -gt 0) {
            Write-Host "A versao instalada ($installed) e mais nova que a oferecida ($offered). Nada mudou. Use -Force para instalar a $offered." -ForegroundColor Yellow
            return $false
        }
        return $true
    }

    # Apaga pasta sem seguir junction de dentro (o Remove-Item -Recurse do PS 5.1 pode seguir).
    function Remove-Dir([string]$path) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            try { [IO.Directory]::Delete($path, $true) } catch {}
        }
    }

    # 1. Pasta do Forever (R1): caminho dado nao cai para a busca automatica.
    if ($WowPath) {
        $flavor = Find-FlavorDir $WowPath
        if (-not $flavor) { throw "nao achei a pasta do Forever ($($FlavorDirs -join ' ou ')) em '$WowPath'." }
    } elseif ($env:FOREVER_WOW) {
        $flavor = Find-FlavorDir $env:FOREVER_WOW
        if (-not $flavor) { throw "nao achei a pasta do Forever ($($FlavorDirs -join ' ou ')) em FOREVER_WOW='$env:FOREVER_WOW'." }
    } else {
        $flavor = $null
        foreach ($root in Get-WowRoots) { $flavor = Find-FlavorDir $root; if ($flavor) { break } }
        if (-not $flavor) {
            throw ("nao achei a instalacao do WoW: Forever. Abra o jogo uma vez pelo Battle.net ou " +
                   "diga onde esta: .\install.ps1 -WowPath ""E:\World of Warcraft""")
        }
    }
    $addons = Join-Path $flavor 'Interface\AddOns'
    $target = Join-Path $addons $AddonName
    Write-Host "Forever: $flavor"

    # 2. Link de desenvolvimento (R6): copiar escreveria no clone.
    $existing = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
    if ($existing -and ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "'$target' e um link (instalacao de desenvolvimento). Apague o link antes de instalar pelo pacote."
    }

    # Versao instalada.
    $oldVersion = $null
    $oldToc = Join-Path $target "$AddonName.toc"
    if (Test-Path -LiteralPath $oldToc) { $oldVersion = Get-TocVersion ([IO.File]::ReadAllText($oldToc)) }
    if ($oldVersion) { Write-Host "Instalada: $oldVersion" } else { Write-Host 'Instalada: nenhuma' }

    $work = Join-Path $env:TEMP ('fp-install-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force $work | Out-Null
    try {
        # 3. Pacote (R2).
        if ($Zip) {
            if (-not (Test-Path -LiteralPath $Zip)) { throw "zip nao encontrado: $Zip" }
            $zipPath = (Resolve-Path -LiteralPath $Zip).Path
        } else {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            Write-Host 'Procurando a versao mais nova no GitHub...'
            $rel = Invoke-RestMethod -Uri $ReleaseApi -Headers $Headers
            $relVersion = ([string]$rel.tag_name) -replace '^v', ''
            Write-Host "Mais nova: $relVersion"
            # Confere pela tag antes de baixar: igual, nao baixa nada.
            if (-not (Test-ShouldInstall $oldVersion $relVersion)) { return 0 }
            $asset = @($rel.assets | Where-Object { $_.name -like "$AddonName-*.zip" }) | Select-Object -First 1
            if (-not $asset) { throw "a release $($rel.tag_name) nao tem o $AddonName-<versao>.zip." }
            $zipPath = Join-Path $work $asset.name
            Write-Host "Baixando $($asset.name)..."
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath -UseBasicParsing -Headers $Headers
        }

        # 4. Conferencia do zip (R3), antes de tocar a instalacao.
        $z = [IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            foreach ($e in $z.Entries) {
                $n = $e.FullName -replace '\\', '/'
                if ($n -notlike "$AddonName/*" -or $n -match '(^|/)\.\.(/|$)' -or $n -match '^[A-Za-z]:' -or $n.StartsWith('/')) {
                    throw "pacote invalido: entrada fora de $AddonName/ ($n)."
                }
            }
            # Zip feito no Windows pode ter '\' nos nomes: procura pelo nome normalizado.
            $tocEntry = @($z.Entries | Where-Object { ($_.FullName -replace '\\', '/') -eq "$AddonName/$AddonName.toc" }) |
                Select-Object -First 1
            if (-not $tocEntry) { throw "pacote invalido: falta $AddonName/$AddonName.toc." }
            $r = New-Object IO.StreamReader($tocEntry.Open())
            try { $newVersion = Get-TocVersion $r.ReadToEnd() } finally { $r.Dispose() }
        } finally { $z.Dispose() }
        if (-not $newVersion) { throw 'pacote invalido: o .toc nao tem ## Version:.' }

        # 5. Versao do pacote (R5): vale a do .toc de dentro do zip.
        if (-not (Test-ShouldInstall $oldVersion $newVersion)) { return 0 }

        # 6. Troca de pasta (R4). Nao e copia por cima: o robocopy /MIR pula arquivo de mesmo
        #    tamanho e data, e a data vem do zip. A nova e montada ao lado (mesmo disco) e entra
        #    por renomeacao. O nome com ponto nao casa com o .toc: o jogo nao carrega as temporarias.
        $extract = Join-Path $work 'x'
        [IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extract)
        New-Item -ItemType Directory -Force $addons | Out-Null
        $tag = [guid]::NewGuid().ToString('N').Substring(0, 8)
        $staged = Join-Path $addons ".$AddonName-novo-$tag"
        $backup = Join-Path $addons ".$AddonName-antigo-$tag"
        try { Copy-Item -LiteralPath (Join-Path $extract $AddonName) -Destination $staged -Recurse -Force }
        catch { Remove-Dir $staged; throw "nao consegui preparar a pasta nova em AddOns: $($_.Exception.Message)" }
        $hadOld = Test-Path -LiteralPath $target
        try {
            if ($hadOld) { [IO.Directory]::Move($target, $backup) }
            [IO.Directory]::Move($staged, $target)
        } catch {
            $why = $_.Exception.Message
            Remove-Dir $staged
            if ($hadOld -and -not (Test-Path -LiteralPath $target) -and (Test-Path -LiteralPath $backup)) {
                try { [IO.Directory]::Move($backup, $target) }
                catch { throw "a troca falhou e a versao antiga ficou em '$backup'. Feche o jogo e renomeie essa pasta para '$AddonName'. ($why)" }
            }
            throw "nao consegui trocar a pasta do addon (feche o jogo e tente de novo): $why"
        }
        if ($hadOld) { Remove-Dir $backup }

        # 7. Resumo (R7).
        if ($oldVersion) { Write-Host "Atualizado: $oldVersion -> $newVersion" -ForegroundColor Green }
        else { Write-Host "Instalado: Forever Planner $newVersion" -ForegroundColor Green }
        Write-Host "Pasta: $target"
        if (-not (Test-Path -LiteralPath (Join-Path $addons 'QuestieDB'))) {
            Write-Host 'ATENCAO: a QuestieDB (versao Forever) nao esta instalada. Ela e obrigatoria: instale pelo CurseForge.' -ForegroundColor Yellow
        }
        Write-Host 'Se o jogo estiver aberto, feche e abra de novo. Depois digite /fp.'
        return 0
    } finally {
        Remove-Dir $work
    }
}

$code = 1
try { $code = Install-ForeverPlanner -WowPath $WowPath -Zip $Zip -Force:$Force }
catch { Write-Host "ERRO: $($_.Exception.Message)" -ForegroundColor Red; $code = 1 }
# R8: 'exit' so no modo -File. Por 'irm | iex', ele fecharia a janela do jogador.
if ($PSCommandPath) { exit $code }
