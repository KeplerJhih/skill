# EKS 踩坑紀錄與排錯指南

實際維運 EKS 叢集時遇到的問題與解決方案。

---

## 踩坑 1：EBS CSI Driver CrashLoopBackOff — 缺少 IRSA 配置

### 症狀

```
$ kubectl get pods -n kube-system
ebs-csi-controller-xxx   1/6     CrashLoopBackOff   39   17m
ebs-csi-controller-xxx   1/6     CrashLoopBackOff   39   17m
```

6 個 container 中只有 `liveness-probe` 正常，其餘 5 個（ebs-plugin、csi-provisioner、csi-attacher、csi-snapshotter、csi-resizer）全部 CrashLoopBackOff。

### 錯誤訊息

```
Failed health check (verify network connection and IAM credentials):
dry-run EC2 API call failed: operation error EC2: DescribeAvailabilityZones,
get identity: get credentials: failed to refresh cached credentials,
no EC2 IMDS role found, operation error ec2imds: GetMetadata,
canceled, context deadline exceeded
```

### 根本原因

Terraform 部署 EKS `aws-ebs-csi-driver` Add-on 時，**未設定 `service_account_role_arn`**。

```hcl
# ❌ 錯誤：缺少 IRSA 配置
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "aws-ebs-csi-driver"
}
```

EBS CSI Driver 需要呼叫 EC2 API（DescribeAvailabilityZones、CreateVolume、AttachVolume 等），但沒有任何 credentials：
1. **IRSA 未配置** — Service Account 沒有 `eks.amazonaws.com/role-arn` annotation
2. **aws-secret 不存在** — Pod 嘗試從 Kubernetes Secret 讀取 credentials 也失敗
3. **Node IAM Role 無 EBS 權限** — Node Role 只有基本的 Worker、CNI、ECR 權限

### 解決方案

**Step 1**：建立 OIDC Provider（通常已有）

```hcl
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}
```

**Step 2**：建立 EBS CSI 專用 IAM Role（IRSA）

```hcl
resource "aws_iam_role" "ebs_csi" {
  name = "${local.name_prefix}-ebs-csi-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi.name
}
```

**Step 3**：在 Add-on 中指定 Role ARN

```hcl
# ✅ 正確：設定 service_account_role_arn
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.ebs_csi.arn
  depends_on               = [aws_eks_node_group.main]
}
```

**Step 4**：Apply 後驗證

```bash
terraform apply
kubectl get pods -n kube-system -l app=ebs-csi-controller
# 預期：6/6 Running, 0 restarts
```

### 排錯流程

```
Pod CrashLoopBackOff
  │
  ▼ kubectl describe pod → 查看 Last State Message
  │
  ▼ 是否包含 "credentials" / "IAM" 關鍵字？
  │
  ├── 是 → IAM 權限問題
  │   │
  │   ▼ kubectl get sa <sa-name> -n kube-system -o yaml
  │   │
  │   ▼ 檢查是否有 annotation:
  │   │  eks.amazonaws.com/role-arn: arn:aws:iam::xxx:role/xxx
  │   │
  │   ├── 無 annotation → IRSA 未配置，需建立 IAM Role + 設定 addon
  │   └── 有 annotation → 檢查 IAM Role trust policy 和 permissions
  │
  └── 否 → 其他原因（OOM / config error / image pull fail）
```

---

## 踩坑 2：IRSA 通用排錯 Checklist

當任何 EKS Pod 因 IAM credentials 失敗時：

### 檢查項目

- [ ] **OIDC Provider 已建立**：`aws eks describe-cluster --name <cluster> --query "cluster.identity.oidc.issuer"`
- [ ] **IAM Role Trust Policy 正確**：Federated Principal 指向正確的 OIDC Provider ARN
- [ ] **Trust Policy Condition 正確**：`:sub` 匹配正確的 `system:serviceaccount:<namespace>:<sa-name>`
- [ ] **Trust Policy Condition 正確**：`:aud` 為 `sts.amazonaws.com`
- [ ] **IAM Policy 已附加**：Role 有正確的權限 Policy
- [ ] **Service Account annotation 正確**：`eks.amazonaws.com/role-arn` 指向正確的 Role ARN
- [ ] **STS VPC Endpoint**（若使用）：確認 Private Subnet 能存取 STS 服務

