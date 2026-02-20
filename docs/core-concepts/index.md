# Core Concepts

Configuration is defined with `cadence.json` files. Cadence works by walking up
the file tree from the current directory, parsing `cadence.json` files as they
are encountered. Traversal stops when the [root](../configuration.md#root) file,
[workspace](workspaces.md) root, or file system root is reached.

The files are then processed in reverse order of discovery. Files deeper in the
tree take precedence, with their values overriding those defined higher up.
