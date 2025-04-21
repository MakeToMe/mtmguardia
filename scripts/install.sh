#!/bin/bash

# Script de instalação do Guardian - Gerenciador de Firewall

# Mudar para um diretório seguro para evitar erros de diretório atual
cd /tmp

# Função para exibir mensagens de log
log() {
    echo "[GUARDIAN] $1"
}

# Solicitar string de conexão com o PostgreSQL
echo "Informe a string de conexão com o PostgreSQL:"
read -p "> " DB_CONN_STRING

# Salvar string de conexão em .env para uso futuro
INSTALL_DIR="/opt/guardian"
mkdir -p "$INSTALL_DIR/config"
echo "DB_CONN_STRING=\"$DB_CONN_STRING\"" > "$INSTALL_DIR/config/.env"

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Função para exibir mensagens
log() {
    echo -e "${GREEN}[GUARDIAN]${NC} $1"
}

error() {
    echo -e "${RED}[ERRO]${NC} $1"
    exit 1
}

warn() {
    echo -e "${YELLOW}[AVISO]${NC} $1"
}

# Verificar se está rodando como root
if [ "$(id -u)" -ne 0 ]; then
    error "Este script deve ser executado como root. Use: sudo bash install.sh"
fi

# Verificar se é um sistema Ubuntu
if [ ! -f /etc/lsb-release ] || ! grep -q "Ubuntu" /etc/lsb-release; then
    warn "Este script foi projetado para Ubuntu. A instalação pode não funcionar corretamente em outras distribuições."
fi

log "Iniciando instalação do Guardian - Gerenciador de Firewall"

# Detectar IP da máquina
IP=$(ip -4 addr show scope global | grep inet | awk '{print $2}' | cut -d/ -f1 | head -n 1)
if [ -z "$IP" ]; then
    error "Não foi possível detectar o IP da máquina"
fi

log "IP detectado: $IP"

# Checar e instalar dependências essenciais
NEED_UPDATE=0
if ! command -v git >/dev/null 2>&1; then
    log "git não encontrado. Instalando..."
    NEED_UPDATE=1
fi
if ! command -v go >/dev/null 2>&1; then
    log "golang não encontrado. Instalando..."
    NEED_UPDATE=1
fi
if ! command -v ufw >/dev/null 2>&1; then
    log "ufw não encontrado. Instalando..."
    NEED_UPDATE=1
fi
if ! command -v curl >/dev/null 2>&1; then
    log "curl não encontrado. Instalando..."
    NEED_UPDATE=1
fi
if [ "$NEED_UPDATE" -eq 1 ]; then
    apt-get update
    apt-get install -y git golang ufw curl
fi

# Checar e instalar Go >= 1.21.9 se necessário
GO_REQUIRED_MAJOR=1
GO_REQUIRED_MINOR=21
GO_REQUIRED_PATCH=9
GO_REQUIRED_VERSION="$GO_REQUIRED_MAJOR.$GO_REQUIRED_MINOR.$GO_REQUIRED_PATCH"
INSTALL_GO=0
if command -v go >/dev/null 2>&1; then
    GOVERSION=$(go version | awk '{print $3}' | sed 's/go//')
    GOVMAJ=$(echo $GOVERSION | cut -d. -f1)
    GOVMIN=$(echo $GOVERSION | cut -d. -f2)
    GOPATCH=$(echo $GOVERSION | cut -d. -f3)
    # Só instala se for menor que a versão requerida
    if [ "$GOVMAJ" -lt "$GO_REQUIRED_MAJOR" ] || { [ "$GOVMAJ" -eq "$GO_REQUIRED_MAJOR" ] && [ "$GOVMIN" -lt "$GO_REQUIRED_MINOR" ]; } || { [ "$GOVMAJ" -eq "$GO_REQUIRED_MAJOR" ] && [ "$GOVMIN" -eq "$GO_REQUIRED_MINOR" ] && [ "$GOPATCH" -lt "$GO_REQUIRED_PATCH" ]; }; then
        INSTALL_GO=1
    fi
