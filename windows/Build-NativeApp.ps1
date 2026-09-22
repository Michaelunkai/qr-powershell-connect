[CmdletBinding()]
param(
    [ValidateSet('Debug','Release','Test','Lint')][string]$Action='Release',
    [string]$StudioRoot='F:\backup\windowsapps\installed\AndroidStudio',
    [string]$BuildTemp='F:\study\.qrbridge-build-tmp',
    [string]$JavaHome,
    [string]$SdkRoot,
    [string]$GradleHome
)
$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot
$app=Join-Path $project 'android-app'
$names=@('JAVA_HOME','ANDROID_HOME','GRADLE_USER_HOME','JAVA_TOOL_OPTIONS','TEMP','TMP','QRBRIDGE_STOREPASS','ORG_GRADLE_PROJECT_keystoreFile','ORG_GRADLE_PROJECT_keystoreAlias','ORG_GRADLE_PROJECT_keystorePassword')
$previous=@{}
foreach($name in $names){$previous[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
try {
    $env:JAVA_HOME=if($JavaHome){$JavaHome}else{Join-Path $StudioRoot 'android-studio\jbr'}
    $env:ANDROID_HOME=if($SdkRoot){$SdkRoot}else{Join-Path $StudioRoot 'android-sdk'}
    $env:GRADLE_USER_HOME=if($GradleHome){$GradleHome}else{Join-Path $StudioRoot 'portable-data\gradle'}
    New-Item -ItemType Directory -Force $BuildTemp | Out-Null
    $env:TEMP=$BuildTemp; $env:TMP=$BuildTemp
    $env:JAVA_TOOL_OPTIONS="-Djava.net.preferIPv4Stack=true -Djava.io.tmpdir=$BuildTemp -Djdk.net.unixdomain.tmpdir=$BuildTemp"
    if($Action -eq 'Release') {
        $state=Join-Path $env:ProgramData 'QrPowerShellConnect'
        if(-not(Test-Path -LiteralPath (Join-Path $state 'installation.json'))){throw 'Install the Windows bridge first so signing material uses its protected state directory.'}
        $secrets=Join-Path $state 'android-signing.json'
        $keystore=Join-Path $state 'android-release.p12'
        if(-not(Test-Path $secrets)) {
            $bytes=New-Object byte[] 32
            $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
            try{$rng.GetBytes($bytes)}finally{$rng.Dispose()}
            @{password=[Convert]::ToBase64String($bytes)} | ConvertTo-Json | Set-Content -LiteralPath $secrets -Encoding UTF8
        }
        $signing=Get-Content -LiteralPath $secrets -Raw | ConvertFrom-Json
        $env:QRBRIDGE_STOREPASS=$signing.password
        if(-not(Test-Path $keystore)) {
            & "$env:JAVA_HOME\bin\keytool.exe" -genkeypair -keystore $keystore -storetype PKCS12 -alias powershell-connect -keyalg RSA -keysize 3072 -validity 10000 -dname 'CN=PowerShell Connect, OU=Local Open Source Build' -storepass:env QRBRIDGE_STOREPASS -keypass:env QRBRIDGE_STOREPASS
            if($LASTEXITCODE -ne 0){throw 'Release signing key generation failed'}
        }
        $env:ORG_GRADLE_PROJECT_keystoreFile=$keystore
        $env:ORG_GRADLE_PROJECT_keystoreAlias='powershell-connect'
        $env:ORG_GRADLE_PROJECT_keystorePassword=$signing.password
    }
    [string[]]$tasks=@(switch($Action){
        'Debug' { @(':app:assembleOssDebug') }
        'Release' { @(':app:assembleOssRelease') }
        'Test' { @(':app:testOssDebugUnitTest','--tests','org.connectbot.bridge.*','--tests','org.connectbot.service.TerminalKeyListenerTest') }
        'Lint' { @(':app:lintOssRelease') }
    })
    & "$app\gradlew.bat" -p $app @tasks --console=plain --no-configuration-cache
    if($LASTEXITCODE -ne 0){throw "Android $Action failed"}
    if($Action -eq 'Release') {
        $destination=Join-Path $project 'dist\PowerShell-Connect-2.0.1.apk'
        New-Item -ItemType Directory -Force (Split-Path $destination) | Out-Null
        Copy-Item -LiteralPath "$app\app\build\outputs\apk\oss\release\app-oss-release.apk" -Destination $destination -Force
        (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash | Set-Content "$destination.sha256"
        Write-Host "APK: $destination"
    }
} finally {foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$previous[$name],'Process')}}
