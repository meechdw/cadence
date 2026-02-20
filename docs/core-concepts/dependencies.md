# Dependencies

Tasks can depend on other tasks either from the same directory or different
directories. A dependency between tasks from different directories is called a
workspace dependency. A prefix of `#` is used to indicate a workspace
dependency.

In the following example, the `build` task depends on the `test` task from the
same directory, and the `test` task depends on `#test`, which is the test task
from each directory listed in
[`dependencies`](../configuration.md#dependencies).

A workspace dependency resolves to every directory in dependencies where the
task is defined. A task is considered defined if, after processing every
`cadence.json` file, it contains a [`cmd`](../task-reference.md#cmd) property
and was not [skipped](../task-reference.md#skip).

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
