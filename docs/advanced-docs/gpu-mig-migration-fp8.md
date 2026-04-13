# NVIDIA GPU Operator MIG Migration Guide (FP8 Optimized)

This guide walks through enabling MIG (Multi-Instance GPU) on your H100 NVL GPUs with FP8 quantized models for maximum efficiency.

## Current State

- **GPUs**: 8x NVIDIA H100 NVL (94GB each = 752GB total)
- **MIG Status**: Disabled
- **GPU Operator**: v25.10.1
- **Models**: Using FP8 quantized models for ~50% memory savings vs BF16
  - LLM: `nvidia/Llama-3_3-Nemotron-Super-49B-v1_5-FP8`
  - VLM: `nvidia/NVIDIA-Nemotron-Nano-12B-v2-VL-FP8`

## FP8 Benefits

FP8 quantization provides:
- **50% memory savings** vs BF16 (1 byte vs 2 bytes per parameter)
- **Similar accuracy** (< 1% degradation for most tasks)
- **Faster inference** on H100 GPUs (native FP8 support)
- **Better GPU utilization** through MIG slicing

## Resource Optimization with MIG + FP8

### Before MIG (Current Waste)

| Model | Memory Needed | GPU Allocated | Waste |
|-------|--------------|---------------|-------|
| LLM (49B FP8) | ~70GB | 2x 94GB = 188GB | **118GB** |
| VLM (12B FP8) | ~15GB | 1x 94GB | **79GB** |
| Embedding (1B) | ~8GB | 1x 94GB | **86GB** |
| Reranking (1B) | ~8GB | 1x 94GB | **86GB** |
| **Total** | **~101GB** | **376GB** | **369GB wasted** |

**In use**: 4 GPUs (376GB)
**Wasted**: ~369GB (equivalent to 4 H100 GPUs!)
**Available**: 4 GPUs (376GB)

### After MIG (Optimized)

| Model | MIG Slice | Memory | GPUs Used |
|-------|-----------|--------|-----------|
| LLM (49B FP8) | 2x 3g.47gb | 92.76GB | GPU 0 (both slices) |
| VLM (12B FP8) | 1x 1g.24gb | 21.62GB | GPU 1 (1 of 4 slices) |
| Embedding | 1x 1g.12gb | 10.75GB | GPU 2 (1 of 7 slices) |
| Reranking | 1x 1g.12gb | 10.75GB | GPU 2 (1 of 7 slices) |
| **Total** | **5 MIG slices** | **~136GB** | **3 GPUs partially** |

**In use**: 3 GPUs with MIG slicing
**Freed resources**:
- 3x 1g.24gb MIG slices (65GB)
- 5x 1g.12gb MIG slices (54GB)
- 5 full H100 GPUs (470GB)
- **Total freed**: ~589GB (equivalent to 6+ H100 GPUs!)

### Optimized MIG Configuration

```yaml
custom-aml-workload:
  # GPU 0: LLM FP8 (tensor parallel across 2 MIG slices)
  - devices: [0]
    mig-enabled: true
    mig-devices:
      "3g.47gb": 2     # 2x 46.38GB = 92.76GB for LLM

  # GPU 1: VLM FP8 + 3 spare slices
  - devices: [1]
    mig-enabled: true
    mig-devices:
      "1g.24gb": 4     # 1 for VLM (21.62GB), 3 available

  # GPU 2: Embedding + Reranking + 5 spare slices
  - devices: [2]
    mig-enabled: true
    mig-devices:
      "1g.12gb": 7     # 2 for models, 5 available (53.75GB)

  # GPU 3-7: Full GPUs available (5x 94GB = 470GB)
  - devices: [3,4,5,6,7]
    mig-enabled: false
```

### Benefits Summary

- **LLM**: 2x 46GB MIG slices (same performance as 2x full GPUs)
- **VLM**: 1x 22GB MIG slice (right-sized for FP8 model)
- **Embedding/Reranking**: 1x 11GB each (perfect fit)
- **Net gain**: 5 full H100 GPUs + 8 MIG slices freed
- **Flexibility**: Massive capacity for new workloads

## Migration Plan (Zero Downtime)

### Phase 1: Update to FP8 Models (No MIG Yet)

