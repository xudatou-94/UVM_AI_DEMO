# RSA 硬件加速器 规格说明书

**版本**：v0.1 草稿  
**场景定位**：安全加速卡（PCIe 独立卡，面向 TLS/PKI/代码签名场景）  
**目标标准**：FIPS 140-3 Level 3

---

## 1. 用例与性能目标

### 1.1 典型使用场景

| 场景 | 操作 | 说明 |
|------|------|------|
| TLS 握手卸载 | RSA-2048 私钥解密 / 签名 | HTTPS 服务器高并发场景 |
| PKI 证书签发 | RSA-2048/4096 CA 签名 | 离线 CA / OCSP Responder |
| 代码签名 | RSA-2048/4096 + SHA-256 | 固件/软件签名流水线 |
| 密钥协商 | RSA-2048 公钥加密 | 会话密钥传输（非主流，备选） |

### 1.2 性能指标（目标）

| 算法 | 操作 | 目标吞吐 | 备注 |
|------|------|---------|------|
| RSA-2048 | 私钥签名（CRT） | ≥ 4,000 ops/s | 单核 |
| RSA-2048 | 公钥验签 | ≥ 40,000 ops/s | e=65537 |
| RSA-4096 | 私钥签名（CRT） | ≥ 800 ops/s | 单核 |
| RSA-4096 | 公钥验签 | ≥ 8,000 ops/s | e=65537 |

> 参考：Thales Luna 7 HSM：RSA-2048 ~3,000 sign/s；设计目标略高于行业基准。

### 1.3 延迟目标

| 算法 | 单次签名延迟 |
|------|------------|
| RSA-2048 | < 250 µs |
| RSA-4096 | < 1.2 ms |

---

## 2. 算法层选型

### 2.1 模幂算法

**选定：Montgomery Ladder（防护优先）**

- 常数时间执行，不依赖私钥 bit 值做分支，天然抗 SPA
- 相比 Sliding Window 吞吐稍低，但安全加速卡场景安全优先
- 公钥验签（e=65537，仅 17 bit）可走快速路径

```
私钥签名：Montgomery Ladder + CRT + exponent blinding
公钥加密/验签：Square-and-Multiply（e 固定 65537，5次平方+1次乘）
```

### 2.2 模乘算法

**选定：Montgomery Multiplication（64-bit MAC 阵列）**

- 消除除法，全部转为乘加操作
- 基本单元：64×64-bit 乘加，支持最大 4096-bit 操作数
- 操作数分解：2048-bit = 32 个 64-bit limb；4096-bit = 64 个 64-bit limb
- 使用 Interleaved Montgomery：每轮迭代处理 1 个 limb，减少临时存储

### 2.3 CRT 优化

对私钥签名启用 CRT：
```
mp = m^dp mod p    （1024 或 2048-bit 模幂）
mq = m^dq mod q
m  = CRT_combine(mp, mq, p, q, qInv)
```
吞吐约 **4× 提升**。必须配套 **CRT 故障检测**（见第 4 节）。

### 2.4 Hash 协处理

内置 SHA-256 / SHA-384 / SHA-512 硬件单元，支持 PKCS#1 v1.5 和 PSS padding，
减少主机 PCIe 往返延迟。

---

## 3. 微架构

### 3.1 顶层框图

```
┌─────────────────────────────────────────────────┐
│                RSA Accelerator                  │
│                                                 │
│  ┌─────────┐   ┌───────────────────────────┐   │
│  │  PCIe   │   │      Control Unit         │   │
│  │ DMA/IF  │──▶│  (Micro-sequencer / FSM)  │   │
│  └─────────┘   └────────┬─────────┬─────────┘   │
│                         │         │             │
│               ┌─────────▼──┐  ┌───▼──────────┐  │
│               │  Operand   │  │ Montgomery   │  │
│               │  RAM Bank  │  │   Mul Unit   │  │
│               │ (A/B/N/TMP)│  │(64×64 MAC×2) │  │
│               └─────────┬──┘  └───┬──────────┘  │
│                         └────┬────┘             │
│                         ┌────▼─────┐            │
│                         │  Adder / │            │
│                         │ Reducer  │            │
│                         └──────────┘            │
│                                                 │
│  ┌───────────┐   ┌─────────┐   ┌─────────────┐  │
│  │  SHA-2    │   │  TRNG   │   │  Key Vault  │  │
│  │  Engine   │   │(entropy)│   │  (OTP/SRAM) │  │
│  └───────────┘   └─────────┘   └─────────────┘  │
└─────────────────────────────────────────────────┘
```

### 3.2 数据通路

