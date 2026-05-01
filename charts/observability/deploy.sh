#!/bin/bash

echo "🚀 Deploying Observability Resources..."
echo ""
echo "⚠️  Note: Run ./install-operators.sh first if you haven't already"
echo ""

echo "📦 Step 1: Installing Tempo with MinIO storage..."
helm upgrade --install tempo helm/tempo/ -n observability-hub
echo ""

echo "📦 Step 2: Installing OTEL Collector..."
helm upgrade --install otel-collector helm/otel-collector/ -n observability-hub
echo ""

echo "📦 Step 3: Installing User Workload Monitoring..."
helm upgrade --install uwm helm/uwm/
echo ""

echo "📦 Step 4: Installing Grafana..."
helm upgrade --install grafana helm/grafana/ -n observability-hub
echo ""

echo "📦 Step 5: Installing Tracing UI Plugin..."
helm upgrade --install tracing-ui helm/distributed-tracing-ui-plugin/
echo ""

echo "🎉 Observability resources deployed successfully!"
echo ""
echo "📊 Check status with:"
echo "  oc get pods -n observability-hub"
echo "  oc get tempostack -n observability-hub"
echo "  oc get grafana -n observability-hub"
