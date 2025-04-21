package main

import (
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/mtm/guardian/internal/api"
	"github.com/mtm/guardian/internal/bruteforce"
	"github.com/mtm/guardian/internal/config"
	"github.com/mtm/guardian/internal/firewall"
)

func main() {
	// Verificar se é um comando de setup
	if len(os.Args) > 1 && os.Args[1] == "setup" {
		setupCommand()
		return
	}

	log.Println("Iniciando Guardian - Gerenciador de Firewall")

	// Carregar configurações
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Erro ao carregar configurações: %v", err)
	}

	// Verificar e configurar o firewall
	fw, err := firewall.New(cfg)
	if err != nil {
		log.Fatalf("Erro ao inicializar o firewall: %v", err)
	}

	// Verificar se o firewall está habilitado
	enabled, err := fw.IsEnabled()
	if err != nil {
		log.Fatalf("Erro ao verificar status do firewall: %v", err)
	}

	if !enabled {
		log.Println("Firewall não está habilitado. Ativando...")
		if err := fw.Enable(); err != nil {
			log.Fatalf("Erro ao ativar o firewall: %v", err)
		}
		log.Println("Firewall ativado com sucesso")
	} else {
		log.Printf("Firewall já está habilitado (%s)", fw.Type())
	}

	// Iniciar o servidor API
	server := api.NewServer(cfg, fw)
	go func() {
		if err := server.Start(); err != nil {
			log.Fatalf("Erro ao iniciar o servidor API: %v", err)
		}
	}()

	// Iniciar o detector de força bruta
	detector := bruteforce.NewDetector(cfg)
	go detector.Start()

	fmt.Printf("Guardian está em execução em http://%s:%d/guardian\n", cfg.IP, cfg.Port)

	// Aguardar sinal para encerrar graciosamente
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	<-sigChan

	log.Println("Encerrando Guardian...")
	if err := server.Shutdown(); err != nil {
		log.Fatalf("Erro ao encerrar o servidor: %v", err)
	}
}
