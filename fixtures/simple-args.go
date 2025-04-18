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

func (m *MyModule) Build(
	name string,
	// +optional
	tag string,
) *dagger.Container {
	return m.Container.
		WithEnvVariable("NAME", name).
		WithEnvVariable("TAG", tag).
		From("alpine:${TAG}").
		WithExec([]string{"sh", "-c", `echo "Hello, World ${NAME}"`}, dagger.ContainerWithExecOpts{Expand: true})
}

func (m *MyModule) ArgsLongName(
	multiWord string,
) *dagger.Container {
	return m.Container.
		WithEnvVariable("MULTI_WORD", multiWord).
		From("alpine").
		WithExec([]string{"sh", "-c", `echo "Hello, World"`}, dagger.ContainerWithExecOpts{Expand: true})
}
