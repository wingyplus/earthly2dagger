package main

import "dagger/earthly-2-dagger/internal/dagger"

func baseImage(ctr *dagger.Container) *dagger.Container {
	return ctr.From("cgr.dev/chainguard/wolfi-base").
		WithExec([]string{"apk", "add", "zig=~0.14", "go=~1.24"})
}
