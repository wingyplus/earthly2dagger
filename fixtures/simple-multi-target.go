package main

import "dagger/my-module/internal/dagger"

type MyModule struct {
	Container *dagger.Container
}

func New(
	// +optional
	container *dagger.Container,
) *MyModule {
	if container == nil {
		container = dag.Container()
	}
	return &MyModule{Container: container}
}

func (m *MyModule) Build() *dagger.Container {
	return m.Container.
		WithExec([]string{"sh", "-c", `echo "Hello, World"`}, dagger.ContainerWithExecOpts{Expand: true})
}

func (m *MyModule) Test() *dagger.Container {
	return m.Container.
		From("alpine")
}
