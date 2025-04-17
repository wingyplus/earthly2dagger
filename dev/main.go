package main

import (
	"context"
)

type Earthly2DaggerDev struct{}

// Run test on earthly2dagger.
func (m *Earthly2DaggerDev) Test(ctx context.Context) error {
	_, err := dag.Earthly2Dagger().Container().
		WithExec([]string{"zig", "build", "test"}).
		Sync(ctx)
	return err
}
