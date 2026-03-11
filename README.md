# LLM Service Helm Chart

vLLM-based LLM serving with RAG ingest (nv-ingest, Milvus, ingestor-server).

## Prerequisites

- OpenShift cluster with GPU nodes
- ODF (OpenShift Data Foundation) with NooBaa object storage
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

## S3 Object Storage (ObjectBucketClaim)

The chart uses an ODF **ObjectBucketClaim** (OBC) to provision an S3-compatible bucket
through NooBaa. This bucket is used by nv-ingest, Milvus, and the ingestor-server for
object storage.

### OBC Configuration 

When `objectStorage.odf.objectBucketClaim.enabled` is `true` (the default), the chart
creates an `ObjectBucketClaim` resource:

```yaml
apiVersion: objectbucket.io/v1alpha1
kind: ObjectBucketClaim
metadata:
  name: default-bucket
spec:
  bucketName: default-bucket
  storageClassName: openshift-storage.noobaa.io
```

Once ODF binds the claim, it **automatically generates** two resources in the same
namespace with the same name as the OBC (`default-bucket` by default):

| Resource | Keys | Purpose |
|----------|------|---------|
| **Secret** | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | S3 credentials |
| **ConfigMap** | `BUCKET_HOST`, `BUCKET_PORT`, `BUCKET_NAME` | S3 endpoint and bucket name |

These resources do not exist until ODF finishes provisioning the bucket, which
introduces a timing dependency for services that consume them.

### OBC values

| Parameter | Default | Description |
|-----------|---------|-------------|
| `objectStorage.odf.objectBucketClaim.enabled` | `true` | Create the OBC resource |
| `objectStorage.odf.objectBucketClaim.name` | `default-bucket` | OBC name (also the name of the generated Secret and ConfigMap) |
| `objectStorage.odf.objectBucketClaim.bucketName` | `default-bucket` | Requested S3 bucket name |
| `objectStorage.odf.objectBucketClaim.storageClassName` | `openshift-storage.noobaa.io` | ODF storage class |

### Services that consume OBC credentials

Three services inject the OBC Secret and ConfigMap into their environment:

- **ingestor-server** -- Uses `envFrom` to inject the OBC Secret/ConfigMap, then maps them to
  `MINIO_ACCESSKEY`, `MINIO_SECRETKEY`, `MINIO_ENDPOINT`, `MINIO_BUCKET`, and
  `NVINGEST_MINIO_BUCKET` in its startup command.

- **nv-ingest** -- Uses `extraEnvFrom` to inject the OBC Secret/ConfigMap directly.
  The `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `BUCKET_HOST`, `BUCKET_PORT`, and
  `BUCKET_NAME` env vars are available to the nv-ingest container as-is.

- **Milvus standalone** -- Uses `extraEnv` with `valueFrom` references to map individual keys
  from the OBC Secret/ConfigMap to Milvus-specific env vars (`MINIO_ADDRESS`,
  `MINIO_ACCESS_KEY_ID`, `MINIO_SECRET_ACCESS_KEY`, `MINIO_BUCKET_NAME`). The built-in
  Milvus MinIO sub-chart is disabled (`minio.enabled: false`) in favor of ODF.

### How services wait for the OBC

The OBC Secret and ConfigMap are created asynchronously by ODF, so they may not exist
when pods first start. Each service handles this differently:

- **ingestor-server** -- Uses a `wait-for-obc-secret` init container (`bitnami/kubectl`)
  that polls for the Secret and ConfigMap every 2 seconds. The chart creates a dedicated
  ServiceAccount, Role, and RoleBinding to grant it `get` access to these resources.
- **nv-ingest** and **Milvus** -- Reference the OBC Secret/ConfigMap via `envFrom` /
  `valueFrom` directly; Kubernetes blocks pod startup until the referenced resources exist.

### AWS CLI tagging pod

When both `awscliPod.enabled` and the OBC are enabled, the chart deploys a one-shot Pod
(`awscli-add-tag`) that applies S3 bucket tags using the AWS CLI. It consumes OBC
credentials via `envFrom` and runs:

```bash
aws s3api put-bucket-tagging \
  --endpoint-url "$SCHEME://$BUCKET_HOST:$BUCKET_PORT" \
  --no-verify-ssl \
  --bucket "$BUCKET_NAME" \
  --tagging "TagSet=[{Key=Environment,Value=dev}]"
```

Tagging is configurable via `awscliPod.tagging`.

### Disabling the OBC

To use an external S3-compatible store instead of ODF, set:

```yaml
objectStorage:
  odf:
    objectBucketClaim:
      enabled: false
```

You will then need to provide `MINIO_*` environment variables (or equivalent) to
ingestor-server, nv-ingest, and Milvus manually.

## Key Values

| Parameter | Description |
|-----------|-------------|
| `nvidiaApiKey.password` | NGC API key (image pull + NGC_API_KEY) |
| `secret.hf_token` | HuggingFace token |
| `objectStorage.odf.objectBucketClaim.enabled` | Enable OBC-based S3 storage (default `true`) |
| `objectStorage.odf.objectBucketClaim.name` | OBC resource name (default `default-bucket`) |
| `objectStorage.odf.objectBucketClaim.storageClassName` | ODF storage class (default `openshift-storage.noobaa.io`) |
| `awscliPod.enabled` | Deploy bucket-tagging pod (default `true`) |

## Setting up secret for NGC API key to pull NIMs

```bash
export API_KEY=<paste>
cat << EOF
apiVersion: v1
kind: Secret
metadata:
  name: ngc-api
  namespace: rag
type: kubernetes.io/dockerconfigjson
stringData:
  .dockerconfigjson: >
    {"auths": {"nvcr.io": {"auth": "$(echo -n '$oauthuser:'"$API_KEY" | base64 -w0)"}}}
  NGC_API_KEY: $API_KEY
  NVIDIA_API_KEY: $API_KEY
EOF
```

