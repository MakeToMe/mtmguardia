#!/bin/bash

# Script de atualização do Guardian - Gerenciador de Firewall
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
    error "Este script deve ser executado como root. Use: sudo bash update.sh"
fi

# Verificar se o Guardian está instalado
INSTALL_DIR="/opt/guardian"
if [ ! -d "$INSTALL_DIR" ]; then
    error "Guardian não está instalado. Execute o script de instalação primeiro."
fi

log "Iniciando atualização do Guardian - Gerenciador de Firewall"

# Parar o serviço
log "Parando o serviço Guardian..."
systemctl stop guardian || warn "Não foi possível parar o serviço Guardian"

# Backup da configuração atual
log "Fazendo backup da configuração..."
if [ -f $INSTALL_DIR/config/config.env ]; then
    cp $INSTALL_DIR/config/config.env $INSTALL_DIR/config/config.env.bak
    log "Backup criado em $INSTALL_DIR/config/config.env.bak"
fi

# Atualizar o código
log "Atualizando o código fonte..."
cd $INSTALL_DIR
git fetch origin || error "Falha ao buscar atualizações"
git reset --hard origin/main || error "Falha ao atualizar o código"

# Recompilar o código
log "Recompilando o Guardian..."
go build -o guardian cmd/guardian/main.go || error "Falha ao compilar o código"

# Restaurar configuração
if [ -f $INSTALL_DIR/config/config.env.bak ]; then
    log "Restaurando configuração..."
    cp $INSTALL_DIR/config/config.env.bak $INSTALL_DIR/config/config.env
fi

# Verificar e recriar o link simbólico se necessário
if [ ! -L "/etc/guardian" ] || [ ! -d "/etc/guardian" ]; then
    log "Recriando link simbólico para a configuração..."
    if [ -e "/etc/guardian" ]; then
        rm -rf /etc/guardian
    fi
    ln -s $INSTALL_DIR/config /etc/guardian
fi

# Reiniciar o serviço
log "Reiniciando o serviço Guardian..."
systemctl start guardian

# Verificar status do serviço
if systemctl is-active --quiet guardian; then
    log "Guardian atualizado e reiniciado com sucesso!"
else
    error "Falha ao iniciar o serviço Guardian. Verifique os logs com: journalctl -u guardian"
fi

# Instruções finais
log "Atualização concluída!"
log "Para visualizar os logs do serviço: journalctl -u guardian -f"
