package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"time"

	"github.com/mtm/guardian/internal/bruteforce"
	"github.com/mtm/guardian/internal/config"
	"github.com/mtm/guardian/internal/database"
)

func main() {
	// Configurar log
	log.SetFlags(log.LstdFlags | log.Lshortfile)
	logFile := filepath.Join(os.TempDir(), "guardian_bruteforce_processor.log")
	f, err := os.OpenFile(logFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		log.Printf("Erro ao abrir arquivo de log: %v", err)
	} else {
		defer f.Close()
		log.SetOutput(f)
	}

	// Definir flags
	logFilePath := flag.String("log", "/opt/guardian/data/bruteforce.log", "Caminho para o arquivo de log")
	minCount := flag.Int("min", 3, "Número mínimo de tentativas para considerar um IP suspeito")
	flag.Parse()

	log.Printf("Iniciando processador de força bruta")
	log.Printf("Arquivo de log: %s", *logFilePath)
	log.Printf("Contagem mínima: %d", *minCount)

	// Carregar configuração
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Erro ao carregar configuração: %v", err)
	}

	// Verificar se a conexão com o banco de dados está configurada
	if cfg.DBConnString == "" {
		log.Println("String de conexão com o banco de dados não configurada")
		log.Println("Os IPs serão processados, mas não serão enviados para o banco de dados")
		
		// Processar o arquivo de log e salvar em JSON
		entries, err := processLogToJSON(cfg, *logFilePath, *minCount)
		if err != nil {
			log.Fatalf("Erro ao processar arquivo de log: %v", err)
		}
		
		log.Printf("Processamento concluído. %d IPs encontrados", len(entries))
		return
	}

	// Conectar ao banco de dados
	log.Println("Conectando ao banco de dados...")
	dbClient, err := database.NewPostgresClient(cfg)
	if err != nil {
		log.Fatalf("Erro ao conectar ao banco de dados: %v", err)
	}
	defer dbClient.Close()

	// Criar processador
	processor := bruteforce.NewProcessor(*logFilePath, dbClient, *minCount)

	// Processar arquivo de log e enviar para o banco de dados
	log.Println("Processando arquivo de log e enviando para o banco de dados...")
	if err := processor.ProcessLogAndSendToDatabase(); err != nil {
		log.Fatalf("Erro ao processar arquivo de log: %v", err)
	}

	log.Println("Processamento concluído com sucesso")
}

// processLogToJSON processa o arquivo de log e salva em JSON quando não há conexão com o banco
func processLogToJSON(cfg *config.Config, logFilePath string, minCount int) ([]bruteforce.IPEntry, error) {
	// Criar processador sem cliente de banco de dados
	processor := bruteforce.NewProcessor(logFilePath, nil, minCount)

	// Extrair IPs do arquivo de log
	entries, err := processor.ExtractIPsFromLog()
	if err != nil {
		return nil, fmt.Errorf("erro ao extrair IPs do arquivo de log: %w", err)
	}

	// Salvar em JSON
	jsonPath := filepath.Join(cfg.InstallDir, "data", "bruteforce_processed.json")
	if err := processor.SaveIPsToJSON(jsonPath); err != nil {
		return nil, fmt.Errorf("erro ao salvar IPs em JSON: %w", err)
	}

	return entries, nil
}
