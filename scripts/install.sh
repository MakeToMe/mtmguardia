#!/bin/bash

# Script de instalação do Guardian - Gerenciador de Firewall
# Este script deve ser executado com privilégios de root

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

# Instalar dependências
log "Instalando dependências..."
apt-get update
apt-get install -y golang git ufw curl

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

# Compilar o código
log "Compilando o Guardian..."
cd $INSTALL_DIR
go build -o guardian cmd/guardian/main.go || error "Falha ao compilar o código"

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

# Garantir permissões corretas para os diretórios
log "Configurando permissões..."
chmod -R 777 $INSTALL_DIR/data
ls -la $INSTALL_DIR/data

# Criar arquivos iniciais
log "Criando arquivos iniciais..."
echo '[]' > $INSTALL_DIR/data/bruteforce.json
echo 'teste de json' > $INSTALL_DIR/data/test.json

# Verificar se os arquivos foram criados
if [ ! -f "$INSTALL_DIR/data/bruteforce.json" ]; then
    log "Tentando método alternativo para criar bruteforce.json..."
    sudo bash -c "echo '[]' > $INSTALL_DIR/data/bruteforce.json"
fi

if [ ! -f "$INSTALL_DIR/data/test.json" ]; then
    log "Tentando método alternativo para criar test.json..."
    sudo bash -c "echo 'teste de json' > $INSTALL_DIR/data/test.json"
fi

# Definir permissões dos arquivos
log "Definindo permissões dos arquivos..."
chmod 666 $INSTALL_DIR/data/bruteforce.json || true
chmod 666 $INSTALL_DIR/data/test.json || true

# Criar arquivo de log vazio com permissões corretas
log "Criando arquivo de log..."
touch $INSTALL_DIR/data/bruteforce.log
chmod 666 $INSTALL_DIR/data/bruteforce.log || true

# Verificar arquivos criados
log "Verificando arquivos criados:"
ls -la $INSTALL_DIR/data/

# Salvar o token em um arquivo seguro para referência futura
TOKEN_FILE="$INSTALL_DIR/config/auth_token.txt"
echo "$TOKEN" > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE" # Apenas root pode ler

# Criar arquivo de configuração
log "Criando arquivo de configuração..."
cat > $INSTALL_DIR/config/config.env << EOF
GUARDIAN_IP=$IP
GUARDIAN_PORT=4554
GUARDIAN_AUTH_TOKEN=$TOKEN
GUARDIAN_FIREWALL_TYPE=auto
GUARDIAN_INSTALL_DIR=$INSTALL_DIR
EOF

# Criar serviço systemd
log "Configurando serviço systemd..."
cat > /etc/systemd/system/guardian.service << EOF
[Unit]
Description=Guardian - Gerenciador de Firewall
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/guardian
ExecStart=/opt/guardian/guardian
Restart=on-failure
RestartSec=5
EnvironmentFile=/opt/guardian/config/config.env

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
