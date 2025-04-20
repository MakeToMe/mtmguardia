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
