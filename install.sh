#!/bin/bash

# =========================================================
# StarBot + NapCat 管理面板 
# 功能：一键安装、管理、配置、删除容器
# =========================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
PLAIN='\033[0m'

# 配置文件路径
CONFIG_FILE="/etc/starbot-manager.conf"
LOG_FILE="/var/log/starbot-manager.log"

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误：必须使用 root 用户运行此脚本！${PLAIN}"
   exit 1
fi

# 验证安装状态
verify_installation() {
    if [[ ! -d "$BASE_DIR" ]]; then
        echo -e "${RED}错误：未找到安装目录 ${BASE_DIR}${PLAIN}"
        echo -e "${YELLOW}请先完成安装，然后再进行管理操作${PLAIN}"
        return 1
    fi
    
    if [[ ! -f "${BASE_DIR}/docker-compose.yml" ]]; then
        echo -e "${RED}错误：未找到 docker-compose.yml 配置文件${PLAIN}"
        echo -e "${YELLOW}安装可能不完整，请重新安装${PLAIN}"
        return 1
    fi
    
    return 0
}

# 路径规范化函数
normalize_path() {
    local path="$1"
    # 替换多个斜杠为单个，移除末尾斜杠
    echo "$path" | sed 's|//*|/|g' | sed 's|/$||'
}

# 初始化配置文件
init_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        mkdir -p "$(dirname "$CONFIG_FILE")"
        # 获取当前目录作为默认安装路径
        CURRENT_DIR=$(pwd)
        CURRENT_DIR=${CURRENT_DIR%/}  # 移除末尾的斜杠
        cat > "$CONFIG_FILE" <<EOF
# StarBot 管理面板配置文件
BASE_DIR="${CURRENT_DIR}/starbot"
QQ_NUMBER=""
NAPCAT_PORT=6102
STARBOT_PORT=7828
WEB_CONFIG_PORT=5000
DOCKER_MIRROR="auto"
INSTALL_DIR="./starbot"
EOF
    fi
    source "$CONFIG_FILE"
    
    # 规范化已有的 BASE_DIR
    if [[ -n "$BASE_DIR" ]]; then
        BASE_DIR=$(normalize_path "$BASE_DIR")
    fi
}

# 保存配置
save_config() {
    cat > "$CONFIG_FILE" <<EOF
# StarBot 管理面板配置文件
BASE_DIR="$BASE_DIR"
QQ_NUMBER="$QQ_NUMBER"
NAPCAT_PORT=$NAPCAT_PORT
STARBOT_PORT=$STARBOT_PORT
WEB_CONFIG_PORT=$WEB_CONFIG_PORT
DOCKER_MIRROR="$DOCKER_MIRROR"
INSTALL_DIR="$INSTALL_DIR"
EOF
}

# 日志记录
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 检测系统环境
detect_system() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_NAME=$ID
        OS_VERSION=$VERSION_ID
    elif [[ -f /etc/lsb-release ]]; then
        . /etc/lsb-release
        OS_NAME=$DISTRIB_ID
        OS_VERSION=$DISTRIB_RELEASE
    else
        OS_NAME=$(uname -s)
        OS_VERSION=$(uname -r)
    fi
    
    echo -e "${BLUE}检测到系统: $OS_NAME $OS_VERSION${PLAIN}"
    
    # 检测网络连接
    if ping -c 2 www.baidu.com &> /dev/null; then
        NETWORK_STATUS="online"
        echo -e "${GREEN}网络连接正常${PLAIN}"
    else
        NETWORK_STATUS="offline"
        echo -e "${YELLOW}警告：网络连接异常，可能影响安装${PLAIN}"
    fi
}

# 检查并安装 Docker
check_docker() {
    log "检查 Docker 环境..."
    
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}检测到未安装 Docker，准备开始安装...${PLAIN}"
        
        # 检测是否使用国内镜像
        if [[ "$DOCKER_MIRROR" == "auto" ]]; then
            if ping -c 2 www.baidu.com &> /dev/null; then
                echo -e "${CYAN}检测到国内网络环境，使用阿里云镜像安装...${PLAIN}"
                curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
            else
                echo -e "${CYAN}使用官方源安装 Docker...${PLAIN}"
                curl -fsSL https://get.docker.com | sh
            fi
        elif [[ "$DOCKER_MIRROR" == "Aliyun" ]]; then
            echo -e "${CYAN}使用阿里云镜像安装 Docker...${PLAIN}"
            curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
        elif [[ "$DOCKER_MIRROR" == "AzureChinaCloud" ]]; then
            echo -e "${CYAN}使用 Azure 中国镜像安装 Docker...${PLAIN}"
            curl -fsSL https://get.docker.com | bash -s docker --mirror AzureChinaCloud
        else
            echo -e "${CYAN}使用官方源安装 Docker...${PLAIN}"
            curl -fsSL https://get.docker.com | sh
        fi
        
        systemctl enable docker
        systemctl start docker
        log "Docker 安装完成！"
        echo -e "${GREEN}Docker 安装完成！${PLAIN}"
    else
        echo -e "${GREEN}Docker 已安装，版本: $(docker --version)${PLAIN}"
    fi

    # 检查 Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        echo -e "${YELLOW}正在安装 Docker Compose 插件...${PLAIN}"
        if [[ "$OS_NAME" == "ubuntu" || "$OS_NAME" == "debian" ]]; then
            apt-get update && apt-get install -y docker-compose-plugin
        elif [[ "$OS_NAME" == "centos" || "$OS_NAME" == "rhel" || "$OS_NAME" == "fedora" ]]; then
            yum install -y docker-compose-plugin
        fi
        log "Docker Compose 安装完成！"
        echo -e "${GREEN}Docker Compose 安装完成！${PLAIN}"
    else
        echo -e "${GREEN}Docker Compose 已安装，版本: $(docker compose version --short 2>/dev/null || echo 'unknown')${PLAIN}"
    fi
}

