package config

import (
	"fmt"
	"os"
	"strconv"
)

type Config struct {
	Port                  string
	DBHost                string
	DBPort                string
	DBUser                string
	DBPassword            string
	DBName                string
	DBSSLMode             string
	KafkaBrokers          string
	KafkaOrdersTopic      string
	KafkaPaymentsTopic    string
	KafkaFulfillmentTopic string
	KafkaGroupID          string
	Environment           string
}

func LoadConfig() *Config {
	return &Config{
		Port:                  getEnv("SERVER_PORT", "8085"),
		DBHost:                getEnv("DB_HOST", "localhost"),
		DBPort:                getEnv("DB_PORT", "5436"),
		DBUser:                getEnv("DB_USER", "postgres"),
		DBPassword:            getEnv("DB_PASSWORD", "admin"),
		DBName:                getEnv("DB_NAME", "ms_payments"),
		DBSSLMode:             getEnv("DB_SSLMODE", "disable"),
		KafkaBrokers:          getEnv("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092"),
		KafkaOrdersTopic:      getEnv("KAFKA_ORDERS_TOPIC", "orders-topic"),
		KafkaPaymentsTopic:    getEnv("KAFKA_PAYMENTS_TOPIC", "payments-topic"),
		KafkaFulfillmentTopic: getEnv("KAFKA_FULFILLMENT_TOPIC", "fulfillment-topic"),
		KafkaGroupID:          getEnv("KAFKA_GROUP_ID", "payments-service-group"),
		Environment:           getEnv("ENV", "development"),
	}
}

func (c *Config) GetDSN() string {
	return fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=%s TimeZone=UTC",
		c.DBHost, c.DBPort, c.DBUser, c.DBPassword, c.DBName, c.DBSSLMode)
}

func getEnv(key, defaultVal string) string {
	if val, ok := os.LookupEnv(key); ok && val != "" {
		return val
	}
	return defaultVal
}

func getEnvAsInt(key string, defaultVal int) int {
	valStr := getEnv(key, "")
	if val, err := strconv.Atoi(valStr); err == nil {
		return val
	}
	return defaultVal
}
