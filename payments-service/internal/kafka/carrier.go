package kafka

import (
	"strings"

	"github.com/segmentio/kafka-go"
)

// HeaderCarrier adapts kafka.Header slice for OpenTelemetry TextMapCarrier.
type HeaderCarrier []kafka.Header

func (c *HeaderCarrier) Get(key string) string {
	for _, h := range *c {
		if strings.EqualFold(h.Key, key) {
			return string(h.Value)
		}
	}
	return ""
}

func (c *HeaderCarrier) Set(key, value string) {
	for i, h := range *c {
		if strings.EqualFold(h.Key, key) {
			(*c)[i].Value = []byte(value)
			return
		}
	}
	*c = append(*c, kafka.Header{Key: key, Value: []byte(value)})
}

func (c *HeaderCarrier) Keys() []string {
	keys := make([]string, len(*c))
	for i, h := range *c {
		keys[i] = h.Key
	}
	return keys
}