# 配置安装参数
configure_installation() {
    clear
    echo -e "${MAGENTA}=========================================${PLAIN}"
    echo -e "${MAGENTA}      StarBot + NapCat 安装配置          ${PLAIN}"
    echo -e "${MAGENTA}=========================================${PLAIN}"
    
    # 自定义 Docker 镜像源
    echo -e "${CYAN}Docker 镜像源设置:${PLAIN}"
    echo "1. 自动检测 (推荐)"
    echo "2. 阿里云镜像"
    echo "3. Azure 中国镜像"
    echo "4. 官方源"
    read -p "请选择镜像源 [1-4]: " mirror_choice
    case $mirror_choice in
        1) DOCKER_MIRROR="auto" ;;
        2) DOCKER_MIRROR="Aliyun" ;;
        3) DOCKER_MIRROR="AzureChinaCloud" ;;
        4) DOCKER_MIRROR="official" ;;
        *) DOCKER_MIRROR="auto" ;;
    esac
    
    # 安装目录
    echo -e "\n${CYAN}安装目录设置:${PLAIN}"
    read -p "请输入安装目录 (默认: ./starbot): " INSTALL_DIR
    INSTALL_DIR=${INSTALL_DIR:-"./starbot"}
    
    # 规范化路径处理，避免双斜杠问题
    if [[ "$INSTALL_DIR" == "./starbot" ]]; then
        # 获取当前目录并确保不以斜杠结尾
        CURRENT_DIR=$(pwd)
        CURRENT_DIR=${CURRENT_DIR%/}  # 移除末尾的斜杠
        BASE_DIR="${CURRENT_DIR}/starbot"
    elif [[ "$INSTALL_DIR" =~ ^/ ]]; then
        # 绝对路径
        BASE_DIR=$(echo "$INSTALL_DIR" | sed 's|//*|/|g' | sed 's|/$||')
    else
        # 相对路径
        CURRENT_DIR=$(pwd)
        CURRENT_DIR=${CURRENT_DIR%/}
        BASE_DIR="${CURRENT_DIR}/${INSTALL_DIR}"
        BASE_DIR=$(echo "$BASE_DIR" | sed 's|//*|/|g' | sed 's|/$||')
    fi
    
    # 检测目录是否存在
    if [ -d "$BASE_DIR" ]; then
        echo -e "${YELLOW}警告：目录已存在: $BASE_DIR${PLAIN}"
        echo "1. 覆盖现有配置 (保留数据)"
        echo "2. 重新选择目录"
        echo "3. 退出安装"
        read -p "请选择操作 [1-3]: " dir_choice
        case $dir_choice in
            1) echo -e "${YELLOW}将覆盖现有配置文件...${PLAIN}" ;;
            2) configure_installation; return ;;
            3) exit 0 ;;
            *) echo -e "${YELLOW}默认覆盖现有配置...${PLAIN}" ;;
        esac
    fi
    
    # 配置参数
    echo -e "\n${CYAN}基础配置:${PLAIN}"
    while true; do
        read -p "请输入机器人QQ号 (必填): " QQ_NUMBER
        if [[ -n "$QQ_NUMBER" ]]; then break; else echo -e "${RED}QQ号不能为空！${PLAIN}"; fi
    done
    
    read -p "请输入 NapCat 端口 (默认: 6102): " NAPCAT_PORT
    NAPCAT_PORT=${NAPCAT_PORT:-6102}
    
    read -p "请输入 StarBot 端口 (默认: 7828): " STARBOT_PORT
    STARBOT_PORT=${STARBOT_PORT:-7828}
    
    read -p "请输入 Web 配置面板端口 (默认: 5000): " WEB_CONFIG_PORT
    WEB_CONFIG_PORT=${WEB_CONFIG_PORT:-5000}
    
    # 保存配置
    save_config
    
    # 规范化路径显示
    echo -e "\n${GREEN}配置完成！${PLAIN}"
    echo -e "安装目录: $(normalize_path "$BASE_DIR")"
    echo -e "机器人QQ: $QQ_NUMBER"
    echo -e "NapCat端口: $NAPCAT_PORT"
    echo -e "StarBot端口: $STARBOT_PORT"
    echo -e "Web面板端口: $WEB_CONFIG_PORT"
    echo -e "Docker镜像源: $DOCKER_MIRROR"
    
    read -p "按回车键继续安装，或按Ctrl+C取消..."
}

