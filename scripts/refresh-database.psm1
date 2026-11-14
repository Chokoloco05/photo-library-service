function Assert-RefreshDatabaseName {
    param([string]$Name)
    if ($Name -notmatch '^(photo_service|photo_(refresh|previous|failed|check)_[a-f0-9]{32})$') {
        throw 'Unexpected Test refresh database name.'
    }
}

function Invoke-RefreshSql {
    param(
        [ValidateSet('photo-db-0','photo-db-shard-1-0')][string]$Pod,
        [string]$Database = 'postgres',
        [Parameter(Mandatory = $true)][string]$Sql
    )
    if ($Database -ne 'postgres') { Assert-RefreshDatabaseName $Database }
    $raw = $Sql | & kubectl --context docker-desktop -n test exec -i $Pod -c postgres -- psql -X -U photo -d $Database -qAt -v ON_ERROR_STOP=1
    if ($LASTEXITCODE -ne 0) { throw "Test refresh SQL failed on $Pod." }
    return (($raw -join "`n").Trim())
}

function Get-RefreshCatalog {
    param([string]$Pod, $Names)
    $list = foreach ($name in @($Names.Active,$Names.Stage,$Names.Previous,$Names.Failed)) {
        Assert-RefreshDatabaseName $name
        "'$name'"
    }
    $raw = Invoke-RefreshSql -Pod $Pod -Sql "SELECT datname FROM pg_database WHERE datname IN ($($list -join ','));"
    return @($raw -split "`n" | Where-Object { $_ })
}

function Set-RefreshConnections {
    param([string]$Pod, [string]$Database, [bool]$Enabled)
    Assert-RefreshDatabaseName $Database
    $flag = if ($Enabled) { 'true' } else { 'false' }
    Invoke-RefreshSql -Pod $Pod -Sql "ALTER DATABASE $Database ALLOW_CONNECTIONS $flag;" | Out-Null
    if (-not $Enabled) {
        Invoke-RefreshSql -Pod $Pod -Sql "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$Database' AND pid<>pg_backend_pid();" | Out-Null
        for ($attempt=0; $attempt -lt 30; $attempt++) {
            $count = Invoke-RefreshSql -Pod $Pod -Sql "SELECT count(*) FROM pg_stat_activity WHERE datname='$Database';"
            if ($count -eq '0') { return }
            Start-Sleep -Milliseconds 100
        }
        throw 'Test connections did not close before database rename.'
    }
}

function Switch-RefreshDatabasePair {
    param($Names)
    $pods = @('photo-db-shard-1-0','photo-db-0')
    foreach ($pod in $pods) {
        $catalog = Get-RefreshCatalog $pod $Names
        if ($Names.Active -notin $catalog -or $Names.Stage -notin $catalog -or $Names.Previous -in $catalog -or $Names.Failed -in $catalog) {
            throw 'Test database layout changed before refresh cutover.'
        }
    }
    foreach ($pod in $pods) {
        Set-RefreshConnections $pod $Names.Active $false
        Set-RefreshConnections $pod $Names.Stage $false
    }
    foreach ($pod in $pods) {
        Invoke-RefreshSql -Pod $pod -Sql "BEGIN; ALTER DATABASE $($Names.Active) RENAME TO $($Names.Previous); ALTER DATABASE $($Names.Stage) RENAME TO $($Names.Active); COMMIT;" | Out-Null
    }
    foreach ($pod in $pods) { Set-RefreshConnections $pod $Names.Active $true }
}

function Restore-RefreshDatabasePair {
    param($Names)
    foreach ($pod in @('photo-db-shard-1-0','photo-db-0')) {
        $catalog = Get-RefreshCatalog $pod $Names
        if ($Names.Previous -in $catalog) {
            if ($Names.Active -in $catalog) {
                if ($Names.Failed -in $catalog) { throw 'A failed refresh copy already exists. Inspect the recovery journal.' }
                Set-RefreshConnections $pod $Names.Active $false
                Invoke-RefreshSql -Pod $pod -Sql "ALTER DATABASE $($Names.Active) RENAME TO $($Names.Failed);" | Out-Null
            }
            Invoke-RefreshSql -Pod $pod -Sql "ALTER DATABASE $($Names.Previous) RENAME TO $($Names.Active);" | Out-Null
        } elseif ($Names.Active -notin $catalog) { throw 'Original Test database is missing. Use the verified pre-refresh backup.' }
        Set-RefreshConnections $pod $Names.Active $true
    }
}

function Remove-RefreshDatabase {
    param([string]$Pod, [string]$Database)
    if ($Database -notmatch '^photo_(refresh|previous|failed|check)_[a-f0-9]{32}$') { throw 'Only generated refresh databases can be removed.' }
    Invoke-RefreshSql -Pod $Pod -Sql "DROP DATABASE IF EXISTS $Database WITH (FORCE);" | Out-Null
}

Export-ModuleMember -Function Assert-RefreshDatabaseName,Invoke-RefreshSql,Get-RefreshCatalog,Set-RefreshConnections,Switch-RefreshDatabasePair,Restore-RefreshDatabasePair,Remove-RefreshDatabase