### 常用診斷指令

```bash
# 檢查 OIDC Provider
aws iam list-open-id-connect-providers

# 檢查 Service Account
kubectl get sa <sa-name> -n <namespace> -o yaml

# 檢查 Pod 環境變數（IRSA 會注入 AWS_ROLE_ARN 和 AWS_WEB_IDENTITY_TOKEN_FILE）
kubectl exec <pod> -n <namespace> -- env | grep AWS

# 手動測試 IRSA Token（進入 Pod 內）
kubectl exec -it <pod> -n <namespace> -- aws sts get-caller-identity
```

---

## 踩坑 3：EKS Add-on 需要 IRSA 的完整列表

以下 EKS Add-on 需要額外的 IAM 權限，**必須配置 IRSA**：

| Add-on | Service Account | 需要的 IAM Policy |
|--------|----------------|-------------------|
| `aws-ebs-csi-driver` | `ebs-csi-controller-sa` | `AmazonEBSCSIDriverPolicy` |
| `aws-efs-csi-driver` | `efs-csi-controller-sa` | `AmazonEFSCSIDriverPolicy` |
| `aws-mountpoint-s3-csi-driver` | `s3-csi-driver-sa` | 自訂 S3 存取 Policy |
| `adot` (OpenTelemetry) | `adot-collector-sa` | `AmazonPrometheusRemoteWriteAccess` 等 |
| `amazon-cloudwatch-observability` | `cloudwatch-agent-sa` | `CloudWatchAgentServerPolicy` |

以下 Add-on **不需要額外 IRSA**（使用 Node Role 或不需 AWS API）：

| Add-on | 說明 |
|--------|------|
| `vpc-cni` | 預設使用 Node IAM Role（已含 `AmazonEKS_CNI_Policy`） |
| `coredns` | DNS 解析，不存取 AWS API |
| `kube-proxy` | 網路代理，不存取 AWS API |

### Terraform 模板：Add-on + IRSA 一條龍

```hcl
# 通用 IRSA 模板（以 EBS CSI 為例）
resource "aws_iam_role" "addon_role" {
  name = "${local.name_prefix}-<addon>-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.eks.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:sub" = "system:serviceaccount:<namespace>:<sa-name>"
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "addon_policy" {
  policy_arn = "<managed-policy-arn>"
  role       = aws_iam_role.addon_role.name
}

resource "aws_eks_addon" "addon" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "<addon-name>"
  service_account_role_arn = aws_iam_role.addon_role.arn
}
```

---

## 踩坑 4：Terraform 註解 Module 時 Outputs 報錯

### 症狀

```
Error: Reference to undeclared module
  on outputs.tf line 8, in output "cluster_name":
  No module call named "eks" is declared in the root module.
```

### 原因

在 `main.tf` 中註解掉 `module "eks"` 時，`outputs.tf` 仍然引用 `module.eks.*`，Terraform 所有 `.tf` 是一起解析的。

### 解決方案

註解 module 時，**必須同時註解所有引用該 module 的 output 和其他 resource**。

---

## 通用排錯流程

```
kubectl get pods -A（找到異常 Pod）
  │
  ▼
kubectl describe pod <pod> -n <ns>（看 Events + Last State）
  │
  ├── ImagePullBackOff → ECR 權限 / Image 不存在 / Registry 認證
  ├── CrashLoopBackOff → 看 Last State Message
  │   ├── OOMKilled → 增加 memory limits
  │   ├── Error + credentials → IRSA / IAM 問題（見踩坑 1-2）
  │   └── Error + config → 環境變數 / ConfigMap / Secret 設定問題
  ├── Pending → 資源不足 / Node Selector 不匹配 / PVC 無法綁定
  └── Init:Error → Init Container 失敗，kubectl logs <pod> -c <init-container>
  │
  ▼
kubectl logs <pod> -n <ns> --tail=100（看應用日誌）
kubectl logs <pod> -n <ns> -c <container> --previous（看上次 crash 的日誌）
```
