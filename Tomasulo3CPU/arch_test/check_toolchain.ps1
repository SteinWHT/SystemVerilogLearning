# Quick check that the xPack RISC-V toolchain is visible.
$BinDir = "D:\riscv-toolchain\xpack-riscv-none-elf-gcc-14.2.0-3\bin"
if ($env:RISCV_TOOLCHAIN_BIN) { $BinDir = $env:RISCV_TOOLCHAIN_BIN }

$gcc = Join-Path $BinDir "riscv-none-elf-gcc.exe"
if (-not (Test-Path $gcc)) {
    Write-Host "NOT FOUND: $gcc"
    Write-Host "Fix PATH or run:"
    Write-Host '  $env:RISCV_TOOLCHAIN_BIN = "D:\riscv-toolchain\xpack-riscv-none-elf-gcc-14.2.0-3\bin"'
    exit 1
}

& $gcc --version
Write-Host "OK: $gcc"
