---
title: 将 Hexo 博客部署到 GitHub Pages
date: 2026-03-17 12:00:00
categories:
  - 教程
tags:
  - Hexo
  - GitHub
  - GitHub Pages
  - 博客
---

本文记录从零到把 Hexo 博客成功部署到 GitHub Pages 的完整过程，方便日后查阅或分享给他人。

## 一、前提条件

- 已安装 **Node.js**（建议 12.0 及以上）
- 已安装 **Git**
- 已注册 **GitHub** 账号（本文示例用户名为 `goodisok`）

## 二、初始化 Hexo 项目

在本地选一个目录（如 `e:\hexo-blog`），执行：

```bash
npx hexo-cli init .
```

执行完成后，当前目录下会生成 Hexo 的站点结构，并自动安装依赖（若使用 pnpm 则可能是 `pnpm install`）。

## 三、配置站点与 GitHub 部署

### 1. 修改站点信息

编辑项目根目录的 `_config.yml`，按需修改以下部分：

```yaml
# Site
title: goodisok 的博客    # 博客标题
author: goodisok          # 作者名
language: zh-CN           # 语言
timezone: 'Asia/Shanghai' # 时区

# URL（GitHub 用户名.github.io）
url: https://goodisok.github.io
root: /
```

将 `goodisok` 替换为你自己的 GitHub 用户名即可。

### 2. 配置部署到 GitHub

在 `_config.yml` 末尾的 **Deployment** 部分填写：

```yaml
deploy:
  type: git
  repo: https://github.com/goodisok/goodisok.github.io.git   # 替换为你的仓库地址
  branch: main
  message: 'Deploy Hexo: {{ now("YYYY-MM-DD HH:mm:ss") }}'
```

若使用 SSH，可改为：

```yaml
repo: git@github.com:goodisok/goodisok.github.io.git
```

### 3. 安装部署插件

若未安装 `hexo-deployer-git`，需要先安装：

```bash
pnpm add hexo-deployer-git
# 或
npm install hexo-deployer-git --save
```

## 四、在 GitHub 创建仓库

1. 打开 [GitHub 新建仓库](https://github.com/new)
2. **仓库名**必须填：`<你的用户名>.github.io`  
   - 例如用户名为 `goodisok`，则仓库名为 **goodisok.github.io**
3. 选择 Public，可勾选「Add a README」，然后创建仓库

只有仓库名与用户名一致时，才能通过 `https://<用户名>.github.io` 直接访问博客。

## 五、执行部署

在项目根目录执行：

```bash
pnpm run deploy
# 或
npx hexo deploy
```

首次使用 HTTPS 时，可能会提示输入 GitHub 用户名和密码；若已启用两步验证，需使用 **Personal Access Token** 作为密码。使用 SSH 则需提前配置好 SSH 密钥。

命令执行成功后，会将 Hexo 生成的静态文件推送到仓库的 `main` 分支（或你所配置的分支）。

## 六、开启 GitHub Pages

1. 打开仓库 **Settings** → **Pages**
2. 在 **Build and deployment** 中：
   - **Source** 选择 **Deploy from a branch**
   - **Branch** 选择 **main**（或你部署时使用的分支）
   - 文件夹选择 **/ (root)**
3. 保存后等待 1～2 分钟

## 七、访问博客

在浏览器中打开：

**https://goodisok.github.io**

（将 `goodisok` 换成你的用户名）

若能看到与本地 `hexo server` 一致的页面，说明部署成功。

## 八、之后如何更新

每次写完新文章或修改配置后，在项目目录执行：

```bash
pnpm run deploy
```

即可将最新内容部署到 GitHub，过一会儿刷新博客地址即可看到更新。

---

## 小结

| 步骤 | 操作 |
|------|------|
| 1 | 使用 `hexo init` 初始化项目 |
| 2 | 在 `_config.yml` 中配置 `url`、`deploy`，并安装 `hexo-deployer-git` |
| 3 | 在 GitHub 创建名为 `<用户名>.github.io` 的仓库 |
| 4 | 执行 `pnpm run deploy` 推送静态文件 |
| 5 | 在仓库 Settings → Pages 中选择从 main 分支的 root 部署 |
| 6 | 访问 `https://<用户名>.github.io` 查看博客 |

按以上流程操作即可稳定地将 Hexo 博客部署到 GitHub Pages，无需自备服务器，且支持 HTTPS。
