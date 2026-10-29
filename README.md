# parcel

A small cross-platform package manager and Git repository dashboard.

Parcel has one interface with two tabs:

- **Tools** manages GitHub release binaries listed in `_packages.tsv`.
- **Repos** manages the Git checkouts listed in `repos.tsv`.

Parcel is a personal tool and is still early. The package catalog in this
repository is the author's own; edit it to suit your machine.

Use the native launcher for your operating system:

```text
macOS    ./parcel.command
Linux    ./parcel.sh
Windows  parcel.cmd
```

On macOS or Linux, make the launcher executable once if needed with
`chmod +x parcel.command parcel.sh`. On Windows, `parcel.cmd` is implemented as
a plain Command Prompt batch file. The only exception is raw `.gz` release
assets, which are decompressed with Windows PowerShell's built-in .NET gzip
support.

## Keyboard interface

Run a launcher without arguments to open the combined interface. The POSIX
interface supports the movement and selection keys below. The pure-batch
Windows interface uses labeled action keys and prompts for one or more package
or repository names.

| Key | Action |
| --- | --- |
| Left / Right | Switch between Tools and Repos |
| Up / Down or `k` / `j` | Move through the active tab |
| `J` / `K` | Move ten rows on macOS/Linux |
| Space | Toggle the current item |
| `*` | Select every item in the active tab |
| `q` | Quit |

Tools actions are `+` to install or update, `^` to update installed tools, and
`-` to remove. Repos actions are `<` to fast-forward pull, `>` to stage all
changes, commit, and push, `+` to commit already staged changes, and `-` to
roll back after an explicit `ROLLBACK` confirmation.

On Windows, the Tools actions are `I` install/update, `U` update, `D` remove,
and `R` switch to Repos. The Repos actions are `F` refresh, `L` pull, `P` push,
`C` commit, `B` rollback, and `T` switch to Tools. Press `Q` to quit either
dashboard.

## Command line

Package commands use a direct form:

```text
parcel catalog
parcel list
parcel install <package> [package ...]
parcel remove <package|all> [package ...]
parcel update [package ...|all]
```

`tools` is also accepted as an optional namespace, for example
`parcel tools list`. Repository commands use the `repos` namespace so the two
different `list` operations are unambiguous:

```text
parcel repos list
parcel repos refresh [repo ...]
parcel repos pull <repo> [repo ...]
parcel repos push <repo> [repo ...] --message "message"
parcel repos commit <repo> [repo ...] --message "message"
parcel repos rollback <repo> [repo ...]
```

Replace `parcel` in these examples with the launcher for your platform.

## Data and installed files

- `_packages.tsv` is the tool catalog and remains the only file needed to add a
  package. Its columns are `PACKAGE`, GitHub repository `URL`, release-asset
  regular expression `FILE`, and comma-separated executable paths `EXE`.
- `_state.tsv` is local install state. It is created automatically on first run
  and is ignored by Git. Its tab-separated columns are:

  ```text
  PACKAGE\tDATE\tVERSION\tSIZE_KB\tFILES
  ```

  `PACKAGE` is the catalog package name, `DATE` is the UTC installation date,
  `VERSION` is the installed release tag, `SIZE_KB` is the installed size in
  KiB, and `FILES` is the installed file count.
- `repos.tsv` stores repository paths and refreshed Git/checkout metadata. It
  is local and ignored by Git; it is created empty on first run, or you can
  start from `repos.example.tsv`. To add a repository, fill in `REPOSITORY`,
  `REMOTE_URL`, `BRANCHES`, and `LOCAL_URL`, then run `parcel repos refresh`
  to fill in the rest. (The Windows launcher needs all four, because empty
  tab-separated fields shift the columns after them.)
- `packages/` stores releases; `packages/bin/` stores commands exposed on PATH.

`VERSION` in a catalog asset pattern is replaced with the release tag without
its leading `v`. Assets are matched to the current OS and CPU architecture.
Parcel adds `packages/bin` to the user PATH on first use. Open a new terminal
after that first run on Windows. On Windows, Parcel creates `.cmd` launchers
that forward all arguments to each installed executable, so no Developer Mode
or elevation is needed.

When Workerd's latest GitHub release does not include a Windows binary, the
Windows launcher temporarily falls back to `v1.20260801.1`.

The POSIX implementation requires `curl` and standard archive tools (`tar`,
`unzip`, and `gzip` as applicable). Windows uses `curl`, `tar`, `findstr`, and
Windows PowerShell's built-in .NET gzip support for raw `.gz` release assets.