else
    INSTALL_GO=1
fi
if [ "$INSTALL_GO" -eq 1 ]; then
    log "Instalando Go $GO_REQUIRED_VERSION..."
    wget -q https://go.dev/dl/go$GO_REQUIRED_VERSION.linux-amd64.tar.gz -O /tmp/go$GO_REQUIRED_VERSION.linux-amd64.tar.gz
    rm -rf /usr/local/go
    tar -C /usr/local -xzf /tmp/go$GO_REQUIRED_VERSION.linux-amd64.tar.gz
    export PATH=$PATH:/usr/local/go/bin
    if ! grep -q '/usr/local/go/bin' /etc/profile; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
    fi
    log "Go $GO_REQUIRED_VERSION instalado com sucesso."
else
    log "Go já está na versão requerida ou superior."
fi
# Garante que o PATH está correto nesta sessão
export PATH=$PATH:/usr/local/go/bin

# Criar diretório de instalação
INSTALL_DIR="/opt/guardian"

# Verificar se o diretório já existe
if [ -d "$INSTALL_DIR" ]; then
    log "Diretório $INSTALL_DIR já existe."
    log "Removendo instalação anterior..."
    rm -rf "$INSTALL_DIR"
    if [ $? -ne 0 ]; then
        error "Não foi possível remover o diretório existente. Verifique as permissões."
    fi
fi

# Criar diretório de instalação
mkdir -p $INSTALL_DIR || error "Não foi possível criar o diretório de instalação"

# Baixar o código do repositório
log "Baixando o código fonte..."
git clone https://github.com/MakeToMe/mtmguardia.git $INSTALL_DIR || error "Falha ao baixar o código fonte"

# Criar diretórios necessários
mkdir -p "$INSTALL_DIR/bin"
mkdir -p "$INSTALL_DIR/data"
mkdir -p "$INSTALL_DIR/scripts"
mkdir -p "$INSTALL_DIR/config"

# Compilar os binários
log "Compilando os binários..."
cd "$INSTALL_DIR"
go build -o "$INSTALL_DIR/bin/guardian" ./cmd/guardian
chmod +x "$INSTALL_DIR/bin/guardian"


# Gerar token aleatório se não for fornecido
if [ -z "$GUARDIAN_AUTH_TOKEN" ]; then
    TOKEN=$(openssl rand -hex 16)
    log "Token de autenticação gerado: $TOKEN"
else
    TOKEN=$GUARDIAN_AUTH_TOKEN
    log "Usando token de autenticação fornecido"
fi

# Criar diretórios necessários dentro da pasta de instalação
log "Criando diretórios..."
mkdir -p $INSTALL_DIR/config
mkdir -p $INSTALL_DIR/data

# Garantir que o firewall está ativo e portas essenciais abertas
log "Verificando e ativando firewall, se necessário..."
echo "[DEBUG] === INÍCIO BLOCO FIREWALL ==="

# Detectar firewall (ufw, iptables, firewalld)
FIREWALL=""
if command -v ufw >/dev/null 2>&1; then
    FIREWALL="ufw"
elif command -v iptables >/dev/null 2>&1; then
    FIREWALL="iptables"
elif command -v firewall-cmd >/dev/null 2>&1; then
    FIREWALL="firewalld"
else
    error "Nenhum firewall suportado encontrado (ufw, iptables, firewalld)"
fi

