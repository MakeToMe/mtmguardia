# Guardian API

Este documento descreve a API REST do Guardian para gerenciamento de regras de firewall.

## Autenticação

Todas as requisições para a API Guardian devem incluir um token de autenticação no cabeçalho HTTP:

```
Authorization: Bearer <seu-token>
```

O token é definido durante a instalação e pode ser encontrado no arquivo de configuração `/etc/guardian/config.env`.

## Endpoints

### Banir/Desbanir IP

**URL**: `/guardian`

**Método**: `POST`

**Headers**:
- `Authorization: Bearer <seu-token>`
- `Content-Type: application/json`

**Corpo da Requisição**:
```json
{
  "acao": "banir", // ou "desbanir"
  "ip": "111.111.11.11"
}
```

**Parâmetros**:
- `acao` (string, obrigatório): Ação a ser executada. Valores aceitos: "banir" ou "desbanir".
- `ip` (string, obrigatório): Endereço IP a ser banido ou desbanido. Deve ser um endereço IPv4 válido.

**Resposta de Sucesso**:
- Código: `200 OK`
- Conteúdo:
```json
{
  "success": true,
  "message": "IP 111.111.11.11 banido com sucesso"
}
```

**Respostas de Erro**:
- Código: `400 Bad Request`
  - Corpo inválido
  - Ação inválida
  - IP inválido
  - Campos obrigatórios ausentes

- Código: `401 Unauthorized`
  - Token de autenticação ausente ou inválido

- Código: `405 Method Not Allowed`
  - Método HTTP diferente de POST

- Código: `500 Internal Server Error`
  - Erro ao processar a solicitação

## Exemplos

### Banir um IP

```bash
curl -X POST \
  -H "Authorization: Bearer seu-token-aqui" \
  -H "Content-Type: application/json" \
  -d '{"acao":"banir","ip":"192.168.1.100"}' \
  http://seu-servidor:4554/guardian
```

### Desbanir um IP

```bash
curl -X POST \
  -H "Authorization: Bearer seu-token-aqui" \
  -H "Content-Type: application/json" \
  -d '{"acao":"desbanir","ip":"192.168.1.100"}' \
  http://seu-servidor:4554/guardian
```
