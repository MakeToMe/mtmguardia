package firewall

import (
	"testing"

	"github.com/mtm/guardian/internal/config"
)

// TestFirewallTypeDetection testa a detecção do tipo de firewall
func TestFirewallTypeDetection(t *testing.T) {
	// Teste com tipo específico
	cfg := &config.Config{
		FirewallType: "ufw",
	}

	fw, err := New(cfg)
	if err != nil {
		t.Fatalf("Erro ao criar firewall: %v", err)
	}

	if fw.Type() != "ufw" {
		t.Errorf("Tipo de firewall esperado: ufw, obtido: %s", fw.Type())
	}

	// Teste com tipo inválido
	cfg = &config.Config{
		FirewallType: "invalid",
	}

	_, err = New(cfg)
	if err == nil {
		t.Error("Deveria retornar erro para tipo de firewall inválido")
	}
}

// MockFirewall implementa a interface Firewall para testes
type MockFirewall struct {
	enabled bool
	banned  map[string]bool
}

func NewMockFirewall() *MockFirewall {
	return &MockFirewall{
		enabled: false,
		banned:  make(map[string]bool),
	}
}

func (f *MockFirewall) IsEnabled() (bool, error) {
	return f.enabled, nil
}

func (f *MockFirewall) Enable() error {
	f.enabled = true
	return nil
}

func (f *MockFirewall) Disable() error {
	f.enabled = false
	return nil
}

func (f *MockFirewall) BanIP(ip string) error {
	f.banned[ip] = true
	return nil
}

func (f *MockFirewall) UnbanIP(ip string) error {
	delete(f.banned, ip)
	return nil
}

func (f *MockFirewall) Type() string {
	return "mock"
}

// TestMockFirewall testa a implementação do MockFirewall
func TestMockFirewall(t *testing.T) {
	fw := NewMockFirewall()

	// Testar habilitação
	enabled, err := fw.IsEnabled()
	if err != nil {
		t.Fatalf("Erro ao verificar status: %v", err)
	}
	if enabled {
		t.Error("Firewall deveria estar desabilitado inicialmente")
	}

	// Testar ativação
	if err := fw.Enable(); err != nil {
		t.Fatalf("Erro ao ativar firewall: %v", err)
	}

	enabled, _ = fw.IsEnabled()
	if !enabled {
		t.Error("Firewall deveria estar habilitado após Enable()")
	}

	// Testar banimento de IP
	ip := "192.168.1.100"
	if err := fw.BanIP(ip); err != nil {
		t.Fatalf("Erro ao banir IP: %v", err)
	}
	if !fw.banned[ip] {
		t.Errorf("IP %s deveria estar banido", ip)
	}

	// Testar desbanimento de IP
	if err := fw.UnbanIP(ip); err != nil {
		t.Fatalf("Erro ao desbanir IP: %v", err)
	}
	if fw.banned[ip] {
		t.Errorf("IP %s não deveria estar banido após UnbanIP()", ip)
	}

	// Testar desativação
	if err := fw.Disable(); err != nil {
		t.Fatalf("Erro ao desativar firewall: %v", err)
	}

	enabled, _ = fw.IsEnabled()
	if enabled {
		t.Error("Firewall deveria estar desabilitado após Disable()")
	}
}
