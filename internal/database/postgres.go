package database

import (
	"context"
	"database/sql"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"regexp"
	"strconv"
	"time"

	"github.com/google/uuid"
	"github.com/lib/pq"
	_ "github.com/lib/pq"
	"github.com/mtm/guardian/internal/config"
)

// PostgresClient representa um cliente para o PostgreSQL
type PostgresClient struct {
	db       *sql.DB
	cfg      *config.Config
	schema   string
	serverIP string
}

// BannedIP representa um IP banido no banco de dados
type BannedIP struct {
	IP        string
	Count     int
	Timestamp time.Time
}

// NewPostgresClient cria um novo cliente PostgreSQL
func NewPostgresClient(cfg *config.Config) (*PostgresClient, error) {
	if cfg.DBConnString == "" {
		return nil, fmt.Errorf("string de conexão com o banco de dados não configurada")
	}

	// Conectar ao banco de dados
	db, err := sql.Open("postgres", cfg.DBConnString)
	if err != nil {
		return nil, fmt.Errorf("erro ao conectar ao banco de dados: %w", err)
	}

	// Testar conexão
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := db.PingContext(ctx); err != nil {
		db.Close()
		return nil, fmt.Errorf("erro ao testar conexão com o banco de dados: %w", err)
	}

	// Definir configurações do pool de conexões
	db.SetMaxOpenConns(5)
	db.SetMaxIdleConns(2)
	db.SetConnMaxLifetime(time.Hour)

	schema := cfg.DBSchema
	if schema == "" {
		schema = "mtm"
	}

	return &PostgresClient{
		db:       db,
		cfg:      cfg,
		schema:   schema,
		serverIP: cfg.IP,
	}, nil
}

// Close fecha a conexão com o banco de dados
func (c *PostgresClient) Close() error {
	return c.db.Close()
}

// GetServerInfo busca o servidor_id (uid) e titular com base no IP do servidor
func (c *PostgresClient) GetServerInfo(ctx context.Context) (string, string, error) {
	query := fmt.Sprintf(`
		SELECT uid, titular FROM %s.servidores WHERE ip = $1 LIMIT 1
	`, c.schema)

	var serverID, titularID string
	err := c.db.QueryRowContext(ctx, query, c.serverIP).Scan(&serverID, &titularID)
	if err != nil {
		if err == sql.ErrNoRows {
			// Se o servidor não for encontrado, tentar criar um novo registro
			return c.createServerRecord(ctx)
		}
		return "", "", fmt.Errorf("erro ao buscar informações do servidor: %w", err)
	}

	return serverID, titularID, nil
}

// createServerRecord cria um novo registro de servidor no banco de dados
func (c *PostgresClient) createServerRecord(ctx context.Context) (string, string, error) {
	// Verificar se temos informações sobre o sistema
	hostname, err := os.Hostname()
	if err != nil {
		hostname = "servidor-" + c.serverIP
	}

	// Buscar o primeiro titular disponível (administrador)
	titularQuery := fmt.Sprintf(`
		SELECT id FROM %s.users WHERE role = 'admin' LIMIT 1
	`, c.schema)

	var titularID string
	err = c.db.QueryRowContext(ctx, titularQuery).Scan(&titularID)
	if err != nil {
		if err == sql.ErrNoRows {
			return "", "", fmt.Errorf("nenhum usuário administrador encontrado no banco de dados")
		}
		return "", "", fmt.Errorf("erro ao buscar titular: %w", err)
	}

	// Gerar um UUID para o servidor
	serverID := uuid.New().String()

	// Inserir o novo servidor
	insertQuery := fmt.Sprintf(`
		INSERT INTO %s.servidores (uid, titular, ip, nome, sistema, created_at)
		VALUES ($1, $2, $3, $4, $5, NOW())
	`, c.schema)

	_, err = c.db.ExecContext(
		ctx,
		insertQuery,
		serverID,
		titularID,
		c.serverIP,
		hostname,
		"Linux",
	)

	if err != nil {
		return "", "", fmt.Errorf("erro ao criar registro de servidor: %w", err)
	}

	log.Printf("Novo servidor registrado com sucesso. ID: %s, Titular: %s", serverID, titularID)
	return serverID, titularID, nil
}

