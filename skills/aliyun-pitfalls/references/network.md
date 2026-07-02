## 🌐 網路 (VPC / NAT / EIP / vSwitch)

### 16. EIP PayByTraffic 帶寬上限

PayByTraffic 模式下單 EIP 帶寬**上限 200 Mbps**。要更高用「共享帶寬包 (CBWP)」：

```hcl
resource "alicloud_common_bandwidth_package" "main" {
  bandwidth            = 500
  internet_charge_type = "PayByBandwidth"
}

resource "alicloud_common_bandwidth_package_attachment" "main" {
  bandwidth_package_id = alicloud_common_bandwidth_package.main.id
  instance_id          = alicloud_eip_address.main.id
}
```

### 17. NAT Gateway 必須 force delete 才能帶走 SNAT 規則

**現象**：刪 NAT 報 `IpInUse.HasBeenUsedBySnatTable`

**修復**：
```bash
# CLI
aliyun vpc DeleteNatGateway --NatGatewayId ngw-xxx --Force true
```

```hcl
# TF — 改 lifecycle / 用 depends_on 保證順序
# 或先 terraform state rm 然後手動清
```

### 18. vSwitch 被 ACR EE VPC endpoint 占用刪不掉

**現象**：刪 vSwitch 報 `DependencyViolation.Acr`

**修復**：先解除 ACR EE 的 VPC endpoint 綁定：
```bash
aliyun cr DeleteInstanceVpcEndpointLinkedVpc \
  --InstanceId cri-xxx \
  --VpcId vpc-xxx \
  --VswitchId vsw-xxx \
  --ModuleName Registry
```

或 TF 同步刪除（`alicloud_cr_vpc_endpoint_linked_vpc`）。

### 19. CMS 自動建 SG 殘留

**現象**：刪 ACK 後 VPC 還有個 `alicloud-cms-auto-created-security-group-vpc-xxx` 殘留。

**原因**：CloudMonitor 自動加的 SG，ACK 不會清。**手動刪 vSwitch 前要先刪這個 SG**。

---
