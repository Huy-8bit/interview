package labs

import (
	"errors"
	"fmt"
)

func Example_deferArguments() {
	x := 1
	defer fmt.Println("argument", x)
	defer func() { fmt.Println("closure", x) }()
	x = 2
	// Output:
	// closure 2
	// argument 1
}
func namedResult() (n int) { defer func() { n++ }(); return 4 }
func Example_namedReturn() {
	fmt.Println(namedResult())
	// Output: 5
}
func recoverValue() (err error) {
	defer func() {
		if value := recover(); value != nil {
			err = fmt.Errorf("task panic: %v", value)
		}
	}()
	panic("broken invariant")
}
func Example_recoverBoundary() {
	fmt.Println(recoverValue())
	// Output: task panic: broken invariant
}

var missing = errors.New("missing")

type typedFailure struct{}

func (*typedFailure) Error() string { return "failure" }
func Example_typedNilAndWrapping() {
	var pointer *typedFailure
	var err error = pointer
	fmt.Println(err == nil)
	wrapped := fmt.Errorf("load: %w", missing)
	fmt.Println(errors.Is(wrapped, missing))
	// Output:
	// false
	// true
}
