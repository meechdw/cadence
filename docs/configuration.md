# Configuration Reference

Complete examples of both
[unimodular](https://github.com/meechdw/cadence/tree/main/examples/unimodular)
and
[multimodular](https://github.com/meechdw/cadence/tree/main/examples/multimodular)
project configurations can be found in the
[examples](https://github.com/meechdw/cadence/tree/main/examples) directory.

---

## `dependencies`

An array of relative paths to dependency directories. This property is used in
combination with [`depends_on`](task-reference.md#depends_on).

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

## `modules`

A map from module names to arrays of glob patterns matching files and
directories whose presence indicate the given module type is active. This
property is used in combination with task-level
[`modules`](task-reference.md#modules).

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
        "client": "bun test",
        "server": "go test ./..."
      }
    }
  }
}
```

## `root`

A boolean that when `true`, indicates that this file is the root for the
project.

```json
{
  "root": true
}
```

## `shell`

The shell to use when executing commands. The possible values are `ash`, `bash`,
`powershell`, `sh`, and `zsh`. The default is `sh`.

```json
{
  "shell": "zsh"
}
```

## `tasks`

A map from task names to [task definitions](task-reference.md).

```json
{
  "tasks": {
    "test": "bun test"
  }
}
```

## `workspace`

An array of glob patterns matching directories to include in the workspace.
Traversal will stop when this property is encountered. See
[Workspaces](core-concepts/workspaces.md) for more information.

```json
{
  "workspace": ["workspace/*"],
  "tasks": {
    "test": "bun test"
  }
}
```
