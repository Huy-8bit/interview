package labs

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

// ListUserIDs requires a PostgreSQL-compatible driver/schema supplied by caller.
func ListUserIDs(ctx context.Context, db *sql.DB, limit int) (ids []int64, err error) {
	if limit < 1 || limit > 1000 {
		return nil, errors.New("limit must be between 1 and 1000")
	}
	rows, err := db.QueryContext(ctx, "SELECT id FROM users ORDER BY id LIMIT $1", limit)
	if err != nil {
		return nil, fmt.Errorf("query users: %w", err)
	}
	defer func() { err = errors.Join(err, rows.Close()) }()
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return nil, fmt.Errorf("scan user: %w", err)
		}
		ids = append(ids, id)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate users: %w", err)
	}
	return ids, nil
}

// InTx does not retry: the caller must decide whether the complete operation
// is replay-safe. fn must use tx for every operation in this transaction.
func InTx(ctx context.Context, db *sql.DB, fn func(*sql.Tx) error) (err error) {
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin: %w", err)
	}
	defer func() {
		rollbackErr := tx.Rollback()
		if rollbackErr != nil && !errors.Is(rollbackErr, sql.ErrTxDone) {
			err = errors.Join(err, fmt.Errorf("rollback: %w", rollbackErr))
		}
	}()
	if err = fn(tx); err != nil {
		return err
	}
	if err = tx.Commit(); err != nil {
		return fmt.Errorf("commit: %w", err)
	}
	return nil
}
