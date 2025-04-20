# Guardian - Gerenciador de Firewall

Guardian é um serviço em Go que gerencia regras de firewall em servidores Ubuntu, oferecendo uma API REST para banir e desbanir IPs.

## Funcionalidades

- Detecção automática do firewall instalado (UFW, iptables, etc.)
- Ativação de firewall caso não esteja habilitado
- API REST para gerenciar regras de firewall (banir/desbanir IPs)
- Autenticação via token
- Execução como serviço systemd

## Requisitos

- Ubuntu Server
- Privilégios de root para instalação

## Instalação

```bash
curl -sSL https://raw.githubusercontent.com/mtm/guardian/main/install.sh | sudo bash
```

## API

### Banir/Desbanir IP

```
POST http://[ip-do-servidor]:4554/guardian
```

Headers:
```
Authorization: Bearer [seu-token]
Content-Type: application/json
```

Body:
```json
{
  "acao": "banir", // ou "desbanir"
  "ip": "111.111.11.11"
}
```

## Configuração

O arquivo de configuração está localizado em `/etc/guardian/config.env`
