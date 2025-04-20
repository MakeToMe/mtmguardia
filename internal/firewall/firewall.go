package firewall

import (
	"errors"
	"fmt"
	"os/exec"
	"strings"

	"github.com/mtm/guardian/internal/config"
)

// Firewall é a interface que define as operações do firewall
type Firewall interface {
	IsEnabled() (bool, error)
	Enable() error
	Disable() error
	BanIP(ip string) error
	UnbanIP(ip string) error
	Type() string
}

// New cria uma nova instância do firewall apropriado
func New(cfg *config.Config) (Firewall, error) {
	if cfg.FirewallType != "auto" {
		return createFirewall(cfg.FirewallType)
	}

	// Detectar automaticamente o firewall
	firewallType, err := detectFirewall()
	if err != nil {
		return nil, err
	}

	return createFirewall(firewallType)
}

// detectFirewall detecta o tipo de firewall instalado no sistema
func detectFirewall() (string, error) {
	// Verificar UFW
	if _, err := exec.LookPath("ufw"); err == nil {
		return "ufw", nil
	}

	// Verificar iptables
	if _, err := exec.LookPath("iptables"); err == nil {
		return "iptables", nil
	}

	// Verificar firewalld
	if _, err := exec.LookPath("firewall-cmd"); err == nil {
		return "firewalld", nil
	}

	return "", errors.New("nenhum firewall suportado encontrado")
}

// createFirewall cria uma instância do firewall baseado no tipo
func createFirewall(firewallType string) (Firewall, error) {
	switch strings.ToLower(firewallType) {
	case "ufw":
		return &UFWFirewall{}, nil
	case "iptables":
		return &IPTablesFirewall{}, nil
	case "firewalld":
		return &FirewalldFirewall{}, nil
	default:
		return nil, fmt.Errorf("tipo de firewall não suportado: %s", firewallType)
	}
}
