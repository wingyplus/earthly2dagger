package main

import (
	"context"
	"dagger/earthly-2-dagger/internal/dagger"
)

func New(
	// +defaultPath="/"
	// +ignore=["**/*", "!build.zig", "!build.zig.zon", "!src/**/*.zig"]
	source *dagger.Directory,
) *Earthly2Dagger {
	return &Earthly2Dagger{
		Source: source,
		Container: dag.Container().
			With(baseImage).
			WithWorkdir("/source").
			WithMountedDirectory(".", source),
	}
}

type Earthly2Dagger struct {
	Source    *dagger.Directory
	Container *dagger.Container
}

// Build earthly2dagger binary.
func (m *Earthly2Dagger) Build() *dagger.Container {
	return m.Container.
		WithExec([]string{
			"zig", "build", "install", "--prefix", "/usr/local", "-Doptimize=ReleaseSafe",
		})
}

// Convert Earthfile into Dagger module.
func (m *Earthly2Dagger) Run(
	ctx context.Context,
	// +optional
	earthfile string,
) (string, error) {
	return m.Build().
		WithExec([]string{"e2d"}, dagger.ContainerWithExecOpts{
			RedirectStdout: "/tmp/out.go",
		}).
		WithExec([]string{"go", "fmt", "/tmp/out.go"}).
		File("/tmp/out.go").
		Contents(ctx)
}
