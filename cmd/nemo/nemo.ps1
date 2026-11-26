<#
.SYNOPSIS
    Ask NVIDIA Nemotron 3.5 Super VL 120B A12B to write code or answers.

.DESCRIPTION
    Calls the hosted NVIDIA NIM Chat Completions API and prints the response as
    markdown, with fenced, language-tagged code blocks. The API key is read from
    NVIDIA_API_KEY or from a key file (default: %USERPROFILE%\.nvidia-key).

.EXAMPLE
    nemo "write a python function that merges two sorted lists"

.EXAMPLE
    nemo "powershell script to find files over 1 GB" -CodeOnly -OutFile bigfiles.ps1

.EXAMPLE
    nemo "explain TCP congestion control in 5 bullets"

.EXAMPLE
    nemo -ListModels
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true, Position = 0)]
    [string[]] $Task,

    [string] $System,
    [string] $Model = "nvidia/nemotron-3.5-super-vl-120b-a12b",
    [string] $Endpoint = "https://integrate.api.nvidia.com/v1/chat/completions",
    [string] $KeyFile,
    [int] $MaxTokens = 8192,
    [double] $Temperature = 0.2,
    [switch] $CodeOnly,
    [switch] $Raw,
    [switch] $ShowReasoning,
    [string] $OutFile,
    [switch] $ListModels,
    [switch] $Help
)

$ErrorActionPreference = "Stop"

function Show-NemoHelp {
    @"
nemo <task> [options]

  <task>              What to write. Quote it. Remaining arguments are joined.

Options:
  -CodeOnly           Ask for one fenced code block only; strip the fence on output.
  -Raw                Strip an outer markdown fence from the response.
  -OutFile <path>     Write the answer to a UTF-8 file instead of the console.
  -ShowReasoning      Also print the model's reasoning trace (uses extra tokens).
  -System <text>      Replace the default system prompt.
  -Model <id>         Override the model id.
  -KeyFile <path>     Override the API key file location.
  -MaxTokens <n>      Default $MaxTokens. Reasoning counts toward this.
  -Temperature <n>    Default $Temperature.
  -Endpoint <url>     Override the chat completions URL.
  -ListModels         List models available to this key.
  -Help               Show this help.

Key lookup order: NVIDIA_API_KEY, -KeyFile, %USERPROFILE%\.nvidia-key,
%USERPROFILE%\nvidia.key, %USERPROFILE%\.config\nvidia\key, %HOME%\.nvidia-key.

Examples:
  nemo "write a python quicksort with tests"
  nemo "regex to validate an IPv4 address" -CodeOnly
  nemo "rest api in fastapi with jwt auth" -OutFile .\api.md
"@
}

function Get-NemoKey {
    param([string] $Override)

    if ($env:NVIDIA_API_KEY) {
        $v = $env:NVIDIA_API_KEY.Trim()
        if ($v) { return $v }
    }

    $candidates = @()
    if ($Override) { $candidates += $Override }
    if ($env:USERPROFILE) {
        $candidates += (Join-Path $env:USERPROFILE ".nvidia-key")
        $candidates += (Join-Path $env:USERPROFILE "nvidia.key")
        $candidates += (Join-Path $env:USERPROFILE ".config\nvidia\key")
    }
    if ($env:HOME) {
        $candidates += (Join-Path $env:HOME ".nvidia-key")
    }

    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $v = (Get-Content -LiteralPath $path -Raw).Trim()
            if ($v) { return $v }
        }
    }
    return $null
}