# 生成 Docker Compose 文件
generate_compose_file() {
    mkdir -p "${BASE_DIR}/napcat/config"
    mkdir -p "${BASE_DIR}/napcat/ntqq"
    
    cat > "${BASE_DIR}/docker-compose.yml" <<EOF
services:
  starbot-webconfig:
    image: heiyub/starbot:3.0-beta7web
    container_name: starbot-webconfig
    restart: unless-stopped
    ports:
      - "${WEB_CONFIG_PORT}:5000"
    volumes:
      - "${BASE_DIR}:/starbot/"
    environment:
      TZ: "Asia/Shanghai"
    networks:
      - starbot_napcat
    depends_on:
      - starbot

  starbot:
    image: heiyub/starbot:3.0-beta7nc
    container_name: Starbot3.0-beta7nc
    restart: unless-stopped
    ports:
      - "${STARBOT_PORT}:7827"
    volumes:
      - "${BASE_DIR}:/app"
      - "${BASE_DIR}/napcat/config:/napcat_config"
    environment:
      SENDERS_QQ: ${QQ_NUMBER}
      TZ: "Asia/Shanghai"
    networks:
      - starbot_napcat

  napcat:
    image: mlikiowa/napcat-docker:latest
    container_name: napcat_starbot
    restart: unless-stopped
    ports:
      - "${NAPCAT_PORT}:6099" # 默认密码admin 请及时更改
    volumes:
      - "${BASE_DIR}/napcat/config:/app/napcat/config"
      - "${BASE_DIR}/napcat/ntqq:/app/.config/QQ"
    environment:
      TZ: "Asia/Shanghai"
    networks:
      - starbot_napcat
    depends_on:
      - starbot

networks:
  starbot_napcat:
    name: starbot_napcat
    driver: bridge
EOF

    echo -e "${GREEN}docker-compose.yml 文件已生成！${PLAIN}"
}

# 配置防火墙
configure_firewall() {
    echo -e "${YELLOW}正在配置防火墙开放端口...${PLAIN}"
    
    # 记录要开放的端口
    mkdir -p "$BASE_DIR"
    echo "$NAPCAT_PORT" > "${BASE_DIR}/opened_ports.txt"
    echo "$STARBOT_PORT" >> "${BASE_DIR}/opened_ports.txt"
    echo "$WEB_CONFIG_PORT" >> "${BASE_DIR}/opened_ports.txt"
    
    if systemctl is-active --quiet firewalld; then
        echo -e "${CYAN}检测到 firewalld 防火墙...${PLAIN}"
        firewall-cmd --zone=public --add-port=${NAPCAT_PORT}/tcp --permanent >/dev/null 2>&1
        firewall-cmd --zone=public --add-port=${STARBOT_PORT}/tcp --permanent >/dev/null 2>&1
        firewall-cmd --zone=public --add-port=${WEB_CONFIG_PORT}/tcp --permanent >/dev/null 2>&1
        firewall-cmd --reload
        echo -e "${GREEN}firewalld 防火墙配置完成！${PLAIN}"
    elif command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        echo -e "${CYAN}检测到 UFW 防火墙...${PLAIN}"
        ufw allow ${NAPCAT_PORT}/tcp >/dev/null 2>&1
        ufw allow ${STARBOT_PORT}/tcp >/dev/null 2>&1
        ufw allow ${WEB_CONFIG_PORT}/tcp >/dev/null 2>&1
        ufw reload
        echo -e "${GREEN}UFW 防火墙配置完成！${PLAIN}"
    else
        echo -e "${YELLOW}未检测到活跃的防火墙，跳过配置...${PLAIN}"
    fi
}

# 关闭防火墙端口
close_firewall_ports() {
    if [[ ! -d "$BASE_DIR" || ! -f "${BASE_DIR}/opened_ports.txt" ]]; then
        echo -e "${YELLOW}未找到开放的端口记录文件，跳过防火墙关闭操作${PLAIN}"
        return
    fi
    
    echo -e "${YELLOW}正在关闭之前开放的防火墙端口...${PLAIN}"
    
    while read port; do
        if systemctl is-active --quiet firewalld; then
            firewall-cmd --zone=public --remove-port=${port}/tcp --permanent >/dev/null 2>&1
        elif command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
            ufw delete allow ${port}/tcp >/dev/null 2>&1
        fi
    done < "${BASE_DIR}/opened_ports.txt"
    
    if systemctl is-active --quiet firewalld; then
        firewall-cmd --reload
    elif command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        ufw reload
    fi
    
    echo -e "${GREEN}防火墙端口已关闭！${PLAIN}"
}

