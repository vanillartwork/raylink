# aws-ss-clash

One-click AWS EC2 Shadowsocks setup script with auto-generated Clash configuration.  
AWS EC2 一键部署 Shadowsocks，并自动生成 Clash 配置文件。

This project deploys a Shadowsocks server on an AWS EC2 Ubuntu instance and generates a Clash-compatible configuration file automatically.  
本项目用于在 AWS EC2 Ubuntu 服务器上一键部署 Shadowsocks 服务端，并自动生成 Clash 可导入的配置文件。

Default settings / 默认配置：

- Server / 服务器：AWS EC2
- OS / 系统：Ubuntu 22.04 / 24.04
- Protocol / 协议：Shadowsocks
- Port / 端口：8388
- Cipher / 加密方式：aes-256-gcm
- Client / 客户端：Clash / Clash Verge / Clash for Windows / Clash Meta
- Docker image / Docker 镜像：`shadowsocks/shadowsocks-libev`

> Use this project only for legal and compliant network access. AWS EC2 and data transfer may incur charges.  
> 请仅用于合法、合规的网络访问。AWS EC2 和流量可能产生费用，请注意账单。

---

## 1. Features / 功能

The script automatically performs the following tasks:  
该脚本会自动完成以下操作：

1. Update the Ubuntu package list.  
   更新 Ubuntu 软件包列表。
2. Install Docker.  
   安装 Docker。
3. Start and enable the Docker service.  
   启动并启用 Docker 服务。
4. Generate a random Shadowsocks password.  
   自动生成 Shadowsocks 随机密码。
5. Remove the old Shadowsocks container if it exists.  
   如果旧的 Shadowsocks 容器存在，则自动删除。
6. Create a new Shadowsocks Docker container.  
   创建新的 Shadowsocks Docker 容器。
7. Generate a Clash configuration file automatically.  
   自动生成 Clash 配置文件。
8. Print the server information and Clash configuration.  
   输出服务器信息和 Clash 配置。

Final traffic path / 最终流量路径：

```text
Clash → EC2 Public IP:8388 → Docker Container:8388 → Shadowsocks Server
```

---

## 2. AWS EC2 Preparation / AWS EC2 准备

### 2.1 Create an EC2 Instance / 创建 EC2 实例

Recommended settings / 推荐配置：

| Item | Recommended value |
|---|---|
| Region / 区域 | Any region / 任意区域 |
| AMI / 系统镜像 | Ubuntu Server 22.04 LTS / 24.04 LTS |
| Instance type / 实例类型 | t3.micro / t2.micro |
| Storage / 存储 | Default is enough / 默认即可 |
| Key pair / 密钥对 | Create and download a `.pem` key / 创建并下载 `.pem` 私钥文件 |

Make sure the instance has a **Public IPv4 address**.  
请确保实例拥有 **Public IPv4 address**。

---

### 2.2 Configure Security Group / 配置安全组

In the EC2 Security Group inbound rules, add:  
在 EC2 Security Group 的 Inbound rules 中添加：

| Type | Protocol | Port | Source |
|---|---|---:|---|
| SSH | TCP | 22 | Your IP / 你的 IP |
| Custom TCP | TCP | 8388 | 0.0.0.0/0 |
| Custom UDP | UDP | 8388 | 0.0.0.0/0 |

Explanation / 说明：

- Port `22` is used for SSH login. It is recommended to allow only your own IP.  
  `22` 端口用于 SSH 登录服务器，建议只允许你自己的 IP 访问。
- Port `8388` is used by Clash to connect to the Shadowsocks server.  
  `8388` 端口用于 Clash 连接 Shadowsocks 服务端。
- If you use another port, such as `443`, change the Security Group rules accordingly.  
  如果你使用其他端口，例如 `443`，请同步修改安全组规则。

---

## 3. SSH into the EC2 Instance / SSH 登录 EC2 实例

For Windows PowerShell / Windows PowerShell 示例：

```powershell
cd $env:USERPROFILE\Downloads
ssh -i aws-clash-key.pem ubuntu@YOUR_EC2_PUBLIC_IP
```

Example / 示例：

```powershell
ssh -i aws-clash-key.pem ubuntu@13.232.43.141
```

For Ubuntu AMI, the default username is usually:  
对于 Ubuntu AMI，默认用户名通常是：

```text
ubuntu
```

---

## 4. One-line Installation / 一键安装

Run this command on the EC2 instance:  
在 EC2 服务器中运行：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/aws-ss-clash/main/clash_ss.sh | sudo bash
```

---

## 5. Custom Port / 自定义端口

The default port is:  
默认端口是：

```text
8388
```

To use another port, for example `443`, run:  
如果想使用其他端口，例如 `443`，可以运行：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/aws-ss-clash/main/clash_ss.sh | sudo PORT=443 bash
```

If you use a custom port, remember to update the AWS Security Group:  
如果使用自定义端口，请同时修改 AWS Security Group：

