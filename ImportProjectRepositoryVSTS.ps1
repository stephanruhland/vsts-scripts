Param(
   [string]$VSTS_ACCOUNT = "<VSTS-ACCOUNT-NAME>",
   [string]$PROJECT_SOURCE_NAME = "<PROJECT-NAME>",
   [string]$PROJECT_TARGET_NAME = "<PROJECT-NAME>",
   [string]$USER = "<USER-NAME>",
   [string]$TOKEN = "<PERSONAL-ACCESS-TOKEN>"
)

# Imports multiple vsts repositories to another project

### EXAMPLE PARAMETER ####
$VSTS_ACCOUNT = "companyABC"
$PROJECT_SOURCE_NAME = "projectA"
$PROJECT_TARGET_NAME = "projectB"
$USER = "user1234"
$TOKEN = "47rth73tfjs7iuaa3huzfsgdshfjggf"
####

function GetSourceRepositories()
{
    $uri = "https://$VSTS_ACCOUNT.visualstudio.com/$PROJECT_SOURCE_NAME/_apis/git/repositories?api-version=4.1"
    $result = Invoke-RestMethod -Uri $uri -Method Get -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $AUTH_INFO_BASE64)}
    return $result.value
}

function GetTargetRepositories()
{
    $uri = "https://$VSTS_ACCOUNT.visualstudio.com/$PROJECT_TARGET_NAME/_apis/git/repositories?api-version=4.1"
    $result = Invoke-RestMethod -Uri $uri -Method Get -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $AUTH_INFO_BASE64)}
    return $result.value
}

function CreateTargetRepository([string] $repositoryName)
{
    $uri = "https://$VSTS_ACCOUNT.visualstudio.com/$PROJECT_TARGET_NAME/_apis/git/repositories?api-version=4.1"
    $body = '{ "name": "'+$repositoryName+'" }'
    $result = Invoke-RestMethod -Uri $uri -Method Post -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $AUTH_INFO_BASE64)} -Body $body
    return $result
}

function CreateTargetServiceEndpoint([string] $repositoryName, [string] $sourceRepositoryUrl)
{
    $uri = "https://$VSTS_ACCOUNT.visualstudio.com/$PROJECT_TARGET_NAME/_apis/serviceendpoint/endpoints?api-version=4.1-preview.1"
    $bodyAuth = ' { "scheme": "UsernamePassword", "parameters": { "username": "'+$USER+'", "password": "'+$TOKEN+'" } }'
    $body = '{ "name": "Repository Import '+$repositoryName+'", "type": "git", "url": "'+$sourceRepositoryUrl+'", "authorization": '+$bodyAuth+'}'
    $result = Invoke-RestMethod -Uri $uri -Method Post -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $AUTH_INFO_BASE64)} -Body $body
    return $result.id
}

function ImportRepositoryToTarget([string] $repositoryName, [string] $serviceEndpointId)
{
    $uri = "https://$VSTS_ACCOUNT.visualstudio.com/$PROJECT_TARGET_NAME/_apis/git/repositories/"+$repositoryName+"/importRequests?api-version=4.1-preview.1"
    $sourceUrl = "https://$VSTS_ACCOUNT.visualstudio.com/$PROJECT_SOURCE_NAME/_git/$repositoryName"
    $body = '{ "parameters": { "gitSource": { "url": "'+$sourceUrl+'" }, "serviceEndpointId": "'+$serviceEndpointId+'", "deleteServiceEndpointAfterImportIsDone": "true" } }'
    $result = Invoke-RestMethod -Uri $uri -Method Post -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $AUTH_INFO_BASE64)} -Body $body
    return $result
}

function GetTargetRepositoryCommits([string] $repositoryName)
{
    $uri = "https://$VSTS_ACCOUNT.visualstudio.com/$PROJECT_TARGET_NAME/_apis/git/repositories/"+$repositoryName+"/commits?api-version=4.1"
    $result = Invoke-RestMethod -Uri $uri -Method Get -ContentType "application/json" -Headers @{Authorization=("Basic {0}" -f $AUTH_INFO_BASE64)}
    return $result
}

$AUTH_INFO_BASE64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $USER,$TOKEN)))

$sourceRepositories = GetSourceRepositories
$targetRepositories = GetTargetRepositories
$sourceRepositories | Sort-Object -Property name | Format-Table -Property name,url | Out-String| ForEach-Object {Write-Host $_}

$selection = Read-Host "Enter a single repository name or leave blank to import all repositories"
$selectedRepositories = $sourceRepositories | Where-Object {$_.name -eq $selection -or [string]::IsNullOrEmpty($selection)}
   
foreach ($repository in $selectedRepositories)
{
    $repositoryName = $repository.name
    $targetRepository = $targetRepositories | Where-Object {$_.name -eq $repositoryName }

    if (@($targetRepository).Count -eq 1)
    {
        Write-Host "Repository $repositoryName already exists."
    }
    else
    {
        Write-Host "Creating repository $repositoryName..."
        $creationResult = CreateTargetRepository($repositoryName)
        $repositoryId = $creationResult.id;
        Write-Host "Created repository $repositoryName with id $repositoryId."
    }

    Write-Host "Getting target commits for repository $repositoryName..."
    $commits = GetTargetRepositoryCommits $repositoryName
    $commitsCount = $commits.count;
    Write-Host "Found $commitsCount commits in repository $repositoryName."

    if ($commitsCount -le 0)
    {
        $sourceUrl = $repository.url
        Write-Host "Creating service endpoint $repositoryName..."
        $serviceEndpointId = CreateTargetServiceEndpoint $repositoryName $sourceUrl

        Write-Host "Importing repository $repositoryName..."
        $importResult = ImportRepositoryToTarget $repositoryName $serviceEndpointId
    }
    else
    {
        Write-Host "Target repository $repositoryName is not empty, skipping import."
    }
}

Write-Host "Completed"