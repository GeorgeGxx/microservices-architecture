package config_test

import (
	"os"
	"testing"

	"github.com/georgegxx/payments-service/config"
	"github.com/stretchr/testify/assert"
)

func TestLoadConfig_Defaults(t *testing.T) {
	cfg := config.LoadConfig()
	assert.NotNil(t, cfg)
	assert.NotEmpty(t, cfg.Port)
	assert.NotEmpty(t, cfg.DBName)
	assert.NotEmpty(t, cfg.GetDSN())
	assert.Contains(t, cfg.GetDSN(), "ms_payments")
}

func TestLoadConfig_Overrides(t *testing.T) {
	os.Setenv("SERVER_PORT", "9999")
	os.Setenv("DB_NAME", "custom_db")
	defer func() {
		os.Unsetenv("SERVER_PORT")
		os.Unsetenv("DB_NAME")
	}()

	cfg := config.LoadConfig()
	assert.Equal(t, "9999", cfg.Port)
	assert.Equal(t, "custom_db", cfg.DBName)
	assert.Contains(t, cfg.GetDSN(), "custom_db")
}
