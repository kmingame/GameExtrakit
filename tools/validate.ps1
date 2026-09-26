param([Parameter(Mandatory=$true)][string]$Godot)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$results = Join-Path $projectRoot 'test-results'
New-Item -ItemType Directory -Path $results -Force | Out-Null
Set-Content -LiteralPath (Join-Path $results '.gdignore') -Value ''

function Invoke-CheckedGodot([string[]]$GodotArgs, [string]$LogName) {
    $logPath = Join-Path $results $LogName
    & $Godot @GodotArgs --log-file $logPath 2>&1 | Tee-Object -FilePath "$logPath.console.txt"
    if ($LASTEXITCODE -ne 0) { throw "Godot failed: $LogName ($LASTEXITCODE)" }
    if (Select-String -LiteralPath "$logPath.console.txt" -Pattern 'SCRIPT ERROR:|ERROR:|FAIL:|ObjectDB instances were leaked|resources still in use' -Quiet) {
        throw "Godot reported errors: $logPath"
    }
}

Invoke-CheckedGodot @('--headless','--path',$projectRoot,'--editor','--quit') 'import.log'
Invoke-CheckedGodot @('--headless','--path',$projectRoot,'--script','tests/run_tests.gd') 'tests.log'
Invoke-CheckedGodot @('--headless','--path',$projectRoot,'--quit-after','15') 'demo-headless.log'

$fixture = Join-Path $results ('editor-fixture-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $fixture 'addons/editor_driver') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot 'addons/game_extrakit') -Destination (Join-Path $fixture 'addons') -Recurse
Copy-Item -LiteralPath (Join-Path $projectRoot 'tests/editor_driver.gd') -Destination (Join-Path $fixture 'addons/editor_driver/driver.gd')
Copy-Item -LiteralPath (Join-Path $projectRoot 'tests/export_smoke.gd') -Destination (Join-Path $fixture 'smoke.gd')
@'
[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://smoke.gd" id="1"]
[node name="ExportSmoke" type="Node"]
script = ExtResource("1")
'@ | Set-Content -LiteralPath (Join-Path $fixture 'smoke.tscn')
@'
[preset.0]
name="Contract test"
platform="Windows Desktop"
runnable=true
export_filter="all_resources"
include_filter=""
exclude_filter="addons/editor_driver/*"
export_path=""
[preset.0.options]
binary_format/architecture="x86_64"
'@ | Set-Content -LiteralPath (Join-Path $fixture 'export_presets.cfg')
@'
[plugin]
name="Editor lifecycle test"
description="Disposable GameExtrakit validation"
author="Kmingame"
version="1"
script="driver.gd"
'@ | Set-Content -LiteralPath (Join-Path $fixture 'addons/editor_driver/plugin.cfg')
@'
config_version=5
[application]
config/name="GameExtrakit editor fixture"
config/features=PackedStringArray("4.7", "GL Compatibility")
[rendering]
renderer/rendering_method="gl_compatibility"
[editor_plugins]
enabled=PackedStringArray()
'@ | Set-Content -LiteralPath (Join-Path $fixture 'project.godot')
Invoke-CheckedGodot @('--headless','--path',$fixture,'--editor','--quit') 'fixture-import.log'
$fixtureProject = Join-Path $fixture 'project.godot'
$fixtureText = Get-Content -LiteralPath $fixtureProject -Raw
$fixtureText = $fixtureText.Replace('enabled=PackedStringArray()', 'enabled=PackedStringArray("res://addons/editor_driver/plugin.cfg")')
Set-Content -LiteralPath $fixtureProject -Value $fixtureText
Invoke-CheckedGodot @('--headless','--path',$fixture,'--editor','--quit-after','600') 'editor-lifecycle.log'
if (-not (Select-String -LiteralPath (Join-Path $results 'editor-lifecycle.log') -SimpleMatch 'editor lifecycle: PASS' -Quiet)) {
    throw 'Editor lifecycle did not finish.'
}
$pack = Join-Path $results 'smoke.pck'
Invoke-CheckedGodot @('--headless','--path',$fixture,'--export-pack','Contract test',$pack) 'pack-export.log'
Invoke-CheckedGodot @('--headless','--path',$fixture,'--main-pack',$pack,'--quit-after','600') 'pack-runtime.log'
if (-not (Select-String -LiteralPath (Join-Path $results 'pack-runtime.log') -SimpleMatch 'exported PCK: PASS' -Quiet)) {
    throw 'Exported PCK did not complete its smoke test.'
}
Write-Output 'All GameExtrakit checks passed.'