set -x
case "$FIREWALL" in
    ufw)
        log "Configurando UFW..."
        echo "[DEBUG] Rodando: ufw --force enable"
        ufw --force enable > /tmp/ufw_enable.log 2>&1
        echo "[DEBUG] Saída ufw --force enable:"
        cat /tmp/ufw_enable.log
        if command -v systemctl >/dev/null 2>&1; then
            echo "[DEBUG] Rodando: systemctl enable ufw && systemctl start ufw"
            systemctl enable ufw >> /tmp/ufw_enable.log 2>&1
            systemctl start ufw >> /tmp/ufw_enable.log 2>&1
            UFW_SERVICE=$(systemctl is-active ufw)
            echo "[DEBUG] systemctl is-active ufw: $UFW_SERVICE"
        else
            UFW_SERVICE="unknown"
        fi
        ufw allow 22/tcp
        ufw allow 4554/tcp
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw allow 22/tcp comment 'SSH'
        ufw allow 4554/tcp comment 'API Guardian'
        ufw allow 80/tcp comment 'HTTP'
        ufw allow 443/tcp comment 'HTTPS'
        # As regras abaixo eram inválidas e removidas:
        # ufw allow 22/tcp from any to any proto tcp
        # ufw allow 4554/tcp from any to any proto tcp
        # ufw allow 80/tcp from any to any proto tcp
        # ufw allow 443/tcp from any to any proto tcp
        # ufw allow 22/tcp from any to any proto tcp comment 'SSH IPv6'
        # ufw allow 4554/tcp from any to any proto tcp comment 'API IPv6'
        # ufw allow 80/tcp from any to any proto tcp comment 'HTTP IPv6'
        # ufw allow 443/tcp from any to any proto tcp comment 'HTTPS IPv6'
        echo "[DEBUG] Status do UFW após ativação:"
        ufw status verbose
        STATUS=$(ufw status | grep -i 'Status: active')
        echo "[DEBUG] Conteúdo completo do log de ativação do UFW:"
        cat /tmp/ufw_enable.log
        if [ -z "$STATUS" ] || { command -v systemctl >/dev/null 2>&1 && [ "$UFW_SERVICE" != "active" ]; }; then
            error "UFW não foi ativado corretamente! Veja o log abaixo:\n$(cat /tmp/ufw_enable.log)\nSaída do journalctl:\n$(journalctl -u ufw --no-pager | tail -20)"
        fi
        ;;



    iptables)
        log "Configurando iptables..."
        iptables -F
        iptables -X
        iptables -P INPUT DROP
        iptables -P FORWARD DROP
        iptables -P OUTPUT ACCEPT
        iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        iptables -A INPUT -i lo -j ACCEPT
        iptables -A INPUT -p tcp --dport 22 -j ACCEPT
        iptables -A INPUT -p tcp --dport 4554 -j ACCEPT
        iptables -A INPUT -p tcp --dport 80 -j ACCEPT
        iptables -A INPUT -p tcp --dport 443 -j ACCEPT
        ip6tables -A INPUT -p tcp --dport 22 -j ACCEPT
        ip6tables -A INPUT -p tcp --dport 4554 -j ACCEPT
        ip6tables -A INPUT -p tcp --dport 80 -j ACCEPT
        ip6tables -A INPUT -p tcp --dport 443 -j ACCEPT
        iptables-save > /etc/iptables/rules.v4 || (mkdir -p /etc/iptables && iptables-save > /etc/iptables/rules.v4)
        ip6tables-save > /etc/iptables/rules.v6 || (mkdir -p /etc/iptables && ip6tables-save > /etc/iptables/rules.v6)
        # Checar se iptables está ativo (INPUT default DROP)
        IPT_STATUS=$(iptables -L | grep 'Chain INPUT (policy DROP)')
        if [ -z "$IPT_STATUS" ]; then
            error "iptables não foi ativado corretamente!"
        fi
        iptables -L -v -n
        ;;
    firewalld)
        log "Configurando firewalld..."
        systemctl start firewalld
        systemctl enable firewalld
        firewall-cmd --permanent --add-service=ssh
        firewall-cmd --permanent --add-port=4554/tcp
        firewall-cmd --permanent --add-port=80/tcp
        firewall-cmd --permanent --add-port=443/tcp
        firewall-cmd --reload
        # Checar status firewalld
        FW_STATUS=$(firewall-cmd --state)
        if [ "$FW_STATUS" != "running" ]; then
            error "firewalld não foi ativado corretamente!"
        fi
        firewall-cmd --list-all
        ;;
