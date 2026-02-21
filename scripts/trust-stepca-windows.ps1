param(
  [Parameter(Mandatory = $false)]
  [string]$CertificatePath = ".\\.secrets\\step-ca\\root_ca.crt"
)

if (-not (Test-Path $CertificatePath)) {
  Write-Error "Certificate not found: $CertificatePath"
  exit 1
}

Import-Certificate -FilePath $CertificatePath -CertStoreLocation Cert:\\CurrentUser\\Root | Out-Null
Write-Output "Step-CA root certificate imported into CurrentUser Root store"