function Invoke-NemoApi {
    param(
        [string] $Uri,
        [hashtable] $Headers,
        [System.Array] $BodyBytes,
        [string] $Method = "Post"
    )

    $lastStatus = $null
    $lastDetail = $null
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $params = @{
                Uri         = $Uri
                Method      = $Method
                Headers     = $Headers
                ContentType = "application/json"
                TimeoutSec  = 300
            }
            if ($BodyBytes -and $BodyBytes.Length -gt 0) {
                $params.Body = $BodyBytes
            }
            return Invoke-RestMethod @params
        }
        catch {
            $lastStatus = $null
            if ($_.Exception.Response) {
                $lastStatus = [int] $_.Exception.Response.StatusCode
            }
            $lastDetail = $null
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                $lastDetail = $_.ErrorDetails.Message
            }
            if (-not $lastDetail -and $_.Exception.Response) {
                try {
                    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                    $lastDetail = $reader.ReadToEnd()
                }
                catch { }
            }
            if ($lastStatus -eq 400 -or $lastStatus -eq 401 -or $lastStatus -eq 403 -or $lastStatus -eq 404) {
                throw "NVIDIA API error $lastStatus`: $lastDetail"
            }
            if ($attempt -lt 3) {
                Start-Sleep -Seconds (2 * $attempt)
                continue
            }
            throw "NVIDIA API request failed after 3 attempts (status $lastStatus): $lastDetail $($_.Exception.Message)"
        }
    }
}

if ($Help) {
    Show-NemoHelp
    return
}

$key = Get-NemoKey -Override $KeyFile
if (-not $key) {
    throw "No NVIDIA API key found. Set NVIDIA_API_KEY or put the key in %USERPROFILE%\.nvidia-key. Run 'nemo -Help' for details."
}
$headers = @{ Authorization = "Bearer $key" }

if ($ListModels) {
    $modelsUri = [regex]::Replace($Endpoint, '/chat/completions$', '/models')
    $result = Invoke-NemoApi -Uri $modelsUri -Headers $headers -BodyBytes @() -Method Get
    $result.data | ForEach-Object { $_.id } | Sort-Object
    return
}

$userText = ($Task -join " ").Trim()
if (-not $userText) {
    Show-NemoHelp
    return
}

if ($CodeOnly) {
    $systemText = @"
Return exactly one fenced code block with a language tag, containing complete,
runnable code. No prose before or after it. Never use placeholder bodies such as
'TODO' or '...'. Do not invent libraries or APIs.
"@
}
elseif ($System) {
    $systemText = $System
}
else {
    $systemText = @"
You are a precise senior software engineer.
- Complete the user's task exactly; do not restate it.
- Give a short answer, then show code in fenced code blocks with the correct language tag.
- Code must be complete and runnable, with clear names and no placeholder bodies like '...'.
- Never invent libraries, endpoints, or APIs. Note assumptions briefly if needed.
- If the task is not about code, answer directly in clean, compact markdown.
"@
}

$payload = [ordered]@{
    model       = $Model
    messages    = @(
        [ordered]@{ role = "system"; content = $systemText },
        [ordered]@{ role = "user"; content = $userText }
    )
    max_tokens  = $MaxTokens
    temperature = $Temperature
    stream      = $false
}
$json = $payload | ConvertTo-Json -Depth 12 -Compress
$bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($json)

$response = Invoke-NemoApi -Uri $Endpoint -Headers $headers -BodyBytes $bodyBytes -Method Post

$choice = @($response.choices)[0]
if (-not $choice) {
    throw "NVIDIA API returned no choices."
}
$message = $choice.message
$refusal = [string] $message.refusal
if ($refusal) {
    throw "Model refused the task: $refusal"
}

$content = [string] $message.content
$reasoning = [string] $message.reasoning_content

if ([string]::IsNullOrWhiteSpace($content)) {
    throw "Model returned an empty answer. Increase -MaxTokens (reasoning consumes tokens) or simplify the task."
}

if ($Raw -or $CodeOnly) {
    $match = [regex]::Match($content, '(?s)^\s*```[^\r\n]*\r?\n(.*?)\r?\n```\s*$')
    if ($match.Success) {
        $content = $match.Groups[1].Value
    }
}

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
}
catch { }

if ($ShowReasoning -and -not [string]::IsNullOrWhiteSpace($reasoning)) {
    [Console]::Error.WriteLine("--- reasoning ---")
    [Console]::Error.WriteLine($reasoning)
    [Console]::Error.WriteLine("--- answer ---")
}

if ($OutFile) {
    $fullPath = [System.IO.Path]::GetFullPath($OutFile)
    $dir = [System.IO.Path]::GetDirectoryName($fullPath)
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    [System.IO.File]::WriteAllText($fullPath, $content, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Wrote $fullPath"
}
else {
    Write-Output $content
}