# 启动容器（按顺序）
start_containers() {
    echo -e "${YELLOW}按顺序启动容器 (starbot -> napcat -> webconfig)...${PLAIN}"
    
    # 验证目录是否存在，不存在则创建
    mkdir -p "$BASE_DIR"
    cd "$BASE_DIR" || {
        echo -e "${RED}错误：无法进入目录 $BASE_DIR${PLAIN}"
        return 1
    }
    
    # 先启动 starbot
    docker compose up -d starbot
    echo -e "${CYAN}StarBot 容器已启动，等待15秒初始化...${PLAIN}"
    sleep 15
    
    # 启动 napcat
    docker compose up -d napcat
    echo -e "${CYAN}NapCat 容器已启动，等待8秒初始化...${PLAIN}"
    sleep 8
    
    # 启动 Web 配置面板
    docker compose up -d starbot-webconfig
    
    echo -e "${GREEN}所有容器已启动！${PLAIN}"
}

# 重启容器（按顺序）
restart_containers() {
    # 首先验证安装状态
    if ! verify_installation; then
        read -p "按回车键继续..."
        return 1
    fi
    
    echo -e "${YELLOW}按顺序重启容器 (starbot -> napcat -> webconfig)...${PLAIN}"
    
    # 停止所有容器
    cd "$BASE_DIR" || {
        echo -e "${RED}错误：无法进入目录 $BASE_DIR${PLAIN}"
        return 1
    }
    docker compose stop
    sleep 5
    
    # 按顺序启动
    start_containers
    
    echo -e "${GREEN}所有容器已重启！${PLAIN}"
}

