# Task Merging

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
