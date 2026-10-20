$ErrorActionPreference = "Stop"

$version = "5.5.1"
$expectedHash = "da07b543872dc0bb2ff12aabd0c248578d78df3eb6b67efdc537a46d455c7f31"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$destination = Join-Path $root "tests/upstream/lua-$version-tests"

$temporary = Join-Path $env:TEMP (
    "quvrena-tests-" + [guid]::NewGuid().ToString("N")
)

New-Item -ItemType Directory -Path $temporary -Force | Out-Null

try {
    $archive = Join-Path $temporary "tests.tar.gz"
    $url = "https://www.lua.org/tests/lua-$version-tests.tar.gz"

    Write-Host "Downloading Lua $version tests..."
    Invoke-WebRequest -Uri $url -OutFile $archive

    # Verify official archive
    $hash = (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant()

    if ($hash -ne $expectedHash) {
        throw "Invalid upstream test archive SHA-256"
    }

    Write-Host "Archive checksum verified."

    tar -xzf $archive -C $temporary

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to extract Lua tests"
    }

    $sourceDir = Join-Path $temporary "lua-$version-tests"
    $filesLua = Join-Path $sourceDir "files.lua"

    if (-not (Test-Path $filesLua)) {
        throw "Missing files.lua in official test suite"
    }

    # Adapt the upstream flush test for Windows.
    $content = [System.IO.File]::ReadAllText($filesLua)

    $pattern = '(?ms)^do print\("testing flush"\)[^\r\n]*\r?\n.*?^end[ \t]*(?=\r?\n)'

    $replacement = @'
do print("testing flush")
  local is_windows = package.config:sub(1, 1) == "\\"

  -- Successful flushing
  local null_device = is_windows and "NUL" or "/dev/null"
  local f = io.output(null_device)

  assert(f:write("abcd"))
  assert(f:flush())
  assert(f:write("abcd"))
  assert(io.flush())
  assert(f:close())

  -- /dev/full is not available on Windows.
  if not is_windows then
    local full = io.open("/dev/full", "w")

    if full then
      io.output(full)

      assert(full:write("abcd"))
      assert(not full:flush())
      assert(full:write("abcd"))
      assert(not io.flush())
      assert(full:close())
    end
  end
end
'@

    $matches = [regex]::Matches($content, $pattern)

    if ($matches.Count -ne 1) {
        throw "Unexpected upstream files.lua format: flush test not found uniquely"
    }

    $content = [regex]::Replace(
        $content,
        $pattern,
        $replacement
    )

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($filesLua, $content, $utf8)

    # Install only after successful verification and patching
    New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null

    if (Test-Path $destination) {
        Remove-Item $destination -Recurse -Force
    }

    Move-Item $sourceDir $destination

    Write-Host "Quvrena upstream tests prepared successfully."
}
finally {
    if (Test-Path $temporary) {
        Remove-Item $temporary -Recurse -Force
    }
}
