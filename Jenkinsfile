// build -> test -> publish -> dev -> manual approval -> prod
pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    // fires on the GitHub push webhook
    triggers { githubPush() }

    environment {
        VERSION = "1.0.${BUILD_NUMBER}"
        ZIP = "demoapp-${VERSION}.zip"
        DOTNET_CLI_TELEMETRY_OPTOUT = '1'
        DOTNET_NOLOGO = '1'
    }

    stages {
        stage('Build') {
            steps {
                bat 'dotnet restore DemoApp.sln'
                bat 'dotnet build DemoApp.sln -c Release --no-restore /p:Version=%VERSION%'
            }
        }

        stage('Test') {
            // red here = nothing gets deployed
            steps {
                bat 'dotnet test DemoApp.sln -c Release --no-build'
            }
        }

        stage('Dependency scan') {
            steps {
                // warn only, marks the build unstable instead of blocking
                catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
                    powershell '''
                        $out = dotnet list DemoApp.sln package --vulnerable --include-transitive 2>&1 | Out-String
                        Write-Host $out
                        if ($out -match 'has the following vulnerable packages') { throw 'vulnerable packages found' }
                    '''
                }
            }
        }

        stage('Publish artifact') {
            steps {
                bat '''
                    if exist publish rmdir /s /q publish
                    del /q demoapp-*.zip 2>nul
                    dotnet publish DemoApp.Web/DemoApp.Web.csproj -c Release --no-build -o publish /p:Version=%VERSION%
                '''
                powershell 'Compress-Archive -Path publish/* -DestinationPath $env:ZIP -Force'
                archiveArtifacts artifacts: 'demoapp-*.zip', fingerprint: true
            }
        }

        stage('Deploy Dev') {
            steps {
                // deploy.ps1 backs up, swaps files, checks /health, rolls back on failure
                powershell '''
                    & ./scripts/deploy.ps1 -Zip "$env:WORKSPACE/$env:ZIP" -Site DemoDev -Path C:/sites/dev -Port 8081 -ExpectedVersion $env:VERSION
                    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
                '''
            }
        }

        stage('Approve Prod') {
            steps {
                timeout(time: 30, unit: 'MINUTES') {
                    input message: "Promote ${VERSION} to Production?", ok: 'Promote'
                }
            }
        }

        stage('Deploy Prod') {
            // same zip that ran in dev, no rebuild
            steps {
                powershell '''
                    & ./scripts/deploy.ps1 -Zip "$env:WORKSPACE/$env:ZIP" -Site DemoProd -Path C:/sites/prod -Port 8082 -ExpectedVersion $env:VERSION
                    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
                '''
            }
        }
    }

    post {
        success  { echo "Version ${VERSION} is live in Production" }
        unstable { echo 'Finished with warnings, check the dependency scan' }
        failure {
            echo 'Pipeline failed'
            // mail to: 'you@example.com', subject: "FAILED ${JOB_NAME} #${BUILD_NUMBER}", body: "${BUILD_URL}"
        }
    }
}
