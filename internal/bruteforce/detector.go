package bruteforce

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/mtm/guardian/internal/config"
)

// LoginAttempt representa uma tentativa de login malsucedida
type LoginAttempt struct {
	IP        string    `json:"ip"`
	Count     int       `json:"count"`
	Timestamp time.Time `json:"timestamp"`
}

// Detector é responsável por detectar tentativas de força bruta
type Detector struct {
	cfg            *config.Config
	outputFilePath string
	minAttempts    int
}

// NewDetector cria uma nova instância do detector de força bruta
func NewDetector(cfg *config.Config) *Detector {
	return &Detector{
		cfg:            cfg,
		outputFilePath: filepath.Join(cfg.InstallDir, "data", "bruteforce.json"),
		minAttempts:    3, // Número mínimo de tentativas para considerar como força bruta
	}
}

// Start inicia o detector em um loop
func (d *Detector) Start() {
	// Criar diretório de dados se não existir
	dataDir := filepath.Dir(d.outputFilePath)
	if err := os.MkdirAll(dataDir, 0755); err != nil {
		fmt.Printf("Erro ao criar diretório de dados: %v\n", err)
		return
	}

	fmt.Printf("Detector de força bruta iniciado. Arquivo de saída: %s\n", d.outputFilePath)

	// Executar imediatamente a primeira vez
	err := d.Detect()
	if err != nil {
		fmt.Printf("Erro na primeira execução do detector: %v\n", err)
	}

	// Configurar ticker para executar a cada 5 minutos
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()

	fmt.Printf("Detector configurado para executar a cada 5 minutos\n")

	for range ticker.C {
		err := d.Detect()
		if err != nil {
			fmt.Printf("Erro na execução do detector: %v\n", err)
		}
	}
}

// Detect executa a detecção de força bruta
func (d *Detector) Detect() error {
	// Executar comando para obter tentativas de login malsucedidas
	cmd := exec.Command("bash", "-c", "sudo lastb | awk '{ print $3 }' | sort | uniq -c | sort -nr")
	output, err := cmd.CombinedOutput()
	if err != nil {
		fmt.Printf("Aviso: erro ao executar comando lastb: %v\n", err)
		fmt.Printf("Saída do comando: %s\n", string(output))
		// Criar um arquivo JSON vazio para evitar erros
		emptyData, _ := json.MarshalIndent([]LoginAttempt{}, "", "  ")
		ioutil.WriteFile(d.outputFilePath, emptyData, 0644)
		return err
	}

	// Processar a saída
	attempts, err := d.parseOutput(string(output))
	if err != nil {
		return fmt.Errorf("erro ao processar saída: %w", err)
	}

	// Filtrar apenas tentativas com contagem >= minAttempts
	var filteredAttempts []LoginAttempt
	for _, attempt := range attempts {
		if attempt.Count >= d.minAttempts {
			filteredAttempts = append(filteredAttempts, attempt)
		}
	}

	// Salvar resultado em JSON
	return d.saveToJSON(filteredAttempts)
}

// parseOutput converte a saída do comando em uma lista de LoginAttempt
func (d *Detector) parseOutput(output string) ([]LoginAttempt, error) {
	lines := strings.Split(strings.TrimSpace(output), "\n")
	var attempts []LoginAttempt
	now := time.Now()

	// Regex para extrair contagem e IP
	re := regexp.MustCompile(`^\s*(\d+)\s+(\S+)`)

	for _, line := range lines {
		matches := re.FindStringSubmatch(line)
		if len(matches) != 3 {
			continue
		}

		count, err := strconv.Atoi(matches[1])
		if err != nil {
			continue
		}

		ip := matches[2]
		// Validar IP (simplificado)
		if !isValidIP(ip) {
			continue
		}

		attempts = append(attempts, LoginAttempt{
			IP:        ip,
			Count:     count,
			Timestamp: now,
		})
	}

	return attempts, nil
}

// saveToJSON salva as tentativas em um arquivo JSON
func (d *Detector) saveToJSON(attempts []LoginAttempt) error {
	data, err := json.MarshalIndent(attempts, "", "  ")
	if err != nil {
		return fmt.Errorf("erro ao serializar JSON: %w", err)
	}

	// Garantir que o diretório existe
	dataDir := filepath.Dir(d.outputFilePath)
	if err := os.MkdirAll(dataDir, 0755); err != nil {
		fmt.Printf("Erro ao criar diretório de dados: %v\n", err)
	}

	if err := ioutil.WriteFile(d.outputFilePath, data, 0644); err != nil {
		fmt.Printf("Erro ao salvar arquivo JSON: %v\n", err)
		return err
	}

	fmt.Printf("Dados de força bruta salvos em %s (%d IPs detectados)\n", d.outputFilePath, len(attempts))
	
	// Mostrar o conteúdo do arquivo para debug
	fmt.Printf("Conteúdo do arquivo JSON:\n%s\n", string(data))
	return nil
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
