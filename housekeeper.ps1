#################################################
# HouseKeeper script to archive and clean files #
#################################################

# Script parameters
# -testMode : Execute the script without doing anything (Archiving or Deleting)
Param([Bool]$testMode=$false)

#################################################
# Functions                                     #
#################################################

Function WriteLog {
    param(  [string]$log,
            [string]$loglevel="INFO")

    $now = Get-Date -f "dd/MM/yyyy HH:mm:ss"
    
    Write-Host "$now | $loglevel | $log"
}

Function ResolveMasks {
    param(  [string]$pattern,
            [string]$package="")

    $pattern = $pattern -replace "%PACKAGE", $package
    $pattern = $pattern -replace "%DATE", (Get-Date -f "yyyyMMdd")
    $pattern = $pattern -replace "%TIME", (Get-Date -f "HHmmss")

    return $pattern
}

Function GetFileToArchive {
    param(  [string]$folder,
            [string]$pattern,
            [int]$archiveDelay,
            [int]$deleteDelay,
            [bool]$recursive)

    $files = @()

    if(!(Test-Path $folder -pathtype container)) {
        WriteLog "The folder $pathToScan doesn't exists" "ERROR"
    } else {
        foreach($item in Get-ChildItem $folder) {
            if((Test-Path "$folder\$item" -pathtype container) -and $recursive) {
                $data = getFileToArchive "$folder\$item" $pattern $archiveDelay $deleteDelay $recursive
                if(!($data -eq $null)){
                    $files += $data
                }
            } else {
                if($item -match $pattern) {
                    $toArchive = $false
                    $toDelete = $false

                    #Should we archive this file ?
                    if($archiveAfter -gt 0 -and (Get-Date ($item.LastWriteTime)) -lt ((Get-Date).AddDays(-1 * $archiveDelay))) {
                       $toArchive = $true
                       WriteLog "$folder\$item will be archived"
                    }

                    #Shoudl we delete this file ?
                    if($deleteAfter -gt 0 -and (Get-Date ($item.LastWriteTime)) -lt ((Get-Date).AddDays(-1 * $deleteDelay))) {
                       $toDelete = $true
                       WriteLog "$folder\$item will be deleted"
                    }

                    if($toArchive -or $toDelete) {
                        $lastModificationdate = "{0:yyyyMMdd}" -f (Get-Date ($item.LastWriteTime))
                        $files += ,("$folder\$item",$lastModificationdate,$toArchive,$toDelete)
                    }
                }
            }
        }
    }

    return (,($files))
}

Function ProcessFile {
    param(  $file,
            [string]$archivePath,
            [string]$packageName,
            [bool]$testMode)

    
}

#################################################
# Main sripts                                   #
#################################################

$configFile = "housekeeper.xml"

#Open the config files
if(!(Test-Path $configFile)) {
    WriteLog "Unable to open the config file $configFile"
    exit 1
}

WriteLog "Parsing the config file $configFile"
$config = [xml](get-content $configFile)

#get 7Zip path
$compressionTool = $config.configuration.compress.Value

#Get the logging information
$logPath = $config.configuration.logging.path.Value
$logTemplate = $config.configuration.logging.filename.Value

#Get the packages configs
foreach ($packageNode in $config.configuration.packages.package) {
    $packageName = $packageNode.Value
    $archiveAfter = $packageNode.archiveafter
    $deleteAfter = $packageNode.deleteafter
    $archivePath = $packageNode.archivepath

    if(!($archiveAfter -match "^\d+$") -or ([int]$archiveAfter) -lt 1) { $archiveAfter = -1 }
    if(!($deleteAfter -match "^\d+$") -or ([int]$deleteAfter) -lt 1) { $deleteAfter = -1 }

    #Initiate the log file
    $logFile = ResolveMasks $logTemplate $packageName
    $logFile = "$logFile.log"

    #Start the transcript
    Start-Transcript "$logPath\$logFile" -Append

    if($testMode) { WriteLog "TEST MODE - No file will be archived or deleted !!!!" }

    WriteLog "Package : $packageName"
    WriteLog "Archive After : $archiveAfter"
    WriteLog "Delete After : $deleteAfter"

    #Getting all pattern
    foreach ($patternNode in $packageNode.pattern) {
        #parse the pattern
        $pathToScan = $patternNode.path
        $pattern = $patternNode.pattern
        $recursive = $patternNode.recursive

        WriteLog "Pattern : [$pathToScan] [$pattern] [$recursive]"

        WriteLog "Set location to $pathToScan"
        set-location "$pathToScan"

        if($recursive -eq "true") { 
            $recursive = $true 
        } else {
            $recursive = $false
        }

        #Retreive the list of file to archive or delete
        $result = GetFileToArchive "." $pattern $archiveAfter $deleteAfter $recursive

        if ($result -and $result.length -gt 0)
        {
            WriteLog ("Number of results :" + $result.length)

            foreach ($file in $result) {
                if($file -and $file.length -gt 0) {
                    $fileName = $file[0]
                    $fileDate = $file[1]
                    $fileToArchive = $file[2]
                    $fileToDelete = $file[3]

                    if($fileToArchive) {
                        $args=@()
                        $args += "a"
                        $args += "`"$archivePath\$fileDate\$packageName`_$fileDate.rar`""
                        $args +=  "`"$fileName`""

                        #Creating the archive folder
                        if(!(Test-Path "$archivePath\$fileDate" -pathtype container)){
                            WriteLog "Creating directory $archivePath\$fileDate"
                            New-Item "$archivePath\$fileDate" -ItemType directory
                        }
                        
                        WriteLog "Adding $fileName to $archivePath\$fileDate\$packageName`_$fileDate.rar"
                        #WriteLog "$compressionTool $args"

                        if(! $testMode) { start-process $compressionTool -argument $args -Wait }
                    }

                    if($fileToDelete) {
                        WriteLog "Deleting $fileName"

                        if(! $testMode) { remove-item $fileName }
                    }
                }
            }
        } else {
            WriteLog "Nothing to archive or delete with this pattern"
        }
    
    }
    Stop-Transcript
}
