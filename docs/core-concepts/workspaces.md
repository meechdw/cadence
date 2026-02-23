# Workspaces

A workspace is a set of sub-projects within the codebase. The
[`workspace`](../configuration.md#workspace) property defines which directories
belong to the workspace using glob patterns. When a task is run from the
workspace root, it will be run for each workspace directory that defines the
task.

Modules are used to categorize workspace directories. The top-level
[`modules`](../configuration.md#modules) property defines module types, where
each type has a list of glob patterns. A directory is considered a given module
type if it contains a file matching any of the patterns.

Within a task definition, the [`modules`](../task-reference.md#modules) property
allows configuration to be applied only to specific module types. Task
definitions can contain all of the properties they normally do.

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
        "client": "bun test",
        "server": "go test ./..."
      }
    }
  }
}
```

In this example, `apps/client` matches the `client` module type because it
contains a `package.json` file, and `apps/server` matches the `server` module
type because it contains a `go.mod` file. Each workspace member's `test` task
depends on `#test`, which resolves to the `test` task from each directory in its
own [`dependencies`](../configuration.md#dependencies) list.
