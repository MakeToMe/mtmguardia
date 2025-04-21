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

# Criar um arquivo temporário para construir o JSON
TMP_JSON_FILE="/tmp/bruteforce_tmp.json"
echo "[" > "$TMP_JSON_FILE"

# Variável para controlar se é o primeiro item
FIRST=true

# Processar cada linha da saída
log "Processando $(echo "$PROCESSED_OUTPUT" | wc -l) linhas de saída..."
while IFS= read -r line; do
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
                echo "," >> "$TMP_JSON_FILE"
            fi
            
            # Adicionar ao JSON
            TIMESTAMP=$(date -Iseconds)
            echo "  {" >> "$TMP_JSON_FILE"
            echo "    \"ip\": \"$IP\"," >> "$TMP_JSON_FILE"
            echo "    \"count\": $COUNT," >> "$TMP_JSON_FILE"
            echo "    \"timestamp\": \"$TIMESTAMP\"" >> "$TMP_JSON_FILE"
            echo "  }" >> "$TMP_JSON_FILE"
            
            log "Detectado IP com múltiplas tentativas: $IP (contagem: $COUNT)"
        fi
    fi
done <<< "$PROCESSED_OUTPUT"

# Finalizar o JSON
echo "]" >> "$TMP_JSON_FILE"

# Verificar se o JSON foi gerado corretamente
if [ -f "$TMP_JSON_FILE" ]; then
    log "JSON temporário gerado com sucesso. Tamanho: $(wc -c < "$TMP_JSON_FILE") bytes"
    
    # Copiar para o arquivo final
    log "Salvando resultados em $JSON_FILE..."
    cp "$TMP_JSON_FILE" "$JSON_FILE"
    chmod 666 "$JSON_FILE" 2>/dev/null || true
    
    # Mostrar o conteúdo do JSON (primeiras 5 linhas)
    log "Primeiras linhas do JSON gerado:"
    head -5 "$JSON_FILE" | while IFS= read -r line; do
        log "  $line"
    done
else
    log "ERRO: Falha ao gerar arquivo JSON temporário"
fi

log "Detector de força bruta concluído com sucesso."

# Chamar o processador Go para enviar os IPs para o banco de dados
if [ -f "$INSTALL_DIR/bin/bruteforce" ]; then
    log "Chamando processador Go para enviar IPs para o banco de dados..."
    "$INSTALL_DIR/bin/bruteforce" --log "$LOG_FILE" --min 3
    log "Processador Go concluído."
else
    log "Processador Go não encontrado. Os IPs não serão enviados para o banco de dados."
fi

exit 0
