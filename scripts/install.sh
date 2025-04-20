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

# Configurar o detector de força bruta baseado em script
log "Configurando detector de força bruta..."

# Criar diretório de dados e scripts com permissões amplas
mkdir -p $INSTALL_DIR/data
mkdir -p $INSTALL_DIR/scripts
chmod -R 777 $INSTALL_DIR/data

# Copiar script de monitoramento de força bruta
log "Copiando script de monitoramento de força bruta..."
cat > $INSTALL_DIR/scripts/bruteforce_monitor.sh << 'EOF'
#!/bin/bash

# Script para monitorar tentativas de login malsucedidas usando lastb
# Este script é executado a cada 5 minutos via crontab

# Definir diretório de dados e arquivos
DATA_DIR="/opt/guardian/data"
JSON_FILE="$DATA_DIR/bruteforce.json"
LOG_FILE="$DATA_DIR/bruteforce.log"

# Função para log
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Garantir que o diretório existe
mkdir -p "$DATA_DIR"
chmod -R 777 "$DATA_DIR" 2>/dev/null || true

# Iniciar log se não existir
if [ ! -f "$LOG_FILE" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Arquivo de log do detector de força bruta criado" > "$LOG_FILE"
    chmod 666 "$LOG_FILE" 2>/dev/null || true
fi

log "Executando detector de força bruta..."

# Executar lastb e processar saída
log "Executando comando lastb..."
LASTB_OUTPUT=$(sudo lastb 2>&1)

if [ $? -ne 0 ]; then
    log "ERRO ao executar lastb: $LASTB_OUTPUT"
    exit 1
fi

# Processar a saída para obter IPs e contagens
log "Processando saída do lastb..."
PROCESSED_OUTPUT=$(echo "$LASTB_OUTPUT" | awk '{ print $3 }' | sort | uniq -c | sort -nr)

if [ -z "$PROCESSED_OUTPUT" ]; then
    log "Nenhuma tentativa de login malsucedida encontrada."
    echo "[]" > "$JSON_FILE"
    chmod 666 "$JSON_FILE" 2>/dev/null || true
    exit 0
fi

# Converter para JSON
log "Convertendo resultados para JSON..."
JSON="["
FIRST=true

echo "$PROCESSED_OUTPUT" | while read line; do
    # Extrair contagem e IP
    COUNT=$(echo "$line" | awk '{print $1}')
    IP=$(echo "$line" | awk '{print $2}')
    
    # Verificar se a contagem é um número e o IP não está vazio
    if [[ "$COUNT" =~ ^[0-9]+$ ]] && [ ! -z "$IP" ]; then
        # Verificar se a contagem é maior ou igual a 3
        if [ "$COUNT" -ge 3 ]; then
            if [ "$FIRST" = true ]; then
                FIRST=false
            else
                JSON="$JSON,"
            fi
            
            # Adicionar ao JSON
            TIMESTAMP=$(date -Iseconds)
            JSON="$JSON
  {
    \"ip\": \"$IP\",
    \"count\": $COUNT,
    \"timestamp\": \"$TIMESTAMP\"
  }"
            
            log "Detectado IP com múltiplas tentativas: $IP (contagem: $COUNT)"
        fi
    fi
done

JSON="$JSON
]"

# Salvar JSON no arquivo
log "Salvando resultados em $JSON_FILE..."
echo "$JSON" > "$JSON_FILE"
chmod 666 "$JSON_FILE" 2>/dev/null || true

log "Detector de força bruta concluído com sucesso."
EOF

# Tornar o script executável
log "Tornando o script executável..."
chmod +x $INSTALL_DIR/scripts/bruteforce_monitor.sh

# Criar arquivo de teste
echo "teste de json" > $INSTALL_DIR/data/test.json
chmod 666 $INSTALL_DIR/data/test.json || true

# Configurar crontab para executar o script a cada 5 minutos
log "Configurando crontab para executar o script a cada 5 minutos..."
(crontab -l 2>/dev/null | grep -v "bruteforce_monitor.sh"; echo "*/5 * * * * $INSTALL_DIR/scripts/bruteforce_monitor.sh") | crontab -

# Executar o script imediatamente
log "Executando o script pela primeira vez..."
$INSTALL_DIR/scripts/bruteforce_monitor.sh

# Verificar arquivos criados
log "Verificando arquivos criados:"
ls -la $INSTALL_DIR/data/

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
