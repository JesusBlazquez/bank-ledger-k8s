<#
.SYNOPSIS
  Crea un cluster kind, instala el ingress, construye la imagen y despliega la aplicacion.
  Equivalente a deploy-kind.sh, que es el que ejecuta el CI en Linux.
.EXAMPLE
  .\scripts\deploy-kind.ps1
#>
param(
  [string]$Cluster = 'ledger',
  [string]$Image = 'bank-ledger-k8s:local',
  [string]$IngressVersion = 'controller-v1.15.1'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

function Paso($t) { Write-Host "`n>>> $t" -ForegroundColor Cyan }
function Check($what) { if ($LASTEXITCODE -ne 0) { throw "Fallo en: $what" } }

if (-not ((kind get clusters) -contains $Cluster)) {
  Paso "Creando el cluster kind '$Cluster'"
  kind create cluster --config "$root\k8s\kind-cluster.yaml"; Check 'kind create cluster'
} else {
  Paso "El cluster '$Cluster' ya existe"
}

Paso 'Instalando el controlador de ingress'
kubectl apply -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/$IngressVersion/deploy/static/provider/kind/deploy.yaml"; Check 'kubectl apply ingress'
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=180s; Check 'espera del ingress'

Paso 'Construyendo la imagen y cargandola en el cluster'
docker build -t $Image $root; Check 'docker build'
kind load docker-image $Image --name $Cluster; Check 'kind load'

Paso 'Desplegando'
kubectl apply -k "$root\k8s\overlays\local"; Check 'kubectl apply -k'
kubectl -n ledger rollout status statefulset/ledger-postgres --timeout=180s; Check 'rollout postgres'
kubectl -n ledger rollout status deployment/ledger-app --timeout=240s; Check 'rollout app'

Paso 'Prueba de humo a traves del ingress'
$ok = $false
foreach ($intento in 1..10) {
  try {
    $r = Invoke-RestMethod -Uri 'http://localhost/actuator/health' -Headers @{ Host = 'ledger.local' } -TimeoutSec 10
    if ($r.status -eq 'UP') { $ok = $true; break }
  } catch { Start-Sleep -Seconds 3 }
}
if (-not $ok) { throw 'La aplicacion no responde UP a traves del ingress' }

Write-Host "`nDesplegado y respondiendo UP." -ForegroundColor Green
Write-Host "Anade '127.0.0.1 ledger.local' al fichero hosts y abre http://ledger.local/swagger-ui.html"
Write-Host "Sin permisos de administrador: kubectl -n ledger port-forward svc/ledger-app 8080:80"
Write-Host "Estado:   kubectl -n ledger get pods"
Write-Host "Borrar:   kind delete cluster --name $Cluster"
