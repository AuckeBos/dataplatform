<# 
.SYNOPSIS
    Read environment variables from a .env file in the root of the repository.
#>
function Read-Env {
    $envPath = "$(git rev-parse --show-toplevel)/.env"
    if (Test-Path $envPath) {
        Get-Content $envPath | ForEach-Object {
            if ($_ -match "^(.*?)=(.*)$") {
                [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2])
            }
        }
    }
}