# Day-01: Deployment & Testing Scripts

This directory contains automated deployment and testing scripts for all Day-01 labs. Each script builds, deploys, and validates the lab objectives on OpenShift Sandbox.

## 📁 Scripts Overview

### 🚀 Master Deployment Scripts
| Script | Description | Platform |
|--------|-------------|----------|
| `deploy-all-labs.sh` | Deploys all 6 labs sequentially | Bash (Linux/macOS/WSL) |
| `deploy-all-labs.ps1` | Deploys all 6 labs sequentially | PowerShell (Windows) |

### 🧪 Individual Lab Scripts
| Lab | Bash Script | PowerShell Script |
|-----|------------|-------------------|
| 1.2a - Basic Producer | `deploy-and-test-1.2a.sh` | `deploy-and-test-1.2a.ps1` |
| 1.2b - Keyed Producer | `deploy-and-test-1.2b.sh` | `deploy-and-test-1.2b.ps1` |
| 1.2c - Resilient Producer | `deploy-and-test-1.2c.sh` | `deploy-and-test-1.2c.ps1` |
| 1.3a - Fraud Detection | `deploy-and-test-1.3a.sh` | `deploy-and-test-1.3a.ps1` |
| 1.3b - Balance Service | `deploy-and-test-1.3b.sh` | `deploy-and-test-1.3b.ps1` |
| 1.3c - Audit Service | `deploy-and-test-1.3c.sh` | `deploy-and-test-1.3c.ps1` |

### 📊 Testing Scripts
| Script | Description | Platform |
|--------|-------------|----------|
| `test-all-apis.sh` | Tests all deployed APIs with scenario validation | Bash |
| `test-all-apis.ps1` | Tests all deployed APIs with scenario validation | PowerShell |

## 🚀 Quick Start

### Option 1: Deploy All Labs (Recommended)

```bash
# Bash/Linux/macOS/WSL
./deploy-all-labs.sh --token=sha256~XXXX --server=https://api.xxx.openshiftapps.com:6443

# PowerShell (Windows)
.\deploy-all-labs.ps1 -Token "sha256~XXXX" -Server "https://api.xxx.openshiftapps.com:6443"
```

### Option 2: Deploy Individual Lab

```bash
# Deploy Lab 1.2a (Basic Producer)
./deploy-and-test-1.2a.sh

# Deploy Lab 1.2b (Keyed Producer)
./deploy-and-test-1.2b.sh
```

### Option 3: Test Already Deployed APIs

```bash
# Test all APIs
./test-all-apis.sh

# Test with PowerShell
.\test-all-apis.ps1
```

## 📋 Prerequisites

1. **OpenShift CLI (oc)** installed and configured
2. **jq** for JSON parsing (Linux/macOS/WSL)
3. **curl** for HTTP requests
4. Access to OpenShift Sandbox with valid token

## 🔧 What Each Script Does

### Deployment Scripts (`deploy-and-test-*.sh/.ps1`)

Each lab deployment script performs:

1. **Prerequisites Check**
   - Validates oc CLI installation
   - Checks OpenShift login status

2. **Build Phase**
   - Creates BuildConfig (if needed)
   - Builds .NET application using S2I
   - Pushes image to OpenShift registry

3. **Deploy Phase**
   - Creates/updates Deployment
   - Sets environment variables (Kafka, ASP.NET Core)
   - Creates secure Edge Route
   - Waits for pod readiness

4. **Verification Phase**
   - Health check endpoint
   - Swagger UI accessibility
   - API responsiveness

5. **Lab Objectives Validation**
   - Tests specific lab concepts
   - Validates Kafka integration
   - Checks partition/offset behavior
   - Verifies error handling (for resilient producer)

6. **Kafka Topic Verification**
   - Confirms topic creation
   - Shows message distribution
   - Validates partition assignments

### Testing Scripts (`test-all-apis.sh/.ps1`)

The testing script:

