<h1>
<p align="center">
  <img src="./docs/images/cadence-logo-blue.svg" width="128" height="128" alt="Cadence logo">
  <br>Cadence
</h1>
  <p align="center">
    High-performance task orchestration system for any codebase.
  </p>
</p>

<!-- prettier-ignore-start -->
> [!WARNING]
> This project is in early development and is not ready for use.
<!-- prettier-ignore-end -->

## About

Cadence is a language-agnostic task orchestration system designed to scale from
small projects to large monorepos with minimal configuration.

Tasks are executed in topological order according to their dependencies,
parallelizing where possible. They can be defined once and extended or
overridden to suit specific project requirements.

Opt-in caching ensures tasks only run when their inputs have changed, restoring
artifacts from previous runs when nothing has.

## Documentation

Visit the [documentation site](https://meechdw.github.io/cadence) for
installation instructions, configuration reference, and usage guides.
