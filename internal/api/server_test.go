package api

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/mtm/guardian/internal/config"
	"github.com/mtm/guardian/internal/firewall"
)

// TestHandleGuardian testa o endpoint da API Guardian
func TestHandleGuardian(t *testing.T) {
	// Configuração de teste
	cfg := &config.Config{
		IP:        "127.0.0.1",
		Port:      4554,
		AuthToken: "test-token",
	}

	// Criar mock do firewall
	mockFw := firewall.NewMockFirewall()

	// Criar servidor
	server := NewServer(cfg, mockFw)

	// Teste 1: Requisição válida para banir IP
	t.Run("Ban IP Valid Request", func(t *testing.T) {
		reqBody := Request{
			Acao: "banir",
			IP:   "192.168.1.100",
		}
		body, _ := json.Marshal(reqBody)

		req := httptest.NewRequest("POST", "/guardian", bytes.NewReader(body))
		req.Header.Set("Authorization", "Bearer test-token")
		req.Header.Set("Content-Type", "application/json")

		rr := httptest.NewRecorder()
		server.handleGuardian(rr, req)

		// Verificar status code
		if status := rr.Code; status != http.StatusOK {
			t.Errorf("Status code esperado: %d, obtido: %d", http.StatusOK, status)
		}

		// Verificar resposta
		var resp Response
		if err := json.Unmarshal(rr.Body.Bytes(), &resp); err != nil {
			t.Fatalf("Erro ao decodificar resposta: %v", err)
		}

		if !resp.Success {
			t.Errorf("Resposta deveria indicar sucesso")
		}
	})

	// Teste 2: Requisição sem token de autenticação
	t.Run("Missing Auth Token", func(t *testing.T) {
		reqBody := Request{
			Acao: "banir",
			IP:   "192.168.1.100",
		}
		body, _ := json.Marshal(reqBody)

		req := httptest.NewRequest("POST", "/guardian", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")

		rr := httptest.NewRecorder()
		server.handleGuardian(rr, req)

		// Verificar status code
		if status := rr.Code; status != http.StatusUnauthorized {
			t.Errorf("Status code esperado: %d, obtido: %d", http.StatusUnauthorized, status)
		}
	})

	// Teste 3: Requisição com token inválido
	t.Run("Invalid Auth Token", func(t *testing.T) {
		reqBody := Request{
			Acao: "banir",
			IP:   "192.168.1.100",
		}
		body, _ := json.Marshal(reqBody)

		req := httptest.NewRequest("POST", "/guardian", bytes.NewReader(body))
		req.Header.Set("Authorization", "Bearer invalid-token")
		req.Header.Set("Content-Type", "application/json")

		rr := httptest.NewRecorder()
		server.handleGuardian(rr, req)

		// Verificar status code
		if status := rr.Code; status != http.StatusUnauthorized {
			t.Errorf("Status code esperado: %d, obtido: %d", http.StatusUnauthorized, status)
		}
	})

	// Teste 4: Requisição com método inválido
	t.Run("Invalid Method", func(t *testing.T) {
		req := httptest.NewRequest("GET", "/guardian", nil)
		req.Header.Set("Authorization", "Bearer test-token")

		rr := httptest.NewRecorder()
		server.handleGuardian(rr, req)

		// Verificar status code
		if status := rr.Code; status != http.StatusMethodNotAllowed {
			t.Errorf("Status code esperado: %d, obtido: %d", http.StatusMethodNotAllowed, status)
		}
	})

	// Teste 5: Requisição com ação inválida
	t.Run("Invalid Action", func(t *testing.T) {
		reqBody := Request{
			Acao: "invalidAction",
			IP:   "192.168.1.100",
		}
		body, _ := json.Marshal(reqBody)

		req := httptest.NewRequest("POST", "/guardian", bytes.NewReader(body))
		req.Header.Set("Authorization", "Bearer test-token")
		req.Header.Set("Content-Type", "application/json")

		rr := httptest.NewRecorder()
		server.handleGuardian(rr, req)

		// Verificar status code
		if status := rr.Code; status != http.StatusBadRequest {
			t.Errorf("Status code esperado: %d, obtido: %d", http.StatusBadRequest, status)
		}
	})

	// Teste 6: Requisição com IP inválido
	t.Run("Invalid IP", func(t *testing.T) {
		reqBody := Request{
			Acao: "banir",
			IP:   "invalid-ip",
		}
		body, _ := json.Marshal(reqBody)

		req := httptest.NewRequest("POST", "/guardian", bytes.NewReader(body))
		req.Header.Set("Authorization", "Bearer test-token")
		req.Header.Set("Content-Type", "application/json")

		rr := httptest.NewRecorder()
		server.handleGuardian(rr, req)

		// Verificar status code
		if status := rr.Code; status != http.StatusBadRequest {
			t.Errorf("Status code esperado: %d, obtido: %d", http.StatusBadRequest, status)
		}
	})
}
