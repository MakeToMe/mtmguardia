package bruteforce

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"regexp"
	"strconv"
	"time"

	"github.com/mtm/guardian/internal/database"
)

// Processor processa os logs de força bruta e envia para o PostgreSQL
type Processor struct {
	logFilePath string
	dbClient    *database.PostgresClient
	minCount    int
}

// IPEntry representa uma entrada de IP detectado no log
type IPEntry struct {
	IP        string
	Count     int
	Timestamp time.Time
}

// NewProcessor cria um novo processador de logs
func NewProcessor(logFilePath string, dbClient *database.PostgresClient, minCount int) *Processor {
	return &Processor{
		logFilePath: logFilePath,
		dbClient:    dbClient,
		minCount:    minCount,
	}
}

// ProcessLogAndSendToDatabase processa o arquivo de log e envia os IPs para o banco de dados
func (p *Processor) ProcessLogAndSendToDatabase() error {
	// Verificar se o arquivo de log existe
	if _, err := os.Stat(p.logFilePath); os.IsNotExist(err) {
		return fmt.Errorf("arquivo de log não encontrado: %s", p.logFilePath)
	}

	// Abrir o arquivo de log
	file, err := os.Open(p.logFilePath)
	if err != nil {
		return fmt.Errorf("erro ao abrir arquivo de log: %w", err)
	}
	defer file.Close()

	// Compilar regex para extrair IPs e contagens
	re := regexp.MustCompile(`Detectado IP com múltiplas tentativas: (\d+\.\d+\.\d+\.\d+) \(contagem: (\d+)\)`)

	// Mapa para armazenar IPs únicos (para evitar duplicatas)
	uniqueIPs := make(map[string]bool)

	// Processar o arquivo linha por linha
	scanner := bufio.NewScanner(file)
	processedCount := 0
	
	log.Printf("Processando arquivo de log: %s", p.logFilePath)
	
	for scanner.Scan() {
		line := scanner.Text()
		matches := re.FindStringSubmatch(line)
		
		if len(matches) == 3 {
			ip := matches[1]
			countStr := matches[2]
			
			// Converter contagem para inteiro
			count, err := strconv.Atoi(countStr)
			if err != nil {
				log.Printf("Erro ao converter contagem para IP %s: %v", ip, err)
				continue
			}
			
			// Verificar se a contagem é maior ou igual ao mínimo
			if count >= p.minCount && !uniqueIPs[ip] {
				// Marcar IP como processado
				uniqueIPs[ip] = true
				
				// Enviar para o banco de dados
				ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
				if err := p.dbClient.InsertBannedIP(ctx, ip); err != nil {
					cancel()
					log.Printf("Erro ao enviar IP %s para o banco de dados: %v", ip, err)
				} else {
					cancel()
					processedCount++
					log.Printf("IP %s enviado para o banco de dados (contagem: %d)", ip, count)
				}
			}
		}
	}
	
	if err := scanner.Err(); err != nil {
		return fmt.Errorf("erro ao ler arquivo de log: %w", err)
	}
	
	log.Printf("Processamento concluído. %d IPs enviados para o banco de dados", processedCount)
	return nil
}

// ExtractIPsFromLog extrai IPs do arquivo de log sem enviar para o Supabase
func (p *Processor) ExtractIPsFromLog() ([]IPEntry, error) {
	// Verificar se o arquivo de log existe
	if _, err := os.Stat(p.logFilePath); os.IsNotExist(err) {
		return nil, fmt.Errorf("arquivo de log não encontrado: %s", p.logFilePath)
	}

	// Abrir o arquivo de log
	file, err := os.Open(p.logFilePath)
	if err != nil {
		return nil, fmt.Errorf("erro ao abrir arquivo de log: %w", err)
	}
	defer file.Close()

	// Compilar regex para extrair IPs e contagens
	re := regexp.MustCompile(`\[([^\]]+)\] Detectado IP com múltiplas tentativas: (\d+\.\d+\.\d+\.\d+) \(contagem: (\d+)\)`)

	// Slice para armazenar os resultados
	var entries []IPEntry

	// Processar o arquivo linha por linha
	scanner := bufio.NewScanner(file)
	
	for scanner.Scan() {
		line := scanner.Text()
		matches := re.FindStringSubmatch(line)
		
		if len(matches) == 4 {
			timestampStr := matches[1]
			ip := matches[2]
			countStr := matches[3]
			
			// Converter contagem para inteiro
			count, err := strconv.Atoi(countStr)
			if err != nil {
				log.Printf("Erro ao converter contagem para IP %s: %v", ip, err)
				continue
			}
			
			// Converter timestamp
			timestamp, err := time.Parse("2006-01-02 15:04:05", timestampStr)
			if err != nil {
				// Se falhar, usar timestamp atual
				timestamp = time.Now()
			}
			
			// Verificar se a contagem é maior ou igual ao mínimo
			if count >= p.minCount {
				entries = append(entries, IPEntry{
					IP:        ip,
					Count:     count,
					Timestamp: timestamp,
				})
			}
		}
	}
	
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("erro ao ler arquivo de log: %w", err)
	}
	
	return entries, nil
}

// SaveIPsToJSON salva os IPs extraídos em um arquivo JSON
func (p *Processor) SaveIPsToJSON(outputPath string) error {
	entries, err := p.ExtractIPsFromLog()
	if err != nil {
		return err
	}
	
	// Verificar se existem entradas
	if len(entries) == 0 {
		log.Printf("Nenhum IP encontrado no log com contagem >= %d", p.minCount)
		return nil
	}
	
	// Criar estrutura para o JSON
	type jsonEntry struct {
		IP        string    `json:"ip"`
		Count     int       `json:"count"`
		Timestamp time.Time `json:"timestamp"`
	}
	
	jsonEntries := make([]jsonEntry, len(entries))
	for i, entry := range entries {
		jsonEntries[i] = jsonEntry{
			IP:        entry.IP,
			Count:     entry.Count,
			Timestamp: entry.Timestamp,
		}
	}
	
	// Converter para JSON
	jsonData, err := json.Marshal(jsonEntries)
	if err != nil {
		return fmt.Errorf("erro ao converter para JSON: %w", err)
	}
	
	// Salvar no arquivo
	if err := ioutil.WriteFile(outputPath, jsonData, 0644); err != nil {
		return fmt.Errorf("erro ao salvar arquivo JSON: %w", err)
	}
	
	log.Printf("%d IPs salvos no arquivo JSON: %s", len(entries), outputPath)
	return nil
}
