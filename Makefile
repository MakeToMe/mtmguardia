.PHONY: build test clean install

# Variáveis
BINARY_NAME=guardian
BUILD_DIR=bin
INSTALL_DIR=/opt/guardian

# Compilação
build:
	@echo "Compilando $(BINARY_NAME)..."
	@mkdir -p $(BUILD_DIR)
	@go build -o $(BUILD_DIR)/$(BINARY_NAME) cmd/guardian/main.go
	@echo "Compilação concluída: $(BUILD_DIR)/$(BINARY_NAME)"

# Testes
test:
	@echo "Executando testes..."
	@go test -v ./...

# Limpeza
clean:
	@echo "Limpando arquivos temporários..."
	@rm -rf $(BUILD_DIR)
	@go clean
	@echo "Limpeza concluída"

# Instalação (apenas para desenvolvimento local)
install: build
	@echo "Instalando $(BINARY_NAME)..."
	@mkdir -p $(INSTALL_DIR)
	@cp $(BUILD_DIR)/$(BINARY_NAME) $(INSTALL_DIR)/
	@echo "Instalação concluída"

# Execução local para testes
run: build
	@echo "Executando $(BINARY_NAME)..."
	@$(BUILD_DIR)/$(BINARY_NAME)

# Gerar token de autenticação para testes
gen-token:
	@echo "Gerando token de autenticação..."
	@openssl rand -hex 16
