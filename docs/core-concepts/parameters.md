# Parameters

Parameters can be provided to a task's command via the command line. Consider
the following configuration:

```json
{
  "tasks": {
    "test": "bun test {{opts}}"
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

## Passing Parameters to Dependencies

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