# 显示配置链接
show_config_links() {
    if [[ ! -d "$BASE_DIR" ]]; then
        echo -e "${RED}未找到安装目录，请先完成安装！${PLAIN}"
        return
    fi
    
    # 获取服务器IP
    EXTERNAL_IP=$(curl -s https://api.ipify.org 2>/dev/null || echo "无法获取外网IP")
    INTERNAL_IP=$(hostname -I | awk '{print $1}' | head -n1)
    
    # 如果内网IP为空，尝试其他方法获取
    if [[ -z "$INTERNAL_IP" ]]; then
        INTERNAL_IP=$(ip addr show eth0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
        if [[ -z "$INTERNAL_IP" ]]; then
            INTERNAL_IP=$(ip addr show ens33 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
            if [[ -z "$INTERNAL_IP" ]]; then
                INTERNAL_IP="无法获取内网IP"
            fi
        fi
    fi
    
    echo -e "\n${MAGENTA}=========================================${PLAIN}"
    echo -e "${MAGENTA}            配置链接信息                ${PLAIN}"
    echo -e "${MAGENTA}=========================================${PLAIN}"
    
    echo -e "${CYAN}🌐 外网访问地址:${PLAIN}"
    echo -e "  Web 配置面板: http://$EXTERNAL_IP:$WEB_CONFIG_PORT ${YELLOW}(在线编辑配置文件)${PLAIN}"
    echo -e "  StarBot API: http://$EXTERNAL_IP:$STARBOT_PORT ${YELLOW}(StarBot API)${PLAIN}"
    echo -e "  NapCat 管理: http://$EXTERNAL_IP:$NAPCAT_PORT ${RED}(默认密码: admin)${PLAIN}"
    
    echo -e "\n${CYAN}🏠 内网访问地址:${PLAIN}"
    echo -e "  Web 配置面板: http://$INTERNAL_IP:$WEB_CONFIG_PORT"
    echo -e "  StarBot API: http://$INTERNAL_IP:$STARBOT_PORT"
    echo -e "  NapCat 管理: http://$INTERNAL_IP:$NAPCAT_PORT"
    
    # 读取 .url 文件中的内容作为配置链接
    URL_SUFFIX=""
    if [[ -f "${BASE_DIR}/.url" ]]; then
        URL_SUFFIX=$(cat "${BASE_DIR}/.url" | tr -d '[:space:]')
        echo -e "\n${CYAN}🔐 在线配置主播 链接:${PLAIN}"
        echo -e "  外网: http://$EXTERNAL_IP:$WEB_CONFIG_PORT/$URL_SUFFIX/"
        echo -e "  内网: http://$INTERNAL_IP:$WEB_CONFIG_PORT/$URL_SUFFIX/"
        
        echo -e "\n${CYAN}🔐 扫码登录B站 链接:${PLAIN}"
        echo -e "  外网: http://$EXTERNAL_IP:$STARBOT_PORT/bilibili/login/qrcode"
        echo -e "  内网: http://$INTERNAL_IP:$STARBOT_PORT/bilibili/login/qrcode"
    else
        echo -e "\n${YELLOW}⚠️ 警告：未找到 .url 文件，将使用默认访问方式${PLAIN}"
        echo -e "请在 ${BASE_DIR}/.url 文件中设置您的访问后缀"
    fi

    echo -e "\n${YELLOW}📌 注意事项:${PLAIN}"
    echo -e "1. 首次访问 NapCat 时，请使用默认密码 'admin' 登录并立即修改密码 ${RED}[危险]${PLAIN}"
    echo -e "2. Web 配置面板的链接请勿泄露，有链接谁都可以更改配置"
    echo -e "3. 登录QQ时必须使用配置的QQ，如若不是配置的QQ请重新配置或手动修改 StarBot/NapCat 配置"
    echo -e "4. 确保防火墙和服务商防火墙已开放相应端口，否则可能无法访问"
}

# 显示安装失败页面
show_install_failure() {
    clear
    echo -e "${RED}================================================${PLAIN}"
    echo -e "${RED}              安装失败！                      ${PLAIN}"
    echo -e "${RED}================================================${PLAIN}"
    echo -e "${YELLOW}未能检测到安装成功的标志文件 (.lock)${PLAIN}"
    echo -e "${YELLOW}可能的原因：${PLAIN}"
    echo -e "1. 网络连接不稳定，容器下载失败"
    echo -e "2. 服务器资源不足，容器无法正常启动"
    echo -e "3. Docker 配置问题"
    echo -e "4. 端口冲突"
    echo -e "\n${CYAN}建议解决方案：${PLAIN}"
    echo -e "1. 检查网络连接是否正常"
    echo -e "2. 查看容器日志: cd $(normalize_path "$BASE_DIR") && docker compose logs"
    echo -e "3. 重新运行安装脚本"
    echo -e "\n${MAGENTA}技术支持：${PLAIN}"
    echo -e "${GREEN}QQ群：799915082${PLAIN}"
    echo -e "请加入QQ群获取技术支持和帮助"
    echo -e "\n${YELLOW}按回车键返回主菜单...${PLAIN}"
    read
}

# 一键安装
install_starbot() {
    clear
    echo -e "${BLUE}=========================================${PLAIN}"
    echo -e "${BLUE}      一键安装 StarBot + NapCat          ${PLAIN}"
    echo -e "${BLUE}=========================================${PLAIN}"
    
    # 配置安装参数
    configure_installation
    
    # 检查 Docker
    check_docker
    
    # 创建目录
    echo -e "${YELLOW}正在创建目录结构...${PLAIN}"
    mkdir -p "$BASE_DIR"
    
    # 生成 docker-compose 文件
    generate_compose_file
    
    # 配置防火墙
    configure_firewall
    
    # 启动容器
    echo -e "${YELLOW}正在启动容器...${PLAIN}"
    start_containers
    
    # 显示配置链接
    echo -e "\n${YELLOW}安装完成！正在显示配置链接...${PLAIN}"
    sleep 2
    show_config_links
    
    # 延迟重启
    echo -e "\n${YELLOW}将在60秒后重启所有容器以完成初始化...${PLAIN}"
    echo -e "${CYAN}按 Ctrl+C 可跳过重启步骤${PLAIN}"
    for i in {60..1}; do
        echo -ne "\r剩余时间: ${i} 秒..."
        sleep 1
    done
    echo -e "\n${YELLOW}正在重启所有容器...${PLAIN}"
    restart_containers
    
    # 检查安装是否成功 - 检测 .lock 文件
    echo -e "\n${YELLOW}正在检查安装状态...${PLAIN}"
    sleep 5
    
    if [[ -f "${BASE_DIR}/.lock" ]]; then
        echo -e "\n${GREEN}=========================================${PLAIN}"
        echo -e "${GREEN}      安装完成！StarBot 已成功部署      ${PLAIN}"
        echo -e "${GREEN}=========================================${PLAIN}"
        echo -e "安装目录: $(normalize_path "$BASE_DIR")"
        echo -e "配置文件: ${BASE_DIR}/docker-compose.yml"
        echo -e "日志文件: ${BASE_DIR}/logs/"
        echo -e "\n${CYAN}常用管理命令:${PLAIN}"
        echo -e "  启动所有: cd $(normalize_path "$BASE_DIR") && docker compose up -d"
        echo -e "  停止所有: cd $(normalize_path "$BASE_DIR") && docker compose down"
        echo -e "  查看日志: cd $(normalize_path "$BASE_DIR") && docker compose logs -f"
        echo -e "\n${MAGENTA}提示: 您可以随时运行此脚本进行管理${PLAIN}"
    else
        echo -e "${RED}警告：未检测到 .lock 文件，安装可能未成功完成！${PLAIN}"
        echo -e "${YELLOW}等待10秒再次检查...${PLAIN}"
        sleep 10
        
        if [[ -f "${BASE_DIR}/.lock" ]]; then
            echo -e "\n${GREEN}=========================================${PLAIN}"
            echo -e "${GREEN}      安装完成！StarBot 已成功部署      ${PLAIN}"
            echo -e "${GREEN}=========================================${PLAIN}"
            echo -e "安装目录: $(normalize_path "$BASE_DIR")"
            echo -e "配置文件: ${BASE_DIR}/docker-compose.yml"
            echo -e "日志文件: ${BASE_DIR}/logs/"
            echo -e "\n${CYAN}常用管理命令:${PLAIN}"
            echo -e "  启动所有: cd $(normalize_path "$BASE_DIR") && docker compose up -d"
            echo -e "  停止所有: cd $(normalize_path "$BASE_DIR") && docker compose down"
            echo -e "  查看日志: cd $(normalize_path "$BASE_DIR") && docker compose logs -f"
            echo -e "\n${MAGENTA}提示: 您可以随时运行此脚本进行管理${PLAIN}"
        else
            # 显示安装失败页面
            show_install_failure
            return
        fi
    fi
    
    read -p "按回车键返回主菜单..."
}

# 重新配置
reconfigure() {
    if ! verify_installation; then
        read -p "按回车键继续..."
        return
    fi
    
    echo -e "${MAGENTA}=========================================${PLAIN}"
    echo -e "${MAGENTA}            重新配置参数                ${PLAIN}"
    echo -e "${MAGENTA}=========================================${PLAIN}"
    
    echo -e "${RED}警告：重新配置将删除现有容器并重新创建！${PLAIN}"
    echo -e "${YELLOW}配置数据将被保留，但容器状态会重置${PLAIN}"
    
    read -p "确认要重新配置吗？(y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo -e "${CYAN}操作已取消${PLAIN}"
        return
    fi
    
    # 保存当前工作目录
    ORIGINAL_DIR=$(pwd)
    
    # 删除 .lock 文件
    echo -e "${YELLOW}删除 .lock 文件...${PLAIN}"
    if [ -f "${BASE_DIR}/.lock" ]; then
        rm -f "${BASE_DIR}/.lock"
        echo -e "${GREEN}.lock 文件已删除${PLAIN}"
    else
        echo -e "${YELLOW}未找到 .lock 文件，继续执行...${PLAIN}"
    fi
    
    # 停止并删除现有容器
    echo -e "${YELLOW}停止并删除现有容器...${PLAIN}"
    cd "$BASE_DIR" || {
        echo -e "${RED}错误：无法进入目录 $BASE_DIR${PLAIN}"
        cd "$ORIGINAL_DIR" || true
        read -p "按回车键继续..."
        return 1
    }
    docker compose down
    
    # 重要修复：切换回原始目录，避免路径嵌套
    cd "$ORIGINAL_DIR" || {
        echo -e "${RED}错误：无法返回原始目录 $ORIGINAL_DIR${PLAIN}"
        read -p "按回车键继续..."
        return 1
    }
    
    # 重新配置
    configure_installation
    
    # 重新生成配置文件
    generate_compose_file
    
    # 重新配置防火墙
    close_firewall_ports
    configure_firewall
    
    # 重新启动
    start_containers
    
    # 延迟重启
    echo -e "\n${YELLOW}将在30秒后重启所有容器以完成初始化...${PLAIN}"
    echo -e "${CYAN}按 Ctrl+C 可跳过重启步骤${PLAIN}"
    for i in {30..1}; do
        echo -ne "\r剩余时间: ${i} 秒..."
        sleep 1
    done
    echo -e "\n${YELLOW}正在重启所有容器...${PLAIN}"
    restart_containers
    
    # 检查重新配置是否成功 - 检测 .lock 文件
    echo -e "\n${YELLOW}正在检查配置状态...${PLAIN}"
    sleep 5
    
    if [[ ! -f "${BASE_DIR}/.lock" ]]; then
        echo -e "${RED}警告：未检测到 .lock 文件，配置可能未成功完成！${PLAIN}"
        echo -e "${YELLOW}等待30秒再次检查...${PLAIN}"
        sleep 30
        
        if [[ ! -f "${BASE_DIR}/.lock" ]]; then
            echo -e "${RED}仍然未检测到 .lock 文件，配置可能失败！${PLAIN}"
            show_install_failure
            read -p "按回车键继续..."
            return
        fi
    fi
    
    echo -e "\n${GREEN}=========================================${PLAIN}"
    echo -e "${GREEN}      重新配置完成！StarBot 已成功配置      ${PLAIN}"
    echo -e "${GREEN}=========================================${PLAIN}"
    echo -e "安装目录: $(normalize_path "$BASE_DIR")"
    echo -e "配置文件: ${BASE_DIR}/docker-compose.yml"
    echo -e "\n${CYAN}常用管理命令:${PLAIN}"
    echo -e "  启动所有: cd $(normalize_path "$BASE_DIR") && docker compose up -d"
    echo -e "  停止所有: cd $(normalize_path "$BASE_DIR") && docker compose down"
    echo -e "  查看日志: cd $(normalize_path "$BASE_DIR") && docker compose logs -f"
    echo -e "\n${MAGENTA}提示: 您可以随时运行此脚本进行管理${PLAIN}"
    
    show_config_links
    read -p "按回车键返回主菜单..."
}

# 一键删除
uninstall_starbot() {
    if ! verify_installation; then
        read -p "按回车键继续..."
        return
    fi
    
    echo -e "${MAGENTA}=========================================${PLAIN}"
    echo -e "${MAGENTA}            一键卸载                    ${PLAIN}"
    echo -e "${MAGENTA}=========================================${PLAIN}"
    
    echo -e "${RED}警告：此操作将删除所有容器和相关配置！${PLAIN}"
    echo -e "安装目录: $(normalize_path "$BASE_DIR")"
    echo -e "1. 仅删除容器，保留数据文件"
    echo -e "2. 完全删除（包括数据文件）"
    echo -e "3. 取消操作"
    
    read -p "请选择操作 [1-3]: " choice
    
    case $choice in
        1)
            echo -e "${YELLOW}正在删除容器...${PLAIN}"
            cd "$BASE_DIR"
            docker compose down
            close_firewall_ports
            echo -e "${GREEN}容器已删除，数据文件保留在 $(normalize_path "$BASE_DIR")${PLAIN}"
            ;;
        2)
            echo -e "${RED}警告：这将永久删除所有数据！${PLAIN}"
            read -p "确认要完全删除吗？(y/n): " confirm
            if [[ "$confirm" == "y" ]]; then
                echo -e "${YELLOW}正在删除容器和数据...${PLAIN}"
                cd "$BASE_DIR" || {
                    echo -e "${RED}错误：无法进入目录 $BASE_DIR${PLAIN}"
                    read -p "按回车键继续..."
                    return
                }
                docker compose down
                close_firewall_ports
                cd ..
                rm -rf "$BASE_DIR"
                echo -e "${GREEN}已完全删除 StarBot + NapCat！${PLAIN}"
            else
                echo -e "${CYAN}操作已取消${PLAIN}"
            fi
            ;;
        3)
            echo -e "${CYAN}操作已取消${PLAIN}"
            ;;
        *)
            echo -e "${RED}无效选择${PLAIN}"
            ;;
    esac
    
    read -p "按回车键返回主菜单..."
}

