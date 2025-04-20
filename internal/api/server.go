package api

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/mtm/guardian/internal/config"
	"github.com/mtm/guardian/internal/firewall"
)

// Request representa uma solicitação para a API
type Request struct {
	Acao string `json:"acao"`
	IP   string `json:"ip"`
}

// Response representa uma resposta da API
type Response struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
}

// Server representa o servidor da API
type Server struct {
	cfg      *config.Config
	fw       firewall.Firewall
	server   *http.Server
}

// NewServer cria uma nova instância do servidor API
func NewServer(cfg *config.Config, fw firewall.Firewall) *Server {
	return &Server{
		cfg: cfg,
		fw:  fw,
	}
}

// Start inicia o servidor HTTP
func (s *Server) Start() error {
	mux := http.NewServeMux()
	mux.HandleFunc("/guardian", s.handleGuardian)

	s.server = &http.Server{
		Addr:    fmt.Sprintf("%s:%d", s.cfg.IP, s.cfg.Port),
		Handler: mux,
	}

	return s.server.ListenAndServe()
}

// Shutdown encerra o servidor HTTP graciosamente
func (s *Server) Shutdown() error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	return s.server.Shutdown(ctx)
}

// handleGuardian processa as solicitações para a API Guardian
func (s *Server) handleGuardian(w http.ResponseWriter, r *http.Request) {
	// Verificar método HTTP
	if r.Method != http.MethodPost {
		http.Error(w, "Método não permitido", http.StatusMethodNotAllowed)
		return
	}

	// Verificar token de autenticação
	authHeader := r.Header.Get("Authorization")
	if !s.validateToken(authHeader) {
		http.Error(w, "Não autorizado", http.StatusUnauthorized)
		return
	}

	// Decodificar o corpo da requisição
	var req Request
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Formato de requisição inválido", http.StatusBadRequest)
		return
	}

	// Validar campos
	if req.Acao == "" || req.IP == "" {
		http.Error(w, "Campos 'acao' e 'ip' são obrigatórios", http.StatusBadRequest)
		return
	}

	// Validar IP
	if !isValidIP(req.IP) {
		http.Error(w, "Endereço IP inválido", http.StatusBadRequest)
		return
	}

	// Processar a ação
	var err error
	var message string

	switch strings.ToLower(req.Acao) {
	case "banir":
		err = s.fw.BanIP(req.IP)
		message = fmt.Sprintf("IP %s banido com sucesso", req.IP)
	case "desbanir":
		err = s.fw.UnbanIP(req.IP)
		message = fmt.Sprintf("IP %s desbanido com sucesso", req.IP)
	default:
		http.Error(w, "Ação inválida. Use 'banir' ou 'desbanir'", http.StatusBadRequest)
		return
	}

	// Verificar se houve erro
	if err != nil {
		log.Printf("Erro ao processar ação %s para IP %s: %v", req.Acao, req.IP, err)
		http.Error(w, fmt.Sprintf("Erro ao processar a solicitação: %v", err), http.StatusInternalServerError)
		return
	}

	// Enviar resposta de sucesso
	resp := Response{
		Success: true,
		Message: message,
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(resp)
}

// validateToken verifica se o token de autenticação é válido
func (s *Server) validateToken(authHeader string) bool {
	// Formato esperado: "Bearer <token>"
	parts := strings.Split(authHeader, " ")
	if len(parts) != 2 || parts[0] != "Bearer" {
		return false
	}

	token := parts[1]
	return token == s.cfg.AuthToken
}

// isValidIP verifica se uma string é um endereço IP válido
func isValidIP(ip string) bool {
	parts := strings.Split(ip, ".")
	if len(parts) != 4 {
		return false
	}

	for _, part := range parts {
		// Verificar se cada parte é um número entre 0 e 255
		var num int
		if _, err := fmt.Sscanf(part, "%d", &num); err != nil || num < 0 || num > 255 {
			return false
		}
	}

	return true
}
