# Scoop: 'scoop search' -> scoop-search (Rust), ~500x faster
if (Get-Command scoop-search.exe -ErrorAction SilentlyContinue) {
    function scoop {
        if ($args.Count -ge 2 -and $args[0] -eq 'search') {
            scoop-search.exe @($args | Select-Object -Skip 1)
        }
        else {
            scoop.ps1 @args
        }
    }
}

# Scoop: tab completion for app names / buckets
if (Get-Module -ListAvailable -Name scoop-completion) {
    Import-Module scoop-completion -ErrorAction SilentlyContinue
}