# 容器管理菜单
container_management() {
    while true; do
        clear
        echo -e "${BLUE}=========================================${PLAIN}"
        echo -e "${BLUE}          容器管理菜单                  ${PLAIN}"
        echo -e "${BLUE}=========================================${PLAIN}"
        echo -e "1. 重启所有容器 (按顺序)"
        echo -e "2. 重启 StarBot 容器"
        echo -e "3. 重启 NapCat 容器" 
        echo -e "4. 重启 Web 配置面板"
        echo -e "5. 查看容器状态"
        echo -e "6. 查看日志"
        echo -e "0. 返回主菜单"
        
        read -p "请选择操作 [0-6]: " choice
        
        case $choice in
            1)
                restart_containers
                read -p "按回车键继续..."
                ;;
            2)
                if ! verify_installation; then
                    read -p "按回车键继续..."
                    continue
                fi
                cd "$BASE_DIR" || {
                    echo -e "${RED}错误：无法进入目录 $BASE_DIR${PLAIN}"
                    read -p "按回车键继续..."
                    continue
                }
                docker compose restart starbot
                echo -e "${GREEN}StarBot 容器已重启！${PLAIN}"
                read -p "按回车键继续..."
                ;;
            3)
                if ! verify_installation; then
                    read -p "按回车键继续..."
                    continue
                fi
                cd "$BASE_DIR" || {
                    echo -e "${RED}错误：无法进入目录 $BASE_DIR${PLAIN}"
                    read -p "按回车键继续..."
                    continue
                }
                docker compose restart napcat
                echo -e "${GREEN}NapCat 容器已重启！${PLAIN}"
                read -p "按回车键继续..."
                ;;
            4)
                if ! verify_installation; then
                    read -p "按回车键继续..."
                    continue
                fi
                cd "$BASE_DIR" || {
                    echo -e "${RED}错误：无法进入目录 $BASE_DIR${PLAIN}"
                    read -p "按回车键继续..."
                    continue
                }
                docker compose restart starbot-webconfig
                echo -e "${GREEN}Web 配置面板已重启！${PLAIN}"
                read -p "按回车键继续..."
                ;;
            5)
                if ! verify_installation; then
                    read -p "按回车键继续..."
                    continue
                fi
                cd "$BASE_DIR" || {
                    echo -e "${RED}错误：无法进入目录 $BASE_DIR${PLAIN}"
                    read -p "按回车键继续..."
                    continue
                }
                docker compose ps
                read -p "按回车键继续..."
                ;;
            6)
                if ! verify_installation; then
                    read -p "按回车键继续..."
                    continue
                fi
                cd "$BASE_DIR" || {
                    echo -e "${RED}错误：无法进入目录 $BASE_DIR${PLAIN}"
                    read -p "按回车键继续..."
                    continue
                }
                echo -e "${CYAN}查看哪个容器的日志?${PLAIN}"
                echo -e "1. StarBot"
                echo -e "2. NapCat"
                echo -e "3. Web 配置面板"
                echo -e "4. 所有容器"
                read -p "请选择 [1-4]: " log_choice
                
                case $log_choice in
                    1) docker compose logs -f --tail=100 starbot ;;
                    2) docker compose logs -f --tail=100 napcat ;;
                    3) docker compose logs -f --tail=100 starbot-webconfig ;;
                    4) docker compose logs -f --tail=100 ;;
                    *) echo -e "${RED}无效选择${PLAIN}" ;;
                esac
                
                echo -e "${YELLOW}按 Ctrl+C 退出日志查看${PLAIN}"
                read -p "按回车键继续..."
                ;;
            0)
                break
                ;;
            *)
                echo -e "${RED}无效选择，请重新输入${PLAIN}"
                sleep 2
                ;;
        esac
    done
}

