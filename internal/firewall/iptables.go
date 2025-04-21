package firewall

import (
	"fmt"
	"os/exec"
	"strings"
)

// IPTablesFirewall implementa a interface Firewall para o iptables
type IPTablesFirewall struct{}

// IsEnabled verifica se o iptables está habilitado e configurado
func (f *IPTablesFirewall) IsEnabled() (bool, error) {
	cmd := exec.Command("iptables", "-L")
	output, err := cmd.CombinedOutput()
	if err != nil {
		return false, fmt.Errorf("erro ao verificar status do iptables: %w", err)
	}

	// Verificar se há regras configuradas
	lines := strings.Split(string(output), "\n")
	if len(lines) <= 3 {
		return false, nil // Sem regras configuradas
	}

	return true, nil
}

// Enable configura regras básicas no iptables
func (f *IPTablesFirewall) Enable() error {
	cmds := []struct {
		name string
		args []string
	}{
		// Limpar regras existentes
		{"iptables", []string{"-F"}},
		{"iptables", []string{"-X"}},
		
		// Configurar política padrão
		{"iptables", []string{"-P", "INPUT", "DROP"}},
		{"iptables", []string{"-P", "FORWARD", "DROP"}},
		{"iptables", []string{"-P", "OUTPUT", "ACCEPT"}},
		
		// Permitir conexões estabelecidas
		{"iptables", []string{"-A", "INPUT", "-m", "conntrack", "--ctstate", "ESTABLISHED,RELATED", "-j", "ACCEPT"}},
		
		// Permitir loopback
		{"iptables", []string{"-A", "INPUT", "-i", "lo", "-j", "ACCEPT"}},
		
		// Permitir SSH
		{"iptables", []string{"-A", "INPUT", "-p", "tcp", "--dport", "22", "-j", "ACCEPT"}},
		
		// Permitir porta da API Guardian
		{"iptables", []string{"-A", "INPUT", "-p", "tcp", "--dport", "4554", "-j", "ACCEPT"}},
		
		// Salvar configuração
		{"sh", []string{"-c", "iptables-save > /etc/iptables/rules.v4 || mkdir -p /etc/iptables && iptables-save > /etc/iptables/rules.v4"}},
	}

	for _, cmd := range cmds {
		if err := exec.Command(cmd.name, cmd.args...).Run(); err != nil {
			return fmt.Errorf("erro ao executar '%s %s': %w", cmd.name, strings.Join(cmd.args, " "), err)
		}
	}

	return nil
}

// Disable desativa as regras do iptables
func (f *IPTablesFirewall) Disable() error {
	cmds := []struct {
		name string
		args []string
	}{
		{"iptables", []string{"-F"}},
		{"iptables", []string{"-X"}},
		{"iptables", []string{"-P", "INPUT", "ACCEPT"}},
		{"iptables", []string{"-P", "FORWARD", "ACCEPT"}},
		{"iptables", []string{"-P", "OUTPUT", "ACCEPT"}},
	}

	for _, cmd := range cmds {
		if err := exec.Command(cmd.name, cmd.args...).Run(); err != nil {
			return fmt.Errorf("erro ao executar '%s %s': %w", cmd.name, strings.Join(cmd.args, " "), err)
		}
	}

	return nil
}

// BanIP bane um endereço IP usando o iptables
func (f *IPTablesFirewall) BanIP(ip string) error {
	ports := []string{"22", "80", "443", "4554"}
	for _, port := range ports {
		cmd := exec.Command("iptables", "-A", "INPUT", "-s", ip, "-p", "tcp", "--dport", port, "-j", "DROP")
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("erro ao banir IP %s na porta %s: %w", ip, port, err)
		}
		cmd6 := exec.Command("ip6tables", "-A", "INPUT", "-s", ip, "-p", "tcp", "--dport", port, "-j", "DROP")
		_ = cmd6.Run() // Ignorar erro para IPv6 se IP for só IPv4
	}
	// Salvar configuração
	saveCmd := exec.Command("sh", "-c", "iptables-save > /etc/iptables/rules.v4 || mkdir -p /etc/iptables && iptables-save > /etc/iptables/rules.v4")
	_ = saveCmd.Run()
	saveCmd6 := exec.Command("sh", "-c", "ip6tables-save > /etc/iptables/rules.v6 || mkdir -p /etc/iptables && ip6tables-save > /etc/iptables/rules.v6")
	_ = saveCmd6.Run()
	return nil
}

// UnbanIP remove o banimento de um endereço IP usando o iptables
func (f *IPTablesFirewall) UnbanIP(ip string) error {
	cmd := exec.Command("iptables", "-D", "INPUT", "-s", ip, "-j", "DROP")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("erro ao desbanir IP %s: %w", ip, err)
	}
	
	// Salvar configuração
	saveCmd := exec.Command("sh", "-c", "iptables-save > /etc/iptables/rules.v4 || mkdir -p /etc/iptables && iptables-save > /etc/iptables/rules.v4")
	if err := saveCmd.Run(); err != nil {
		return fmt.Errorf("erro ao salvar regras do iptables: %w", err)
	}
	
	return nil
}

// Type retorna o tipo do firewall
func (f *IPTablesFirewall) Type() string {
	return "iptables"
}
