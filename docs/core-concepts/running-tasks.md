# Running Tasks

The most basic implementation of a task is a name with a command to run:

```json
{
  "tasks": {
    "build": "bun build ./cli.ts --compile",
    "test": "bun test"
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
