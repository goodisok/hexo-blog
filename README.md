# goodisok 的 Hexo 博客

基于 [Hexo](https://hexo.io/zh-cn/) 的静态博客，部署到 [GitHub Pages](https://goodisok.github.io)。

## 常用命令

```bash
# 本地预览（默认 http://localhost:4000）
pnpm run server
# 或
npx hexo server

# 写新文章
npx hexo new "文章标题"

# 生成静态文件
pnpm run build
# 或
npx hexo generate

# 部署到 GitHub Pages（需先完成下方「部署前准备」）
pnpm run deploy
# 或
npx hexo deploy
```

## 部署到 GitHub Pages

### 1. 在 GitHub 创建仓库

- 打开 [GitHub 新建仓库](https://github.com/new)
- 仓库名填：**goodisok.github.io**（必须与用户名一致，才能用 `https://goodisok.github.io` 访问）
- 选择 Public，可勾选「Add a README」，然后创建

### 2. 配置推送权限

任选一种方式：

**方式 A：SSH（推荐）**

- 若已配置 SSH key，把 `_config.yml` 里 `deploy.repo` 改为：
  `git@github.com:goodisok/goodisok.github.io.git`
- 未配置可参考：[GitHub 添加 SSH 密钥](https://docs.github.com/cn/authentication/connecting-to-github-with-ssh)

**方式 B：HTTPS + 个人访问令牌**

- 在 GitHub：Settings → Developer settings → Personal access tokens 新建 token，勾选 `repo`
- 把 `_config.yml` 里 `deploy.repo` 改为：
  `https://<你的token>@github.com/goodisok/goodisok.github.io.git`
- 注意：不要把 token 提交到公开仓库，建议用环境变量或本地覆盖配置

### 3. 执行部署

```bash
pnpm run deploy
```

首次会提示输入 GitHub 用户名和密码（若用 HTTPS，密码处填上面创建的 token）。

部署完成后，过几分钟访问：**https://goodisok.github.io** 即可看到博客。

## 部署到云平台

Hexo 生成的是静态文件（在 `public/` 目录），可以部署到任意支持静态托管的云服务。常见方式如下。

### 方式一：对象存储 + CDN（国内访问快）

把 `pnpm run build` 生成的 **整个 `public/` 目录** 上传到对象存储，并开启「静态网站托管」和（可选）CDN。

| 平台     | 服务          | 大致步骤 |
|----------|---------------|----------|
| 阿里云   | OSS           | 创建 Bucket → 开启静态网站托管 → 上传 `public/*` → 可选绑定 CDN/域名 |
| 腾讯云   | COS           | 同上，在 COS 控制台开启「静态网站」并上传 |
| 华为云   | OBS           | 同上，在 OBS 开启「静态网站」并上传 |

- **上传方式**：控制台手动上传，或用官方 CLI / 图形工具（如 ossutil、coscmd）做脚本化部署。
- 若要用自己的域名，在对应云控制台为 Bucket 绑定域名并配置 CDN 即可。

### 方式二：Vercel / Netlify / Cloudflare Pages（连 GitHub 自动部署）

把本仓库推到 GitHub 后，在这些平台「从 GitHub 导入项目」，它们会识别为静态站点并自动构建、部署。

1. **Vercel**：[vercel.com](https://vercel.com) → Import 本仓库 → 构建命令填 `pnpm run build`，输出目录填 `public`。
2. **Netlify**：[netlify.com](https://netlify.com) → 同上，Build command: `pnpm run build`，Publish directory: `public`。
3. **Cloudflare Pages**：[dash.cloudflare.com](https://dash.cloudflare.com) → Pages → 连接 Git → 同上设置构建命令和输出目录。

推送代码后会自动重新部署，适合做「云上」的发布方式之一。

### 方式三：云服务器（ECS）

若已有云服务器（阿里云 / 腾讯云 / 华为云 ECS 等）：

1. 在本地执行 `pnpm run build`，把生成的 **`public/` 目录** 上传到服务器（如 `/var/www/hexo`）。
2. 在服务器上安装 Nginx，配置 root 指向该目录，例如：
   ```nginx
   server {
       listen 80;
       root /var/www/hexo;
       index index.html;
       location / { try_files $uri $uri/ /index.html; }
   }
   ```
3. 绑定域名并（建议）配置 HTTPS（可用 Let’s Encrypt 等）。

之后每次更新博客：本地 `pnpm run build`，再把 `public/` 同步到服务器即可（rsync、FTP 或 CI 脚本均可）。

---

总结：**国内优先访问**用「对象存储 + CDN」；**想省事、自动部署**用 Vercel/Netlify/Cloudflare Pages；**已有服务器**用 ECS + Nginx 托管 `public/`。

## 目录说明

- `source/_posts/` — 文章（Markdown）
- `themes/` — 主题（当前为 landscape）
- `_config.yml` — 站点配置

更多用法见 [Hexo 文档](https://hexo.io/zh-cn/docs/)。

## 在新电脑上写博客

换电脑后只要把「博客源码」拉下来，装好环境，就能继续写文章和部署。注意：**goodisok.github.io** 仓库里只有部署后的静态页面，不包含文章源文件和配置，所以需要单独用一个仓库保存「博客源码」。

### 第一次：在现在这台电脑上保存源码到 GitHub（只需做一次）

1. **在 GitHub 新建一个仓库**（和 goodisok.github.io 分开），例如命名为 `hexo-blog` 或 `blog-source`，不要勾选「Add a README」（避免和本地冲突）。
2. **在本项目目录**（e:\hexo-blog）执行：

   ```bash
   git init
   git add .
   git commit -m "Initial commit: Hexo blog source"
   git branch -M main
   git remote add origin https://github.com/goodisok/hexo-blog.git
   git push -u origin main
   ```

   把 `goodisok/hexo-blog` 换成你刚建的仓库地址。若用 SSH：`git@github.com:goodisok/hexo-blog.git`。

3. 推送完成后，文章、主题、配置就都保存在这个「源码仓库」里了。

### 在新电脑上的操作

1. **安装环境**：Node.js、Git、pnpm（`npm install -g pnpm`）。
2. **克隆源码仓库**：

   ```bash
   git clone https://github.com/goodisok/hexo-blog.git
   cd hexo-blog
   ```

3. **安装依赖**：

   ```bash
   pnpm install
   ```

4. **写文章、预览、部署**：

   ```bash
   npx hexo new "新文章标题"
   # 编辑 source/_posts/新文章标题.md 后：
   pnpm run server   # 本地预览
   pnpm run deploy   # 生成并部署到 GitHub Pages（goodisok.github.io）
   ```

新电脑上不需要再改 `_config.yml` 里的 `deploy.repo`，只要 GitHub 登录/SSH 配置好，`pnpm run deploy` 就会推送到 goodisok.github.io。

### 之后在两台电脑之间同步

- **在 A 电脑**：改完文章后 `git add .` → `git commit` → `git push`，再 `pnpm run deploy`。
- **在 B 电脑**：`git pull` 拉取最新源码，然后 `pnpm run deploy`（如需发布）。

这样源码在「源码仓库」里同步，网站内容在 goodisok.github.io 上展示。