1. **Route Discovery** - Automatically finds all deployed API routes
2. **Sequential Testing** - Tests each lab with its specific scenarios:
   - **Producers**: Send transactions, verify partition/offset
   - **Consumers**: Check metrics, alerts, balances, audit logs
3. **Results Summary** - Shows pass/fail statistics

## 📊 Lab Objectives Tested

### Producer Labs (1.2a, 1.2b, 1.2c)
| Objective | 1.2a Basic | 1.2b Keyed | 1.2c Resilient |
|-----------|------------|------------|----------------|
| Basic message production | ✅ | ✅ | ✅ |
| Transaction serialization | ✅ | ✅ | ✅ |
| Partition assignment | ✅ | ✅ | ✅ |
| Batch processing | ✅ | ✅ | ✅ |
| Key-based partitioning | ❌ | ✅ | ❌ |
| Order guarantee | ❌ | ✅ | ❌ |
| Retry mechanism | ❌ | ❌ | ✅ |
| DLQ handling | ❌ | ❌ | ✅ |
| Circuit breaker | ❌ | ❌ | ✅ |

### Consumer Labs (1.3a, 1.3b, 1.3c)
| Objective | 1.3a Fraud | 1.3b Balance | 1.3c Audit |
|-----------|------------|-------------|------------|
| Basic consumption | ✅ | ✅ | ✅ |
| Consumer groups | ❌ | ✅ | ✅ |
| Manual commits | ❌ | ❌ | ✅ |
| Fraud detection | ✅ | ❌ | ❌ |
| Balance calculation | ❌ | ✅ | ❌ |
| Audit logging | ❌ | ❌ | ✅ |
| Deduplication | ❌ | ❌ | ✅ |
| Rebalancing | ❌ | ✅ | ❌ |

## 🛠️ Troubleshooting

### Common Issues

1. **"oc command not found"**
   - Install OpenShift CLI and add to PATH
   - Windows: Add to System PATH or use PowerShell profile

2. **"Login failed"**
   - Check token expiration (Sandbox tokens expire after ~24 hours)
   - Get fresh token from OpenShift console → Copy Login Command

3. **"Route not found"**
   - API not yet deployed
   - Check deployment status: `oc get deployment`
   - Check pod logs: `oc logs <pod-name>`

4. **"Health check failed"**
   - Pod might be starting (wait 1-2 minutes)
   - Check environment variables: `oc env deployment/<name> --list`
   - Check Kafka connectivity: `oc exec kafka-0 -- ...`

5. **"Build failed"**
   - Check .csproj file exists
   - Verify .NET 8.0 target framework
   - Check for compilation errors in build log

### Debug Commands

```bash
# Check all deployments
oc get deployment

# Check pod status
oc get pods

# Check pod logs
oc logs <pod-name>

# Check routes
oc get route

# Check environment variables
oc env deployment/<name> --list

# Check Kafka topics
oc exec kafka-0 -- /opt/kafka/bin/kafka-topics.sh --list

# Consume messages
oc exec kafka-0 -- /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic banking.transactions --from-beginning
```

## 📝 Notes

- Scripts use **edge routes** for reliable Sandbox access
- All APIs listen on port 8080 internally
- Kafka bootstrap server: `kafka-svc:9092`
- Scripts are idempotent - can be run multiple times
- Each script includes comprehensive error handling and reporting

## 🎯 Best Practices

1. **Deploy Producers First** - Consumers need messages to process
2. **Wait Between Deployments** - Allow pods to fully start
3. **Check Logs** - If tests fail, check pod logs for errors
4. **Monitor Resources** - Sandbox has limited resources
5. **Clean Up** - Use `oc delete all -l app=<name>` to remove deployments

## 📚 Additional Resources

- [OpenShift Sandbox Guide](../module-01-cluster/README.md)
- [Kafka CLI Reference](../module-01-cluster/infra/README.md)
- [Lab Documentation](../module-02-producer/README.md)