| 参数 | 值 | 说明 |
|------|----|------|
| MAC 位宽 | 64×64-bit | 平衡面积与频率 |
| 并行 MAC 数 | 2 | CRT 两半（p路/q路）可并行 |
| 操作数 SRAM | 4 bank × 4 KB | 存 A、B、N、TMP，支持双端口 |
| 临时寄存器 | 8×256-bit | 模乘中间值 |
| 目标频率 | 400 MHz | TSMC 28nm HPC 目标 |

### 3.3 控制方式

**选定：Micro-sequencer（可编程微码，只读 ROM）**

原因：
- 比纯 FSM 灵活，可支持 RSA + 未来 ECC（P-256/P-384）
- ROM 固化，防止运行时代码注入（与 OTBN 思路相同）
- 指令集针对大数运算优化（MODMUL / MODADD / MODSUB / COPY / BR）

RSA 签名微码流程（伪码）：
```
LOAD  p, q, dp, dq, qInv, m   ; 从 Key Vault & DMA 加载
BLIND e_blind = blinding(dp, rng)  ; exponent blinding
MODMUL_LADDER mp = m^e_blind mod p ; Montgomery Ladder 模幂
MODMUL_LADDER mq = m^e_blind mod q
CRT   s = combine(mp, mq, p, q, qInv)
VERIFY s^e mod n == m           ; CRT fault check
OUTPUT s
ZEROIZE tmp                     ; 归零中间值
```

---

## 4. 安全设计

### 4.1 侧信道防护（SCA）

| 威胁 | 防护措施 |
|------|---------|
| SPA（简单功耗分析） | Montgomery Ladder 常数时间；禁止以 key bit 做分支 |
| DPA（差分功耗） | **Exponent Blinding**：`d' = d + r·λ(n)`，r 每次新鲜随机 |
| Message Blinding | 签名前 `m' = m · r^e mod n`，签名后除以 r |
| Timing Attack | 所有操作固定 limb 循环次数，不做 early-exit |
| EM 攻击 | 规则访存模式，操作数 RAM 访问序列与 key 无关 |

### 4.2 故障注入防护（FIA）

| 威胁 | 防护措施 |
|------|---------|
| CRT 故障（Bellcore attack） | 输出前强制 `verify: s^e mod n == H(m)`，不通过则清零并报警 |
| 寄存器翻转 | FSM 状态寄存器 Hamming ECC 编码（SEC-DED） |
| SRAM 翻转 | 操作数 SRAM 加 Parity，关键操作数（d、p、q）加 ECC |
| 时钟毛刺 | 片上 PLL 监测器；检测到异常频率立即 zeroize |
| 电压毛刺 | 片上 LDO + 过压/欠压检测传感器 |
| 温度探针 | 温度传感器，超温触发安全清零 |

### 4.3 密钥保护

- 私钥 `(d, p, q, dp, dq, qInv)` **不可导出**芯片
- Key Vault：专用 SRAM + 硬件清零指令（`ZEROIZE`）
- 支持 Key Wrapping（AES-256-GCM 加密导入）
- 密钥生命周期：loaded → active → zeroized，状态机强制单向
- Power-on：自动 zeroize，防冷启动攻击

### 4.4 DFT 安全

- 生产模式下 scan chain **强制禁用**（由 OTP fuse 控制）
- scan 路径不可观测 Key Vault 和中间运算寄存器
- JTAG 在安全模式下仅保留 IDCODE；调试接口需认证密钥解锁

---

## 5. 主机接口

### 5.1 物理接口

**选定：PCIe Gen3 x4（安全加速卡标准形态）**

- 带宽：~16 Gbps，远超 RSA 数据搬运需求（单次操作 < 1 KB）
- 延迟：~1 µs PCIe 往返，加速效果明显
- 备选：PCIe Gen4 x4（向前兼容）

### 5.2 软件接口

```
Host
 │
 ├── MMIO 寄存器空间（BAR0，4 KB）
 │     CMD / STATUS / IRQ_EN / IRQ_STATUS
 │     KEY_CTRL / KEY_STATUS
 │     ERR_CODE / ALARM_STATUS
 │
 └── DMA 数据通道（BAR1，64 KB）
       INPUT_BUF  : 明文/密文数据
       OUTPUT_BUF : 签名结果/解密结果
       KEY_LOAD   : 加密密钥导入（只写）
```

### 5.3 寄存器映射（顶层）

