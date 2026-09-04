package com.georgegxx.orders_service.model.dtos;

import java.io.Serializable;
import java.util.Arrays;

public record BaseResponse(String[] errorMessages) implements Serializable {
    private static final long serialVersionUID = 1L;

    public boolean hasErrors() {
        return errorMessages != null && errorMessages.length > 0;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof BaseResponse(String[] thatErrorMessages))) return false;
        return Arrays.equals(errorMessages, thatErrorMessages);
    }

    @Override
    public int hashCode() {
        return Arrays.hashCode(errorMessages);
    }

    @Override
    public String toString() {
        return "BaseResponse{" +
                "errorMessages=" + Arrays.toString(errorMessages) +
                '}';
    }
}
