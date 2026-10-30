package repository

import (
	"context"
	"errors"

	"github.com/georgegxx/payments-service/internal/models"
	"github.com/google/uuid"
	"gorm.io/gorm"
)

type PaymentRepository interface {
	CreatePayment(ctx context.Context, payment *models.Payment) error
	UpdatePayment(ctx context.Context, payment *models.Payment) error
	FindByID(ctx context.Context, id uuid.UUID) (*models.Payment, error)
	FindByOrderNumber(ctx context.Context, orderNumber string) (*models.Payment, error)
	FindByIdempotencyKey(ctx context.Context, key string) (*models.Payment, error)
	CreateAuditLog(ctx context.Context, log *models.PaymentAuditLog) error
}

type paymentRepository struct {
	db *gorm.DB
}

func NewPaymentRepository(db *gorm.DB) PaymentRepository {
	return &paymentRepository{db: db}
}

func (r *paymentRepository) CreatePayment(ctx context.Context, payment *models.Payment) error {
	return r.db.WithContext(ctx).Create(payment).Error
}

func (r *paymentRepository) UpdatePayment(ctx context.Context, payment *models.Payment) error {
	return r.db.WithContext(ctx).Save(payment).Error
}

func (r *paymentRepository) FindByID(ctx context.Context, id uuid.UUID) (*models.Payment, error) {
	var payment models.Payment
	err := r.db.WithContext(ctx).First(&payment, "id = ?", id).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, err
	}
	return &payment, nil
}

func (r *paymentRepository) FindByOrderNumber(ctx context.Context, orderNumber string) (*models.Payment, error) {
	var payment models.Payment
	err := r.db.WithContext(ctx).Order("created_at desc").First(&payment, "order_number = ?", orderNumber).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, err
	}
	return &payment, nil
}

func (r *paymentRepository) FindByIdempotencyKey(ctx context.Context, key string) (*models.Payment, error) {
	if key == "" {
		return nil, nil
	}
	var payment models.Payment
	err := r.db.WithContext(ctx).First(&payment, "idempotency_key = ?", key).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, err
	}
	return &payment, nil
}

func (r *paymentRepository) CreateAuditLog(ctx context.Context, log *models.PaymentAuditLog) error {
	return r.db.WithContext(ctx).Create(log).Error
}
