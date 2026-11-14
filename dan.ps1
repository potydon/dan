#!/usr/bin/env pwsh
#
# Minimal dotfile manager
#
# Author: Potydon <potydon@4d2.org>
# Date: November 15, 2026
# License: ISC

# Variables
$esc     = [char]27
$Option  = $args[0]
$Targets = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] } else { @() }

# Helpers
function expand_tilde([string]$p) {
	$p -replace '^~', $HOME.Replace('$', '$$')
}

function to_tilde([string]$p) {
	$homeLen = $HOME.Length
	if ($p.StartsWith($HOME, [StringComparison]::OrdinalIgnoreCase) -and ($p.Length -eq $homeLen -or $p[$homeLen] -in '\', '/')) {
		$p = '~' + $p.Substring($homeLen)
	}
	$p -replace '\\', '/'
}

function entry_pattern([string]$name) {
	'^' + [regex]::Escape($name) + ' = '
}

function new_file_if_missing([string]$Path) {
	if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
		$null = New-Item -ItemType File -Path $Path -Force
	}
}

# Removes $Dest, copies $Src over it, and prints success/failed
function replace_path([string]$Src, [string]$Dest, [string]$Name, [string]$Verb) {
	if (-not (Test-Path -LiteralPath $Src)) {
		Write-Host "failed: $Verb $Name"
		return
	}
	try {
		if (Test-Path -LiteralPath $Dest) { Remove-Item -LiteralPath $Dest -Recurse -Force -ErrorAction Stop }
		$parent = Split-Path -Path $Dest -Parent
		if ($parent) { $null = New-Item -ItemType Directory -Path $parent -Force }
		Copy-Item -LiteralPath $Src -Destination $Dest -Recurse -Force -ErrorAction Stop
		Write-Host "success: $Verb $Name"
	} catch {
		Write-Host "failed: $Verb $Name"
	}
}

# Setup / config
function setup {
	$script:ConfigFile = Join-Path -Path $HOME -ChildPath '.config/dan/config'
	$null = New-Item -ItemType Directory -Path (Split-Path -Path $script:ConfigFile -Parent) -Force
	new_file_if_missing $script:ConfigFile
}

function load_config {
	$raw  = [string](Get-Content -LiteralPath $script:ConfigFile -Raw -ErrorAction Ignore)
	$path = if (-not [string]::IsNullOrEmpty($raw)) { expand_tilde ($raw.Trim() -replace '^path = ') } else { return }

	$script:DotfilesPath = $path
	if ([string]::IsNullOrEmpty($path)) { return $false }

	$script:EntryFile = Join-Path -Path $path -ChildPath '.dan'
	return $true
}

function confirmation {
	param([string]$Text, [string]$ConfText)

	if ([string]::IsNullOrEmpty($ConfText)) {
		$answer = Read-Host "$Text [Y/n]"
	} else {
		Write-Host $Text
		$answer = Read-Host "$ConfText [Y/n]"
	}

	if ($answer -match '^n$') {
		Write-Host 'Cancelled.'
		return $false
	}
	return $true
}

# Path lookup
function get_entry_path {
	param([string]$Target)

	$line = Select-String -Pattern (entry_pattern $Target) -LiteralPath $script:EntryFile -CaseSensitive -ErrorAction Ignore |
		Select-Object -First 1 -ExpandProperty Line

	if ([string]::IsNullOrEmpty($line)) { return $false }

	$script:ChoiceRaw  = $line
	$script:ChoicePath = expand_tilde ($line -replace '^.*? = ')
	$script:ChoiceName = Split-Path -Path $script:ChoicePath -Leaf
	$script:ChoiceDots = Join-Path -Path $script:DotfilesPath -ChildPath $script:ChoiceName
	return $true
}

