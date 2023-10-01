# install kubectl
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
# This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubectl

# install flux cli
$env:FLUX_VERSION = "2.0.1"; curl -s https://fluxcd.io/install.sh | bash

$kvName = 'kv-aksgitops-dev-1'
$kubectlVersion = (kubectl version -o json | ConvertFrom-Json -Depth 100).clientVersion.gitVersion
$fluxVersion = flux version --client
$fluxPatSecret = Get-AzKeyVaultSecret -VaultName $kvName -SecretName 'flux-pat'
$secretVersion = $fluxPatSecret.Version
Import-AzAksCredential -ResourceGroupName 'rg-aksgitops-dev-1' -Name 'aks-aksgitops-dev-1' -Force

$env:GITHUB_TOKEN = $fluxPatSecret.SecretValue | ConvertFrom-SecureString -AsPlainText
flux bootstrap github `
    --token-auth `
    --owner=KacperMucha `
    --repository=aks-gitops-labs `
    --branch=main `
    --path=clusters/dev `
    --private=false `
    --personal

kubectl -n flux-system wait kustomization/apps --for=condition=ready --timeout=5m

$DeploymentScriptOutputs = @{}
$DeploymentScriptOutputs["secretVersion"] = if ($secretVersion) { $secretVersion } else { "N/A" }
$DeploymentScriptOutputs["fluxVersion"] = $fluxVersion
$DeploymentScriptOutputs["kubectlVersion"] = $kubectlVersion