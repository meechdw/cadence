# Caching

In most cases, the caching provided by your language-specific build tools is
sufficient. When it is not, Cadence can cache tasks to prevent them from
rerunning when their inputs have not changed.

Use the [`cache`](../task-reference.md#cache) property to define patterns that
match input and output files:

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
