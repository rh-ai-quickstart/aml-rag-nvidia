#!/bin/bash

echo "🗑️  Uninstalling Observability Stack..."
echo ""

echo "📦 Step 1: Uninstalling Tracing UI Plugin..."
helm uninstall tracing-ui 2>/dev/null || echo "   (not installed)"
echo ""

echo "📦 Step 2: Uninstalling Grafana..."
helm uninstall grafana -n observability-hub 2>/dev/null || echo "   (not installed)"
echo ""

echo "📦 Step 3: Uninstalling User Workload Monitoring..."
helm uninstall uwm 2>/dev/null || echo "   (not installed)"
echo ""

echo "📦 Step 4: Uninstalling OTEL Collector..."
helm uninstall otel-collector -n observability-hub 2>/dev/null || echo "   (not installed)"
echo ""

echo "📦 Step 5: Uninstalling Tempo..."
helm uninstall tempo -n observability-hub 2>/dev/null || echo "   (not installed)"
echo ""

echo "📦 Step 6: Uninstalling Operators..."
helm uninstall tempo-op 2>/dev/null || echo "   tempo-op (not installed)"
helm uninstall otel-op 2>/dev/null || echo "   otel-op (not installed)"
helm uninstall grafana-op 2>/dev/null || echo "   grafana-op (not installed)"
helm uninstall cluster-obs 2>/dev/null || echo "   cluster-obs (not installed)"
echo ""

echo "📦 Step 7: Deleting namespaces..."
oc delete namespace observability-hub --wait=false 2>/dev/null || echo "   observability-hub (not found)"
oc delete namespace openshift-tempo-operator --wait=false 2>/dev/null || echo "   openshift-tempo-operator (not found)"
oc delete namespace openshift-grafana-operator --wait=false 2>/dev/null || echo "   openshift-grafana-operator (not found)"
oc delete namespace openshift-opentelemetry-operator --wait=false 2>/dev/null || echo "   openshift-opentelemetry-operator (not found)"
oc delete namespace openshift-cluster-observability-operator --wait=false 2>/dev/null || echo "   openshift-cluster-observability-operator (not found)"
echo ""

echo "✅ Observability stack uninstallation complete!"
echo ""
echo "Note: Some resources may take time to fully delete."
echo "Check with: oc get namespaces | grep observability"
