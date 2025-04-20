#!/bin/bash

# Exemplos de uso da API Guardian
# Substitua as variáveis abaixo pelos valores corretos

# Configurações
SERVER_IP="seu-servidor-ip"
PORT=4554
TOKEN="seu-token-aqui"

# Função para fazer requisições para a API
call_api() {
    local action=$1
    local ip=$2
    
    echo "Executando ação: $action para IP: $ip"
    
    curl -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"acao\":\"$action\",\"ip\":\"$ip\"}" \
        http://$SERVER_IP:$PORT/guardian
    
    echo -e "\n"
}

# Exemplo 1: Banir um IP
call_api "banir" "192.168.1.100"

# Exemplo 2: Desbanir um IP
call_api "desbanir" "192.168.1.100"

# Exemplo 3: Banir múltiplos IPs
for ip in "10.0.0.1" "10.0.0.2" "10.0.0.3"; do
    call_api "banir" "$ip"
done

# Exemplo 4: Desbanir múltiplos IPs
for ip in "10.0.0.1" "10.0.0.2" "10.0.0.3"; do
    call_api "desbanir" "$ip"
done