function get_choice_path {
	param([string]$Target)

	$resolved = Resolve-Path -LiteralPath $Target -ErrorAction Ignore
	if (-not $resolved) {
		Write-Host 'failed: not a real path'
		return $false
	}

	$script:ChoicePath = $resolved.ProviderPath
	$script:TildePath  = to_tilde $script:ChoicePath
	$script:ChoiceName = Split-Path -Path $script:ChoicePath -Leaf
	$script:ChoiceDots = if ($script:DotfilesPath) { Join-Path -Path $script:DotfilesPath -ChildPath $script:ChoiceName } else { '' }
	return $true
}

function get_current_path {
	$script:CurrentDir = (Get-Location).ProviderPath
	if ([string]::IsNullOrEmpty($script:CurrentDir)) {
		Write-Host 'failed: get current working directory'
		return $false
	}
	$script:TildePath = to_tilde $script:CurrentDir
	return $true
}

function add_path_to_entry {
	$exists = Select-String -Pattern (entry_pattern $script:ChoiceName) -LiteralPath $script:EntryFile -CaseSensitive -Quiet -ErrorAction Ignore
	if ($exists) { return }

	try {
		Add-Content -LiteralPath $script:EntryFile -Value "$($script:ChoiceName) = $($script:TildePath)" -ErrorAction Stop
		Write-Host 'success: added path to entry'
	} catch {
		Write-Host 'failed: adding path to entry'
	}
}

# Commands
function init {
	param([string[]]$Targets)

	$hadConfig = load_config

	if (-not $Targets) {
		if (-not (get_current_path)) { return }
		$newPath = $script:CurrentDir
	} else {
		if (-not (get_choice_path $Targets[0])) { return }
		$newPath = $script:ChoicePath
	}

	if ($hadConfig) {
		$ok   = confirmation "You will overwrite the dotfiles path from '$($script:DotfilesPath)' into '$($script:TildePath)'" 'Proceed to overwrite?'
		$verb = 'overwrite dotfiles path'
	} else {
		$ok   = confirmation "You will set the dotfiles path into '$($script:TildePath)'" 'Proceed to apply?'
		$verb = 'set dotfiles path'
	}
	if (-not $ok) { return }

	new_file_if_missing (Join-Path -Path $newPath -ChildPath '.dan')
	try {
		Set-Content -LiteralPath $script:ConfigFile -Value "path = $($script:TildePath)" -ErrorAction Stop
		Write-Host "success: $verb"
	} catch {
		Write-Host "failed: $verb"
	}
}

function sync {
	param([string[]]$Targets)

	if (-not (load_config)) { Write-Host 'error: no dotfiles path'; return }

	if (-not $Targets) {
		if (-not (confirmation 'You will replace all the folders or files on dotfiles with the local' 'Proceed to syncall?')) { return }
		foreach ($line in Get-Content -LiteralPath $script:EntryFile -ErrorAction Ignore) {
			if ($line -notmatch '^(.*?) = (.*)$') { continue }
			$pkg = $Matches[1]
			replace_path (expand_tilde $Matches[2]) (Join-Path -Path $script:DotfilesPath -ChildPath $pkg) $pkg 'copy'
		}
	} else {
		if (-not (confirmation "Sync $($Targets -join ', ') into the dotfiles" 'Proceed to sync?')) { return }
		foreach ($pkg in $Targets) {
			if (get_entry_path $pkg) {
				replace_path $script:ChoicePath $script:ChoiceDots $script:ChoiceName 'copy'
			} elseif (get_choice_path $pkg) {
				replace_path $script:ChoicePath $script:ChoiceDots $script:ChoiceName 'copy'
				add_path_to_entry
			}
		}
	}
}

