#!/bin/bash
set -e

echo "🚀 Deploying Observability Stack..."
echo ""

echo "📦 Step 1: Creating namespaces..."
oc create namespace observability-hub --dry-run=client -o yaml | oc apply -f -
oc create namespace openshift-user-workload-monitoring --dry-run=client -o yaml | oc apply -f -
echo "✅ Namespaces created"
echo ""

echo "📦 Step 2: Installing operators..."
helm upgrade --install cluster-obs helm/cluster-observability-operator/
helm upgrade --install grafana-op helm/grafana-operator/
helm upgrade --install otel-op helm/otel-operator/
helm upgrade --install tempo-op helm/tempo-operator/
echo "✅ Operators installed"
echo ""

echo "⏳ Step 3: Waiting for operators to be ready (30s)..."
sleep 30
echo "✅ Wait complete"
echo ""

echo "📦 Step 4: Installing Tempo with MinIO storage..."
helm upgrade --install tempo helm/tempo/ -n observability-hub
echo "✅ Tempo installed"
echo ""

echo "📦 Step 5: Installing OTEL Collector..."
helm upgrade --install otel-collector helm/otel-collector/ -n observability-hub
echo "✅ OTEL Collector installed"
echo ""

echo "📦 Step 6: Installing User Workload Monitoring..."
helm upgrade --install uwm helm/uwm/
echo "✅ UWM installed"
echo ""

echo "📦 Step 7: Installing Grafana..."
helm upgrade --install grafana helm/grafana/ -n observability-hub
echo "✅ Grafana installed"
echo ""

echo "📦 Step 8: Installing Tracing UI Plugin..."
helm upgrade --install tracing-ui helm/distributed-tracing-ui-plugin/
echo "✅ Tracing UI Plugin installed"
echo ""

echo "🎉 Observability stack deployment complete!"
echo ""
echo "📊 Check status with:"
echo "  oc get pods -n observability-hub"
echo "  oc get tempostack -n observability-hub"
echo "  oc get grafana -n observability-hub"