// InsertBannedIP insere um IP banido no banco de dados
func (c *PostgresClient) InsertBannedIP(ctx context.Context, ip string) error {
	// Buscar servidor_id e titular
	serverID, titularID, err := c.GetServerInfo(ctx)
	if err != nil {
		return fmt.Errorf("erro ao obter informações do servidor: %w", err)
	}

	// Verificar se os valores necessários estão presentes
	if serverID == "" || titularID == "" {
		return fmt.Errorf("serverID ou titularID não encontrados")
	}

	// Verificar se o IP já está banido
	checkQuery := fmt.Sprintf(`
		SELECT COUNT(*) FROM %s.banned_ips 
		WHERE servidor_id = $1 AND ip_banido = $2
	`, c.schema)

	var count int
	err = c.db.QueryRowContext(ctx, checkQuery, serverID, ip).Scan(&count)
	if err != nil {
		return fmt.Errorf("erro ao verificar IP banido: %w", err)
	}

	// Se o IP já está banido, apenas atualizar
	if count > 0 {
		updateQuery := fmt.Sprintf(`
			UPDATE %s.banned_ips 
			SET updated_at = NOW(), active = TRUE 
			WHERE servidor_id = $1 AND ip_banido = $2
		`, c.schema)

		_, err := c.db.ExecContext(ctx, updateQuery, serverID, ip)
		if err != nil {
			return fmt.Errorf("erro ao atualizar IP banido: %w", err)
		}

		log.Printf("IP %s já está banido. Registro atualizado.", ip)
		return nil
	}

	// Inserir novo IP banido
	insertQuery := fmt.Sprintf(`
		INSERT INTO %s.banned_ips 
		(servidor_id, titular, active, servidor_ip, ip_banido) 
		VALUES ($1, $2, $3, $4, $5)
	`, c.schema)

	_, err = c.db.ExecContext(
		ctx,
		insertQuery,
		serverID,
		titularID,
		true,
		c.serverIP,
		ip,
	)

	if err != nil {
		return fmt.Errorf("erro ao inserir IP banido: %w", err)
	}

	log.Printf("IP %s banido com sucesso.", ip)
	return nil
}

// InsertBannedIPs insere múltiplos IPs banidos no banco de dados em uma única transação
func (c *PostgresClient) InsertBannedIPs(ctx context.Context, ips []BannedIP) error {
	if len(ips) == 0 {
		return nil
	}

	// Buscar servidor_id e titular
	serverID, titularID, err := c.GetServerInfo(ctx)
	if err != nil {
		return fmt.Errorf("erro ao obter informações do servidor: %w", err)
	}

	// Verificar se os valores necessários estão presentes
	if serverID == "" || titularID == "" {
		return fmt.Errorf("serverID ou titularID não encontrados")
	}

	// Iniciar transação
	tx, err := c.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("erro ao iniciar transação: %w", err)
	}
	defer tx.Rollback() // Rollback em caso de erro

	// Verificar IPs já banidos
	checkQuery := fmt.Sprintf(`
		SELECT ip_banido FROM %s.banned_ips 
		WHERE servidor_id = $1 AND ip_banido = ANY($2)
	`, c.schema)

	// Criar array de IPs para verificar
	ipArray := make([]string, len(ips))
	for i, ip := range ips {
		ipArray[i] = ip.IP
	}

	// Executar consulta para verificar IPs já banidos
	rows, err := tx.QueryContext(ctx, checkQuery, serverID, pq.Array(ipArray))
	if err != nil {
		return fmt.Errorf("erro ao verificar IPs banidos: %w", err)
	}

	// Mapear IPs já banidos
	existingIPs := make(map[string]bool)
	for rows.Next() {
		var ip string
		if err := rows.Scan(&ip); err != nil {
			rows.Close()
			return fmt.Errorf("erro ao ler IP banido: %w", err)
		}
		existingIPs[ip] = true
	}
	rows.Close()

	if err := rows.Err(); err != nil {
		return fmt.Errorf("erro ao iterar sobre IPs banidos: %w", err)
	}

	// Preparar statements para inserção e atualização
	insertQuery := fmt.Sprintf(`
		INSERT INTO %s.banned_ips 
		(servidor_id, titular, active, servidor_ip, ip_banido) 
		VALUES ($1, $2, $3, $4, $5)
	`, c.schema)

	updateQuery := fmt.Sprintf(`
		UPDATE %s.banned_ips 
		SET updated_at = NOW(), active = TRUE 
		WHERE servidor_id = $1 AND ip_banido = $2
	`, c.schema)

	insertStmt, err := tx.PrepareContext(ctx, insertQuery)
	if err != nil {
		return fmt.Errorf("erro ao preparar statement de inserção: %w", err)
	}
	defer insertStmt.Close()

	updateStmt, err := tx.PrepareContext(ctx, updateQuery)
	if err != nil {
		return fmt.Errorf("erro ao preparar statement de atualização: %w", err)
	}
	defer updateStmt.Close()

	// Inserir ou atualizar cada IP
	insertedCount := 0
	updatedCount := 0

	for _, ip := range ips {
		if existingIPs[ip.IP] {
			// Atualizar IP existente
			_, err := updateStmt.ExecContext(ctx, serverID, ip.IP)
			if err != nil {
				return fmt.Errorf("erro ao atualizar IP %s: %w", ip.IP, err)
			}
			updatedCount++
		} else {
			// Inserir novo IP
			_, err := insertStmt.ExecContext(
				ctx,
				serverID,
				titularID,
				true,
				c.serverIP,
				ip.IP,
			)
			if err != nil {
				return fmt.Errorf("erro ao inserir IP %s: %w", ip.IP, err)
			}
			insertedCount++
		}
	}

	// Commit da transação
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("erro ao finalizar transação: %w", err)
	}

	log.Printf("Processamento de IPs banidos concluído: %d inseridos, %d atualizados", insertedCount, updatedCount)
	return nil
}
