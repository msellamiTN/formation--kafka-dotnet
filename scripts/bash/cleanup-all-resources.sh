#!/bin/bash

# Cleanup all OpenShift resources created for Kafka Training
# This script removes all deployments, services, routes, and build configs

set -e

# Default values
PROJECT="msellamitn-dev"
NAMESPACE="msellamitn-dev"
FORCE=false
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
        --force)
            FORCE=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 --token <TOKEN> --server <SERVER> [options]"
            echo ""
            echo "Options:"
            echo "  --token <TOKEN>        OpenShift authentication token"
            echo "  --server <SERVER>      OpenShift server URL"
            echo "  --project <PROJECT>    OpenShift project (default: msellamitn-dev)"
            echo "  --namespace <NS>      OpenShift namespace (default: msellamitn-dev)"
            echo "  --force               Skip confirmation prompts"
            echo "  --verbose             Enable verbose logging"
            echo "  -h, --help            Show this help message"
            echo ""
            echo "This script will delete:"
            echo "  - All deployments (ebanking-*, kafka-*, schema-registry, ksqldb)"
            echo "  - All services"
            echo "  - All routes"
            echo "  - All build configs"
            echo "  - All image streams"
            echo ""
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

# Login to OpenShift
log "Logging into OpenShift..."
oc login --token="$TOKEN" --server="$SERVER" > /dev/null 2>&1
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to login to OpenShift"
    exit 1
fi

# Switch to project
log "Switching to project: $PROJECT"
oc project "$PROJECT" > /dev/null 2>&1

# Get current resources
echo ""
echo "🔍 Current resources in project '$PROJECT':"
echo "=========================================="

# Count resources
DEPLOYMENTS=$(oc get deployments -o name 2>/dev/null | wc -l)
SERVICES=$(oc get services -o name 2>/dev/null | wc -l)
ROUTES=$(oc get routes -o name 2>/dev/null | wc -l)
BUILD_CONFIGS=$(oc get buildconfigs -o name 2>/dev/null | wc -l)
IMAGE_STREAMS=$(oc get imagestreams -o name 2>/dev/null | wc -l)
PODS=$(oc get pods -o name 2>/dev/null | wc -l)

echo "📦 Deployments: $DEPLOYMENTS"
echo "🔌 Services: $SERVICES"
echo "🛣️  Routes: $ROUTES"
echo "🏗️  Build Configs: $BUILD_CONFIGS"
echo "🖼️  Image Streams: $IMAGE_STREAMS"
echo "📱 Pods: $PODS"

# Show detailed list if verbose
if [[ "$VERBOSE" == "true" ]]; then
    echo ""
    echo "📋 Detailed resource list:"
    oc get deployments,svc,routes,buildconfigs,imagestreams,pods 2>/dev/null || true
fi

# Confirmation prompt
if [[ "$FORCE" != "true" ]]; then
    echo ""
    echo "⚠️  WARNING: This will delete ALL resources listed above!"
    echo "📝 This includes all Kafka training labs, Kafka cluster, and supporting services"
    echo ""
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo "❌ Cleanup cancelled"
        exit 0
    fi
fi

echo ""
echo "🧹 Starting cleanup..."

# Function to delete resources safely
delete_resources() {
    local resource_type=$1
    local pattern=$2
    local description=$3
    
    log "Deleting $description..."
    local resources=$(oc get $resource_type -o name 2>/dev/null | grep "$pattern" || true)
    if [[ -n "$resources" ]]; then
        echo "$resources" | xargs oc delete $resource_type --grace-period=0 --force 2>/dev/null || true
        echo "✅ Deleted $description"
    else
        echo "ℹ️  No $description found"
    fi
}

# Delete in order to avoid dependency issues
echo ""
echo "🗑️  Deleting resources in dependency order..."

# 1. Delete routes first (no dependencies)
delete_resources "routes" "." "all routes"

# 2. Delete services (routes depend on services)
delete_resources "services" "." "all services"

# 3. Delete deployments (services depend on deployments)
delete_resources "deployments" "." "all deployments"

# 4. Delete build configs
delete_resources "buildconfigs" "." "all build configs"

# 5. Delete image streams
delete_resources "imagestreams" "." "all image streams"

# 6. Delete any remaining pods
delete_resources "pods" "." "all remaining pods"

# 7. Clean up any remaining statefulsets or daemonsets
delete_resources "statefulsets" "." "any statefulsets"
delete_resources "daemonsets" "." "any daemonsets"

# 8. Clean up PVCs (optional - comment out if you want to keep data)
if [[ "$FORCE" == "true" ]]; then
    delete_resources "persistentvolumeclaims" "." "all PVCs"
else
    echo "ℹ️  Skipping PVCs (use --force to delete them)"
fi

# Final verification
echo ""
echo "🔍 Verifying cleanup..."
sleep 5

REMAINING_DEPLOYMENTS=$(oc get deployments -o name 2>/dev/null | wc -l)
REMAINING_SERVICES=$(oc get services -o name 2>/dev/null | wc -l)
REMAINING_ROUTES=$(oc get routes -o name 2>/dev/null | wc -l)
REMAINING_PODS=$(oc get pods -o name 2>/dev/null | wc -l)

echo ""
echo "📊 Remaining resources:"
echo "📦 Deployments: $REMAINING_DEPLOYMENTS"
echo "🔌 Services: $REMAINING_SERVICES"
echo "🛣️  Routes: $REMAINING_ROUTES"
echo "📱 Pods: $REMAINING_PODS"

if [[ $REMAINING_DEPLOYMENTS -eq 0 && $REMAINING_SERVICES -eq 0 && $REMAINING_ROUTES -eq 0 ]]; then
    echo ""
    echo "🎉 Cleanup completed successfully!"
    echo "✅ All Kafka training resources have been removed"
else
    echo ""
    echo "⚠️  Some resources may still remain:"
    if [[ "$VERBOSE" == "true" ]]; then
        oc get all 2>/dev/null || true
    fi
    echo "💡 You may need to manually delete remaining resources or wait for graceful termination"
fi

echo ""
echo "📝 Cleanup summary:"
echo "   - Project: $PROJECT"
echo "   - Timestamp: $(date)"
echo "   - Force mode: $FORCE"
echo ""
echo "🔗 To redeploy labs, use the deploy-and-test-*.sh scripts"
echo "📖 For more information, see the lab README files"
