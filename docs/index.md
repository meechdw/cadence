# Cadence

High-performance, cross-platform task orchestration system for any codebase.

!!! warning

    This project is in early development and is not ready for use.

---

## About

Cadence is a language-agnostic task orchestration system designed to scale from
small projects to large monorepos with minimal configuration.

Tasks are executed in topological order according to their dependencies,
parallelizing where possible. They can be defined once and extended or
overridden to suit specific project requirements.

Opt-in caching ensures tasks only run when their inputs have changed, restoring
artifacts from previous runs when nothing has.
