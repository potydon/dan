#!/usr/bin/env powershell
$path = "$env:USERPROFILE\.local\bin"
$dest = join-path $path 'dan.ps1'
$conf = "$env:USERPROFILE\.config\dan"

if (!(Test-Path $path)) {
	mkdir $path
	[System.Environment]::SetEnvironmentVariable("PATH", $env:PATH + ";$path", "User")
	$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "User")
}

if (!(Test-Path $conf)) {
	mkdir $conf
}

$current = join-path (Get-Location).ProviderPath 'dan.ps1'

if (!(Copy-Item -Path "dan.ps1" -Destination "${path}\dan.ps1" -Force)) {
	Copy-Item -Path $current -Destination "$path\dan.ps1" -Force
}
