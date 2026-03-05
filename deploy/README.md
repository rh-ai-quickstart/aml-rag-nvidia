# LLM Service Helm Chart

vLLM-based LLM serving with RAG ingest (nv-ingest, Milvus, ingestor-server).

## Prerequisites

- OpenShift cluster with GPU nodes
- ODF (Object Storage) with Object Bucket Claim
- NGC API key and HuggingFace token

## Deployment

Replace `<NAMESPACE>` and `<RELEASE_NAME>` with your values.

```bash
export NGC_API_KEY="nvapi-..."
export HF_TOKEN=""

helm repo add nvidia https://helm.ngc.nvidia.com/nvidia/nemo-microservices \
  --username '$oauthtoken' \
  --password $NGC_API_KEY
helm repo update

helm upgrade --install <RELEASE_NAME> ./helm \
  -n <NAMESPACE> \
  --create-namespace \
  --set nvidiaApiKey.password=$NGC_API_KEY \
  --set secret.hf_token=$HF_TOKEN

oc adm policy add-scc-to-user anyuid -z default -n <NAMESPACE>
oc adm policy add-scc-to-user anyuid -z <RELEASE_NAME>-nv-ingest -n <NAMESPACE>
oc adm policy add-scc-to-user anyuid -z ingestor-server -n <NAMESPACE>
```

## Key Values

| Parameter | Description |
|-----------|-------------|
| `nvidiaApiKey.password` | NGC API key (image pull + NGC_API_KEY) |
| `secret.hf_token` | HuggingFace token |