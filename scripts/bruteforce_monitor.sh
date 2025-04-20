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
