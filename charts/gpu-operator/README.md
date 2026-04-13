# NVIDIA GPU Operator Helm Chart

This Helm chart manages the NVIDIA GPU Operator ClusterPolicy and MIG configuration for OpenShift.

**Note**: The GPU Operator itself must be installed via OLM. This chart only manages the ClusterPolicy and MIG ConfigMap.

## Prerequisites

- NVIDIA GPU Operator v25.10+ installed via OLM Subscription
- OpenShift 4.20+
- NVIDIA H100 NVL GPUs (or other MIG-capable GPUs)

## Quick Start

### Install (MIG Disabled - Matches Current State)

```bash
helm install gpu-operator charts/gpu-operator/ -n nvidia-gpu-operator
```

This creates a ClusterPolicy that matches your current configuration with MIG disabled.

### Enable MIG with Custom AML Workload

```bash
helm upgrade gpu-operator charts/gpu-operator/ -n nvidia-gpu-operator \
  --set mig.enabled=true \
  --set migManager.config.default=custom-aml-workload
```

## Configuration

### Key Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `mig.enabled` | Enable MIG mode | `false` |
| `mig.strategy` | MIG strategy (single/mixed) | `single` |
| `migManager.config.default` | MIG config to apply | `all-disabled` |
| `operator.namespace` | GPU Operator namespace | `nvidia-gpu-operator` |
| `operator.defaultRuntime` | Container runtime | `crio` |

### MIG Configurations

Available MIG configurations in the ConfigMap:

- **all-disabled**: MIG disabled on all GPUs (default)
- **all-enabled**: MIG enabled but no slices created
- **all-1g.12gb**: All GPUs with 7x 10.75GB slices
- **all-3g.47gb**: All GPUs with 2x 46.38GB slices
- **custom-aml-workload**: Optimized for AML workload
  - GPU 0-3: 2x 46.38GB slices (for LLM)
  - GPU 4: 2x 46.38GB slices (for VLM)
  - GPU 5: 7x 10.75GB slices (for Embedding/Reranking)
  - GPU 6-7: Full GPUs (no MIG)

## Migration Guide

See [GPU MIG Migration Guide (FP8 Optimized)](../../docs/gpu-mig-migration-fp8.md) for detailed step-by-step instructions.

### Quick Migration Steps

1. Install chart with MIG disabled (no changes)
2. Test with non-critical workloads first
3. Enable MIG gradually (GPU 5 → GPUs 0-4)
4. Update InferenceServices to use MIG resources
5. Monitor and verify

## Examples

### Check Current MIG Status

```bash
# Get driver pod
DRIVER_POD=$(oc get pods -n nvidia-gpu-operator -l app=nvidia-driver -o jsonpath='{.items[0].metadata.name}')

# Check MIG mode
oc exec -n nvidia-gpu-operator $DRIVER_POD -- nvidia-smi -q | grep -A3 "MIG Mode"

# List MIG devices
oc exec -n nvidia-gpu-operator $DRIVER_POD -- nvidia-smi -L
```

### Update MIG Configuration

```bash
# Use a different MIG config
helm upgrade gpu-operator . -n nvidia-gpu-operator \
  --set migManager.config.default=all-3g.47gb
```

### Disable MIG (Rollback)

```bash
helm upgrade gpu-operator . -n nvidia-gpu-operator \
  --set mig.enabled=false \
  --set migManager.config.default=all-disabled
```

## Uninstall

```bash
helm uninstall gpu-operator -n nvidia-gpu-operator
```

**Warning**: This removes the ClusterPolicy and MIG ConfigMap. The GPU Operator subscription remains installed via OLM.

## Troubleshooting

### MIG Not Enabling

Check the mig-manager logs:

```bash
oc logs -n nvidia-gpu-operator -l app=nvidia-mig-manager
```

### GPUs Not Resetting

MIG mode changes require GPU reset. Check driver daemonset:

```bash
oc get pods -n nvidia-gpu-operator -l app=nvidia-driver
oc logs -n nvidia-gpu-operator <driver-pod>
```

### Resources Not Appearing

After MIG enablement, check node resources:

```bash
oc describe node <gpu-node> | grep "nvidia.com/mig"
```

Should show resources like:
```
nvidia.com/mig-3g.47gb: 10
nvidia.com/mig-1g.12gb: 7
```

## References

- [NVIDIA GPU Operator Documentation](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/)
- [MIG User Guide](https://docs.nvidia.com/datacenter/tesla/mig-user-guide/)
- [GPU MIG Migration Guide (FP8 Optimized)](../../docs/gpu-mig-migration-fp8.md)
