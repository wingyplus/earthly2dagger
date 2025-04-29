package main

import (
	"context"
	"dagger/earthly-2-dagger/internal/dagger"
)

func New(
	// +defaultPath="/"
	// +ignore=["**/*", "!build.zig", "!build.zig.zon", "!src/**/*.zig", "!fixtures/**/*.earth", "!fixtures/**/*.go"]
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
func (m *Earthly2Dagger) Convert(
	ctx context.Context,
	earthfile *dagger.File,
	// Dagger module name
	dagModName string,
	// Go module name
	goModName string,
) *dagger.File {
	path := "/earthfile"
	out := "/tmp/out.go"

	return m.Build().
		WithMountedFile(path, earthfile).
		WithExec([]string{"e2d", path, dagModName, goModName}, dagger.ContainerWithExecOpts{
			RedirectStdout: out,
		}).
		WithExec([]string{"go", "fmt", out}).
		File(out)
}
