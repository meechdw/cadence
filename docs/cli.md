# Command Line Reference

```sh
cadence [options] [command]
```

## Global Options

- `-c, --cwd <PATH>`: The directory to begin execution from
- `-h, --help`: Print help menu and exit
- `-v, --version`: Print version and exit

---

## Commands

### clean

Clean the cache.

```sh
cadence clean
```

### run

Run tasks.

```sh
cadence run [options] <task>...
```

**Options**

- `-f, --fail`: Exit the process after the first task failure
- `-j, --jobs <int>`: The maximum number of parallel tasks (default:
  processors + 1)
- `-m, --minimal-logs`: Print task logs only, skip titles and summary
- `-n, --no-cache`: Skip reading and writing the cache
- `-p, --params <params>`: Parameters to pass to tasks
- `-q, --quiet`: Only print output from failed tasks
- `-w, --watch`: Rerun tasks when files matching the pattern change

### tree

Print the dependency tree.

```sh
cadence tree <task>...
```
