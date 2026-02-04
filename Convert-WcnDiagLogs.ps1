param(
    [Parameter(Mandatory=$true)][string]$LogsPath,
    [Parameter(Mandatory=$false)][string]$OutputFolder = "ConvertedEtlLogs"
)

<#
.SYNOPSIS
    Processes wcndiag*.zip files, extracts wcn_trace.etl files, converts them, and collects them in a common folder.

.DESCRIPTION
    This script:
    1. Finds all wcndiag*.zip files in the specified logs path (recursively)
    2. Expands those zip files
    3. Extracts wcn_trace.zip inside each wcndiag folder
    4. Converts wcn_trace.etl using "netsh trace convert"
    5. Copies all converted files to a common output folder

.PARAMETER LogsPath
    The root path containing the extracted pod logs (e.g., C:\Users\ppereira\Logs\Bugs\Cilium\KubeProxyDualStackbehav\CiliumLogs)

.PARAMETER OutputFolder
    The name of the output folder for converted ETL files. Default is "ConvertedEtlLogs".
    Will be created inside LogsPath.

.EXAMPLE
    .\Convert-WcnDiagLogs.ps1 -LogsPath "C:\Users\ppereira\Logs\Bugs\Cilium\KubeProxyDualStackbehav\CiliumLogs"
#>

$ErrorActionPreference = "Continue"

# Create output folder for all converted ETL files
$outputPath = Join-Path -Path $LogsPath -ChildPath $OutputFolder
if (-Not (Test-Path -Path $outputPath)) {
    New-Item -ItemType Directory -Path $outputPath | Out-Null
    Write-Host "Created output folder: $outputPath" -ForegroundColor Cyan
}

# Find all wcndiag*.zip files recursively
$wcndiagZips = Get-ChildItem -Path $LogsPath -Filter "wcndiag*.zip" -Recurse -File
Write-Host "Found $($wcndiagZips.Count) wcndiag*.zip files" -ForegroundColor Yellow

foreach ($wcndiagZip in $wcndiagZips) {
    Write-Host "`nProcessing: $($wcndiagZip.FullName)" -ForegroundColor Cyan
    
    # Get parent folder name (pod name) for unique naming
    $podFolder = $wcndiagZip.Directory.Name
    $wcndiagName = [System.IO.Path]::GetFileNameWithoutExtension($wcndiagZip.Name)
    
    # Create extraction folder for wcndiag zip
    $extractPath = Join-Path -Path $wcndiagZip.DirectoryName -ChildPath $wcndiagName
    
    try {
        # Step 1: Expand wcndiag*.zip
        Write-Host "  Expanding wcndiag zip..." -ForegroundColor DarkYellow
        Expand-Archive -Path $wcndiagZip.FullName -DestinationPath $extractPath -Force -ErrorAction Stop
        
        # Step 2: Find and expand wcn_trace.zip inside
        $wcnTraceZip = Get-ChildItem -Path $extractPath -Filter "wcn_trace.zip" -Recurse -File | Select-Object -First 1
        
        if ($null -eq $wcnTraceZip) {
            Write-Host "  wcn_trace.zip not found in $wcndiagName" -ForegroundColor Red
            continue
        }
        
        Write-Host "  Found wcn_trace.zip: $($wcnTraceZip.FullName)" -ForegroundColor DarkYellow
        
        $wcnTraceExtractPath = Join-Path -Path $wcnTraceZip.DirectoryName -ChildPath "wcn_trace"
        Expand-Archive -Path $wcnTraceZip.FullName -DestinationPath $wcnTraceExtractPath -Force -ErrorAction Stop
        
        # Step 3: Find wcn_trace.etl
        $etlFile = Get-ChildItem -Path $wcnTraceExtractPath -Filter "wcn_trace.etl" -Recurse -File | Select-Object -First 1
        
        if ($null -eq $etlFile) {
            Write-Host "  wcn_trace.etl not found in wcn_trace folder" -ForegroundColor Red
            continue
        }
        
        Write-Host "  Found wcn_trace.etl: $($etlFile.FullName)" -ForegroundColor DarkYellow
        
        # Step 4: Convert ETL file using netsh trace convert
        Write-Host "  Converting ETL file..." -ForegroundColor DarkYellow
        $originalLocation = Get-Location
        Set-Location -Path $etlFile.DirectoryName
        
        $convertResult = netsh trace convert $etlFile.Name 2>&1
        
        Set-Location -Path $originalLocation
        
        # Check for converted file (usually creates .txt or .csv file)
        $convertedFiles = Get-ChildItem -Path $etlFile.DirectoryName -Include "wcn_trace.txt", "wcn_trace.csv", "wcn_trace.xml" -Recurse -File -ErrorAction SilentlyContinue
        
        if ($convertedFiles.Count -eq 0) {
            Write-Host "  Warning: No converted file found. Netsh output: $convertResult" -ForegroundColor Yellow
            # Still copy the ETL file itself
            $convertedFiles = @($etlFile)
        }
        
        # Step 5: Copy converted files to output folder organized by pod name
        $podOutputPath = Join-Path -Path $outputPath -ChildPath $podFolder
        if (-Not (Test-Path -Path $podOutputPath)) {
            New-Item -ItemType Directory -Path $podOutputPath | Out-Null
        }
        
        foreach ($convertedFile in $convertedFiles) {
            # Use simple name: wcndiag<timestamp>.txt
            $extension = $convertedFile.Extension
            $simpleName = "${wcndiagName}${extension}"
            $destPath = Join-Path -Path $podOutputPath -ChildPath $simpleName
            Copy-Item -Path $convertedFile.FullName -Destination $destPath -Force
            Write-Host "  Copied to: $destPath" -ForegroundColor Green
        }
        
    } catch {
        Write-Host "  Error processing $($wcndiagZip.Name): $_" -ForegroundColor Red
    }
}


