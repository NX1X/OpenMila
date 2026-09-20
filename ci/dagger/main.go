// OpenMila's build and test pipeline, as Dagger functions.
//
// Every function builds the same environment (ci/Dockerfile: Ubuntu 26.04
// pinned by digest, Swift 6.4.0 verified against a pinned signing key) and runs
// the same stages as ci/run.sh, so a pipeline run on a laptop, in GitHub
// Actions, or anywhere else with a container engine gives the same result.
//
//	dagger call check              # every stage: packages, shims, core, port, builds, e2e
//	dagger call stage --name=core  # one stage
//	dagger call app-image export --path=dist/OpenMila.AppImage
//
// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.

package main

import (
	"context"
	"fmt"

	"dagger/openmila-ci/internal/dagger"
)

// The tiny Whisper model the end-to-end stage transcribes with, and its
// SHA-256 as published by whisper.cpp.
const (
	tinyModelURL    = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin"
	tinyModelSHA256 = "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21"
)

// syft, for the software bill of materials attached to a release. Pinned by
// digest; bump tag and digest together.
const syftImage = "anchore/syft:v1.52.0@sha256:500e2d872ac019436926e8322b4fc1f39441d94d21f6f4046c6ff29b30e8cb02"

type OpenmilaCi struct{}

// The build environment with the repository at /work/repo. Build output,
// the whisper.cpp build and SwiftPM's caches live in cache volumes, so a
// second run only rebuilds what changed.
func (m *OpenmilaCi) Env(
	// The repository.
	// +defaultPath="/"
	// +ignore=[".build", "Port/App/.build", "Port/Spikes/*/.build", "dist", "docs-internal", "**/build-linux", "Packages/*/.build"]
	source *dagger.Directory,
) *dagger.Container {
	owner := dagger.ContainerWithMountedCacheOpts{Owner: "builder"}
	return source.Directory("ci").DockerBuild().
		WithMountedDirectory("/work/repo", source, dagger.ContainerWithMountedDirectoryOpts{Owner: "builder"}).
		WithMountedCache("/work/repo/.build", dag.CacheVolume("openmila-build"), owner).
		WithMountedCache("/work/repo/Port/App/.build", dag.CacheVolume("openmila-app-build"), owner).
		WithMountedCache("/home/builder/.local", dag.CacheVolume("openmila-whisper-prefix"), owner).
		WithMountedCache("/home/builder/.cache", dag.CacheVolume("openmila-home-cache"), owner).
		WithWorkdir("/work/repo")
}

// The environment plus the checksum-verified tiny Whisper model.
func (m *OpenmilaCi) envWithModel(source *dagger.Directory) *dagger.Container {
	model := dag.HTTP(tinyModelURL)
	return m.Env(source).
		WithFile("/models/ggml-tiny.bin", model, dagger.ContainerWithFileOpts{Owner: "builder"}).
		WithExec([]string{"sh", "-c", fmt.Sprintf("echo '%s  /models/ggml-tiny.bin' | sha256sum -c -", tinyModelSHA256)}).
		WithEnvVariable("OPENMILA_E2E_MODEL", "/models/ggml-tiny.bin")
}

// Run one pipeline stage: whisper, packages, shims, core, port, cli or e2e.
func (m *OpenmilaCi) Stage(
	ctx context.Context,
	// +defaultPath="/"
	// +ignore=[".build", "Port/App/.build", "Port/Spikes/*/.build", "dist", "docs-internal", "**/build-linux", "Packages/*/.build"]
	source *dagger.Directory,
	name string,
) (string, error) {
	return m.envWithModel(source).
		WithExec([]string{"ci/run.sh", name}).
		Stdout(ctx)
}

// Run every stage, as CI does before a merge.
func (m *OpenmilaCi) Check(
	ctx context.Context,
	// +defaultPath="/"
	// +ignore=[".build", "Port/App/.build", "Port/Spikes/*/.build", "dist", "docs-internal", "**/build-linux", "Packages/*/.build"]
	source *dagger.Directory,
) (string, error) {
	return m.Stage(ctx, source, "all")
}

// The Linux packages: the AppImage, the Debian package, and their checksums.
func (m *OpenmilaCi) Packages(
	// +defaultPath="/"
	// +ignore=[".build", "Port/App/.build", "Port/Spikes/*/.build", "dist", "docs-internal", "**/build-linux", "Packages/*/.build"]
	source *dagger.Directory,
) *dagger.Directory {
	return m.Env(source).
		WithExec([]string{"ci/run.sh", "whisper"}).
		WithEnvVariable("OPENMILA_SWIFT_HOME", "/opt/swift").
		WithExec([]string{"packaging/appimage/build.sh"}).
		WithExec([]string{"packaging/deb/build.sh"}).
		WithExec([]string{"sh", "-c", "mkdir -p /tmp/out && cp dist/*.AppImage dist/*.deb dist/*.sha256 /tmp/out/ && rm -f /tmp/out/appimagetool*"}).
		Directory("/tmp/out")
}

// A CycloneDX software bill of materials for the repository.
func (m *OpenmilaCi) Sbom(
	// +defaultPath="/"
	// +ignore=[".build", "Port/App/.build", "Port/Spikes/*/.build", "dist", "docs-internal", ".git"]
	source *dagger.Directory,
) *dagger.File {
	return dag.Container().From(syftImage).
		WithMountedDirectory("/src", source).
		WithExec([]string{"scan", "dir:/src", "-o", "cyclonedx-json=/tmp/openmila-sbom.cdx.json"}).
		File("/tmp/openmila-sbom.cdx.json")
}

// Build the Linux AppImage and its .sha256 file.
func (m *OpenmilaCi) AppImage(
	// +defaultPath="/"
	// +ignore=[".build", "Port/App/.build", "Port/Spikes/*/.build", "dist", "docs-internal", "**/build-linux", "Packages/*/.build"]
	source *dagger.Directory,
) *dagger.Directory {
	return m.Env(source).
		WithExec([]string{"ci/run.sh", "whisper"}).
		WithEnvVariable("OPENMILA_SWIFT_HOME", "/opt/swift").
		WithExec([]string{"packaging/appimage/build.sh"}).
		WithExec([]string{"sh", "-c", "mkdir -p /tmp/out && cp dist/*.AppImage dist/*.sha256 /tmp/out/ && rm -f /tmp/out/appimagetool*"}).
		Directory("/tmp/out")
}
