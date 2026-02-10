#!/bin/bash

# ksqlDB Lab Deployment and Testing Script
# Deploys ksqlDB and C# Banking API to OpenShift Sandbox

set -e

# Default values
NAMESPACE="msellamitn-dev"
BUILD_CONTEXT="dotnet/BankingKsqlDBLab"
APP_NAME="banking-ksqldb-lab"
KSQLDB_URL="http://ksqldb:8088"
KAFKA_BOOTSTRAP="kafka-0.kafka-svc:9092"
ROUTE_HOST=""

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --namespace) NAMESPACE="$2"; shift ;;
        --token) TOKEN="$2"; shift ;;
        --server) SERVER="$2"; shift ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# Validate required arguments
if [ -z "$TOKEN" ] || [ -z "$SERVER" ]; then
    echo "Usage: $0 --token <oc-token> --server <oc-server> [--namespace <namespace>]"
    echo "Example: $0 --token sha256~xxxx --server https://api.sandbox.xxx.openshiftapps.com:6443"
    exit 1
fi

echo "🚀 Deploying ksqlDB Lab to OpenShift Sandbox..."
echo "Namespace: $NAMESPACE"
echo "Server: $SERVER"

# Login to OpenShift
echo "🔐 Logging in to OpenShift..."
oc login --token="$TOKEN" --server="$SERVER" --insecure-skip-tls-verify

# Switch to namespace
echo "📂 Switching to namespace: $NAMESPACE"
oc project "$NAMESPACE" 2>/dev/null || oc new-project "$NAMESPACE"

# Step 1: Ensure Kafka is running
echo "📊 Checking Kafka cluster..."
KAFKA_REPLICAS=$(oc get statefulset kafka -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
if [ "$KAFKA_REPLICAS" = "0" ]; then
    echo "⚠️  Kafka StatefulSet is scaled to 0, scaling up to 3 replicas..."
    oc scale statefulset kafka --replicas=3 -n "$NAMESPACE"
    echo "⏳ Waiting for Kafka brokers to be ready..."
    oc wait --for=condition=ready pod -l app=kafka -n "$NAMESPACE" --timeout=300s
else
    echo "✅ Kafka is running ($KAFKA_REPLICAS replicas)"
fi

# Step 2: Deploy ksqlDB
echo "🔧 Deploying ksqlDB..."
oc apply -f ksqldb-deployment.yaml -n "$NAMESPACE"
echo "⏳ Waiting for ksqlDB to be ready..."
oc wait --for=condition=ready pod -l app=ksqldb -n "$NAMESPACE" --timeout=300s

# Step 3: Create Kafka topics
echo "📋 Creating Kafka topics..."
oc exec deployment/ksqldb -n "$NAMESPACE" -- bash -c "
    kafka-topics --bootstrap-server kafka-0.kafka-svc:9092 --create --topic transactions --partitions 3 --replication-factor 1 --if-not-exists
    kafka-topics --bootstrap-server kafka-0.kafka-svc:9092 --create --topic verified_transactions --partitions 3 --replication-factor 1 --if-not-exists
    kafka-topics --bootstrap-server kafka-0.kafka-svc:9092 --create --topic fraud_alerts --partitions 3 --replication-factor 1 --if-not-exists
    kafka-topics --bootstrap-server kafka-0.kafka-svc:9092 --create --topic account_balances --partitions 3 --replication-factor 1 --if-not-exists
    kafka-topics --bootstrap-server kafka-0.kafka-svc:9092 --create --topic hourly_stats --partitions 3 --replication-factor 1 --if-not-exists
"

# Step 4: Build and deploy C# API
echo "🏗️  Building C# Banking API..."
cd "$BUILD_CONTEXT"
oc start-build "$APP_NAME" --from-dir=. --follow -n "$NAMESPACE"
cd - > /dev/null

echo "⏳ Waiting for deployment to be ready..."
oc wait --for=condition=available deployment/"$APP_NAME" -n "$NAMESPACE" --timeout=300s

# Step 5: Create edge route
echo "🌐 Creating edge route..."
cat > edge-route.yaml << EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: $APP_NAME
  namespace: $NAMESPACE
spec:
  host: ""
  to:
    kind: Service
    name: $APP_NAME
  port:
    targetPort: 8080
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
EOF

oc delete route "$APP_NAME" -n "$NAMESPACE" --ignore-not-found=true
oc apply -f edge-route.yaml -n "$NAMESPACE"
rm edge-route.yaml

# Get route host
ROUTE_HOST=$(oc get route "$APP_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.host}')
echo "📍 Route: https://$ROUTE_HOST"

# Step 6: Health check
echo "🏥 Performing health check..."
for i in {1..30}; do
    if curl -k -s "https://$ROUTE_HOST/api/TransactionStream/health" | grep -q "Healthy"; then
        echo "✅ Health check passed"
        break
    fi
    echo "⏳ Waiting for health endpoint... ($i/30)"
    sleep 5
done

# Step 7: Initialize ksqlDB streams
echo "🔄 Initializing ksqlDB streams..."
INIT_RESPONSE=$(curl -k -s -X POST "https://$ROUTE_HOST/api/TransactionStream/initialize" -H "accept: */*")
if echo "$INIT_RESPONSE" | grep -q "successfully"; then
    echo "✅ ksqlDB streams initialized"
else
    echo "⚠️  Stream initialization may have issues - check logs"
fi

# Step 8: Generate test transactions
echo "💳 Generating test transactions..."
GEN_RESPONSE=$(curl -k -s -X POST "https://$ROUTE_HOST/api/TransactionStream/transactions/generate/20" -H "accept: */*")
if echo "$GEN_RESPONSE" | grep -q "generated"; then
    echo "✅ Test transactions generated"
else
    echo "⚠️  Transaction generation may have issues"
fi

# Step 9: Test pull query
echo "🔍 Testing account balance query..."
sleep 5  # Allow time for processing
BALANCE_RESPONSE=$(curl -k -s -X GET "https://$ROUTE_HOST/api/TransactionStream/account/ACC001/balance" -H "accept: */*")
if echo "$BALANCE_RESPONSE" | grep -q "balance"; then
    echo "✅ Pull query working"
else
    echo "⚠️  Balance query may have issues"
fi

# Step 10: Display results
echo ""
echo "🎉 ksqlDB Lab Deployment Complete!"
echo "=================================="
echo "📊 ksqlDB UI: https://$(oc get route ksqldb -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo 'not-available')"
echo "🌐 API Route: https://$ROUTE_HOST"
echo "📚 Swagger UI: https://$ROUTE_HOST/swagger"
echo "🏥 Health: https://$ROUTE_HOST/api/TransactionStream/health"
echo ""
echo "🧪 Test Commands:"
echo "curl -k -X POST 'https://$ROUTE_HOST/api/TransactionStream/initialize'"
echo "curl -k -X POST 'https://$ROUTE_HOST/api/TransactionStream/transactions/generate/10'"
echo "curl -k -X GET 'https://$ROUTE_HOST/api/TransactionStream/account/ACC001/balance'"
echo ""
echo "📖 Push Query (streaming):"
echo "curl -k -N -X GET 'https://$ROUTE_HOST/api/TransactionStream/verified/stream'"
echo ""
echo "🔍 Troubleshooting:"
echo "oc logs -f deployment/ksqldb -n $NAMESPACE"
echo "oc logs -f deployment/$APP_NAME -n $NAMESPACE"
echo "oc get pods -n $NAMESPACE"
