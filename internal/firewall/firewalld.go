package firewall

import (
	"fmt"
	"os/exec"
	"strings"
)

// FirewalldFirewall implementa a interface Firewall para o firewalld
type FirewalldFirewall struct{}

// IsEnabled verifica se o firewalld está habilitado
func (f *FirewalldFirewall) IsEnabled() (bool, error) {
	cmd := exec.Command("firewall-cmd", "--state")
	output, err := cmd.CombinedOutput()
	if err != nil {
		return false, fmt.Errorf("erro ao verificar status do firewalld: %w", err)
	}

	return strings.TrimSpace(string(output)) == "running", nil
}

// Enable ativa o firewalld
func (f *FirewalldFirewall) Enable() error {
	cmds := []struct {
		name string
		args []string
	}{
		// Iniciar e habilitar o serviço
		{"systemctl", []string{"start", "firewalld"}},
		{"systemctl", []string{"enable", "firewalld"}},
		
		// Configurar regras básicas
		{"firewall-cmd", []string{"--permanent", "--add-service=ssh"}},
		{"firewall-cmd", []string{"--permanent", "--add-port=4554/tcp"}}, // Porta da API Guardian
		
		// Recarregar para aplicar as mudanças
		{"firewall-cmd", []string{"--reload"}},
	}

	for _, cmd := range cmds {
		if err := exec.Command(cmd.name, cmd.args...).Run(); err != nil {
			return fmt.Errorf("erro ao executar '%s %s': %w", cmd.name, strings.Join(cmd.args, " "), err)
		}
	}

	return nil
}

// Disable desativa o firewalld
func (f *FirewalldFirewall) Disable() error {
	cmds := []struct {
		name string
		args []string
	}{
		{"systemctl", []string{"stop", "firewalld"}},
		{"systemctl", []string{"disable", "firewalld"}},
	}

	for _, cmd := range cmds {
		if err := exec.Command(cmd.name, cmd.args...).Run(); err != nil {
			return fmt.Errorf("erro ao executar '%s %s': %w", cmd.name, strings.Join(cmd.args, " "), err)
		}
	}

	return nil
}

// BanIP bane um endereço IP usando o firewalld
func (f *FirewalldFirewall) BanIP(ip string) error {
	ports := []string{"22", "80", "443", "4554"}
	for _, port := range ports {
		rule := fmt.Sprintf("rule family=\"ipv4\" source address=\"%s\" port port=\"%s\" protocol=\"tcp\" reject", ip, port)
		cmd := exec.Command("firewall-cmd", "--permanent", "--add-rich-rule="+rule)
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("erro ao banir IP %s na porta %s: %w", ip, port, err)
		}
		// IPv6
		rule6 := fmt.Sprintf("rule family=\"ipv6\" source address=\"%s\" port port=\"%s\" protocol=\"tcp\" reject", ip, port)
		cmd6 := exec.Command("firewall-cmd", "--permanent", "--add-rich-rule="+rule6)
		_ = cmd6.Run() // Ignorar erro para IPv6 se IP for só IPv4
	}
	cmdReload := exec.Command("firewall-cmd", "--reload")
	_ = cmdReload.Run()
	return nil
}

// UnbanIP remove o banimento de um endereço IP usando o firewalld
func (f *FirewalldFirewall) UnbanIP(ip string) error {
	cmds := []struct {
		name string
		args []string
	}{
		{"firewall-cmd", []string{"--permanent", "--remove-rich-rule=rule family=\"ipv4\" source address=\"" + ip + "\" reject"}},
		{"firewall-cmd", []string{"--reload"}},
	}

	for _, cmd := range cmds {
		if err := exec.Command(cmd.name, cmd.args...).Run(); err != nil {
			return fmt.Errorf("erro ao executar '%s %s': %w", cmd.name, strings.Join(cmd.args, " "), err)
		}
	}

	return nil
}

// Type retorna o tipo do firewall
func (f *FirewalldFirewall) Type() string {
	return "firewalld"
}
