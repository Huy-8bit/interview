package events

import (
	"errors"
	"testing"
)

func TestValidate(t *testing.T) {
	ok := NewOrderCreated(1, 2, 3)
	if err := ok.Validate(); err != nil {
		t.Fatal(err)
	}
	bad := NewOrderCreated(1, 2, -100) // the poison message of labs/09
	if err := bad.Validate(); !errors.Is(err, ErrInvalidOrder) {
		t.Fatalf("want ErrInvalidOrder, got %v", err)
	}
}
