---
title: 在新电脑上写 Hexo 博客
date: 2026-03-17 14:00:00
categories:
  - 教程
tags:
  - Hexo
  - GitHub
  - 博客
  - 多设备
---

换电脑后想继续写博客，只要把「博客源码」从 GitHub 拉下来、装好环境，就能像在本机一样写文章和部署。本文说明如何把源码保存到 GitHub，以及在新电脑上的完整操作步骤。

## 为什么要单独一个「源码仓库」？

部署到 GitHub Pages 时，`hexo deploy` 只会把**生成好的静态文件**（`public/` 里的内容）推送到 **goodisok.github.io** 仓库。那个仓库里**没有**：

- 文章源文件（`source/_posts/*.md`）
- 主题和插件配置
- `_config.yml` 等站点配置

所以要在多台电脑之间写博客，需要**另建一个仓库**专门存放「博客源码」，新电脑克隆这个仓库即可继续写作和部署。

## 一、第一次：在现有电脑上把源码保存到 GitHub（只需做一次）

### 1. 在 GitHub 新建仓库

- 打开 [GitHub 新建仓库](https://github.com/new)
- 仓库名可随意，例如 **hexo-blog** 或 **blog-source**（与 goodisok.github.io 区分开）
- 选择 Public，**不要**勾选「Add a README file」（避免与本地已有文件冲突）
- 创建仓库

### 2. 在本地项目目录执行 Git 命令

在博客项目根目录（如 `E:\hexo-blog`）下执行：

```bash
git init
git add .
git commit -m "Initial commit: Hexo blog source"
git branch -M main
git remote add origin https://github.com/goodisok/hexo-blog.git
git push -u origin main
```

请将 `goodisok/hexo-blog` 替换为你刚创建的仓库地址。若使用 SSH，可改为：

```bash
git remote add origin git@github.com:goodisok/hexo-blog.git
```

项目中的 `.gitignore` 已忽略 `node_modules/`、`public/`、`.deploy_git/` 等，推送的只是源码和配置，体积较小。

### 3. 确认推送成功

在 GitHub 上打开该仓库，应能看到 `source/`、`_config.yml`、`package.json`、文章等。之后换电脑就从这里拉取。

## 二、在新电脑上的操作

### 1. 安装环境

- **Node.js**（建议 12.0 及以上）：[nodejs.org](https://nodejs.org/)
- **Git**：[git-scm.com](https://git-scm.com/)
- **pnpm**（在安装好 Node 后执行）：`npm install -g pnpm`

### 2. 克隆源码仓库

```bash
git clone https://github.com/goodisok/hexo-blog.git
cd hexo-blog
```

使用 SSH 则可写为：`git clone git@github.com:goodisok/hexo-blog.git`

### 3. 安装依赖

```bash
pnpm install
```

会根据 `package.json` 安装 Hexo 及主题、部署插件等。

### 4. 写文章、预览与部署

```bash
# 新建一篇文章
npx hexo new "新文章标题"

# 编辑 source/_posts/新文章标题.md 后，本地预览
pnpm run server

# 生成并部署到 GitHub Pages（发布到 goodisok.github.io）
pnpm run deploy
```

新电脑上**无需**再改 `_config.yml` 里的 `deploy.repo`，只要本机已登录 GitHub（或配置好 SSH），`pnpm run deploy` 就会把静态站推送到 goodisok.github.io。

## 三、多台电脑之间如何同步

- **在 A 电脑**：写完或改完文章后，先同步源码，再部署：
  ```bash
  git add .
  git commit -m "更新文章：xxx"
  git push
  pnpm run deploy
  ```
- **在 B 电脑**：先拉取最新源码，再按需部署：
  ```bash
  git pull
  pnpm run deploy
  ```

这样「源码」在源码仓库里通过 Git 同步，「网站」通过 `pnpm run deploy` 发布到 goodisok.github.io，换电脑写博客就不会丢内容或配置。

## 小结

| 步骤 | 说明 |
|------|------|
| 首次在现电脑 | 新建一个「源码仓库」，在项目目录 `git init` → `add` → `commit` → `remote` → `push` |
| 新电脑 | 安装 Node、Git、pnpm → `git clone` 源码仓库 → `pnpm install` → 正常写文章、`pnpm run deploy` |
| 日常同步 | 改完代码/文章就 `git add` → `commit` → `push`；换电脑先 `git pull` 再写或再部署 |

只要养成「写完就 push 源码、换电脑先 pull」的习惯，就可以在任意一台电脑上持续维护同一份 Hexo 博客。
