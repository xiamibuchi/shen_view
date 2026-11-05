function Set-ShenViewSmokeInstanceMode {
  param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][ValidateSet('singleProcess', 'multiProcess')][string]$Mode
  )
  # Match AppConfigStore's stable transaction lock; a session save can otherwise
  # replace our mode change with the snapshot it read before this edit.
  $lock = [IO.File]::Open($ConfigPath + '.lock', 'OpenOrCreate', 'ReadWrite', 'ReadWrite')
  $temporary = $ConfigPath + '.tmp-smoke-' + [guid]::NewGuid().ToString('N')
  try {
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while ($true) {
      try { $lock.Lock(0, 1); break } catch {
        $code = $_.Exception.GetBaseException().HResult -band 0xffff
        if ($code -ne 33 -or [DateTime]::UtcNow -ge $deadline) { throw }
        Start-Sleep -Milliseconds 20
      }
    }
    $config = [IO.File]::ReadAllText($ConfigPath) | ConvertFrom-Json -ErrorAction Stop
    $config.settings | Add-Member -NotePropertyName instanceMode -NotePropertyValue $Mode -Force
    [IO.File]::WriteAllText($temporary, ($config | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))
    $deadline = [DateTime]::UtcNow.AddSeconds(1)
    while ($true) {
      try { [IO.File]::Replace($temporary, $ConfigPath, [NullString]::Value); break } catch {
        # Snapshot readers need not hold the transaction lock and may briefly
        # open settings without delete sharing, as in AppConfigStore.
        $code = $_.Exception.GetBaseException().HResult -band 0xffff
        if ($code -notin @(5, 32, 33) -or [DateTime]::UtcNow -ge $deadline) { throw }
        Start-Sleep -Milliseconds 10
      }
    }
  } finally {
    $lock.Dispose()
    if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
  }
}