First, switch to FP8 models while still on full GPUs to verify they work correctly.

```bash
# Update model deployments to FP8
helm upgrade model-serving charts/model-serving/ -n rag \
  --reuse-values

# Wait for new pods to start
oc get pods -n rag -w

# Test LLM with FP8
oc exec -n rag <nim-llm-pod> -- curl http://localhost:8080/v1/models

# Test VLM with FP8
oc exec -n rag <nim-vlm-pod> -- curl http://localhost:8080/v1/models

# Test end-to-end RAG application
echo "https://$(oc get route -n rag rag-frontend -o jsonpath='{.spec.host}')"
```

**Verify**: All models respond correctly with FP8 quantization. Performance should be similar or better.

### Phase 2: Install GPU Operator Helm Chart (No MIG Changes)

```bash
# Install chart with MIG disabled (matches current state)
helm install gpu-operator charts/gpu-operator/ -n nvidia-gpu-operator

# Verify no changes occurred
oc get clusterpolicy gpu-cluster-policy -o yaml | grep -A5 "mig:"

# Should show: strategy: single, default: all-disabled
oc get pods -n rag  # All workloads still healthy
```

**Expected**: No disruption. ClusterPolicy unchanged.

### Phase 3: Enable MIG on GPU 2 (Test with Small Models)

Start with the least critical workloads (Embedding/Reranking).

```bash
# Enable MIG on GPU 2 only (1g.12gb slices)
helm upgrade gpu-operator charts/gpu-operator/ -n nvidia-gpu-operator \
  --set mig.enabled=true \
  --set migManager.config.default=custom-aml-workload

# Monitor MIG enablement (takes 2-5 minutes)
watch -n 5 'oc get pods -n nvidia-gpu-operator | grep driver'

# Verify MIG slices created on GPU 2
DRIVER_POD=$(oc get pods -n nvidia-gpu-operator -l openshift.driver-toolkit=true -o jsonpath='{.items[0].metadata.name}')
oc exec -n nvidia-gpu-operator $DRIVER_POD -- nvidia-smi -L | grep -A1 "GPU 2"

# Should show 7x MIG 1g.12gb devices

# Check available MIG resources
oc describe node <gpu-node> | grep "nvidia.com/mig-1g.12gb"
# Should show: nvidia.com/mig-1g.12gb: 7
```

### Phase 4: Migrate Embedding and Reranking to MIG

```bash
# Scale down to drain current pods
oc scale inferenceservice nemoretriever-embedding-ms -n rag --replicas=0
oc scale inferenceservice nemoretriever-ranking-ms -n rag --replicas=0

# Wait for pods to terminate
oc get pods -n rag | grep -E "embedding|ranking"

# Update to use MIG resources
oc patch inferenceservice nemoretriever-embedding-ms -n rag --type=merge -p '
spec:
  predictor:
    model:
      resources:
        limits:
          nvidia.com/mig-1g.12gb: "1"
        requests:
          nvidia.com/mig-1g.12gb: "1"
'

oc patch inferenceservice nemoretriever-ranking-ms -n rag --type=merge -p '
spec:
  predictor:
    model:
      resources:
        limits:
          nvidia.com/mig-1g.12gb: "1"
        requests:
          nvidia.com/mig-1g.12gb: "1"
'

# Scale back up
oc scale inferenceservice nemoretriever-embedding-ms -n rag --replicas=1
oc scale inferenceservice nemoretriever-ranking-ms -n rag --replicas=1

# Verify pods scheduled on MIG slices
oc get pods -n rag -o wide
oc describe pod <embedding-pod> -n rag | grep "nvidia.com/mig"
```

**Test**: Query embedding and reranking endpoints to ensure they work on MIG.

### Phase 5: Enable MIG on GPU 0-1 (LLM and VLM)