# 防火墙管理菜单
firewall_management() {
    while true; do
        clear
        echo -e "${BLUE}=========================================${PLAIN}"
        echo -e "${BLUE}          防火墙管理菜单                ${PLAIN}"
        echo -e "${BLUE}=========================================${PLAIN}"
        echo -e "1. 开放所需端口"
        echo -e "2. 关闭已开放的端口"
        echo -e "3. 查看防火墙状态"
        echo -e "0. 返回主菜单"
        
        read -p "请选择操作 [0-3]: " choice
        
        case $choice in
            1)
                if [[ -z "$BASE_DIR" ]]; then
                    echo -e "${RED}错误：未设置安装目录，请先安装 StarBot${PLAIN}"
                    read -p "按回车键继续..."
                    continue
                fi
                configure_firewall
                read -p "按回车键继续..."
                ;;
            2)
                if [[ -z "$BASE_DIR" ]]; then
                    echo -e "${RED}错误：未设置安装目录，请先安装 StarBot${PLAIN}"
                    read -p "按回车键继续..."
                    continue
                fi
                close_firewall_ports
                read -p "按回车键继续..."
                ;;
            3)
                if systemctl is-active --quiet firewalld; then
                    echo -e "${CYAN}Firewalld 状态:${PLAIN}"
                    firewall-cmd --list-all
                elif command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
                    echo -e "${CYAN}UFW 状态:${PLAIN}"
                    ufw status verbose
                else
                    echo -e "${YELLOW}未检测到活跃的防火墙服务${PLAIN}"
                fi
                read -p "按回车键继续..."
                ;;
            0)
                break
                ;;
            *)
                echo -e "${RED}无效选择，请重新输入${PLAIN}"
                sleep 2
                ;;
        esac
    done
}

