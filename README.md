<h1>
<p align="center">
  <img src="./cadence.svg" width="128" height="128" alt="Cadence logo">
  <br>Cadence
</h1>
  <p align="center">
    High-performance task orchestration system for any codebase.
  </p>
</p>

<!-- prettier-ignore-start -->
> [!WARNING]
> This project is in early development and is not ready for use.
<!-- prettier-ignore-end -->

## About

Cadence is a language-agnostic task orchestration system designed to scale from
small projects to large monorepos with minimal configuration.

Tasks are executed in topological order according to their dependencies,
parallelizing where possible. They can be defined once and extended or
overridden to suit specific project requirements.

Opt-in caching ensures tasks only run when their inputs have changed, restoring
artifacts from previous runs when nothing has.

## Installation

### Linux and macOS

```sh
curl -fsSL https://github.com/meechdw/cadence/scripts/install.sh | bash
```

### Windows

```powershell
powershell -c "irm https://github.com/meechdw/cadence/scripts/install.ps1 | iex"
```

### NixOS

```nix
# Add to your flake inputs
inputs.cadence.url = "github:meechdw/cadence";

# Add to your NixOS module
environment.systemPackages = [ inputs.cadence.packages.${pkgs.system}.default ];
```

## Core Concepts

Configuration is defined with `cadence.json` files. Cadence works by walking up
the file tree from the current directory, parsing `cadence.json` files as they
are encountered. Traversal stops when the [root](#root) file,
[workspace](#workspace) root, or file system root is reached.

The files are then processed in reverse order of discovery. Files deeper in the
tree take precedence, with their values overriding those defined higher up.

### Running Tasks

The most basic implementation of a task is a name with a command to run:

```json
{
  "tasks": {
    "build": {
      "cmd": "bun build ./cli.ts --compile"
    },
    "test": {
      "cmd": "bun test"
    }
  }
}
```

The `build` task can be run with the following command:

```sh
cadence run build
```

Both tasks can be run in parallel with the following command:

```sh
cadence run build test
```

### Task Merging

Task definitions in the same linear directory path are merged together to create
the final definition. This is useful for making small tweaks to tasks in certain
directories.

For example, suppose the root `cadence.json` contains the following
configuration:

```json
{
  "root": true,
  "tasks": {
    "test": {
      "cmd": "bun test --timeout {{timeout}}",
      "params": {
        "timeout": "3000"
      },
      "env": {
        "NODE_ENV": "test",
        "PGHOST": "localhost"
      }
    }
  }
}
```

And a subdirectory named `app` contains a `cadence.json` with the following
configuration:

```json
{
  "tasks": {
    "test": {
      "env": {
        "PGHOST": "postgres",
        "PORT": "8000"
      }
    }
  }
}
```

When `cadence run test` is run from the `app` directory, the final task
definition will be:

```json
{
  "tasks": {
    "test": {
      "cmd": "bun test --timeout {{timeout}}",
      "params": {
        "timeout": "3000"
      },
      "env": {
        "NODE_ENV": "test",
        "PGHOST": "postgres",
        "PORT": "8000"
      }
    }
  }
}
```

### Dependencies

Tasks can depend on other tasks either from the same directory or different
directories. A dependency between tasks from different directories is called a
workspace dependency. A prefix of `#` is used to indicate a workspace
dependency.

In the following example, the `build` task depends on the `test` task from the
same directory, and the `test` task depends on `#test`, which is the test task
from each directory listed in [`dependencies`](#dependencies-1).

A workspace dependency resolves to every directory in dependencies where the
task is defined. A task is considered defined if, after processing every
`cadence.json` file, it contains a [`cmd`] property and was not
[skipped](#skip).

```json
{
  "dependencies": ["../lib"],
  "tasks": {
    "build": {
      "cmd": "bun build ./cli.ts --compile",
      "depends_on": ["test"]
    },
    "test": {
      "cmd": "bun test",
      "depends_on": ["#test"]
    }
  }
}
```

When the following command is run from the terminal, the tasks will be executed
in the order `../lib:test`, `test`, `build`:

```sh
cadence run build
```

### Parameters

Parameters can be provided to a task's command via the command line. Consider
the following configuration:

```json
{
  "tasks": {
    "test": {
      "cmd": "bun test {{opts}}"
    }
  }
}
```

Since the `opts` parameter has no default value, it is an optional parameter. If
no value is provided, the parameter is removed from the command. To effectively
run the command `bun test --timeout 3000` we can run the following command,
where `{{opts}}` will be replaced with `--timeout 3000`:

```sh
cadence run --params "opts=--timeout 3000" test
```

Default values can be provided to parameters via the `params` property:

```json
{
  "tasks": {
    "test": {
      "cmd": "bun test --timeout {{timeout}}",
      "params": {
        "timeout": "3000"
      }
    }
  }
}
```

Multiple parameters can be provided to multiple tasks via the command line.
Parameters are matched to tasks positionally: the first `--params` applies to
the first task, the second `--params` to the second task, and so on. Consider
the following configuration:

```json
{
  "tasks": {
    "build": {
      "cmd": "bun build ./cli.ts --compile --outfile {{outfile}}",
      "params": {
        "outfile": "cli"
      }
    },
    "test": {
      "cmd": "bun test --timeout {{timeout}} {{opts}}",
      "params": {
        "timeout": "3000"
      }
    }
  }
}
```

The following command will effectively run the command
`bun build ./cli.ts --compile --outfile mycli` for the `build` task and
`bun test --timeout 5000 --coverage --randomize` for the `test` task:

```sh
cadence run --params "outfile=mycli" --params "timeout=5000 opts='--coverage --randomize'" build test
```

Parameters can be passed to dependencies using the `pass_to` property. When a
parameter needs to be forwarded to a dependency, the object form is used with
both `value` and `pass_to` required. The forwarded value overrides any default
the dependency has for that parameter.

In the following example, `test` defaults its `cwd` parameter to `.`, but when
run as dependency of `build`, it receives `./app` instead:

```json
{
  "tasks": {
    "build": {
      "cmd": "bun --cwd {{cwd}} build ./cli.ts --compile",
      "depends_on": ["test"],
      "params": {
        "cwd": {
          "value": "./app",
          "pass_to": ["test"]
        }
      }
    },
    "test": {
      "cmd": "bun test --cwd {{cwd}}",
      "params": {
        "cwd": "."
      }
    }
  }
}
```

### Workspaces

A workspace is a set of sub-projects within the codebase. The
[`workspace`](#workspace) property defines which directories belong to the
workspace using glob patterns. When a task is run from the workspace root, it
will be run for each workspace directory that defines the task.

Modules are used to categorize workspace directories. The top-level
[`modules`](#modules) property defines module types, where each type has a list
of glob patterns. A directory is considered a given module type if it contains a
file matching any of the patterns.

Within a task definition, the [`modules`](#modules-1) property allows
configuration to be applied only to specific module types. Task definitions can
contain all of the properties they normally do.

Assume the codebase contains `client` and `server` directories nested under an
`apps` directory:

```json
{
  "workspace": ["apps/*"],
  "modules": {
    "client": ["package.json"],
    "server": ["go.mod"]
  },
  "tasks": {
    "test": {
      "depends_on": ["#test"],
      "modules": {
        "client": {
          "cmd": "bun test"
        },
        "server": {
          "cmd": "go test ./..."
        }
      }
    }
  }
}
```

In this example, `apps/client` matches the `client` module type because it
contains a `package.json` file, and `apps/server` matches the `server` module
type because it contains a `go.mod` file. Each workspace member's `test` task
depends on `#test`, which resolves to the `test` task from each directory in its
own [`dependencies`](#dependencies-1) list.

### Caching

In most cases, the caching provided by your language-specific build tools is
sufficient. When it is not, Cadence can cache tasks to prevent them from
rerunning when their inputs have not changed.

Use the [`cache`](#cache) property to define patterns that match input and
output files:

```json
{
  "tasks": {
    "build": {
      "cmd": "bun build ./cli.ts --compile --outfile mycli",
      "cache": {
        "inputs": ["**/*.ts", "package*.json"],
        "outputs": ["mycli"]
      }
    }
  }
}
```

Input changes are detected using file hashes. If none of the inputs have changed
between runs of the `build` task, the task will be skipped and any outputs will
be restored from the cache. Cache data is stored in `.cadence/cache/`. To bypass
the cache, use the `--no-cache` flag. To clear the cache, run `cadence clean`.

## Configuration Reference

Complete examples of both [unimodular](./examples/unimodular) and
[multimodular](./examples/multimodular) project configurations can be found in
the [examples](./examples) directory.

#### `aliases`

A map from task names to arrays of aliases.

```json
{
  "aliases": {
    "test": ["t", "tst"]
  },
  "tasks": {
    "test": {
      "cmd": "bun test"
    }
  }
}
```

#### `dependencies`

An array of relative paths to dependency directories. This property is used in
combination with [`depends_on`](#depends_on).

```json
{
  "dependencies": ["../lib"],
  "tasks": {
    "test": {
      "cmd": "bun test",
      "depends_on": ["#test"]
    }
  }
}
```

#### `modules`

A map from module names to arrays of glob patterns matching files and
directories whose presence indicate the given module type is active. This
property is used in combination with task-level [`modules`](#modules-1).

```json
{
  "modules": {
    "client": ["package.json"],
    "server": ["go.mod"]
  },
  "tasks": {
    "test": {
      "depends_on": ["#test"],
      "modules": {
        "client": {
          "cmd": "bun test"
        },
        "server": {
          "cmd": "go test ./..."
        }
      }
    }
  }
}
```

#### `root`

A boolean that when `true`, indicates that this file is the root for the
project.

```json
{
  "root": true
}
```

#### `shell`

The shell to use when executing commands. The possible values are `ash`, `bash`,
`powershell`, `sh`, and `zsh`. The default is `sh`.

```json
{
  "shell": "zsh"
}
```

#### `tasks`

A map from task names to [task definitions](#task-reference).

```json
{
  "tasks": {
    "test": {
      "cmd": "bun test"
    }
  }
}
```

#### `workspace`

An array of glob patterns matching directories to include in the workspace.
Traversal will stop when this property is encountered. See
[Workspaces](#workspaces) for more information.

```json
{
  "workspace": ["workspace/*"],
  "tasks": {
    "test": {
      "cmd": "bun test"
    }
  }
}
```

### Task Reference

#### `cache`

**Properties**

- `inputs`: An array of glob patterns matching files and directories that are
  inputs to the task.
- `outputs`: An array of glob patterns matching files and directories that are
  outputs of the task.

See [Caching](#caching) for more information.

```json
{
  "tasks": {
    "build": {
      "cmd": "bun build ./cli.ts --compile --outfile mycli",
      "cache": {
        "inputs": ["**/*.ts", "package*.json"],
        "outputs": ["mycli"]
      }
    }
  }
}
```

#### `cmd`

The command(s) to execute. When an array of commands is provided, they will be
executed sequentially.

```json
{
  "tasks": {
    "test": {
      "cmd": "bun test"
    }
  }
}
```

```json
{
  "tasks": {
    "test": {
      "cmd": ["docker compose up -d --wait", "bun test"]
    }
  }
}
```

#### `depends_on`

An array of task names that the given task depends on. A prefix of `#` indicates
workspace dependency. See [Dependencies](#dependencies) for more information.

```json
{
  "dependencies": ["../lib"],
  "tasks": {
    "test": {
      "cmd": "bun test",
      "depends_on": ["#test"]
    }
  }
}
```

#### `env`

A map of environment variables to set when running the task.

```json
{
  "tasks": {
    "test": {
      "cmd": "bun test",
      "env": {
        "PGHOST": "postgres"
      }
    }
  }
}
```

#### `modules`

Defines project type-specific properties. This property is used in combination
with the root-level [`modules`](#modules) property.

```json
{
  "modules": {
    "client": ["package.json"],
    "server": ["go.mod"]
  },
  "tasks": {
    "test": {
      "modules": {
        "client": {
          "cmd": "bun test"
        },
        "server": {
          "cmd": "go test ./..."
        }
      }
    }
  }
}
```

#### `params`

Parameters to a task's command. Values can be provided as strings or as objects
with `value` and `pass_to` properties. See [Parameters](#parameters) for more
information.

```json
{
  "tasks": {
    "build": {
      "cmd": "bun --cwd {{cwd}} build ./cli.ts --compile",
      "depends_on": ["test"],
      "params": {
        "cwd": {
          "value": "./app",
          "pass_to": ["test"]
        }
      }
    },
    "test": {
      "cmd": "bun test --cwd {{cwd}}",
      "params": {
        "cwd": "."
      }
    }
  }
}
```

#### `skip`

Whether to skip this task or not. When `true` in the starting directory, the
task will not be run. When `true` in a parent directory, the task definition in
that file will not contribute to the final merged definition.

```json
{
  "tasks": {
    "test": {
      "skip": true
    }
  }
}
```

#### `watch`

An array of glob patterns matching files and directories to watch for changes.

```json
{
  "tasks": {
    "test": {
      "cmd": "go test ./...",
      "watch": ["**/*.go", "go.mod", "go.sum"]
    }
  }
}
```

## Command Line Reference

```sh
cadence [options] [command]
```

**Global Options**

- `-c, --cwd <PATH>`: The directory to begin execution from
- `-h, --help`: Print the help menu
- `-v, --version`: Print the current version

### Commands

#### clean

Clean the cache.

```sh
cadence clean
```

#### run

Run tasks.

```sh
cadence run [options] <task>...
```

**Options**

- `-f, --fail`: Exit the process after the first task failure
- `-h, --help`: Print the help menu
- `-j, --jobs <INT>`: The maximum number of parallel tasks (default:
  processors + 1)
- `-m, --minimal-logs`: Print task logs only, skip titles and summary
- `-n, --no-cache`: Skip reading and writing the cache
- `-p, --params <PARAMS>`: Parameters to pass to tasks
- `-q, --quiet`: Only print output from failed tasks
- `-w, --watch`: Rerun tasks when files matching the pattern change

#### tree

Print the dependency tree.

```sh
cadence tree <task>...
```
