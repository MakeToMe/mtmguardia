#!/bin/bash

# Script para verificar o status do serviço Guardian e executar o detector manualmente

echo "Verificando status do serviço Guardian..."
systemctl status guardian

echo "Verificando logs do serviço..."
journalctl -u guardian -n 50

echo "Verificando arquivos do detector de força bruta..."
ls -la /opt/guardian/data/

echo "Conteúdo do arquivo bruteforce.json:"
cat /opt/guardian/data/bruteforce.json

echo "Conteúdo do arquivo bruteforce.log:"
cat /opt/guardian/data/bruteforce.log

echo "Executando o comando lastb manualmente..."
sudo lastb | head -20

echo "Processando saída do lastb manualmente..."
sudo lastb | awk '{ print $3 }' | sort | uniq -c | sort -nr | head -20

echo "Verificando se o Guardian está em execução..."
ps aux | grep guardian

echo "Reiniciando o serviço Guardian..."
systemctl restart guardian

echo "Aguardando 10 segundos..."
sleep 10

echo "Verificando logs após reiniciar..."
journalctl -u guardian -n 20

echo "Verificando arquivos após reiniciar..."
ls -la /opt/guardian/data/

echo "Conteúdo do arquivo bruteforce.json após reiniciar:"
cat /opt/guardian/data/bruteforce.json

echo "Conteúdo do arquivo bruteforce.log após reiniciar:"
cat /opt/guardian/data/bruteforce.log