```bash
# MIG config already set to custom-aml-workload
# Wait for MIG manager to configure GPU 0-1
watch -n 5 "oc exec -n nvidia-gpu-operator $DRIVER_POD -- nvidia-smi -L | grep -E 'GPU 0|GPU 1'"

# You should see:
# GPU 0: MIG 3g.47gb (UUID: ...)
# GPU 0: MIG 3g.47gb (UUID: ...)
# GPU 1: MIG 1g.24gb (UUID: ...)
# GPU 1: MIG 1g.24gb (UUID: ...)
# ... (4 total for GPU 1)

# Check MIG resources
oc describe node <gpu-node> | grep "nvidia.com/mig"
# nvidia.com/mig-3g.47gb: 2
# nvidia.com/mig-1g.24gb: 4
# nvidia.com/mig-1g.12gb: 7
```

### Phase 6: Update LLM and VLM to Use MIG

```bash
# Update LLM to use 2x 3g.47gb MIG slices
oc patch inferenceservice nim-llm -n rag --type=merge -p '
spec:
  predictor:
    model:
      resources:
        limits:
          nvidia.com/mig-3g.47gb: "2"
        requests:
          nvidia.com/mig-3g.47gb: "2"
'

# Update VLM to use 1x 1g.24gb MIG slice
oc patch inferenceservice nim-vlm -n rag --type=merge -p '
spec:
  predictor:
    model:
      resources:
        limits:
          nvidia.com/mig-1g.24gb: "1"
        requests:
          nvidia.com/mig-1g.24gb: "1"
'

# Wait for pods to reschedule
oc get pods -n rag -w
```

### Phase 7: Verify and Celebrate

```bash
# Check all models running on MIG
oc get pods -n rag

# Verify MIG slice allocation
oc exec -n nvidia-gpu-operator $DRIVER_POD -- nvidia-smi

# Test RAG application end-to-end
echo "https://$(oc get route -n rag rag-frontend -o jsonpath='{.spec.host}')"

# Check available capacity
oc describe node <gpu-node> | grep -A20 "Allocated resources"
```

**Results**:
- GPU 0: 2x 3g.47gb used (LLM)
- GPU 1: 1x 1g.24gb used (VLM), 3 slices free (65GB)
- GPU 2: 2x 1g.12gb used, 5 slices free (54GB)
- GPU 3-7: 5 full H100 GPUs available (470GB)
- **Total freed**: ~589GB!

### Phase 8: Monitor and Optimize

```bash
# Check DCGM metrics in Grafana
echo "https://$(oc get route grafana-route -n observability-hub -o jsonpath='{.spec.host}')"

# View MIG utilization
oc exec -n nvidia-gpu-operator $DRIVER_POD -- nvidia-smi dmon -s um

# Check for any GPU memory pressure
oc exec -n nvidia-gpu-operator $DRIVER_POD -- nvidia-smi --query-gpu=memory.used,memory.total --format=csv
```

## Rollback Plan

If issues occur, revert to full GPUs:

```bash
# 1. Backup current state
oc get inferenceservice -n rag -o yaml > /tmp/backup-mig-inferenceservices.yaml

# 2. Disable MIG
helm upgrade gpu-operator charts/gpu-operator/ -n nvidia-gpu-operator \
  --set mig.enabled=false \
  --set migManager.config.default=all-disabled

# 3. Wait for GPUs to reset (~2-5 minutes)
watch -n 5 "oc exec -n nvidia-gpu-operator $DRIVER_POD -- nvidia-smi -q | grep 'MIG Mode'"
# Should show: Current: Disabled

# 4. Restore original resource requests (back to nvidia.com/gpu)
oc patch inferenceservice nim-llm -n rag --type=merge -p '
spec:
  predictor:
    model:
      resources:
        limits:
          nvidia.com/gpu: "2"
        requests:
          nvidia.com/gpu: "2"
'

# Repeat for other models...

# 5. Verify all workloads healthy
oc get pods -n rag
```

## Quick Reference

### MIG Resource Names After Migration

| Model | Before MIG | After MIG |
|-------|-----------|-----------|
| LLM | `nvidia.com/gpu: 2` | `nvidia.com/mig-3g.47gb: 2` |
| VLM | `nvidia.com/gpu: 1` | `nvidia.com/mig-1g.24gb: 1` |
| Embedding | `nvidia.com/gpu: 1` | `nvidia.com/mig-1g.12gb: 1` |
| Reranking | `nvidia.com/gpu: 1` | `nvidia.com/mig-1g.12gb: 1` |

### Available MIG Profiles on H100 NVL

