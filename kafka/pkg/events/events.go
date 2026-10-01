// Package events defines the JSON event contracts that flow through Kafka.
//
// Envelope rules used by every event:
//   - event_id     unique id of THIS event (dedup key for idempotent consumers)
//   - event_type   OrderCreated, OrderUpdated, PaymentSucceeded, ...
//   - schema_version  bumped on contract change (see docs/23-schema-evolution.md)
//   - created_at   producer wall clock (Kafka also stores a record timestamp)
//
// The Kafka record KEY is not part of the payload: it is chosen by the producer
// (order_id by default) and decides the partition.
package events

import (
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
)

const (
	OrderCreated     = "OrderCreated"
	OrderUpdated     = "OrderUpdated"
	PaymentSucceeded = "PaymentSucceeded"
	PaymentFailed    = "PaymentFailed"
	NotificationSent = "NotificationSent"
	InventoryReserve = "InventoryReserved"
	UserProfile      = "UserProfileUpdated"
	OrderStats       = "OrderStatsWindow"
)

// Lab fault injection values for OrderEvent.LabFault. They let a lab trigger a
// specific failure on a specific message (deterministic, no timing games).
const (
	FaultCrashAfterProcess  = "crash_after_process"  // side effects done, crash BEFORE offset commit -> duplicate on restart
	FaultCrashBeforeProcess = "crash_before_process" // crash before any side effect
	FaultAbortTxn           = "abort_txn"            // txn-processor aborts the first attempt
	FaultSlow               = "slow"                 // handler sleeps 5s
)

// OrderEvent is the payload on the `orders` topic.
type OrderEvent struct {
	EventID       string    `json:"event_id"`
	EventType     string    `json:"event_type"`
	SchemaVersion int       `json:"schema_version"`
	OrderID       string    `json:"order_id"`
	UserID        int64     `json:"user_id"`
	ProductID     int64     `json:"product_id"`
	Quantity      int       `json:"quantity"`
	Status        string    `json:"status,omitempty"`
	Sequence      int       `json:"sequence,omitempty"` // per-order sequence number (ordering lab)
	CreatedAt     time.Time `json:"created_at"`
	LabFault      string    `json:"lab_fault,omitempty"`
	Padding       string    `json:"padding,omitempty"` // used by benchmarks / large message lab to inflate size
}

func NewOrderCreated(userID, productID int64, qty int) OrderEvent {
	return OrderEvent{
		EventID:       uuid.NewString(),
		EventType:     OrderCreated,
		SchemaVersion: 1,
		OrderID:       NewOrderID(),
		UserID:        userID,
		ProductID:     productID,
		Quantity:      qty,
		Status:        "CREATED",
		Sequence:      1,
		CreatedAt:     time.Now().UTC(),
	}
}

func NewOrderID() string {
	return "order-" + strings.ReplaceAll(uuid.NewString(), "-", "")[:12]
}

var ErrInvalidOrder = errors.New("invalid order")

// Validate applies business validation. A failure here is a "poison" event:
// retrying will never fix it, but the lab still routes it through retry->DLQ to
// make the pipeline observable (docs/17-retry-dlq.md discusses classifying
// errors as retryable / non-retryable).
func (o OrderEvent) Validate() error {
	switch {
	case o.OrderID == "":
		return fmt.Errorf("%w: missing order_id", ErrInvalidOrder)
	case o.UserID <= 0:
		return fmt.Errorf("%w: user_id must be > 0 (got %d)", ErrInvalidOrder, o.UserID)
	case o.ProductID <= 0:
		return fmt.Errorf("%w: product_id must be > 0 (got %d)", ErrInvalidOrder, o.ProductID)
	case o.Quantity <= 0:
		return fmt.Errorf("%w: quantity must be > 0 (got %d)", ErrInvalidOrder, o.Quantity)
	}
	return nil
}

// UnitPrice is a deterministic fake catalog price.
func UnitPrice(productID int64) float64 {
	return float64(productID%97+1) * 1.25
}

// PaymentEvent is the payload on the `payments` topic.
type PaymentEvent struct {
	EventID       string    `json:"event_id"`
	EventType     string    `json:"event_type"`
	SchemaVersion int       `json:"schema_version"`
	PaymentID     string    `json:"payment_id"`
	OrderID       string    `json:"order_id"`
	UserID        int64     `json:"user_id"`
	Amount        float64   `json:"amount"`
	Reason        string    `json:"reason,omitempty"`
	CausationID   string    `json:"causation_id"` // event_id of the OrderCreated that caused it
	CreatedAt     time.Time `json:"created_at"`
}

// NotificationEvent is the payload on the `notifications` topic.
type NotificationEvent struct {
	EventID     string    `json:"event_id"`
	EventType   string    `json:"event_type"`
	Channel     string    `json:"channel"`
	UserID      int64     `json:"user_id"`
	OrderID     string    `json:"order_id"`
	Template    string    `json:"template"`
	CausationID string    `json:"causation_id"`
	CreatedAt   time.Time `json:"created_at"`
}

// InventoryEvent is the payload on `inventory-events` (key = product_id).
type InventoryEvent struct {
	EventID     string    `json:"event_id"`
	EventType   string    `json:"event_type"`
	ProductID   int64     `json:"product_id"`
	OrderID     string    `json:"order_id"`
	Quantity    int       `json:"quantity"`
	CausationID string    `json:"causation_id"`
	CreatedAt   time.Time `json:"created_at"`
}

// AnalyticsEvent is an aggregated window emitted by analytics-consumer
// (topic analytics-events, key = product_id).
type AnalyticsEvent struct {
	EventID     string    `json:"event_id"`
	EventType   string    `json:"event_type"`
	ProductID   int64     `json:"product_id"`
	Orders      int       `json:"orders"`
	Units       int       `json:"units"`
	Revenue     float64   `json:"revenue"`
	WindowStart time.Time `json:"window_start"`
	WindowEnd   time.Time `json:"window_end"`
}

// UserProfileEvent is used for user-events (stream) and user-profile-compacted (state).
type UserProfileEvent struct {
	EventID   string    `json:"event_id"`
	EventType string    `json:"event_type"`
	UserID    int64     `json:"user_id"`
	Name      string    `json:"name"`
	Email     string    `json:"email"`
	Tier      string    `json:"tier"`
	Version   int       `json:"version"`
	UpdatedAt time.Time `json:"updated_at"`
}

// Record header names. Headers carry metadata without touching the payload.
const (
	HeaderEventType     = "event_type"
	HeaderSchemaVersion = "schema_version"
	HeaderProducer      = "producer"

	// retry / DLQ metadata (docs/17-retry-dlq.md)
	HeaderAttempt           = "retry_attempt"
	HeaderOriginalTopic     = "original_topic"
	HeaderOriginalPartition = "original_partition"
	HeaderOriginalOffset    = "original_offset"
	HeaderOriginalTimestamp = "original_timestamp"
	HeaderError             = "error"
	HeaderFailedAt          = "failed_at"
	HeaderFailedGroup       = "failed_group"
	HeaderFailedBy          = "failed_by"
	HeaderRetryNotBefore    = "retry_not_before"
	HeaderReplayed          = "replayed_from_dlq"
	HeaderReplayCount       = "replay_count"
)
