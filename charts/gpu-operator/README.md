# NVIDIA GPU Operator Helm Chart

This Helm chart manages the NVIDIA GPU Operator ClusterPolicy and MIG configuration on OpenShift.

## Overview

The GPU Operator itself is installed via OLM (Operator Lifecycle Manager). This chart only manages:
- **ClusterPolicy**: GPU operator configuration
- **MIG ConfigMap**: Multi-Instance GPU profiles

## Prerequisites

- OpenShift 4.12+
- NVIDIA GPU Operator v25.10+ installed via OLM
- GPU-enabled worker nodes

## Installation

### Step 1: Verify GPU Operator is Installed

```bash
# Check GPU operator is running
oc get csv -n nvidia-gpu-operator | grep gpu-operator

# Should show: gpu-operator-certified.v25.10.1 or later
```

### Step 2: Update MIG ConfigMap

```bash
# Apply MIG ConfigMap with custom profiles
helm template gpu-operator charts/gpu-operator/ -n nvidia-gpu-operator \
  -s templates/mig-config.yaml | oc apply -f -
```

### Step 3: Enable MIG on Specific Nodes

With `strategy: mixed`, you enable MIG per-node using labels:

```bash
# Label GPU node to use custom-aml-workload MIG config
oc label node <gpu-node-name> nvidia.com/mig.config=custom-aml-workload --overwrite

# Example:
oc label node lp-redhat-ragblueprint-gpu01 nvidia.com/mig.config=custom-aml-workload --overwrite

# Verify label
oc get node <gpu-node-name> --show-labels | grep mig.config

# Monitor MIG manager apply the config (~3-5 minutes)
watch -n 5 'oc get pods -n nvidia-gpu-operator'
```

### Step 4: Verify MIG Slices Created

```bash
# Get driver pod
DRIVER_POD=$(oc get pods -n nvidia-gpu-operator -l openshift.driver-toolkit=true -o jsonpath='{.items[0].metadata.name}')

# List MIG devices
oc exec -n nvidia-gpu-operator $DRIVER_POD -- nvidia-smi -L

# Check available MIG resources
oc describe node <gpu-node-name> | grep nvidia.com/mig
```

## Available MIG Configurations

### Standard Profiles

- **all-disabled**: No MIG (full GPUs)
- **all-enabled**: MIG enabled but no slices created
- **all-1g.12gb**: All GPUs → 7x 10.75GB slices
- **all-3g.47gb**: All GPUs → 2x 46.38GB slices

### Custom Profile: custom-aml-workload (FP8 Optimized)

Optimized for FP8-quantized models:
- **GPU 0**: 2x 3g.47gb (46.38GB) → LLM FP8 with tensor parallel 2
- **GPU 1**: 4x 1g.24gb (21.62GB) → VLM FP8 + 3 spares
- **GPU 2**: 7x 1g.12gb (10.75GB) → Embedding/Reranking + 5 spares
- **GPU 3-7**: Full 94GB GPUs → Future workloads

**Result**: Runs all models on 3 GPUs, freeing 5 full H100s (470GB)!

## Configuration

### values.yaml

```yaml
mig:
  strategy: mixed  # Use per-node MIG configs via labels

migManager:
  config:
    name: default-mig-parted-config
    default: all-disabled  # Fallback for unlabeled nodes
```

### Apply Different Configs to Different Nodes

```bash
# Node 1: Use custom-aml-workload
oc label node gpu-node-01 nvidia.com/mig.config=custom-aml-workload

# Node 2: Use all-3g.47gb
oc label node gpu-node-02 nvidia.com/mig.config=all-3g.47gb

# Node 3: No MIG (uses default: all-disabled)
# No label needed
```

## Updating Model Deployments for MIG

After enabling MIG, update model resource requests:

### LLM (49B FP8) - 2x 3g.47gb slices

```yaml
resources:
  limits:
    nvidia.com/mig-3g.47gb: "2"  # Was: nvidia.com/gpu: "4"
  requests:
    nvidia.com/mig-3g.47gb: "2"

args:
  - --tensor-parallel-size=2
```

### VLM (12B FP8) - 1x 1g.24gb slice

```yaml
resources:
  limits:
    nvidia.com/mig-1g.24gb: "1"  # Was: nvidia.com/gpu: "1"
  requests:
    nvidia.com/mig-1g.24gb: "1"
```

### Embedding/Reranking - 1x 1g.12gb slice each

```yaml
resources:
  limits:
    nvidia.com/mig-1g.12gb: "1"  # Was: nvidia.com/gpu: "1"
  requests:
    nvidia.com/mig-1g.12gb: "1"
```

## Disabling MIG

```bash
# Remove MIG config label from node
oc label node <gpu-node-name> nvidia.com/mig.config-

# MIG Manager will disable MIG and restore full GPUs (~3-5 minutes)
watch -n 5 'oc get pods -n nvidia-gpu-operator'
```

## Troubleshooting

### Check MIG Manager Logs

```bash
oc logs -n nvidia-gpu-operator -l app=nvidia-mig-manager --tail=100
```

### Verify ConfigMap is Loaded

```bash
oc get configmap default-mig-parted-config -n nvidia-gpu-operator -o yaml
```

### Check Node Labels

```bash
oc get nodes -L nvidia.com/mig.config
```

### Driver Pod Issues

```bash
# Check driver pod status
oc get pods -n nvidia-gpu-operator -l openshift.driver-toolkit=true

# View driver logs
oc logs -n nvidia-gpu-operator <driver-pod-name>
```

## Migration Guide

See [GPU MIG Migration Guide (FP8 Optimized)](../../docs/gpu-mig-migration-fp8.md) for detailed step-by-step instructions.

## References

- [NVIDIA GPU Operator Documentation](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/)
- [MIG User Guide](https://docs.nvidia.com/datacenter/tesla/mig-user-guide/)
- [GPU MIG Migration Guide (FP8 Optimized)](../../docs/gpu-mig-migration-fp8.md)