| Profile | Memory | Slices per GPU | Use Case |
|---------|--------|----------------|----------|
| 1g.12gb | 10.75GB | 7 | Small models (Embedding, Reranking) |
| 1g.24gb | 21.62GB | 4 | Medium models (VLM FP8) |
| 2g.24gb | 21.62GB | 3 | Medium models |
| 3g.47gb | 46.38GB | 2 | Large models (LLM FP8) |
| 4g.47gb | 46.38GB | 1 | Full memory, less compute |
| 7g.94gb | 93.12GB | 1 | Full GPU (no slicing) |

### Useful Commands

```bash
# Get driver pod name
DRIVER_POD=$(oc get pods -n nvidia-gpu-operator -l openshift.driver-toolkit=true -o jsonpath='{.items[0].metadata.name}')

# Check MIG mode
oc exec -n nvidia-gpu-operator $DRIVER_POD -- nvidia-smi -q | grep -A3 "MIG Mode"

# List all MIG devices
oc exec -n nvidia-gpu-operator $DRIVER_POD -- nvidia-smi -L

# View MIG instances
oc exec -n nvidia-gpu-operator $DRIVER_POD -- nvidia-smi mig -lgi

# Check node MIG resources
oc describe node <gpu-node> | grep "nvidia.com/mig"

# Monitor GPU utilization
oc exec -n nvidia-gpu-operator $DRIVER_POD -- nvidia-smi dmon -s um
```

## Expected Results

### Memory Efficiency Gains

| Metric | Before (Full GPUs) | After (MIG + FP8) | Improvement |
|--------|-------------------|-------------------|-------------|
| GPUs used | 4 full GPUs | 3 GPUs with MIG | **+25% efficiency** |
| Memory used | 376GB | ~136GB | **-64% waste** |
| Memory freed | 376GB available | 589GB available | **+57% capacity** |
| Workload density | 4 models on 4 GPUs | 4 models on 3 GPUs | **+33% density** |

### Performance Impact

- **LLM (FP8)**: <1% accuracy loss, faster inference on H100
- **VLM (FP8)**: Minimal accuracy impact, better throughput
- **Embedding/Reranking**: No change (always fit in small slices)
- **Overall latency**: Similar or better due to FP8 optimizations

## Next Steps

After successful migration:

1. **Monitor FP8 Quality**: Compare RAG responses before/after FP8 migration
2. **Tune Batch Sizes**: Optimize `max-num-seqs` for MIG slice sizes
3. **Create Resource Quotas**: Prevent MIG slice oversubscription
4. **Deploy New Workloads**: Use freed 5x H100 GPUs for:
   - Additional LLMs (fine-tuned models)
   - Training jobs
   - Batch inference workloads
   - Multi-tenant deployments
5. **Update Documentation**: Document MIG resource requirements for new models
6. **Set up Alerts**: Monitor MIG utilization in Grafana

## Troubleshooting

### FP8 Model Download Fails

```bash
# Check HuggingFace token
oc get secret huggingface-secret -n rag -o yaml

# Verify model exists on HuggingFace
curl -H "Authorization: Bearer $HF_TOKEN" \
  https://huggingface.co/api/models/nvidia/Llama-3_3-Nemotron-Super-49B-v1_5-FP8
```

### MIG Slices Not Created

```bash
# Check mig-manager logs
oc logs -n nvidia-gpu-operator -l app=nvidia-mig-manager --tail=100

# Verify ClusterPolicy
oc get clusterpolicy gpu-cluster-policy -o yaml | grep -A10 "migManager"
```

### Pod Can't Schedule (No MIG Resources)

```bash
# Check available MIG resources
oc describe node <gpu-node> | grep "nvidia.com/mig"

# Check pod events
oc describe pod <pod-name> -n rag | grep -A10 "Events:"
```

## References

- [NVIDIA FP8 Quantization Guide](https://docs.nvidia.com/deeplearning/transformer-engine/user-guide/index.html)
- [vLLM FP8 Support](https://docs.vllm.ai/en/latest/quantization/fp8.html)
- [H100 MIG User Guide](https://docs.nvidia.com/datacenter/tesla/mig-user-guide/)
- [GPU Operator Documentation](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/)
