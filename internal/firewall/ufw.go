package firewall

import (
	"fmt"
	"os/exec"
	"strings"
)

// UFWFirewall implementa a interface Firewall para o UFW
type UFWFirewall struct{}

// IsEnabled verifica se o UFW está habilitado
func (f *UFWFirewall) IsEnabled() (bool, error) {
	cmd := exec.Command("ufw", "status")
	output, err := cmd.CombinedOutput()
	if err != nil {
		return false, fmt.Errorf("erro ao verificar status do UFW: %w", err)
	}

	return strings.Contains(string(output), "Status: active"), nil
}

// Enable ativa o UFW
func (f *UFWFirewall) Enable() error {
	// Configurar regras básicas antes de ativar
	cmds := []struct {
		name string
		args []string
	}{
		{"ufw", []string{"default", "deny", "incoming"}},
		{"ufw", []string{"default", "allow", "outgoing"}},
		{"ufw", []string{"allow", "ssh"}},
		{"ufw", []string{"allow", "4554/tcp"}}, // Porta da API Guardian
		{"ufw", []string{"--force", "enable"}},
	}

	for _, cmd := range cmds {
		if err := exec.Command(cmd.name, cmd.args...).Run(); err != nil {
			return fmt.Errorf("erro ao executar '%s %s': %w", cmd.name, strings.Join(cmd.args, " "), err)
		}
	}

	return nil
}

// Disable desativa o UFW
func (f *UFWFirewall) Disable() error {
	cmd := exec.Command("ufw", "--force", "disable")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("erro ao desativar UFW: %w", err)
	}
	return nil
}

// BanIP bane um endereço IP usando o UFW
func (f *UFWFirewall) BanIP(ip string) error {
	cmd := exec.Command("ufw", "deny", "from", ip, "to", "any")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("erro ao banir IP %s: %w", ip, err)
	}
	return nil
}

// UnbanIP remove o banimento de um endereço IP usando o UFW
func (f *UFWFirewall) UnbanIP(ip string) error {
	cmd := exec.Command("ufw", "delete", "deny", "from", ip, "to", "any")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("erro ao desbanir IP %s: %w", ip, err)
	}
	return nil
}

// Type retorna o tipo do firewall
func (f *UFWFirewall) Type() string {
	return "ufw"
}
