# Task Reference

Task properties are defined within the [`tasks`](configuration.md#tasks) map.

---

## `aliases`

An array of aliases for the task name.

```json
{
  "tasks": {
    "test": {
      "aliases": ["t", "tst"],
      "cmd": "bun test"
    }
  }
}
```

## `cache`

**Properties**

- `inputs`: An array of glob patterns matching files and directories that are
  inputs to the task.
- `outputs`: An array of glob patterns matching files and directories that are
  outputs of the task.

See [Caching](core-concepts/caching.md) for more information.

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

## `cmd`

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

## `depends_on`

An array of task names that the given task depends on. A prefix of `#` indicates
workspace dependency. See [Dependencies](core-concepts/dependencies.md) for more
information.

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

## `env`

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

## `modules`

Defines project type-specific properties. This property is used in combination
with the root-level [`modules`](configuration.md#modules) property.

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

## `params`

Parameters to a task's command. Values can be provided as strings or as objects
with `value` and `pass_to` properties. See
[Parameters](core-concepts/parameters.md) for more information.

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

## `skip`

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

## `watch`

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
