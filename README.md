# aws-ss-clash

[English](#english) | [中文说明](#中文说明)

---

# English

One-click AWS EC2 Shadowsocks setup script with auto-generated Clash configuration and URL link.

This project deploys a Shadowsocks server on an AWS EC2 Ubuntu instance and automatically generates both a Clash-compatible YAML configuration file and a Shadowsocks URL for importing.

## Default Settings

- Server: AWS EC2
- OS: Ubuntu 24.04
- Protocol: Shadowsocks
- Port: 8388
- Cipher: aes-256-gcm
- Client: Clash / Clash Verge / Clash for Windows / Clash Meta
- Docker image: `shadowsocks/shadowsocks-libev`

> Use this project only for legal and compliant network access. AWS EC2 and data transfer may incur charges.

---

## 1. Features

The script automatically performs the following tasks:

1. Updates the Ubuntu package list.
2. Installs Docker.
3. Starts and enables the Docker service.
4. Generates a random Shadowsocks password.
5. Removes the old Shadowsocks container if it exists.
6. Creates a new Shadowsocks Docker container.
7. Generates a Clash configuration file automatically.
8. Prints the server information and Clash configuration.

Final traffic path:

```text
Clash → EC2 Public IP:8388 → Docker Container:8388 → Shadowsocks Server
```

---

## 2. AWS EC2 Preparation

### 2.1 Log in to AWS

Go to the AWS Management Console.

In the search bar, search for:

```text
EC2
```

Open the EC2 service, then click:

```text
Launch instance
```

---

### 2.2 Choose the Operating System

Recommended AMI:

```text
Ubuntu Server 24.04 LTS
```

Do not choose Windows for this setup. Windows Server costs more and is not suitable for this lightweight proxy service.

---

### 2.3 Choose the Instance Type

For personal use, the recommended instance type is:

```text
t3.micro
```

If you want a cheaper ARM-based instance, you may choose:

```text
t4g.micro
```

### 2.4 Create a Key Pair

In the **Key pair** section, select:

```text
Create new key pair
```

Example name:

```text
aws-clash-key
```

Key pair type:

```text
RSA
```

Private key file format:

```text
.pem
```

Then download the key file.

You will get a file similar to:

```text
aws-clash-key.pem
```

This file is very important. You need it later to SSH into the EC2 instance.

---

### 2.5 Configure Security Group

In the EC2 Security Group inbound rules, add:

| Type | Protocol | Port | Source |
|---|---|---:|---|
| SSH | TCP | 22 | Your IP |
| Custom TCP | TCP | 8388 | 0.0.0.0/0 |
| Custom UDP | UDP | 8388 | 0.0.0.0/0 |

Explanation:

- Port `22` is used for SSH login. It is recommended to allow only your own IP.
- Port `8388` is used by Clash to connect to the Shadowsocks server.
- If you use another port, such as `443`, change the Security Group rules accordingly.

---

### 2.6 Launch the Instance

After checking the AMI, instance type, key pair, storage, and security group settings, click:

```text
Launch instance
```

Wait until the instance state becomes:

```text
Running
```

Then copy the instance's public IP address:

```text
Public IPv4 address
```

This IP address will be used for SSH login and Clash configuration.

---

## 3. SSH into the EC2 Instance

This README uses **Windows CMD** by default.

Open CMD and go to the folder where your `.pem` key is saved.

For example, if your key is in the Downloads folder:

```cmd
cd %USERPROFILE%\Downloads
```

Use the following command format:

```cmd
ssh -i [KEY_FILE].pem ubuntu@[EC2_PUBLIC_IP]
```

Example:

```cmd
ssh -i aws-clash-key.pem ubuntu@13.232.43.141
```

For Ubuntu AMI, the default username is usually:

```text
ubuntu
```

---

## 4. One-line Installation

Run this command on the EC2 instance:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/aws-ss-clash/main/clash_ss.sh | sudo bash
```

---

## 5. Custom Port

The default port is:

```text
8388
```

To use another port, for example `443`, run:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/aws-ss-clash/main/clash_ss.sh | sudo PORT=443 bash
```

If you use a custom port, remember to update the AWS Security Group:

| Type | Protocol | Port | Source |
|---|---|---:|---|
| Custom TCP | TCP | 443 | 0.0.0.0/0 |
| Custom UDP | UDP | 443 | 0.0.0.0/0 |

---

## 6. Custom Cipher Method

The default cipher is:

```text
aes-256-gcm
```

To specify another method, for example `aes-128-gcm`, run:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/aws-ss-clash/main/clash_ss.sh | sudo METHOD=aes-128-gcm bash
```

Recommended method:

```text
aes-256-gcm
```

---

## 7. Generated Files

After installation, the script creates:

```text
/opt/aws-clash-ss/server-info.txt
/opt/aws-clash-ss/clash.yaml
```

View server information:

```bash
sudo cat /opt/aws-clash-ss/server-info.txt
```

View Clash configuration:

```bash
sudo cat /opt/aws-clash-ss/clash.yaml
```

---

## 8. Generated Client Configuration

After installation, the script generates two types of client configuration:

1. A Shadowsocks `URL` link for any clients.
2. A Clash YAML configuration file for Clash-compatible clients.

---

### 8.1 Shadowsocks URL

The script generates a standard Shadowsocks URL.

This is the easiest option for mobile clients such as:

- Android: Surfboard
- iOS: Shadowrocket

The URL is printed at the end of the installation output:

```text
URL link:
ss://...
```

It is also saved on the EC2 instance:

```text
/opt/aws-clash-ss/ss-uri.txt
```

View the URL on the EC2 instance:

```bash
sudo cat /opt/aws-clash-ss/ss-uri.txt
```

Download it to your local Windows Downloads folder using CMD:

```cmd
scp -i %USERPROFILE%\Downloads\[KEY_FILE].pem ubuntu@[EC2_PUBLIC_IP]:/opt/aws-clash-ss/ss-uri.txt %USERPROFILE%\Downloads\ss-uri.txt
```

Example:

```cmd
scp -i %USERPROFILE%\Downloads\aws-clash-key.pem ubuntu@13.232.43.141:/opt/aws-clash-ss/ss-uri.txt %USERPROFILE%\Downloads\ss-uri.txt
```

If your mobile client supports importing from clipboard, you can simply copy the `ss://` URL and paste it into the app.

If your mobile client does not support URL import, add a Shadowsocks server manually using the following fields:

```text
Type: Shadowsocks
Server: YOUR_EC2_PUBLIC_IP
Port: 8388
Method / Cipher: aes-256-gcm
Password: YOUR_GENERATED_PASSWORD
UDP: Enable
```

---

### 8.2 Clash YAML Configuration

The script also generates a Clash-compatible YAML configuration file.

The file is saved on the EC2 instance:

```text
/opt/aws-clash-ss/clash.yaml
```

View the Clash configuration:

```bash
sudo cat /opt/aws-clash-ss/clash.yaml
```

The generated Clash configuration looks like this:

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

```text
GLOBAL → AWS-SS
```

Enable system proxy or TUN mode in Clash.

---

## 9. Download Clash Config to Local Computer

The generated Clash config is saved on the EC2 instance:

```text
/opt/aws-clash-ss/clash.yaml
```

On your local Windows CMD, download it to the Downloads folder using `scp`:

```cmd
scp -i %USERPROFILE%\Downloads\[KEY_FILE].pem ubuntu@[EC2_PUBLIC_IP]:/opt/aws-clash-ss/clash.yaml %USERPROFILE%\Downloads\aws-clash.yaml
```

Example:

```cmd
scp -i %USERPROFILE%\Downloads\aws-clash-key.pem ubuntu@13.232.43.141:/opt/aws-clash-ss/clash.yaml %USERPROFILE%\Downloads\aws-clash.yaml
```

If you are already inside the Downloads folder, you can also use:

```cmd
scp -i [KEY_FILE].pem ubuntu@[EC2_PUBLIC_IP]:/opt/aws-clash-ss/clash.yaml aws-clash.yaml
```

Example:

```cmd
scp -i aws-clash-key.pem ubuntu@13.232.43.141:/opt/aws-clash-ss/clash.yaml aws-clash.yaml
```

Then import this file into Clash:

```text
Downloads\aws-clash.yaml
```

---

## 10. Check Docker Status

Check whether the Shadowsocks container is running:

```bash
sudo docker ps
```

Expected output should include something like:

```text
0.0.0.0:8388->8388/tcp
0.0.0.0:8388->8388/udp
```

Check Shadowsocks logs:

```bash
sudo docker logs ss-server
```

Expected logs should include:

```text
initializing ciphers... aes-256-gcm
tcp server listening at 0.0.0.0:8388
udp server listening at 0.0.0.0:8388
```

---

## 11. Test Port Connectivity

This README uses **Windows CMD** by default. CMD does not include `Test-NetConnection`.

To test the port from CMD, run PowerShell through CMD:

```cmd
powershell -Command "Test-NetConnection [EC2_PUBLIC_IP] -Port 8388"
```

Example:

```cmd
powershell -Command "Test-NetConnection 13.232.43.141 -Port 8388"
```

If the result shows:

```text
TcpTestSucceeded : True
```

the port is reachable.

If it shows:

```text
TcpTestSucceeded : False
```

check the following:

1. EC2 Public IPv4 is correct.
2. Security Group allows TCP 8388.
3. Docker container is running.
4. Clash uses the same port as the server.

---

## 12. Useful Commands

View Clash config:

```bash
sudo cat /opt/aws-clash-ss/clash.yaml
```

View server information:

```bash
sudo cat /opt/aws-clash-ss/server-info.txt
```

View running containers:

```bash
sudo docker ps
```

View Shadowsocks logs:

```bash
sudo docker logs ss-server
```

Restart Shadowsocks:

```bash
sudo docker restart ss-server
```

Stop Shadowsocks:

```bash
sudo docker stop ss-server
```

Remove Shadowsocks container:

```bash
sudo docker rm ss-server
```

---

## 13. Regenerate Password and Config

The script generates a new password every time it runs.

To regenerate the password and Clash configuration, run:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/aws-ss-clash/main/clash_ss.sh | sudo bash
```

Then download or copy the new Clash configuration again.

---

## 14. EC2 Public IP Change

If your EC2 instance uses an auto-assigned public IP, the Public IPv4 address may change after stopping and starting the instance.

If Clash suddenly stops working, check:

```text
EC2 → Instances → Public IPv4 address
```

If the IP has changed, update the `server` field in Clash:

```yaml
server: YOUR_NEW_EC2_PUBLIC_IP
```

To avoid this issue, you can bind an Elastic IP to the EC2 instance.

---

## 15. Troubleshooting

### 15.1 Clash Shows Timeout

Run this from Windows CMD:

```cmd
powershell -Command "Test-NetConnection [EC2_PUBLIC_IP] -Port 8388"
```

If `TcpTestSucceeded` is `False`, common causes are:

- Security Group does not allow TCP 8388.
- EC2 Public IP is wrong.
- Docker container is not running.
- The port in Clash does not match the server port.

---

### 15.2 Port Is Reachable but Clash Still Fails

Check whether these fields match the generated `clash.yaml`:

```yaml
server: YOUR_EC2_PUBLIC_IP
port: 8388
cipher: aes-256-gcm
password: "YOUR_PASSWORD"
```

Common issues:

- Password was typed incorrectly.
- Wrong cipher method.
- Old Clash config was not saved or reloaded.
- EC2 public IP changed.

---

### 15.3 Docker Logs Show the Wrong Port

Run:

```bash
sudo docker ps
```

Expected mapping:

```text
0.0.0.0:8388->8388/tcp
0.0.0.0:8388->8388/udp
```

If the mapping is different, rerun the script.

---

### 15.4 SSH Cannot Connect

Check the Security Group rule for SSH:

```text
TCP 22 Your IP
```

If your public IP changes, update the SSH rule to `My IP`.

For temporary testing only, you can use:

```text
TCP 22 0.0.0.0/0
```

Do not keep SSH open to `0.0.0.0/0` permanently.

---

## 16. Uninstall

Stop and remove the Shadowsocks container:

```bash
sudo docker stop ss-server
sudo docker rm ss-server
```

Remove generated files:

```bash
sudo rm -rf /opt/aws-clash-ss
```

If you no longer need the EC2 instance, stop or terminate it from the AWS console to avoid ongoing charges.

---

## 17. Security Notes

Do not upload the following files to GitHub:
- AWS SSH private key
- Shadowsocks password
- Server IP
- Proxy configuration

---

## 18. License

This project is released under the MIT License.

---

# 中文说明

AWS EC2 一键部署 Shadowsocks，并自动生成 Clash 配置文件和手机端 URL 链接。

本项目用于在 AWS EC2 Ubuntu 服务器上一键部署 Shadowsocks 服务端，并自动生成 Clash 可导入的 YAML 配置文件，以及用于一键导入的 Shadowsocks URL 链接。

## 默认配置

- 服务器：AWS EC2
- 系统：Ubuntu 24.04
- 协议：Shadowsocks
- 端口：8388
- 加密方式：aes-256-gcm
- 客户端：Clash / Clash Verge / Clash for Windows / Clash Meta
- Docker 镜像：`shadowsocks/shadowsocks-libev`

> 请仅用于合法、合规的网络访问。AWS EC2 和流量可能产生费用，请注意账单。

---

## 1. 功能

该脚本会自动完成以下操作：

1. 更新 Ubuntu 软件包列表。
2. 安装 Docker。
3. 启动并启用 Docker 服务。
4. 自动生成 Shadowsocks 随机密码。
5. 如果旧的 Shadowsocks 容器存在，则自动删除。
6. 创建新的 Shadowsocks Docker 容器。
7. 自动生成 Clash 配置文件。
8. 输出服务器信息和 Clash 配置。

最终流量路径：

```text
Clash → EC2 Public IP:8388 → Docker Container:8388 → Shadowsocks Server
```

---

## 2. AWS EC2 准备

### 2.1 登录 AWS

进入 AWS 控制台。

在搜索栏中搜索：

```text
EC2
```

打开 EC2 服务后，点击：

```text
Launch instance
```

---

### 2.2 选择服务器系统

推荐系统镜像：

```text
Ubuntu Server 24.04 LTS
```

不建议选择 Windows，因为 Windows Server 成本更高，也不适合运行这种轻量级代理服务。

---

### 2.3 选择实例类型

如果只是个人使用，推荐：

```text
t3.micro
```

如果你想使用更便宜的 ARM 架构实例，可以选择：

```text
t4g.micro
```

### 2.4 创建 Key Pair

在 **Key pair** 部分选择：

```text
Create new key pair
```

示例名称：

```text
aws-clash-key
```

密钥类型：

```text
RSA
```

私钥文件格式：

```text
.pem
```

然后下载该私钥文件。

你会得到类似这样的文件：

```text
aws-clash-key.pem
```

这个文件非常重要，之后 SSH 登录 EC2 服务器需要用到它。

---

### 2.5 配置安全组

在 EC2 Security Group 的 Inbound rules 中添加：

| Type | Protocol | Port | Source |
|---|---|---:|---|
| SSH | TCP | 22 | 你的 IP |
| Custom TCP | TCP | 8388 | 0.0.0.0/0 |
| Custom UDP | UDP | 8388 | 0.0.0.0/0 |

说明：

- `22` 端口用于 SSH 登录服务器，建议只允许你自己的 IP 访问。
- `8388` 端口用于 Clash 连接 Shadowsocks 服务端。
- 如果你使用其他端口，例如 `443`，请同步修改安全组规则。

---

### 2.6 启动实例

检查 AMI、实例类型、Key Pair、存储和安全组设置无误后，点击：

```text
Launch instance
```

等待实例状态变成：

```text
Running
```

然后复制实例的公网 IP：

```text
Public IPv4 address
```

这个 IP 地址后面会用于 SSH 登录和 Clash 配置。

---

## 3. SSH 登录 EC2 实例

本说明默认使用 **Windows CMD**。

打开 CMD，并进入 `.pem` 私钥文件所在的文件夹。

例如，如果你的私钥文件在 Downloads 文件夹：

```cmd
cd %USERPROFILE%\Downloads
```

使用下面的命令格式：

```cmd
ssh -i [KEY_FILE].pem ubuntu@[EC2_PUBLIC_IP]
```

示例：

```cmd
ssh -i aws-clash-key.pem ubuntu@13.232.43.141
```

对于 Ubuntu AMI，默认用户名通常是：

```text
ubuntu
```

---

## 4. 一键安装

在 EC2 服务器中运行：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/aws-ss-clash/main/clash_ss.sh | sudo bash
```

---

## 5. 自定义端口

默认端口是：

```text
8388
```

如果想使用其他端口，例如 `443`，可以运行：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/aws-ss-clash/main/clash_ss.sh | sudo PORT=443 bash
```

如果使用自定义端口，请同时修改 AWS Security Group：

| Type | Protocol | Port | Source |
|---|---|---:|---|
| Custom TCP | TCP | 443 | 0.0.0.0/0 |
| Custom UDP | UDP | 443 | 0.0.0.0/0 |

---

## 6. 自定义加密方式

默认加密方式是：

```text
aes-256-gcm
```

如果想指定其他加密方式，例如 `aes-128-gcm`，可以运行：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/aws-ss-clash/main/clash_ss.sh | sudo METHOD=aes-128-gcm bash
```

推荐使用：

```text
aes-256-gcm
```

---

## 7. 生成的文件

安装完成后，脚本会生成：

```text
/opt/aws-clash-ss/server-info.txt
/opt/aws-clash-ss/clash.yaml
```

查看服务器信息：

```bash
sudo cat /opt/aws-clash-ss/server-info.txt
```

查看 Clash 配置：

```bash
sudo cat /opt/aws-clash-ss/clash.yaml
```

---

## 8. 生成的客户端配置

安装完成后，脚本会生成两种客户端配置：

1. 适合所有客户端的 URL 链接。
2. 适合 Clash 类客户端的 YAML 配置文件。

---

### 8.1 Shadowsocks URL 链接

脚本会生成一个标准的 Shadowsocks URL 链接。

这个链接适合所有客户端，例如：

- Android: Surfboard
- iOS: Shadowrocket

`URL` 链接会在安装完成后的终端输出中显示：

```text
URL link:
ss://...
```

同时也会保存到 EC2 服务器上：

```text
/opt/aws-clash-ss/ss-uri.txt
```

在 EC2 服务器上查看该链接：

```bash
sudo cat /opt/aws-clash-ss/ss-uri.txt
```

使用 Windows CMD 下载到本机 Downloads 文件夹：

```cmd
scp -i %USERPROFILE%\Downloads\[KEY_FILE].pem ubuntu@[EC2_PUBLIC_IP]:/opt/aws-clash-ss/ss-uri.txt %USERPROFILE%\Downloads\ss-uri.txt
```

示例：

```cmd
scp -i %USERPROFILE%\Downloads\aws-clash-key.pem ubuntu@13.232.43.141:/opt/aws-clash-ss/ss-uri.txt %USERPROFILE%\Downloads\ss-uri.txt
```

如果手机端客户端支持从剪贴板导入，可以直接复制 `URL` 链接并粘贴到 App 中。

如果手机端客户端不支持直接导入 `URL`，也可以手动添加 Shadowsocks 节点：

```text
Type: Shadowsocks
Server: YOUR_EC2_PUBLIC_IP
Port: 8388
Method / Cipher: aes-256-gcm
Password: YOUR_GENERATED_PASSWORD
UDP: Enable
```

---

### 8.2 Clash YAML 配置文件

脚本也会生成一个 Clash 兼容的 YAML 配置文件。

该文件保存在 EC2 服务器上：

```text
/opt/aws-clash-ss/clash.yaml
```

查看 Clash 配置文件：

```bash
sudo cat /opt/aws-clash-ss/clash.yaml
```

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

将生成的 `clash.yaml` 导入 Clash，然后选择：

```text
GLOBAL → AWS-SS
```

在 Clash 中开启系统代理或 TUN 模式。

---

## 9. 下载 Clash 配置到本机

生成的 Clash 配置保存在 EC2 服务器上：

```text
/opt/aws-clash-ss/clash.yaml
```

在本地 Windows CMD 中，可以使用 `scp` 下载到 Downloads 文件夹：

```cmd
scp -i %USERPROFILE%\Downloads\[KEY_FILE].pem ubuntu@[EC2_PUBLIC_IP]:/opt/aws-clash-ss/clash.yaml %USERPROFILE%\Downloads\aws-clash.yaml
```

示例：

```cmd
scp -i %USERPROFILE%\Downloads\aws-clash-key.pem ubuntu@13.232.43.141:/opt/aws-clash-ss/clash.yaml %USERPROFILE%\Downloads\aws-clash.yaml
```

如果你当前已经在 Downloads 文件夹，也可以使用：

```cmd
scp -i [KEY_FILE].pem ubuntu@[EC2_PUBLIC_IP]:/opt/aws-clash-ss/clash.yaml aws-clash.yaml
```

示例：

```cmd
scp -i aws-clash-key.pem ubuntu@13.232.43.141:/opt/aws-clash-ss/clash.yaml aws-clash.yaml
```

然后在 Clash 中导入这个文件：

```text
Downloads\aws-clash.yaml
```

---

## 10. 检查 Docker 状态

检查 Shadowsocks 容器是否正在运行：

```bash
sudo docker ps
```

正常输出中应该包含类似内容：

```text
0.0.0.0:8388->8388/tcp
0.0.0.0:8388->8388/udp
```

查看 Shadowsocks 日志：

```bash
sudo docker logs ss-server
```

正常日志中应该包含：

```text
initializing ciphers... aes-256-gcm
tcp server listening at 0.0.0.0:8388
udp server listening at 0.0.0.0:8388
```

---

## 11. 测试端口连通性

本说明默认使用 **Windows CMD**。CMD 本身没有 `Test-NetConnection` 命令。

如果想从 CMD 测试端口，可以在 CMD 中调用 PowerShell：

```cmd
powershell -Command "Test-NetConnection [EC2_PUBLIC_IP] -Port 8388"
```

示例：

```cmd
powershell -Command "Test-NetConnection 13.232.43.141 -Port 8388"
```

如果结果显示：

```text
TcpTestSucceeded : True
```

说明端口可以访问。

如果显示：

```text
TcpTestSucceeded : False
```

请检查以下内容：

1. EC2 Public IPv4 是否正确。
2. Security Group 是否允许 TCP 8388。
3. Docker 容器是否正在运行。
4. Clash 中填写的端口是否和服务器一致。

---

## 12. 常用命令

查看 Clash 配置：

```bash
sudo cat /opt/aws-clash-ss/clash.yaml
```

查看服务器信息：

```bash
sudo cat /opt/aws-clash-ss/server-info.txt
```

查看正在运行的容器：

```bash
sudo docker ps
```

查看 Shadowsocks 日志：

```bash
sudo docker logs ss-server
```

重启 Shadowsocks：

```bash
sudo docker restart ss-server
```

停止 Shadowsocks：

```bash
sudo docker stop ss-server
```

删除 Shadowsocks 容器：

```bash
sudo docker rm ss-server
```

---

## 13. 重新生成密码和配置

脚本每次运行都会生成一个新密码。

如果想重新生成密码和 Clash 配置，可以运行：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/aws-ss-clash/main/clash_ss.sh | sudo bash
```

然后重新下载或复制新的 Clash 配置。

---

## 14. EC2 公网 IP 变化

如果你的 EC2 使用 Auto-assigned public IP，那么实例 Stop 再 Start 后，Public IPv4 可能会改变。

如果 Clash 突然无法连接，优先检查：

```text
EC2 → Instances → Public IPv4 address
```

如果 IP 已经变化，请更新 Clash 配置中的 `server` 字段：

```yaml
server: YOUR_NEW_EC2_PUBLIC_IP
```

如果想避免 IP 改变，可以给 EC2 绑定 Elastic IP。

---

## 15. 常见问题排查

### 15.1 Clash 显示 Timeout

在 Windows CMD 中运行：

```cmd
powershell -Command "Test-NetConnection [EC2_PUBLIC_IP] -Port 8388"
```

如果 `TcpTestSucceeded` 是 `False`，常见原因包括：

- Security Group 没有开放 TCP 8388。
- EC2 Public IP 写错。
- Docker 容器没有运行。
- Clash 中的端口和服务器端口不一致。

---

### 15.2 端口可达但 Clash 仍然失败

检查下面这些字段是否和生成的 `clash.yaml` 完全一致：

```yaml
server: YOUR_EC2_PUBLIC_IP
port: 8388
cipher: aes-256-gcm
password: "YOUR_PASSWORD"
```

常见问题：

- 密码输入错误。
- 加密方式错误。
- Clash 旧配置没有保存或重新加载。
- EC2 公网 IP 已变化。

---

### 15.3 Docker 日志显示端口不对

运行：

```bash
sudo docker ps
```

正常映射应为：

```text
0.0.0.0:8388->8388/tcp
0.0.0.0:8388->8388/udp
```

如果映射不同，建议重新运行脚本。

---

### 15.4 SSH 无法连接

检查 Security Group 中的 SSH 规则：

```text
TCP 22 Your IP
```

如果你的公网 IP 改变了，需要把 SSH 规则重新设置为 `My IP`。

仅在临时测试时，可以使用：

```text
TCP 22 0.0.0.0/0
```

不要长期把 SSH 开放给 `0.0.0.0/0`。

---

## 16. 卸载

停止并删除 Shadowsocks 容器：

```bash
sudo docker stop ss-server
sudo docker rm ss-server
```

删除生成的文件：

```bash
sudo rm -rf /opt/aws-clash-ss
```

如果不再需要该 EC2 实例，请在 AWS 控制台中 Stop 或 Terminate，避免继续产生费用。

---

## 17. 安全提醒

请不要把以下文件上传到 GitHub：
- AWS SSH 私钥
- Shadowsocks 密码
- 服务器 IP
- 代理配置

---

## 18. 开源协议

本项目使用 MIT License 开源。
