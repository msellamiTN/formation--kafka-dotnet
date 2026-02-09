# Day-02: Deployment & Testing Scripts

This directory contains automated deployment and testing scripts for all Day-02 labs. Each script builds, deploys, and validates the lab objectives on OpenShift Sandbox.

## 📁 Directory Structure

```
scripts/
├── README.md                    # This file
├── powershell/                  # PowerShell scripts (Windows)
│   ├── deploy-all-labs.ps1      # Deploy all labs
│   ├── deploy-and-test-2.1a.ps1 # Lab 2.1a - Serialization API
│   ├── deploy-and-test-2.2a.ps1 # Lab 2.2a - Idempotent Producer
│   ├── deploy-and-test-2.3a.ps1 # Lab 2.3a - DLT Consumer
│   ├── test-all-apis.ps1        # Test all deployed APIs
│   └── create-*.ps1             # Test data creation scripts
├── bash/                        # Bash scripts (Linux/macOS/WSL)
│   ├── deploy-all-labs.sh       # Deploy all labs
│   ├── deploy-and-test-2.1a.sh # Lab 2.1a - Serialization API
│   ├── deploy-and-test-2.2a.sh # Lab 2.2a - Idempotent Producer
│   ├── deploy-and-test-2.3a.sh # Lab 2.3a - DLT Consumer
│   ├── test-all-apis.sh        # Test all deployed APIs
│   └── create-*.sh             # Test data creation scripts
└── data/                        # Test data files
    ├── test-transaction-v1.json  # V1 transaction test
    ├── test-transaction-v2.json  # V2 transaction test (schema evolution)
    ├── test-idempotent.json      # Idempotent producer test
    ├── test-dlt-trigger.json     # DLT trigger test (invalid)
    ├── batch-transactions.json   # Batch transaction data
    └── schema-evolution.json     # Schema evolution test data
```

## 📁 Scripts Overview

### 🚀 Master Deployment Scripts
| Script | Description | Platform | Location |
|--------|-------------|----------|----------|
| `deploy-all-labs.sh` | Deploys all 3 labs sequentially | Bash (Linux/macOS/WSL) | `bash/` |
| `deploy-all-labs.ps1` | Deploys all 3 labs sequentially | PowerShell (Windows) | `powershell/` |

### 🧪 Individual Lab Scripts
| Lab | Bash Script | PowerShell Script | Location |
|-----|------------|-------------------|----------|
| 2.1a - Serialization API | `deploy-and-test-2.1a.sh` | `deploy-and-test-2.1a.ps1` | `bash/` / `powershell/` |
| 2.2a - Idempotent Producer | `deploy-and-test-2.2a.sh` | `deploy-and-test-2.2a.ps1` | `bash/` / `powershell/` |
| 2.3a - DLT Consumer | `deploy-and-test-2.3a.sh` | `deploy-and-test-2.3a.ps1` | `bash/` / `powershell/` |

### 📊 Testing Scripts
| Script | Description | Platform | Location |
|--------|-------------|----------|----------|
| `test-all-apis.sh` | Tests all deployed APIs with scenario validation | Bash | `bash/` |
| `test-all-apis.ps1` | Tests all deployed APIs with scenario validation | PowerShell | `powershell/` |

### 📝 Test Data Files
| File | Description | Location |
|------|-------------|----------|
| `test-transaction-v1.json` | V1 transaction (original schema) | `data/` |
| `test-transaction-v2.json` | V2 transaction (schema evolution) | `data/` |
| `test-idempotent.json` | Idempotent producer test | `data/` |
| `test-dlt-trigger.json` | DLT trigger test (invalid amount) | `data/` |
| `batch-transactions.json` | Batch transaction data | `data/` |
| `schema-evolution.json` | Schema evolution test data | `data/` |

