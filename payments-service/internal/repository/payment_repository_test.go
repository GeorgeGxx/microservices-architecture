package repository

import (
	"context"
	"errors"
	"regexp"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/georgegxx/payments-service/internal/models"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

func setupMockDB(t *testing.T) (*gorm.DB, sqlmock.Sqlmock) {
	mockDB, mock, err := sqlmock.New()
	assert.NoError(t, err)

	dialector := postgres.New(postgres.Config{
		Conn:       mockDB,
		DriverName: "postgres",
	})

	gormDB, err := gorm.Open(dialector, &gorm.Config{
		Logger: logger.Default.LogMode(logger.Silent),
	})
	assert.NoError(t, err)

	return gormDB, mock
}

func TestNewPaymentRepository(t *testing.T) {
	gormDB, _ := setupMockDB(t)
	repo := NewPaymentRepository(gormDB)
	assert.NotNil(t, repo)
}

func TestPaymentRepository_CreatePayment(t *testing.T) {
	gormDB, mock := setupMockDB(t)
	repo := NewPaymentRepository(gormDB)

	paymentID := uuid.New()
	payment := &models.Payment{
		ID:             paymentID,
		OrderNumber:    "ORD-1",
		Amount:         100.0,
		Currency:       "USD",
		Status:         models.PaymentStatusCompleted,
		PaymentMethod:  "CARD_VISA",
		TransactionRef: "TXN-1",
		CreatedAt:      time.Now(),
		UpdatedAt:      time.Now(),
	}

	mock.ExpectBegin()
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO "payments"`)).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	err := repo.CreatePayment(context.Background(), payment)
	assert.NoError(t, err)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestPaymentRepository_UpdatePayment(t *testing.T) {
	gormDB, mock := setupMockDB(t)
	repo := NewPaymentRepository(gormDB)

	paymentID := uuid.New()
	payment := &models.Payment{
		ID:          paymentID,
		OrderNumber: "ORD-1",
		Amount:      100.0,
		Status:      models.PaymentStatusRefunded,
		UpdatedAt:   time.Now(),
	}

	mock.ExpectBegin()
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE "payments"`)).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	err := repo.UpdatePayment(context.Background(), payment)
	assert.NoError(t, err)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestPaymentRepository_FindByID(t *testing.T) {
	gormDB, mock := setupMockDB(t)
	repo := NewPaymentRepository(gormDB)

	paymentID := uuid.New()
	rows := sqlmock.NewRows([]string{"id", "order_number", "amount"}).
		AddRow(paymentID, "ORD-1", 100.0)

	mock.ExpectQuery(regexp.QuoteMeta(`SELECT * FROM "payments" WHERE id = $1`)).
		WithArgs(paymentID, 1).
		WillReturnRows(rows)

	res, err := repo.FindByID(context.Background(), paymentID)
	assert.NoError(t, err)
	assert.NotNil(t, res)
	assert.Equal(t, "ORD-1", res.OrderNumber)

	// Not found case
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT * FROM "payments" WHERE id = $1`)).
		WithArgs(paymentID, 1).
		WillReturnRows(sqlmock.NewRows([]string{"id", "order_number"}))

	notFound, err := repo.FindByID(context.Background(), paymentID)
	assert.NoError(t, err)
	assert.Nil(t, notFound)
}

func TestPaymentRepository_FindByOrderNumber(t *testing.T) {
	gormDB, mock := setupMockDB(t)
	repo := NewPaymentRepository(gormDB)

	paymentID := uuid.New()
	rows := sqlmock.NewRows([]string{"id", "order_number", "amount"}).
		AddRow(paymentID, "ORD-1", 100.0)

	mock.ExpectQuery(regexp.QuoteMeta(`SELECT * FROM "payments" WHERE order_number = $1 ORDER BY created_at desc,"payments"."id" LIMIT $2`)).
		WithArgs("ORD-1", 1).
		WillReturnRows(rows)

	res, err := repo.FindByOrderNumber(context.Background(), "ORD-1")
	assert.NoError(t, err)
	assert.NotNil(t, res)
	assert.Equal(t, "ORD-1", res.OrderNumber)

	// Not found case
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT * FROM "payments" WHERE order_number = $1 ORDER BY created_at desc,"payments"."id" LIMIT $2`)).
		WithArgs("ORD-NONE", 1).
		WillReturnRows(sqlmock.NewRows([]string{"id", "order_number"}))

	notFound, err := repo.FindByOrderNumber(context.Background(), "ORD-NONE")
	assert.NoError(t, err)
	assert.Nil(t, notFound)
}

