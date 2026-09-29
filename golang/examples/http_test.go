package labs

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"net/http/httptrace"
	"testing"
)

func TestFetchReusesConnection(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if _, err := w.Write([]byte("hello")); err != nil {
			t.Errorf("write: %v", err)
		}
	}))
	defer server.Close()
	client := NewClient()
	defer client.CloseIdleConnections()
	reused := false
	for i := 0; i < 2; i++ {
		ctx := httptrace.WithClientTrace(context.Background(), &httptrace.ClientTrace{GotConn: func(info httptrace.GotConnInfo) { reused = info.Reused }})
		body, err := Fetch(ctx, client, server.URL, 10)
		if err != nil || string(body) != "hello" {
			t.Fatalf("body=%q err=%v", body, err)
		}
	}
	if !reused {
		t.Fatal("second HTTP/1 request did not reuse connection")
	}
}
func TestFetchLimitsAndCancellation(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if _, err := w.Write([]byte("too large")); err != nil {
			t.Errorf("write: %v", err)
		}
	}))
	defer server.Close()
	client := NewClient()
	defer client.CloseIdleConnections()
	if _, err := Fetch(context.Background(), client, server.URL, 2); err == nil {
		t.Fatal("expected body limit error")
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := Fetch(ctx, client, server.URL, 20); !errors.Is(err, context.Canceled) {
		t.Fatalf("got %v", err)
	}
}