| Type | Protocol | Port | Source |
|---|---|---:|---|
| Custom TCP | TCP | 443 | 0.0.0.0/0 |
| Custom UDP | UDP | 443 | 0.0.0.0/0 |

---

## 6. Custom Cipher Method / 自定义加密方式

The default cipher is:  
默认加密方式是：

```text
aes-256-gcm
```

To specify another method, for example `aes-128-gcm`, run:  
如果想指定其他加密方式，例如 `aes-128-gcm`，可以运行：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/aws-ss-clash/main/clash_ss.sh | sudo METHOD=aes-128-gcm bash
```

Recommended method / 推荐使用：

```text
aes-256-gcm
```

---

## 7. Generated Files / 生成的文件

After installation, the script creates:  
安装完成后，脚本会生成：

```text
/opt/aws-clash-ss/server-info.txt
/opt/aws-clash-ss/clash.yaml
```

View server information / 查看服务器信息：

```bash
sudo cat /opt/aws-clash-ss/server-info.txt
```

View Clash configuration / 查看 Clash 配置：

```bash
sudo cat /opt/aws-clash-ss/clash.yaml
```

---

## 8. Generated Clash Configuration / 生成的 Clash 配置

The generated Clash configuration looks like this:  
生成的 Clash 配置大致如下：

```yaml
mixed-port: 7890
allow-lan: false
mode: global
log-level: info

proxies:
  - name: "AWS-SS"
    type: ss
    server: YOUR_EC2_PUBLIC_IP
    port: 8388
    cipher: aes-256-gcm
    password: "YOUR_GENERATED_PASSWORD"
    udp: true

proxy-groups:
  - name: "GLOBAL"
    type: select
    proxies:
      - AWS-SS
      - DIRECT

rules:
  - MATCH,GLOBAL
```

Import the generated `clash.yaml` into Clash, then select:  
将生成的 `clash.yaml` 导入 Clash，然后选择：

```text
GLOBAL → AWS-SS
```

Enable system proxy or TUN mode in Clash.  
在 Clash 中开启系统代理或 TUN 模式。

---

## 9. Download Clash Config to Local Computer / 下载 Clash 配置到本机

The generated Clash config is saved on the EC2 instance:  
生成的 Clash 配置保存在 EC2 服务器上：

```text
/opt/aws-clash-ss/clash.yaml
```

On your local Windows PowerShell, download it to the Downloads folder using `scp`:  
在本地 Windows PowerShell 中，可以使用 `scp` 下载到 Downloads 文件夹：

```powershell
scp -i $env:USERPROFILE\Downloads\aws-clash-key.pem ubuntu@YOUR_EC2_PUBLIC_IP:/opt/aws-clash-ss/clash.yaml $env:USERPROFILE\Downloads\aws-clash.yaml
```

Example / 示例：

```powershell
scp -i $env:USERPROFILE\Downloads\aws-clash-key.pem ubuntu@13.232.43.141:/opt/aws-clash-ss/clash.yaml $env:USERPROFILE\Downloads\aws-clash.yaml
```

Then import this file into Clash:  
然后在 Clash 中导入这个文件：

```text
Downloads/aws-clash.yaml
```

---

## 10. Check Docker Status / 检查 Docker 状态

Check whether the Shadowsocks container is running:  
检查 Shadowsocks 容器是否正在运行：

```bash
sudo docker ps
```

Expected output should include something like:  
正常输出中应该包含类似内容：

```text
0.0.0.0:8388->8388/tcp
0.0.0.0:8388->8388/udp
```

Check Shadowsocks logs:  
查看 Shadowsocks 日志：

```bash
sudo docker logs ss-server
```

Expected logs should include:  
正常日志中应该包含：

```text
initializing ciphers... aes-256-gcm
tcp server listening at 0.0.0.0:8388
udp server listening at 0.0.0.0:8388
```

---

## 11. Test Port Connectivity / 测试端口连通性

On your local Windows PowerShell, run:  
在本地 Windows PowerShell 中运行：

```powershell
Test-NetConnection YOUR_EC2_PUBLIC_IP -Port 8388
```

Example / 示例：

```powershell
Test-NetConnection 13.232.43.141 -Port 8388
```

If the result shows:  
如果结果显示：

```text
TcpTestSucceeded : True
```

the port is reachable.  
说明端口可以访问。

If it shows:  
如果显示：

```text
TcpTestSucceeded : False
```

check the following:  
请检查以下内容：

1. EC2 Public IPv4 is correct.  
   EC2 Public IPv4 是否正确。
2. Security Group allows TCP 8388.  
   Security Group 是否允许 TCP 8388。
3. Docker container is running.  
   Docker 容器是否正在运行。
4. Clash uses the same port as the server.  
   Clash 中填写的端口是否和服务器一致。

---

## 12. Useful Commands / 常用命令

View Clash config / 查看 Clash 配置：

```bash
sudo cat /opt/aws-clash-ss/clash.yaml
```

View server information / 查看服务器信息：

```bash
sudo cat /opt/aws-clash-ss/server-info.txt
```

View running containers / 查看正在运行的容器：

```bash
sudo docker ps
```

View Shadowsocks logs / 查看 Shadowsocks 日志：

```bash
sudo docker logs ss-server
```

Restart Shadowsocks / 重启 Shadowsocks：

```bash
sudo docker restart ss-server
```

Stop Shadowsocks / 停止 Shadowsocks：

```bash
sudo docker stop ss-server
```

Remove Shadowsocks container / 删除 Shadowsocks 容器：

```bash
sudo docker rm ss-server
```

---

## 13. Regenerate Password and Config / 重新生成密码和配置

The script generates a new password every time it runs.  
脚本每次运行都会生成一个新密码。

To regenerate the password and Clash configuration, run:  
如果想重新生成密码和 Clash 配置，可以运行：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/aws-ss-clash/main/clash_ss.sh | sudo bash
```

