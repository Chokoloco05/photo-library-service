[CmdletBinding()]
param([Parameter(Mandatory = $true)][ValidateSet('dev', 'test')][string]$Namespace)
$ErrorActionPreference = 'Stop'
$schema = 'replication_check_' + [Guid]::NewGuid().ToString('N')
$created = $false
$replicaStopped = $false

function Invoke-Sql {
    param([string]$Pod, [string]$Sql)
    $raw = & kubectl --context docker-desktop -n $Namespace exec $Pod -c postgres -- psql -X -U photo -d photo_service -At -v ON_ERROR_STOP=1 -c $Sql
    if ($LASTEXITCODE -ne 0) { throw "Replication exercise failed on $Pod." }
    return (($raw -join "`n").Trim())
}
function Wait-ReplicaValue {
    param([string]$Expected)
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        $value = Invoke-Sql 'photo-db-replica-0' "SELECT payload FROM $schema.probe WHERE id=1;"
        if ($value -eq $Expected) { return }
        Start-Sleep -Seconds 2
    }
    throw 'Committed probe did not reach the replica.'
}
try {
    & "$PSScriptRoot/database.ps1" -Namespace $Namespace -Action Check
    Invoke-Sql 'photo-db-0' "CREATE SCHEMA $schema; CREATE TABLE $schema.probe(id integer PRIMARY KEY, payload text NOT NULL); INSERT INTO $schema.probe VALUES(1,'before_restart');" | Out-Null
    $created = $true
    # Wait for schema creation to be replayed before querying the probe table.
    & "$PSScriptRoot/database.ps1" -Namespace $Namespace -Action Check
    Wait-ReplicaValue 'before_restart'
    $readOnly = 'DO $$ BEGIN EXECUTE ''CREATE TABLE ' + $schema + '.forbidden(id integer)''; RAISE EXCEPTION ''Replica accepted a write''; EXCEPTION WHEN read_only_sql_transaction THEN NULL; END $$;'
    Invoke-Sql 'photo-db-replica-0' $readOnly | Out-Null
    Write-Host 'Committed changes replicated; replica rejects writes.'

    $claimUid = & kubectl --context docker-desktop -n $Namespace get pvc data-photo-db-replica-0 -o 'jsonpath={.metadata.uid}'
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect replica volume.' }
    & kubectl --context docker-desktop -n $Namespace scale statefulset/photo-db-replica --replicas=0
    if ($LASTEXITCODE -ne 0) { throw 'Cannot stop the replica for the recovery exercise.' }
    $replicaStopped = $true
    & kubectl --context docker-desktop -n $Namespace wait --for=delete pod/photo-db-replica-0 --timeout=180s
    if ($LASTEXITCODE -ne 0) { throw 'Replica did not stop.' }
    Invoke-Sql 'photo-db-0' "UPDATE $schema.probe SET payload='written_while_replica_stopped' WHERE id=1;" | Out-Null
    & kubectl --context docker-desktop -n $Namespace scale statefulset/photo-db-replica --replicas=1
    if ($LASTEXITCODE -ne 0) { throw 'Cannot restart the replica.' }
    & kubectl --context docker-desktop -n $Namespace rollout status statefulset/photo-db-replica --timeout=240s
    if ($LASTEXITCODE -ne 0) { throw 'Replica did not recover.' }
    $replicaStopped = $false
    & "$PSScriptRoot/database.ps1" -Namespace $Namespace -Action Check
    Wait-ReplicaValue 'written_while_replica_stopped'
    $currentUid = & kubectl --context docker-desktop -n $Namespace get pvc data-photo-db-replica-0 -o 'jsonpath={.metadata.uid}'
    if ($LASTEXITCODE -ne 0 -or $claimUid -ne $currentUid) { throw 'Replica persistent volume changed.' }
    Write-Host 'Replica recovered missed writes using its original persistent volume.'
} finally {
    if ($replicaStopped) {
        & kubectl --context docker-desktop -n $Namespace scale statefulset/photo-db-replica --replicas=1
        if ($LASTEXITCODE -ne 0) { Write-Warning 'Restore photo-db-replica to one replica.' }
    }
    if ($created) {
        & kubectl --context docker-desktop -n $Namespace exec photo-db-0 -c postgres -- psql -X -U photo -d photo_service -v ON_ERROR_STOP=1 -c "DROP SCHEMA $schema CASCADE;"
        if ($LASTEXITCODE -ne 0) { Write-Warning "Remove the exercise schema $schema after diagnosis." }
    }
}