function apply {
	param([string[]]$Targets)

	if (-not (load_config)) { Write-Host 'error: no dotfiles path'; return }

	if (-not $Targets) {
		if (-not (confirmation 'You will replace all the folders or files on local with the dotfiles' 'Proceed to applyall?')) { return }
		foreach ($line in Get-Content -LiteralPath $script:EntryFile -ErrorAction Ignore) {
			if ($line -notmatch '^(.*?) = (.*)$') { continue }
			$pkg = $Matches[1]
			replace_path (Join-Path -Path $script:DotfilesPath -ChildPath $pkg) (expand_tilde $Matches[2]) $pkg 'apply'
		}
	} else {
		if (-not (confirmation "Apply $($Targets -join ', ') into local" 'Proceed to apply?')) { return }
		foreach ($pkg in $Targets) {
			if (get_entry_path $pkg) {
				replace_path $script:ChoiceDots $script:ChoicePath $script:ChoiceName 'apply'
			} else {
				Write-Host "error: $pkg not found in entry list"
			}
		}
	}
}

function remove {
	param([string[]]$Targets)

	if (-not (load_config)) { Write-Host 'error: no dotfiles path'; return }
	if (-not $Targets) {
		Write-Host "error: no targets specified (use 'dan help' for help)"
		return
	}
	if (-not (confirmation "Are you sure to delete $($Targets -join ', ')" 'Proceed to remove?')) { return }

	foreach ($pkg in $Targets) {
		if (-not (get_entry_path $pkg)) {
			Write-Host "error: $pkg not found in entry list"
			continue
		}
		try {
			if (Test-Path -LiteralPath $script:ChoiceDots) { Remove-Item -LiteralPath $script:ChoiceDots -Recurse -Force -ErrorAction Stop }
			$kept = @(Get-Content -LiteralPath $script:EntryFile | Where-Object { $_ -ne $script:ChoiceRaw })
			Set-Content -LiteralPath $script:EntryFile -Value $kept -ErrorAction Stop
			Write-Host "success: remove $($script:ChoiceName)"
		} catch {
			Write-Host "failed: remove $($script:ChoiceName)"
		}
	}
}

function list {
	if (-not (load_config)) { Write-Host 'error: no dotfiles path'; return }

	$distance = 30
	$blue  = "$esc[1;34m"
	$black = "$esc[0;30m"
	$none  = "$esc[0m"

	Write-Host "$black##$none[${blue}dan$none] $($script:DotfilesPath)"

	$found = 0
	foreach ($line in Get-Content -LiteralPath $script:EntryFile -ErrorAction Ignore) {
		if ($line -notmatch '^(.*?) = (.*)$') { continue }
		$pkg  = $Matches[1]
		$path = expand_tilde $Matches[2]

		if (Test-Path -LiteralPath $path -PathType Container) {
			Write-Host "$black-- $blue $($pkg.PadRight($distance))$none"
			$found++
		} elseif (Test-Path -LiteralPath $path -PathType Leaf) {
			Write-Host "$black-- $none $($pkg.PadRight($distance))"
			$found++
		}
	}
	if ($found -eq 0) {
		Write-Host "there's nothing in your dotfiles($($script:DotfilesPath))."
	}
}

function helps {
	@'
usage: dan [-v | --version] [-h | --help]
           <command> [<args>]

commands (with arguments)
   help     show the help page
   list     show existing things inside dotfiles
   init     create a dan directory
   sync     add specified things into dotfiles
   apply    apply specified folder into local
   remove   remove things from dotfiles

commands (without arguments)
   sync     sync all from the list on dotfiles
   apply    apply all from the list on dotfiles

'dan help' or 'dan -h' shows this page.
'@
}

function version {
	@'
Dan v1.0.0 - powershell
Copyright (C) 2025-2026 @Pointers

This program may be freely redistributed under
the terms of the ISC License.
'@
}

# Run
setup

switch -CaseSensitive ($Option) {
	{ $_ -in 'help',    '-h', '--help'    } { helps }
	{ $_ -in 'version', '-v', '--version' } { version }
	'list'   { list }
	'init'   { init   $Targets }
	'sync'   { sync   $Targets }
	'apply'  { apply  $Targets }
	'remove' { remove $Targets }
	default  { helps }
}