esac

log "Firewall configurado, portas essenciais abertas e ativação confirmada."

# Salvar o token em um arquivo seguro para referência futura
TOKEN_FILE="$INSTALL_DIR/config/auth_token.txt"
echo "$TOKEN" > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE" # Apenas root pode ler

# Solicitar informações do banco de dados
log "Configurando acesso ao banco de dados..."

# Informar que os IDs serão obtidos automaticamente
log "Os IDs de servidor e titular serão obtidos automaticamente do banco de dados."

# Criar arquivo de configuração
log "Criando arquivo de configuração..."
cat > "$INSTALL_DIR/config/config.env" << EOF
GUARDIAN_IP=$IP
GUARDIAN_PORT=4554
GUARDIAN_AUTH_TOKEN=$TOKEN
GUARDIAN_INSTALL_DIR=$INSTALL_DIR
GUARDIAN_DB_CONN_STRING=$DB_CONN_STRING
GUARDIAN_DB_SCHEMA=mtm
EOF

# Criar serviço systemd
log "Configurando serviço systemd..."
SERVICE_FILE="/etc/systemd/system/guardian.service"
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Guardian Firewall Manager
After=network.target

[Service]
Type=simple
User=root
Environment="GUARDIAN_IP=$IP"
Environment="GUARDIAN_PORT=4554"
Environment="GUARDIAN_AUTH_TOKEN=$TOKEN"
Environment="GUARDIAN_INSTALL_DIR=$INSTALL_DIR"
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/guardian
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Recarregar systemd
systemctl daemon-reload

# Iniciar e habilitar o serviço
log "Iniciando o serviço Guardian..."
systemctl enable guardian
systemctl start guardian

# Verificar status do serviço
if systemctl is-active --quiet guardian; then
    log "Guardian instalado e iniciado com sucesso!"
    log "API disponível em: http://$IP:4554/guardian"
    log "Token de autenticação: $TOKEN"
    log "Guarde este token em um local seguro!"
    log "Exemplo de uso:"
    log "curl -X POST -H \"Authorization: Bearer $TOKEN\" -H \"Content-Type: application/json\" -d '{\"acao\":\"banir\",\"ip\":\"192.168.1.100\"}' http://$IP:4554/guardian"
else
    error "Falha ao iniciar o serviço Guardian. Verifique os logs com: journalctl -u guardian"
fi

# Instruções finais
log "Instalação concluída!"
log "Para visualizar os logs do serviço: journalctl -u guardian -f"
log "Para reiniciar o serviço: systemctl restart guardian"
log "Para parar o serviço: systemctl stop guardian"

# Criar um link simbólico para facilitar o acesso à configuração
if [ -d "/etc/guardian" ]; then
    rm -rf /etc/guardian
fi
ln -s $INSTALL_DIR/config /etc/guardian
log "Link simbólico criado em /etc/guardian apontando para $INSTALL_DIR/config"

# Exibir informações sobre o token de autenticação
echo ""
echo "==================== INFORMAÇÕES DE AUTENTICAÇÃO ===================="
echo "Token de autenticação: $TOKEN"
echo "Este token foi salvo em: $TOKEN_FILE"
echo "Para visualizar o token posteriormente, execute: cat $TOKEN_FILE"
echo ""
echo "Exemplo de uso da API:"
echo "curl -X POST \\"
echo "  -H \"Authorization: Bearer $TOKEN\" \\"
echo "  -H \"Content-Type: application/json\" \\"
echo "  -d '{\"acao\":\"banir\",\"ip\":\"192.168.1.100\"}' \\"
echo "  http://$IP:4554/guardian"
echo "================================================================="
