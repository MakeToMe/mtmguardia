#!/bin/bash
# Script para coletar IPs de tentativas de acesso mal-sucedidas (lastb)
# Gera um relatório de IPs com >= 3 tentativas, ordenado por frequência
# Salva o resultado em logs/ips_bloqueio.txt dentro do projeto

# Diretório do projeto (ajuste se necessário)
PROJ_DIR="$(dirname "$(realpath "$0")")/.."
LOG_DIR="$PROJ_DIR/logs"
ARQUIVO="$LOG_DIR/ips_bloqueio.txt"

mkdir -p "$LOG_DIR"
echo "[DEBUG] Pasta de logs garantida: $LOG_DIR"

lastb | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort | uniq -c | sort -nr | awk '$1 >= 3' > "$ARQUIVO"
echo "[DEBUG] Arquivo de IPs gerado: $ARQUIVO"