# 主菜单
main_menu() {
    while true; do
        clear
        echo -e "${GREEN}================================================${PLAIN}"
        echo -e "${GREEN}          StarBot + NapCat 管理面板            ${PLAIN}"
        echo -e "${GREEN}================================================${PLAIN}"
        echo -e "系统信息: $OS_NAME $OS_VERSION"
        echo -e "安装目录: ${BASE_DIR:-'未安装'}"
        echo -e "网络状态: ${NETWORK_STATUS:-'未知'}"
        echo -e "------------------------------------------------"
        echo -e "1. 一键安装 (Docker + 容器)"
        echo -e "2. 容器管理 (重启/查看状态)"
        echo -e "3. 重新配置参数"
        echo -e "4. 防火墙管理"
        echo -e "5. 显示配置链接"
        echo -e "6. 一键卸载"
        echo -e "0. 退出脚本"
        echo -e "------------------------------------------------"
        
        read -p "请选择操作 [0-6]: " choice
        
        case $choice in
            1)
                install_starbot
                ;;
            2)
                container_management
                ;;
            3)
                reconfigure
                read -p "按回车键返回主菜单..."
                ;;
            4)
                firewall_management
                ;;
            5)
                show_config_links
                read -p "按回车键返回主菜单..."
                ;;
            6)
                uninstall_starbot
                read -p "按回车键返回主菜单..."
                ;;
            0)
                echo -e "${GREEN}感谢使用 StarBot + NapCat 管理面板！${PLAIN}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选择，请重新输入${PLAIN}"
                sleep 2
                ;;
        esac
    done
}

# 初始化
init_config
detect_system
main_menu
