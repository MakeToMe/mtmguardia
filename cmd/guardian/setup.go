package main

import (
	"flag"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"path/filepath"
	"strings"
)

// setupCommand executa o comando de configuração do Guardian
func setupCommand() {
	// Subcomando setup
	setupCmd := flag.NewFlagSet("setup", flag.ExitOnError)
	dbConnString := setupCmd.String("db-conn-string", "", "String de conexão com o PostgreSQL")

	// Verificar se o comando setup foi chamado
	if len(os.Args) < 2 || os.Args[1] != "setup" {
		return
	}

	// Parsear argumentos do subcomando
	setupCmd.Parse(os.Args[2:])

	// Verificar se a string de conexão foi fornecida
	if *dbConnString == "" {
		fmt.Println("Erro: String de conexão com o PostgreSQL não fornecida.")
		fmt.Println("Uso: guardian setup --db-conn-string='sua_string_de_conexao'")
		os.Exit(1)
	}

	// Caminho do arquivo de configuração
	configDir := "/opt/guardian/config"
	configFile := filepath.Join(configDir, "config.env")

	// Verificar se o arquivo de configuração existe
	if _, err := os.Stat(configFile); os.IsNotExist(err) {
		fmt.Printf("Arquivo de configuração não encontrado: %s\n", configFile)
		fmt.Println("Criando novo arquivo de configuração...")

		// Criar diretório se não existir
		if err := os.MkdirAll(configDir, 0755); err != nil {
			log.Fatalf("Erro ao criar diretório de configuração: %v", err)
		}

		// Criar arquivo de configuração vazio
		if err := ioutil.WriteFile(configFile, []byte{}, 0644); err != nil {
			log.Fatalf("Erro ao criar arquivo de configuração: %v", err)
		}
	}

	// Ler o arquivo de configuração atual
	content, err := ioutil.ReadFile(configFile)
	if err != nil {
		log.Fatalf("Erro ao ler arquivo de configuração: %v", err)
	}

	// Converter para string
	configContent := string(content)

	// Verificar se a variável já existe
	if strings.Contains(configContent, "GUARDIAN_DB_CONN_STRING=") {
		// Substituir a linha existente
		lines := strings.Split(configContent, "\n")
		for i, line := range lines {
			if strings.HasPrefix(line, "GUARDIAN_DB_CONN_STRING=") {
				lines[i] = fmt.Sprintf("GUARDIAN_DB_CONN_STRING=%s", *dbConnString)
				break
			}
		}
		configContent = strings.Join(lines, "\n")
	} else {
		// Adicionar nova linha
		if !strings.HasSuffix(configContent, "\n") && configContent != "" {
			configContent += "\n"
		}
		configContent += fmt.Sprintf("GUARDIAN_DB_CONN_STRING=%s\n", *dbConnString)
	}

	// Salvar o arquivo de configuração
	if err := ioutil.WriteFile(configFile, []byte(configContent), 0644); err != nil {
		log.Fatalf("Erro ao salvar arquivo de configuração: %v", err)
	}

	fmt.Println("String de conexão configurada com sucesso!")
	fmt.Println("Reinicie o serviço Guardian para aplicar as alterações:")
	fmt.Println("sudo systemctl restart guardian")

	// Sair após a configuração
	os.Exit(0)
}
