package main

import (
	"fmt"

	"github.com/example/internal/version"
)

func main() {
	versionInfo := version.Get()
	fmt.Println(versionInfo.GitVersion)
	fmt.Println(versionInfo.BuildDate)
	fmt.Println(versionInfo.GitCommit)
}
