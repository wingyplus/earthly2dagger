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

func (m *MyModule) TestCmdString() *dagger.Container {
	return m.Container.
		From("alpine").
		WithDefaultArgs([]string{"sh", "-c", `echo 'hello, world'`})
}

func (m *MyModule) TestCmdArray() *dagger.Container {
	return m.Container.
		From("alpine").
		WithDefaultArgs([]string{"echo", "hello, world"})
}
