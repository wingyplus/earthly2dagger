// A generated module for Earthly2Dagger functions
//
// This module has been generated via dagger init and serves as a reference to
// basic module structure as you get started with Dagger.
//
// Two functions have been pre-created. You can modify, delete, or add to them,
// as needed. They demonstrate usage of arguments and return types using simple
// echo and grep commands. The functions can be called from the dagger CLI or
// from one of the SDKs.
//
// The first line in this comment block is a short description line and the
// rest is a long description with more detail on the module's purpose or usage,
// if appropriate. All modules should have a short description.

package main

import (
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
			With(zig).
			WithWorkdir("/source").
			WithMountedDirectory(".", source),
	}
}

type Earthly2Dagger struct {
	Source    *dagger.Directory
	Container *dagger.Container
}

func (m *Earthly2Dagger) Binary() *dagger.Directory {
	return m.Container.WithExec([]string{"zig", "build"}).Directory("zig-out")
}
