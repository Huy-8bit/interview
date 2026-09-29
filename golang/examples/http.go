package labs

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"time"
)

// NewClient owns a reusable Transport. Numbers are lab defaults; size from
// latency, concurrency, protocol, and downstream capacity before deployment.
func NewClient() *http.Client {
	tr := http.DefaultTransport.(*http.Transport).Clone()
	tr.DialContext = (&net.Dialer{Timeout: 2 * time.Second, KeepAlive: 30 * time.Second}).DialContext
	tr.MaxIdleConns = 100
	tr.MaxIdleConnsPerHost = 20
	tr.MaxConnsPerHost = 40
	tr.IdleConnTimeout = 90 * time.Second
	tr.TLSHandshakeTimeout = 3 * time.Second
	tr.ResponseHeaderTimeout = 3 * time.Second
	return &http.Client{Transport: tr, Timeout: 5 * time.Second}
}

// Fetch requires a trusted or separately validated URL. The byte limit applies
// to the decoded body Reader and prevents unbounded ReadAll allocations.
func Fetch(ctx context.Context, client *http.Client, url string, maxBytes int64) (body []byte, err error) {
	if maxBytes < 1 || maxBytes == int64(^uint64(0)>>1) {
		return nil, errors.New("invalid body limit")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetch: %w", err)
	}
	defer func() { err = errors.Join(err, resp.Body.Close()) }()
	body, err = io.ReadAll(io.LimitReader(resp.Body, maxBytes+1))
	if err != nil {
		return nil, fmt.Errorf("read body: %w", err)
	}
	if int64(len(body)) > maxBytes {
		return nil, errors.New("response body exceeds limit")
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("unexpected HTTP status: %d", resp.StatusCode)
	}
	return body, nil
}
