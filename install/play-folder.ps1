param([Parameter(Mandatory = $true)][string]$Folder)
$exts = '.mkv','.mp4','.avi','.mov','.webm','.m4v','.ts','.flv','.wmv','.mpg','.mpeg'
$first = Get-ChildItem -LiteralPath $Folder -File -ErrorAction SilentlyContinue |
    Where-Object { $exts -contains $_.Extension.ToLower() } |
    Sort-Object { [regex]::Replace($_.Name, '\d+', { $args[0].Value.PadLeft(10,'0') }) } |
    Select-Object -First 1
if ($first) {
    & (Join-Path $PSScriptRoot 'DinaPlayer.exe') $first.FullName
}