### 🛠️ Data Creation Scripts
| Script | Description | Platform | Location |
|--------|-------------|----------|----------|
| `create-transactions.sh` | Creates test transaction data | Bash | `bash/` |
| `create-batch-transactions.sh` | Creates batch transaction data | Bash | `bash/` |
| `create-schema-evolution.sh` | Creates schema evolution test data | Bash | `bash/` |

## 🚀 Quick Start

### Prerequisites

1. **OpenShift Sandbox access** with token and server URL
2. **Docker** installed and running
3. **kubectl/oc** CLI tools installed
4. **jq** for JSON processing

### Deploy All Labs

```bash
# Bash (Linux/macOS/WSL)
cd day-02-development/scripts
./bash/deploy-all-labs.sh --token=<TOKEN> --server=<SERVER>

# PowerShell (Windows)
cd day-02-development\scripts
.\powershell\deploy-all-labs.ps1 -Token <TOKEN> -Server <SERVER>
```

### Deploy Individual Lab

```bash
# Lab 2.1a - Serialization API
./bash/deploy-and-test-2.1a.sh --token=<TOKEN> --server=<SERVER>

# Lab 2.2a - Idempotent Producer  
./bash/deploy-and-test-2.2a.sh --token=<TOKEN> --server=<SERVER>

# Lab 2.3a - DLT Consumer
./bash/deploy-and-test-2.3a.sh --token=<TOKEN> --server=<SERVER>
```

### Test All APIs

```bash
# After deployment
./bash/test-all-apis.sh
```

## 📋 What Each Script Does

### Individual Lab Scripts

Each `deploy-and-test-*.sh` script:

1. **Login to OpenShift** using provided token and server
2. **Create project** if it doesn't exist (`ebanking-labs`)
3. **Build Docker image** using S2I binary build
4. **Deploy application** with proper environment variables
5. **Create edge route** for secure HTTPS access
6. **Wait for deployment** to be ready
7. **Run validation tests** specific to lab objectives
8. **Display success criteria** and URLs

### Master Script

The `deploy-all-labs.sh` script:

1. Deploys all 3 labs in sequence
2. Validates each lab individually
3. Runs cross-lab integration tests
4. Provides summary of all deployed services

### Testing Scripts

The `test-all-apis.sh` script:

1. Tests serialization concepts (V1/V2 compatibility)
2. Validates idempotence (PID tracking, no duplicates)
3. Verifies DLT functionality (retry, headers, backoff)
4. Checks cross-lab data flow
5. Provides detailed test report

## 🔧 Environment Variables

All scripts accept these parameters:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `--token` | OpenShift token | Required |
| `--server` | OpenShift server URL | Required |
| `--project` | OpenShift project name | `ebanking-labs` |
| `--namespace` | Kubernetes namespace | `ebanking-labs` |
| `--skip-tests` | Skip validation tests | `false` |
| `--verbose` | Verbose output | `false` |

## 🐛 Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| `Build failed` | Check Dockerfile and .csproj files |
| `Route hanging` | Use edge routes (scripts do this automatically) |
| `Pod CrashLoopBackOff` | Check environment variables and Kafka connectivity |
| `Tests failing` | Verify Kafka topics exist and are accessible |

### Debug Mode

```bash
# Enable verbose output
./bash/deploy-and-test-2.1a.sh --token=<TOKEN> --server=<SERVER> --verbose

# Skip tests for faster iteration
./bash/deploy-and-test-2.1a.sh --token=<TOKEN> --server=<SERVER> --skip-tests
```

## 📚 Additional Resources

- [Day 02 README](../README.md) - Module overview
- [Lab 2.1a README](../module-04-advanced-patterns/lab-2.1a-serialization/README.md) - Serialization details
- [Lab 2.2a README](../module-04-advanced-patterns/lab-2.2-producer-advanced/README.md) - Idempotent producer details
- [Lab 2.3a README](../module-04-advanced-patterns/lab-2.3a-consumer-dlt-retry/README.md) - DLT consumer details
