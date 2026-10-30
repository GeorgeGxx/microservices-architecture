package com.georgegxx.orders_service.model.dtos;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class BaseResponseTest {

    @Test
    @DisplayName("hasErrors returns expected boolean status")
    void testHasErrors() {
        BaseResponse empty = new BaseResponse(new String[0]);
        assertThat(empty.hasErrors()).isFalse();

        BaseResponse nullErrors = new BaseResponse(null);
        assertThat(nullErrors.hasErrors()).isFalse();

        BaseResponse withErrors = new BaseResponse(new String[]{"error 1", "error 2"});
        assertThat(withErrors.hasErrors()).isTrue();
    }

    @Test
    @DisplayName("equals, hashCode, and toString contracts")
    void testContracts() {
        BaseResponse r1 = new BaseResponse(new String[]{"e1"});
        BaseResponse r2 = new BaseResponse(new String[]{"e1"});
        BaseResponse r3 = new BaseResponse(new String[]{"e2"});

        assertThat(r1).isEqualTo(r1);
        assertThat(r1).isEqualTo(r2);
        assertThat(r1).isNotEqualTo(r3);
        assertThat(r1).isNotEqualTo(null);
        assertThat(r1).isNotEqualTo("otherType");

        assertThat(r1.hashCode()).isEqualTo(r2.hashCode());
        assertThat(r1.toString()).contains("e1");
    }
}
