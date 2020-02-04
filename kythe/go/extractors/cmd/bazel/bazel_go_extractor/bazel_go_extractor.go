/*
 * Copyright 2016 The Kythe Authors. All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// bazel_go_extractor is a Bazel extra action that extracts Go compilations.
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"

	"kythe.io/kythe/go/extractors/bazel"
	"kythe.io/kythe/go/extractors/govname"
	"kythe.io/kythe/go/util/vnameutil"

	apb "kythe.io/kythe/proto/analysis_go_proto"
	gopb "kythe.io/kythe/proto/go_go_proto"
)

var (
	corpus = flag.String("corpus", "kythe", "The corpus label to assign (required)")
)

const baseUsage = `Usage: %[1]s [flags] <extra-action> <output-file> <vname-config>`

func init() {
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, baseUsage+`

Extract a Kythe compilation record for Go from a Bazel extra action.

Arguments:
 <extra-action> is a file containing a wire format ExtraActionInfo protobuf.
 <output-file>  is the path where the output kindex file is written.
 <vname-config> is the path of a VName configuration JSON file.

Flags:
`, filepath.Base(os.Args[0]))
		flag.PrintDefaults()
	}
}

func main() {
	flag.Parse()
	if flag.NArg() != 3 {
		log.Fatalf(baseUsage+` [run "%[1]s --help" for details]`, filepath.Base(os.Args[0]))
	}
	extraActionFile := flag.Arg(0)
	outputFile := flag.Arg(1)
	vnameRuleFile := flag.Arg(2)

	info, err := bazel.LoadAction(extraActionFile)
	if err != nil {
		log.Fatalf("Error loading extra action: %v", err)
	}
	if m := info.GetMnemonic(); m != "GoCompilePkg" {
		log.Fatalf("Extractor is not applicable to this action: %q", m)
	}

	// Load vname rewriting rules. We handle this directly, becaues the Bazel
	// Go rules have some pathological symlink handling that the normal rules
	// need to be patched for.
	rules, err := vnameutil.LoadRules(vnameRuleFile)
	if err != nil {
		log.Fatalf("Error loading vname rules: %v", err)
	}

	ext := &extractor{rules: rules}
	config := &bazel.Config{
		Corpus:      *corpus,
		Language:    govname.Language,
		Rules:       rules,
		CheckAction: ext.checkAction,
		CheckInput:  ext.checkInput,
		CheckEnv:    ext.checkEnv,
		IsSource:    ext.isSource,
		FixUnit:     ext.fixup,
	}
	ai, err := bazel.SpawnAction(info)
	if err != nil {
		log.Fatalf("Invalid extra action: %v", err)
	}

	ctx := context.Background()
	if err := config.ExtractToKzip(ctx, ai, outputFile); err != nil {
		log.Fatalf("Extraction failed: %v", err)
	}
}

type extractor struct {
	rules       vnameutil.Rules
	compileArgs *compileArgs

	goos, goarch, goroot string
	cgoEnabled           bool
}

func (e *extractor) checkAction(_ context.Context, info *bazel.ActionInfo) error {
	e.compileArgs = parseCompileArgs(info.Arguments)
	for name, value := range info.Environment {
		switch name {
		case "GOOS":
			e.goos = value
		case "GOARCH":
			e.goarch = value
		case "GOROOT":
			e.goroot = value
		case "CGO_ENABLED":
			e.cgoEnabled = value == "1"
		}
	}

	// The standard library packages aren't included explicitly.
	// Walk the os_arch subdirectory of GOROOT to find them.
	libRoot := filepath.Join(e.goroot, "pkg", e.goos+"_"+e.goarch)
	return filepath.Walk(libRoot, func(path string, fi os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if !fi.IsDir() && filepath.Ext(path) == ".a" {
			info.Inputs = append(info.Inputs, path)
		}
		return nil
	})
}

func (e *extractor) checkInput(path string) (string, bool) {
	switch filepath.Ext(path) {
	case ".go", ".a":
		return path, true // keep source files, archives
	}
	return path, false
}

func (*extractor) isSource(name string) bool { return filepath.Ext(name) == ".go" }

func (*extractor) checkEnv(name, _ string) bool { return name != "PATH" }

func (e *extractor) fixup(unit *apb.CompilationUnit) error {
	// Try to infer a unit vname from the output.
	if vname, ok := e.rules.Apply(e.compileArgs.outputPath); ok {
		vname.Language = govname.Language
		unit.VName = vname
	}
	return bazel.AddDetail(unit, &gopb.GoDetails{
		Goos:       e.goos,
		Goarch:     e.goarch,
		Goroot:     e.goroot,
		CgoEnabled: e.cgoEnabled,
		Compiler:   "gc",
	})
}

// compileArgs records the build information extracted from the GoCompilePkg
// action's argument list.
type compileArgs struct {
	outputPath string // output object file
}

func parseCompileArgs(args []string) *compileArgs {
	c := &compileArgs{}

	flag := ""
	for _, arg := range args {
		if arg == "--" {
			break
		} else if flag == "" && strings.HasPrefix(arg, "-") {
			// Record the name of a flag we want an argument for.
			flag = strings.TrimLeft(arg, "-")
			continue
		}

		// At this point we have the argument for a flag.  These are the
		// relevant flags from the toolchain's compile command.
		switch flag {
		case "o":
			c.outputPath = arg
		}
		flag = "" // reset
	}

	return c
}
