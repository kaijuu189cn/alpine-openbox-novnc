# legacy/ -- earlier builds, kept for reference

Nothing in here is built by default. `docker compose` and `./scripts/build.sh`
only build the current image from the repository root.

| 目录 / 文件 | 是什么 |
|---|---|
| `Dockerfile.v1-dockercli` | 本项目的 v1：`linuxserver/webtop:alpine-openbox` 的替代品，镜像里带 `docker-cli`（v2 已移除），桌面是 Xvfb + x11vnc + tint2。 |
| `alpine-openbox/` | 最早的 selkies 版本（复用 LinuxServer 的 `baseimage-selkies`），已停止维护。 |
| `alpine-sway/` | 同期的 sway/Wayland 版本，同样基于 selkies 基础镜像。 |

两个 selkies 版本需要 `ghcr.io` 的基础镜像，本网络下 `docker pull` 会静默挂起，
用 `../scripts/fetch-baseimage.sh`（走 skopeo）取，然后用各自的目录作上下文构建：

```bash
./scripts/fetch-baseimage.sh alpine324 amd64
docker build -t webtop:selkies-openbox legacy/alpine-openbox
docker build -t webtop:selkies-sway    legacy/alpine-sway
```

`Dockerfile.v1-dockercli` 是**记录性质**的：它当年构建时用的是 v1 那版的
`root/` 覆盖层，那份覆盖层在本仓库里没有留存（v2 改造时被覆盖）。
现在若用仓库根的 `root/` 去构建它，得到的是"当前镜像去掉 Wine、加回
docker-cli"的混合体——只能用来对比体积/差异，不是当年的 v1。它仍有用的地方：

```bash
# 看 v1 与现在的定义差在哪
git log -p -- legacy/Dockerfile.v1-dockercli
```

v1 与当前版本的差别（去 docker-cli、加 Wine、Xvnc 自适应、无面板、
LinuxServer 样式）见根目录 README 的「v3 变更」与各专题小节。
