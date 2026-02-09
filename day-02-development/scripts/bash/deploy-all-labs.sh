#!/bin/bash

# Day-02: Deploy All Labs Script
# Deploys all 3 Day-02 labs sequentially to OpenShift Sandbox

set -e

# Default values
PROJECT="ebanking-labs"
NAMESPACE="ebanking-labs"
SKIP_TESTS=false
VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --token)
            TOKEN="$2"
            shift 2
            ;;
        --server)
            SERVER="$2"
            shift 2
            ;;
        --project)
            PROJECT="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --skip-tests)
            SKIP_TESTS=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 --token <TOKEN> --server <SERVER> [options]"
            echo ""
            echo "Required:"
            echo "  --token <TOKEN>     OpenShift token"
            echo "  --server <SERVER>   OpenShift server URL"
            echo ""
            echo "Optional:"
            echo "  --project <PROJECT>    OpenShift project (default: ebanking-labs)"
            echo "  --namespace <NAMESPACE> Kubernetes namespace (default: ebanking-labs)"
            echo "  --skip-tests          Skip validation tests"
            echo "  --verbose             Verbose output"
            echo "  -h, --help            Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check required arguments
if [[ -z "$TOKEN" || -z "$SERVER" ]]; then
    echo "Error: --token and --server are required"
    echo "Use --help for usage information"
    exit 1
fi

# Logging function
log() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    fi
}

log "Starting Day-02 deployment with token: ${TOKEN:0:10}..."

# Login to OpenShift
log "Logging into OpenShift..."
oc login --token="$TOKEN" --server="$SERVER" > /dev/null 2>&1
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to login to OpenShift"
    exit 1
fi

# Create project if it doesn't exist
log "Creating project: $PROJECT"
oc new-project "$PROJECT" > /dev/null 2>&1 || true

# Deploy labs in sequence
LABS=("2.1a" "2.2a" "2.3a")
SCRIPT_DIR="$(dirname "$0")"

for lab in "${LABS[@]}"; do
    echo ""
    echo "🚀 Deploying Lab $lab..."
    
    script="$SCRIPT_DIR/deploy-and-test-$lab.sh"
    if [[ ! -f "$script" ]]; then
        echo "Error: Script not found: $script"
        exit 1
    fi
    
    # Build command with arguments
    cmd="$script --token $TOKEN --server $SERVER --project $PROJECT --namespace $NAMESPACE"
    if [[ "$SKIP_TESTS" == "true" ]]; then
        cmd="$cmd --skip-tests"
    fi
    if [[ "$VERBOSE" == "true" ]]; then
        cmd="$cmd --verbose"
    fi
    
    log "Running: $cmd"
    eval $cmd
    
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to deploy Lab $lab"
        exit 1
    fi
    
    echo "✅ Lab $lab deployed successfully"
done

# Summary
echo ""
echo "🎉 All Day-02 labs deployed successfully!"
echo ""
echo "Deployed Services:"
echo "  Lab 2.1a - Serialization API: https://$(oc get route ebanking-serialization-api-secure -o jsonpath='{.spec.host}' 2>/dev/null || echo 'pending')/swagger"
echo "  Lab 2.2a - Idempotent Producer: https://$(oc get route ebanking-idempotent-api-secure -o jsonpath='{.spec.host}' 2>/dev/null || echo 'pending')/swagger"
echo "  Lab 2.3a - DLT Consumer: https://$(oc get route ebanking-dlt-consumer-secure -o jsonpath='{.spec.host}' 2>/dev/null || echo 'pending')/swagger"
echo ""
echo "To test all APIs:"
echo "  ./bash/test-all-apis.sh --token $TOKEN --server $SERVER"
echo ""
echo "To view logs:"
echo "  oc logs -l deployment=ebanking-serialization-api"
echo "  oc logs -l deployment=ebanking-idempotent-api"
echo "  oc logs -l deployment=ebanking-dlt-consumer"
