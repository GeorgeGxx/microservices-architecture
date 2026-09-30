package com.georgegxx.notification_service.config;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.kafka.autoconfigure.ConcurrentKafkaListenerContainerFactoryConfigurer;
import org.springframework.kafka.config.ConcurrentKafkaListenerContainerFactory;
import org.springframework.kafka.core.ConsumerFactory;
import org.springframework.kafka.core.KafkaOperations;
import org.springframework.kafka.listener.CommonErrorHandler;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

class KafkaConsumerConfigTest {

    private final KafkaConsumerConfig config = new KafkaConsumerConfig();

    @Test
    @DisplayName("errorHandler should create a default error handler")
    void testErrorHandler() {
        @SuppressWarnings("unchecked")
        KafkaOperations<Object, Object> ops = mock(KafkaOperations.class);
        CommonErrorHandler handler = config.errorHandler(ops);
        assertThat(handler).isNotNull();
    }

    @Test
    @DisplayName("kafkaListenerContainerFactory should configure virtual threads and error handler")
    void testKafkaListenerContainerFactory() {
        ConcurrentKafkaListenerContainerFactoryConfigurer configurer = mock(ConcurrentKafkaListenerContainerFactoryConfigurer.class);
        @SuppressWarnings("unchecked")
        ConsumerFactory<Object, Object> consumerFactory = mock(ConsumerFactory.class);
        CommonErrorHandler errorHandler = mock(CommonErrorHandler.class);

        ConcurrentKafkaListenerContainerFactory<Object, Object> factory =
                config.kafkaListenerContainerFactory(configurer, consumerFactory, errorHandler);

        assertThat(factory).isNotNull();
        assertThat(factory.getContainerProperties().getListenerTaskExecutor()).isNotNull();
        verify(configurer).configure(factory, consumerFactory);
    }
}