| 偏移 | 名称 | 访问 | 说明 |
|------|------|------|------|
| 0x00 | CHIP_ID | RO | 芯片 ID 和版本 |
| 0x04 | CMD | WO | 操作命令（见下表） |
| 0x08 | STATUS | RO | 当前状态 |
| 0x0C | CTRL | RW | 配置（key_len/op_mode/irq_en） |
| 0x10 | IRQ_STATUS | RW1C | 中断状态 |
| 0x14 | ERR_CODE | RO | 错误码（含 CRT_FAIL/SCA_ALARM 等） |
| 0x18 | KEY_CTRL | WO | 密钥操作（load/zeroize/select） |
| 0x1C | KEY_STATUS | RO | 密钥槽状态 |
| 0x20 | ALARM_STATUS | RO | 安全告警（glitch/temp/voltage） |
| 0x24 | PERF_CNT | RO | 完成操作计数（调试用） |

**CMD 编码**：

| 值 | 操作 |
|----|------|
| 0x01 | RSA_SIGN（私钥签名，启用 CRT + blinding） |
| 0x02 | RSA_VERIFY（公钥验签） |
| 0x03 | RSA_ENCRYPT（公钥加密） |
| 0x04 | RSA_DECRYPT（私钥解密，启用 CRT + blinding） |
| 0x10 | KEY_LOAD（从 DMA 缓冲区导入加密密钥） |
| 0x11 | KEY_ZEROIZE（清除指定密钥槽） |
| 0x20 | SELF_TEST（FIPS 上电自检） |

---

## 6. 随机数需求

- 内置 **TRNG**（基于热噪声环振荡器）
- 输出经 AES-CTR_DRBG 处理后供 blinding 使用（NIST SP 800-90A）
- TRNG 健康检测：Repetition Count Test + Adaptive Proportion Test（NIST SP 800-90B）
- 每次签名操作需新鲜随机数：`r`（message blinding）+ `r'`（exponent blinding），共 2 × key_len/2 bits

---

## 7. 错误与告警分级

| 级别 | 事件 | 响应 |
|------|------|------|
| **FATAL** | CRT 验证失败 / glitch 检测 / 温度/电压异常 | 立即 zeroize 所有密钥；芯片锁定，需硬件复位 |
| **RECOVERABLE** | SRAM 单 bit ECC 纠正 / DMA 超时 | 报 IRQ，当前操作中止，芯片可继续工作 |
| **INFO** | 操作完成 / TRNG 重新播种 | 正常 IRQ 通知 |

---

## 8. 工艺与功耗

| 参数 | 目标值 |
|------|--------|
| 工艺节点 | TSMC 28nm HPC（或同等） |
| 目标频率 | 400 MHz |
| 核心面积（估算） | ~2 mm²（不含 PCIe PHY） |
| 动态功耗（峰值） | < 500 mW（RSA-2048 满负荷） |
| 待机功耗 | < 50 mW（clock gating） |

---

## 9. 验证计划（概要）

| 层次 | 方法 | 工具 |
|------|------|------|
| 单元级 | UVM + 定向测试 | VCS / Questa |
| 子系统级 | UVM + cocotb | 模乘单元与参考模型对拍 |
| 顶层 | SystemVerilog TB | NIST CAVS KAT 向量全量回归 |
| 安全验证 | 形式化（常数时间性） | FIVER / Coco |
| 侧信道仿真 | Power trace 前仿 | TVLA + VCS power 估计 |
| 故障注入 | Bit-flip 注入仿真 | 自定义 FI framework |

### 9.1 关键测试向量

- NIST FIPS 186-5 RSA 签名/验签向量
- OpenSSL 交叉验证（`openssl dgst -sign / -verify`）
- CRT fault injection：注入单 bit 翻转，验证 FATAL 告警触发并且不输出错误签名
- Blinding 验证：相同输入两次签名，中间值不同但结果相同

---

## 10. 开放问题（待决策）

| # | 问题 | 候选方案 | 影响 |
|---|------|---------|------|
| 1 | 是否支持 ECC（P-256/P-384）？ | A. 仅 RSA；B. 通用大数协处理器 | 面积 +20~40%，但未来扩展性强 |
| 2 | 密钥槽数量？ | 4 / 8 / 16 | 影响 Key Vault SRAM 大小 |
| 3 | 是否支持 RSA-1024 Legacy？ | 是/否 | FIPS 已不推荐，增加兼容测试成本 |
| 4 | 多核并行（2个加速核）？ | 是/否 | 吞吐 ×2，面积 ×1.8 |
| 5 | PKCS#1 v1.5 还是 PSS 或两者都支持？ | 都支持 | padding 逻辑复杂度增加 |
| 6 | PCIe Gen4 向前兼容？ | 是/否 | PHY IP 选型影响 |

---

*下一步：根据开放问题的决策更新 v0.2，然后进入 RTL 微架构详细设计（模乘单元 / 控制器 / Key Vault）。*