Then download or copy the new Clash configuration again.  
然后重新下载或复制新的 Clash 配置。

---

## 14. EC2 Public IP Change / EC2 公网 IP 变化

If your EC2 instance uses an auto-assigned public IP, the Public IPv4 address may change after stopping and starting the instance.  
如果你的 EC2 使用 Auto-assigned public IP，那么实例 Stop 再 Start 后，Public IPv4 可能会改变。

If Clash suddenly stops working, check:  
如果 Clash 突然无法连接，优先检查：

```text
EC2 → Instances → Public IPv4 address
```

If the IP has changed, update the `server` field in Clash:  
如果 IP 已经变化，请更新 Clash 配置中的 `server` 字段：

```yaml
server: YOUR_NEW_EC2_PUBLIC_IP
```

To avoid this issue, you can bind an Elastic IP to the EC2 instance.  
如果想避免 IP 改变，可以给 EC2 绑定 Elastic IP。

---

## 15. Troubleshooting / 常见问题排查

### 15.1 Clash Shows Timeout / Clash 显示 Timeout

Run this on your local PowerShell:  
在本地 PowerShell 中运行：

```powershell
Test-NetConnection YOUR_EC2_PUBLIC_IP -Port 8388
```

If `TcpTestSucceeded` is `False`, common causes are:  
如果 `TcpTestSucceeded` 是 `False`，常见原因包括：

- Security Group does not allow TCP 8388.  
  Security Group 没有开放 TCP 8388。
- EC2 Public IP is wrong.  
  EC2 Public IP 写错。
- Docker container is not running.  
  Docker 容器没有运行。
- The port in Clash does not match the server port.  
  Clash 中的端口和服务器端口不一致。

---

### 15.2 Port Is Reachable but Clash Still Fails / 端口可达但 Clash 仍然失败

Check whether these fields match the generated `clash.yaml`:  
检查下面这些字段是否和生成的 `clash.yaml` 完全一致：

```yaml
server: YOUR_EC2_PUBLIC_IP
port: 8388
cipher: aes-256-gcm
password: "YOUR_PASSWORD"
```

Common issues / 常见问题：

- Password was typed incorrectly.  
  密码输入错误。
- Wrong cipher method.  
  加密方式错误。
- Old Clash config was not saved or reloaded.  
  Clash 旧配置没有保存或重新加载。
- EC2 public IP changed.  
  EC2 公网 IP 已变化。

---

### 15.3 Docker Logs Show the Wrong Port / Docker 日志显示端口不对

Run / 运行：

```bash
sudo docker ps
```

Expected mapping / 正常映射应为：

```text
0.0.0.0:8388->8388/tcp
0.0.0.0:8388->8388/udp
```

If the mapping is different, rerun the script.  
如果映射不同，建议重新运行脚本。

---

### 15.4 SSH Cannot Connect / SSH 无法连接

Check the Security Group rule for SSH:  
检查 Security Group 中的 SSH 规则：

```text
TCP 22 Your IP
```

If your public IP changes, update the SSH rule to `My IP`.  
如果你的公网 IP 改变了，需要把 SSH 规则重新设置为 `My IP`。

For temporary testing only, you can use:  
仅在临时测试时，可以使用：

```text
TCP 22 0.0.0.0/0
```

Do not keep SSH open to `0.0.0.0/0` permanently.  
不要长期把 SSH 开放给 `0.0.0.0/0`。

---

## 16. Uninstall / 卸载

Stop and remove the Shadowsocks container:  
停止并删除 Shadowsocks 容器：

```bash
sudo docker stop ss-server
sudo docker rm ss-server
```

Remove generated files:  
删除生成的文件：

```bash
sudo rm -rf /opt/aws-clash-ss
```

If you no longer need the EC2 instance, stop or terminate it from the AWS console to avoid ongoing charges.  
如果不再需要该 EC2 实例，请在 AWS 控制台中 Stop 或 Terminate，避免继续产生费用。

---

## 17. License / 开源协议

This project is released under the MIT License.  
本项目使用 MIT License 开源。
