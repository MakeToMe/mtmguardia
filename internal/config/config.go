package config

import (
	"fmt"
	"net"
	"os"
	"strconv"

	"github.com/joho/godotenv"
)

// Config contém as configurações da aplicação
type Config struct {
	IP           string
	Port         int
	AuthToken    string
	FirewallType string
}

// Load carrega as configurações do arquivo .env ou variáveis de ambiente
func Load() (*Config, error) {
	// Tenta carregar do arquivo .env se existir
	_ = godotenv.Load("/etc/guardian/config.env")
	_ = godotenv.Load(".env")

	// Configuração padrão
	cfg := &Config{
		Port:         4554,
		FirewallType: "auto", // auto, ufw, iptables
	}

	// Obter IP automaticamente se não estiver definido
	if ip := os.Getenv("GUARDIAN_IP"); ip != "" {
		cfg.IP = ip
	} else {
		detectedIP, err := getOutboundIP()
		if err != nil {
			return nil, fmt.Errorf("falha ao detectar IP: %w", err)
		}
		cfg.IP = detectedIP
	}

	// Obter porta se estiver definida
	if portStr := os.Getenv("GUARDIAN_PORT"); portStr != "" {
		port, err := strconv.Atoi(portStr)
		if err != nil {
			return nil, fmt.Errorf("porta inválida: %w", err)
		}
		cfg.Port = port
	}

	// Token de autenticação é obrigatório
	if token := os.Getenv("GUARDIAN_AUTH_TOKEN"); token != "" {
		cfg.AuthToken = token
	} else {
		return nil, fmt.Errorf("token de autenticação não definido (GUARDIAN_AUTH_TOKEN)")
	}

	// Tipo de firewall
	if fwType := os.Getenv("GUARDIAN_FIREWALL_TYPE"); fwType != "" {
		cfg.FirewallType = fwType
	}

	return cfg, nil
}

// getOutboundIP obtém o IP preferencial da máquina para conexões externas
func getOutboundIP() (string, error) {
	conn, err := net.Dial("udp", "8.8.8.8:80")
	if err != nil {
		return "", err
	}
	defer conn.Close()

	localAddr := conn.LocalAddr().(*net.UDPAddr)
	return localAddr.IP.String(), nil
}