# Find all wcndiag*.zip files recursively
$wcndiagZips = Get-ChildItem -Path $LogsPath -Filter "traces.zip" -Recurse -File
Write-Host "Found $($wcndiagZips.Count) traces.zip files" -ForegroundColor Yellow

foreach ($wcndiagZip in $wcndiagZips) {
    Write-Host "`nProcessing: $($wcndiagZip.FullName)" -ForegroundColor Cyan
    
    # Get parent folder name (pod name) for unique naming
    $podFolder = $wcndiagZip.Directory.Name
    $wcndiagName = [System.IO.Path]::GetFileNameWithoutExtension($wcndiagZip.Name)
    
    # Create extraction folder for traces.zip
    $extractPath = Join-Path -Path $wcndiagZip.DirectoryName -ChildPath $wcndiagName
    
    try {
        # Step 1: Expand traces.zip
        Write-Host "  Expanding traces.zip..." -ForegroundColor DarkYellow
        Expand-Archive -Path $wcndiagZip.FullName -DestinationPath $extractPath -Force -ErrorAction Stop
        
        
        # Step 3: Find wcn_trace.etl
        $etlFiles = Get-ChildItem -Path $extractPath -Filter "trace*.etl" -Recurse -File

        foreach ($etlFile in $etlFiles) {
            Write-Host "  Found trace ETL file: $($etlFile.FullName)" -ForegroundColor DarkYellow
            
            # Step 4: Convert ETL file using netsh trace convert
            Write-Host "  Converting ETL file..." -ForegroundColor DarkYellow
            $originalLocation = Get-Location
            Set-Location -Path $etlFile.DirectoryName
            
            $convertResult = netsh trace convert $etlFile.Name 2>&1
            
            Set-Location -Path $originalLocation
            
            # Check for converted file (usually creates .txt or .csv file)
            $convertedFiles = Get-ChildItem -Path $etlFile.DirectoryName -Include "*.txt" -Recurse -File -ErrorAction SilentlyContinue
            
            if ($convertedFiles.Count -eq 0) {
                Write-Host "  Warning: No converted file found. Netsh output: $convertResult" -ForegroundColor Yellow
                # Still copy the ETL file itself
                $convertedFiles = @($etlFile)
            }
            
            # Step 5: Copy converted files to output folder organized by pod name
            $podOutputPath = Join-Path -Path $outputPath -ChildPath $podFolder
            if (-Not (Test-Path -Path $podOutputPath)) {
                New-Item -ItemType Directory -Path $podOutputPath | Out-Null
            }
            
            foreach ($convertedFile in $convertedFiles) {
                # Use simple name: traces<timestamp>.txt
                $extension = $convertedFile.Extension
                Copy-Item -Path $convertedFile.FullName -Destination $podOutputPath -Force
                Write-Host "  Copied to: $podOutputPath" -ForegroundColor Green
            }
        }
        
    } catch {
        Write-Host "  Error processing $($wcndiagZip.Name): $_" -ForegroundColor Red
    }
}

Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host "All converted ETL files are in: $outputPath" -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta

# List the output folder contents organized by pod
Write-Host "`nConverted files:" -ForegroundColor Cyan
Get-ChildItem -Path $outputPath -Directory | ForEach-Object {
    Write-Host "`n$($_.Name):" -ForegroundColor Yellow
    Get-ChildItem -Path $_.FullName | Format-Table Name, Length, LastWriteTime -AutoSize
}