func TestPaymentRepository_FindByIdempotencyKey(t *testing.T) {
	gormDB, mock := setupMockDB(t)
	repo := NewPaymentRepository(gormDB)

	paymentID := uuid.New()
	rows := sqlmock.NewRows([]string{"id", "order_number", "idempotency_key"}).
		AddRow(paymentID, "ORD-1", "idem-key-1")

	mock.ExpectQuery(regexp.QuoteMeta(`SELECT * FROM "payments" WHERE idempotency_key = $1 ORDER BY "payments"."id" LIMIT $2`)).
		WithArgs("idem-key-1", 1).
		WillReturnRows(rows)

	res, err := repo.FindByIdempotencyKey(context.Background(), "idem-key-1")
	assert.NoError(t, err)
	assert.NotNil(t, res)

	// Blank key returns nil, nil
	blankRes, err := repo.FindByIdempotencyKey(context.Background(), "")
	assert.NoError(t, err)
	assert.Nil(t, blankRes)
}

func TestPaymentRepository_CreateAuditLog(t *testing.T) {
	gormDB, mock := setupMockDB(t)
	repo := NewPaymentRepository(gormDB)

	logEntry := &models.PaymentAuditLog{
		ID:        uuid.New(),
		PaymentID: uuid.New(),
		Action:    "PAYMENT_AUTHORIZED",
		Details:   "Success",
		CreatedAt: time.Now(),
	}

	mock.ExpectBegin()
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO "payment_audit_logs"`)).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	err := repo.CreateAuditLog(context.Background(), logEntry)
	assert.NoError(t, err)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestPaymentRepository_CreateAndUpdateWithOutbox(t *testing.T) {
	gormDB, mock := setupMockDB(t)
	repo := NewPaymentRepository(gormDB)

	now := time.Now().UTC()
	payment := &models.Payment{
		ID:            uuid.New(),
		OrderNumber:   "ORD-OUTBOX-1",
		Amount:        120.0,
		Currency:      "USD",
		Status:        models.PaymentStatusCompleted,
		PaymentMethod: "CARD_VISA",
		CreatedAt:     now,
		UpdatedAt:     now,
	}
	outbox := &models.OutboxEvent{
		ID:            uuid.New(),
		AggregateType: "PAYMENT",
		AggregateID:   "ORD-OUTBOX-1",
		EventType:     "PAYMENT_COMPLETED",
		Payload:       "{}",
		Status:        "PENDING",
		CreatedAt:     now,
	}

	mock.ExpectBegin()
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO "payments"`)).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO "outbox_events"`)).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	assert.NoError(t, repo.CreatePaymentWithOutbox(context.Background(), payment, outbox))
	assert.NoError(t, mock.ExpectationsWereMet())

	mock.ExpectBegin()
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE "payments"`)).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO "outbox_events"`)).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	assert.NoError(t, repo.UpdatePaymentWithOutbox(context.Background(), payment, outbox))
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestPaymentRepository_IsMessageProcessed(t *testing.T) {
	t.Run("empty id short-circuits", func(t *testing.T) {
		gormDB, mock := setupMockDB(t)
		repo := NewPaymentRepository(gormDB)
		processed, err := repo.IsMessageProcessed(context.Background(), "")
		assert.NoError(t, err)
		assert.False(t, processed)
		assert.NoError(t, mock.ExpectationsWereMet())
	})

	for _, test := range []struct {
		name     string
		count    int64
		want     bool
		queryErr error
	}{
		{name: "already processed", count: 1, want: true},
		{name: "not processed", count: 0, want: false},
	} {
		t.Run(test.name, func(t *testing.T) {
			gormDB, mock := setupMockDB(t)
			repo := NewPaymentRepository(gormDB)
			mock.ExpectQuery(regexp.QuoteMeta(`SELECT count(*) FROM "processed_messages" WHERE message_id = $1`)).
				WithArgs("event-1").WillReturnRows(sqlmock.NewRows([]string{"count"}).AddRow(test.count))
			processed, err := repo.IsMessageProcessed(context.Background(), "event-1")
			assert.NoError(t, err)
			assert.Equal(t, test.want, processed)
			assert.NoError(t, mock.ExpectationsWereMet())
		})
	}

	t.Run("database error", func(t *testing.T) {
		gormDB, mock := setupMockDB(t)
		repo := NewPaymentRepository(gormDB)
		mock.ExpectQuery(regexp.QuoteMeta(`SELECT count(*) FROM "processed_messages" WHERE message_id = $1`)).
			WithArgs("event-error").WillReturnError(errors.New("database unavailable"))
		processed, err := repo.IsMessageProcessed(context.Background(), "event-error")
		assert.Error(t, err)
		assert.False(t, processed)
		assert.NoError(t, mock.ExpectationsWereMet())
	})
}

func TestPaymentRepository_RecordProcessedMessage(t *testing.T) {
	gormDB, mock := setupMockDB(t)
	repo := NewPaymentRepository(gormDB)
	assert.NoError(t, repo.RecordProcessedMessage(context.Background(), nil))
	assert.NoError(t, repo.RecordProcessedMessage(context.Background(), &models.ProcessedMessage{}))

	message := &models.ProcessedMessage{MessageID: "event-1", ConsumerID: "payments-service", EventType: "PAYMENT_COMPLETED"}
	mock.ExpectBegin()
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO "processed_messages"`)).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()
	assert.NoError(t, repo.RecordProcessedMessage(context.Background(), message))
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestPaymentRepository_OutboxPersistenceMethods(t *testing.T) {
	gormDB, mock := setupMockDB(t)
	repo := NewPaymentRepository(gormDB)
	event := &models.OutboxEvent{
		ID: uuid.New(), AggregateType: "PAYMENT", AggregateID: "ORD-OUTBOX",
		EventType: "PAYMENT_COMPLETED", Payload: "{}", Status: "PENDING",
	}

	mock.ExpectBegin()
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO "outbox_events"`)).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()
	assert.NoError(t, repo.SaveOutboxEvent(context.Background(), event))

	mock.ExpectBegin()
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE "outbox_events"`)).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()
	assert.NoError(t, repo.UpdateOutboxEvent(context.Background(), event))
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestPaymentRepository_GetPendingOutboxEvents(t *testing.T) {
	gormDB, mock := setupMockDB(t)
	repo := NewPaymentRepository(gormDB)

	evID := uuid.New()
	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT * FROM "outbox_events"`)).
		WillReturnRows(sqlmock.NewRows([]string{"id", "aggregate_type", "aggregate_id", "event_type", "payload", "status"}).
			AddRow(evID, "PAYMENT", "ORD-1", "PAYMENT_COMPLETED", "{}", "PENDING"))
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE "outbox_events"`)).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	events, err := repo.GetPendingOutboxEvents(context.Background(), 10)
	assert.NoError(t, err)
	assert.Len(t, events, 1)
	assert.Equal(t, "PROCESSING", events[0].Status)
	assert.NoError(t, mock.ExpectationsWereMet())
}
