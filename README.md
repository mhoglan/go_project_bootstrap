# go_project_bootstrap
Bootstrapping a go project repository with Makefile and version injection

If you want to populate an existing source directory with these files, you can use the GitHub API to download a tarball and extract into current directory.  Just change the username to yours.

```
curl -u "username" -L https://api.github.com/repos/TuneDB/go_project_bootstrap/tarball | tar --strip-components=1 -zxvf -
```

This will clobber any files in the directory named the same.  So if you have a `Makefile` already, then it will get overidden. 

The `.gitignore` file in this repository has already been populated with `target`, `version_info` and `textfile_constants.go`

You can exclude a file in the tarball extract command to avoid clobbering.  Such as excluding the `.gitignore` file.

```
curl -u "username" -L https://api.github.com/repos/TuneDB/go_project_bootstrap/tarball | tar --strip-components=1 -zxvf - --exclude=".gitignore"
```
