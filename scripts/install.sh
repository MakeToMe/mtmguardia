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
mkdir -p $INSTALL_DIR/scripts

# Copiar script de configuração do detector de força bruta
log "Copiando script de configuração do detector de força bruta..."
cat > $INSTALL_DIR/scripts/bruteforce_setup.sh << 'EOF'
#!/bin/bash

# Script para configurar e testar o detector de força bruta

INSTALL_DIR="/opt/guardian"
DATA_DIR="$INSTALL_DIR/data"
LOG_FILE="$DATA_DIR/bruteforce.log"
JSON_FILE="$DATA_DIR/bruteforce.json"
TEST_FILE="$DATA_DIR/test.json"

# Função para log
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Criar diretório de dados se não existir
mkdir -p "$DATA_DIR"
chmod -R 777 "$DATA_DIR"

# Iniciar arquivo de log
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Iniciando configuração do detector de força bruta" > "$LOG_FILE"
chmod 666 "$LOG_FILE"

# Criar arquivo de teste
echo "teste de json" > "$TEST_FILE"
chmod 666 "$TEST_FILE"

# Verificar se o comando lastb existe
log "Verificando se o comando lastb existe..."
if which lastb > /dev/null 2>&1; then
    log "Comando lastb encontrado: $(which lastb)"
else
    log "AVISO: Comando lastb não encontrado no PATH"
    # Procurar pelo comando lastb no sistema
    LASTB_PATH=$(find /usr -name lastb 2>/dev/null || find / -name lastb 2>/dev/null | head -1)
    if [ -n "$LASTB_PATH" ]; then
        log "Comando lastb encontrado em: $LASTB_PATH"
    else
        log "ERRO: Comando lastb não encontrado no sistema"
    fi
fi

# Verificar permissões do sudo
log "Verificando permissões do sudo..."
if sudo -n true 2>/dev/null; then
    log "Sudo sem senha disponível"
else
    log "Sudo requer senha - isso pode causar problemas para o detector"
fi

# Tentar executar o comando lastb
log "Tentando executar o comando lastb..."
if sudo lastb > /tmp/lastb_output 2>&1; then
    log "Comando lastb executado com sucesso"
    log "Primeiras 10 linhas da saída:"
    head -10 /tmp/lastb_output | while read line; do
        log "  $line"
    done
else
    log "ERRO ao executar lastb: $?"
    log "Saída de erro:"
    cat /tmp/lastb_output | while read line; do
        log "  $line"
    done
fi

# Criar dados fictícios para o arquivo JSON
log "Criando dados fictícios para o arquivo JSON..."
cat > "$JSON_FILE" << EOF
[
  {
    "ip": "192.168.1.100",
    "count": 5,
    "timestamp": "$(date -Iseconds)"
  },
  {
    "ip": "10.0.0.1",
    "count": 3,
    "timestamp": "$(date -Iseconds)"
  }
]
EOF
chmod 666 "$JSON_FILE"

# Verificar se os arquivos foram criados
log "Verificando arquivos criados:"
ls -la "$DATA_DIR" | while read line; do
    log "  $line"
done

# Verificar conteúdo do arquivo JSON
log "Conteúdo do arquivo JSON:"
cat "$JSON_FILE" | while read line; do
    log "  $line"
done

log "Configuração do detector de força bruta concluída"
EOF

# Tornar o script executável
chmod +x $INSTALL_DIR/scripts/bruteforce_setup.sh

# Executar o script de configuração
log "Executando script de configuração do detector de força bruta..."
$INSTALL_DIR/scripts/bruteforce_setup.sh

# Verificar arquivos criados
log "Verificando arquivos criados após a configuração:"
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
ExecStartPre=$INSTALL_DIR/scripts/bruteforce_setup.sh
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
