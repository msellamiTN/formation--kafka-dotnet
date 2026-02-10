# 🧹 OpenShift Cleanup Scripts

This directory contains scripts to manage OpenShift resources for the Kafka training labs.

## 📁 Scripts Overview

### Deployment Scripts
| Script | Purpose | Environment |
|--------|---------|-------------|
| `bash/deploy-and-test-*.sh` | Deploy and validate individual labs | Linux/macOS |
| `powershell/deploy-and-test-*.ps1` | Deploy and validate individual labs | Windows PowerShell |

### Cleanup Scripts
| Script | Purpose | Environment |
|--------|---------|-------------|
| `bash/cleanup-all-resources.sh` | Remove ALL OpenShift resources with detailed logging | Linux/macOS |
| `powershell/cleanup-all-resources.ps1` | Remove ALL OpenShift resources with detailed logging | Windows PowerShell |
| `powershell/cleanup-simple.ps1` | Simple cleanup using `oc delete all --all` | Windows PowerShell |

## 🗑️ Cleanup All Resources

### Bash (Linux/macOS)
```bash
./scripts/bash/cleanup-all-resources.sh \
  --token=sha256~xxx \
  --server=https://api.xxx.com:6443
```

### PowerShell (Windows)

#### Detailed Cleanup
```powershell
./scripts/powershell/cleanup-all-resources.ps1 `
  -Token "sha256~xxx" `
  -Server "https://api.xxx.com:6443"
```

#### Simple Cleanup (Recommended)
```powershell
./scripts/powershell/cleanup-simple.ps1 `
  -Token "sha256~xxx" `
  -Server "https://api.xxx.com:6443" `
  -Force
```

### Options
- `--project` / `-Project`: OpenShift project (default: `msellamitn-dev`)
- `--force` / `-Force`: Skip confirmation prompts
- `--verbose` / `-Verbose`: Enable detailed logging
- `--help`: Show usage information

## 📋 What Gets Cleaned Up

The cleanup scripts will delete in dependency order:

1. **Routes** - Edge routes for external access
2. **Services** - Internal service endpoints
3. **Deployments** - Application deployments
4. **Build Configs** - S2I build configurations
5. **Image Streams** - Container image references
6. **Pods** - Any remaining pods
7. **StatefulSets/DaemonSets** - If any exist
8. **PVCs** - Persistent volumes (only with `--force`)

## 🚨 Important Notes

### ⚠️ Data Loss Warning
- **ALL** resources in the project will be deleted
- This includes Kafka cluster, all labs, and supporting services
- PVCs (persistent data) are only deleted with `--force` flag
- **This action is irreversible**

### 🔄 Deployment Order
Resources are deleted in dependency order to avoid conflicts:
- Routes → Services → Deployments → Build Configs → Image Streams

### 📊 Resource Verification
Scripts show:
- Current resource count before cleanup
- Detailed list (with `--verbose`)
- Final verification of remaining resources

## 🛠️ Usage Examples

### Quick Cleanup (with confirmation)
```bash
# Bash
./scripts/bash/cleanup-all-resources.sh \
  --token=sha256~gygLN7See0OuNioYoriSpjhqr6FWicldAeTxf_YyOvk \
  --server=https://api.rm3.7wse.p1.openshiftapps.com:6443

# PowerShell
./scripts/powershell/cleanup-all-resources.ps1 `
  -Token "sha256~gygLN7See0OuNioYoriSpjhqr6FWicldAeTxf_YyOvk" `
  -Server "https://api.rm3.7wse.p1.openshiftapps.com:6443"
```

### Force Cleanup (no confirmation)
```bash
# Bash
./scripts/bash/cleanup-all-resources.sh \
  --token=xxx \
  --server=xxx \
  --force

# PowerShell
./scripts/powershell/cleanup-all-resources.ps1 `
  -Token "xxx" `
  -Server "xxx" `
  -Force
```

### Verbose Cleanup (detailed output)
```bash
# Bash
./scripts/bash/cleanup-all-resources.sh \
  --token=xxx \
  --server=xxx \
  --verbose

# PowerShell
./scripts/powershell/cleanup-all-resources.ps1 `
  -Token "xxx" `
  -Server "xxx" `
  -Verbose
```

## 🔄 After Cleanup

### Redeploying Labs
After cleanup, you can redeploy labs using the individual deployment scripts:

```bash
# Deploy all Day 01 labs
./scripts/bash/deploy-and-test-1.2a.sh --token=xxx --server=xxx
./scripts/bash/deploy-and-test-1.2b.sh --token=xxx --server=xxx
./scripts/bash/deploy-and-test-1.2c.sh --token=xxx --server=xxx
./scripts/bash/deploy-and-test-1.3a.sh --token=xxx --server=xxx
./scripts/bash/deploy-and-test-1.3b.sh --token=xxx --server=xxx
./scripts/bash/deploy-and-test-1.3c.sh --token=xxx --server=xxx

# Deploy all Day 02 labs
./scripts/bash/deploy-and-test-2.1a.sh --token=xxx --server=xxx
./scripts/bash/deploy-and-test-2.2a.sh --token=xxx --server=xxx
./scripts/bash/deploy-and-test-2.2b.sh --token=xxx --server=xxx
./scripts/bash/deploy-and-test-2.3a.sh --token=xxx --server=xxx
```

### Manual Cleanup
If some resources remain after script execution:

```bash
# Check remaining resources
oc get all

# Manually delete specific resources
oc delete deployment <name>
oc delete service <name>
oc delete route <name>
oc delete buildconfig <name>
```

## 📚 Related Documentation

- [Day 01 README](../day-01-foundations/README.md)
- [Day 02 README](../day-02-development/README.md)
- [Individual Lab READMEs](../day-01-foundations/module-*/lab-*/README.md)

## 🆘 Troubleshooting

### Common Issues

1. **Permission Denied**
   - Ensure you have admin rights to the project
   - Check if token is valid and not expired

2. **Resources Still Exist**
   - Wait for graceful termination (up to 5 minutes)
   - Use `--force` flag for immediate deletion
   - Manually delete remaining resources

3. **Project Not Found**
   - Verify project name (default: `msellamitn-dev`)
   - Check if you're logged into correct cluster

4. **Token Invalid**
   - Generate new token from OpenShift console
   - Ensure token has sufficient permissions

### Getting Help
```bash
# Show help
./scripts/bash/cleanup-all-resources.sh --help
./scripts/powershell/cleanup-all-resources.ps1 -Help

# Check current status
oc project
oc get all
```
