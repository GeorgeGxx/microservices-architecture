package config

import (
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestLoadConfig_Defaults(t *testing.T) {
	cfg := LoadConfig()
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

	cfg := LoadConfig()
	assert.Equal(t, "9999", cfg.Port)
	assert.Equal(t, "custom_db", cfg.DBName)
	assert.Contains(t, cfg.GetDSN(), "custom_db")
}

func TestGetEnvAsInt(t *testing.T) {
	// Default when unset
	assert.Equal(t, 10, getEnvAsInt("NON_EXISTENT_VAR", 10))

	// Valid integer
	os.Setenv("SAMPLE_INT", "123")
	defer os.Unsetenv("SAMPLE_INT")
	assert.Equal(t, 123, getEnvAsInt("SAMPLE_INT", 10))

	// Invalid integer fallback
	os.Setenv("SAMPLE_INVALID_INT", "abc")
	defer os.Unsetenv("SAMPLE_INVALID_INT")
	assert.Equal(t, 10, getEnvAsInt("SAMPLE_INVALID_INT", 10))
}
