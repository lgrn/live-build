# live-build
live-build configuration for building a live debian system with encrypted persistence

## How to use

Always refer to the [original
documentation](https://live-team.pages.debian.net/live-manual/html/live-manual/index.en.html).
It can also be searched for relevant terms (like "persistence") like so:
`site:live-team.pages.debian.net persistence`

### Preparation

Debian is required. Use a VM if necessary.

```
apt install live-build git
```

Create a directory and initialize a configuration from (this) repo:

```
mkdir live-build && cd live-build
lb config --config https://github.com/lgrn/live-build.git
```


