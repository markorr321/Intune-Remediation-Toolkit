# ============================================================================
#  IntuneRemediationToolkit module loader
#  Dot-sources every Private helper first, then every Public function, then
#  exports the public functions and the Push-IntuneRemediation alias.
# ============================================================================

$Private = @( Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue )
$Public  = @( Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public')  -Filter '*.ps1' -ErrorAction SilentlyContinue )

foreach ($file in $Private) {
    . $file.FullName
}

foreach ($file in $Public) {
    . $file.FullName
}

# Backwards-compatible alias for the original Push-* verb
New-Alias -Name Push-IntuneRemediation -Value Publish-IntuneRemediation -Force

Export-ModuleMember -Function $Public.BaseName -Alias 'Push-IntuneRemediation'
