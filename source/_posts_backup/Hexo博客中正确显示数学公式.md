---
title: Hexo 博客中正确显示数学公式
date: 2026-03-19 12:00:00
categories:
  - 博客
  - 教程
tags:
  - Hexo
  - 数学公式
  - KaTeX
  - Markdown
---

在 Hexo 里写带公式的文章时，经常会遇到公式显示成乱码、下标变成斜体、或整段 LaTeX 原样输出等问题。本文记录问题原因和用 **hexo-filter-katex** 在构建阶段渲染公式的完整做法。

---

## 一、为什么公式会显示不对

### 1.1 Markdown 本身不支持公式

标准 Markdown 没有「数学公式」语法。对 Hexo 来说：

- `$...$` 和 `$$...$$` 只是普通字符，默认不会被任何引擎当成公式；
- 若不做额外处理，它们会原样出现在最终 HTML 里，浏览器不会渲染成数学符号。

### 1.2 默认渲染器会破坏公式里的符号

Hexo 常用 **hexo-renderer-marked**（基于 marked.js）把 Markdown 转成 HTML。marked 会解析一些符号：

- **下划线 `_`** 会被当成强调（italic），例如 `x_n` 可能被变成 `x<em>n</em>`；
- 公式里大量出现的 `_{下标}` 一旦被这样处理，整段 LaTeX 就坏了，再交给任何数学渲染器也无法恢复。

因此：**不能**只依赖「先 Markdown 再在浏览器里用 JS 渲染公式」，必须保证在 Markdown 解析之前，公式就已经被处理掉，或者用「占位符」保护起来。

---

## 二、思路：在 Markdown 解析前渲染公式

比较稳妥的做法是：

1. **在文章被 Markdown 解析之前**，先识别出所有 `$...$` 和 `$$...$$`；
2. 用 **KaTeX** 在 Node 端把这段 LaTeX 转成 HTML（带好 class、样式等）；
3. 用**占位符**替换掉原文里的公式，再交给 marked；
4. 最后在合适阶段把占位符换回已经生成好的公式 HTML。

这样：

- marked 永远不会看到公式里的 `_`、`\` 等，自然也就不会破坏公式；
- 文章里可以写**标准 LaTeX**，不需要在 Markdown 里给下划线加反斜杠转义。

实现这一套流程的插件，就是 **hexo-filter-katex**。

---

## 三、用 hexo-filter-katex 实现

### 3.1 安装插件

项目若用 **pnpm**（存在 `pnpm-lock.yaml` 时）：

```bash
cd <你的 Hexo 根目录>
pnpm add hexo-filter-katex
```

若用 **npm**：

```bash
npm install hexo-filter-katex --save
```

插件会自带依赖 **katex**，无需单独安装。

### 3.2 配置 Hexo

在站点根目录的 `_config.yml` 里增加（或合并到已有配置中）：

```yaml
# 数学公式：在 Markdown 解析前用 KaTeX 渲染，避免被 marked 破坏
katex:
  stylesheet_fragment: '<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css" crossorigin="anonymous">'
  render_options:
    throwOnError: false
```

说明：

- **stylesheet_fragment**：在页面 `<head>` 里插入 KaTeX 的 CSS，公式才有正确样式；不配的话公式 HTML 在，但可能看起来不对。
- **throwOnError: false**：单条公式报错时只影响该条，不会让整站生成失败。

### 3.3 写文章时的公式写法

- **行内公式**：`$...$`，例如：`$\mathbf{F}_{drag} = -k_{linear} \mathbf{v}$`
- **块级公式**：单独一行 `$$`，下一行写公式，再一行 `$$`，例如：

```text
$$
m \mathbf{a} = \mathbf{F}_{total} = \mathbf{F}_{thrust} + \mathbf{F}_{gravity} + \ldots
$$
```

**不需要**在公式里把下划线写成 `\_`，直接写标准 LaTeX 即可（如 `_{total}`、`C_T`），因为插件在 marked 之前就处理掉了。

### 3.4 重新生成与部署

改完配置或文章后：

```bash
npx hexo clean
npx hexo generate
npx hexo server   # 本地预览
```

若部署到 GitHub Pages 等，再执行：

```bash
npx hexo deploy
```

---

## 四、流程小结

| 步骤       | 说明 |
|------------|------|
| 1. 安装    | `pnpm add hexo-filter-katex`（或 npm 对应命令） |
| 2. 配置    | 在 `_config.yml` 中配置 `katex`，至少设置 `stylesheet_fragment` |
| 3. 写公式  | 使用 `$...$` 与 `$$...$$`，按标准 LaTeX 写，无需转义下划线 |
| 4. 生成    | `hexo clean && hexo generate`，需要时再 `hexo deploy` |

插件在 **before_post_render** 阶段（优先级 9）先跑，把正文里的公式用 KaTeX 转成 HTML 并替换为占位符；随后 marked（默认优先级 10）只处理普通 Markdown，不会破坏公式；最终页面里是完整的 KaTeX 输出（含 MathML 与样式），公式即可正常显示。

---

## 五、之前试过但不够稳的办法（可选阅读）

- **只在页面里注入 KaTeX 的 JS，用浏览器渲染**：若不做「先替换再给 marked」的处理，marked 仍会先把公式里的 `_` 等符号改掉，生成的 HTML 里的「公式」已经损坏，客户端再渲染也会错。所以仅靠前端脚本不够。
- **在 Markdown 里把公式中的 `_` 写成 `\_`**：理论上可以保护下标，但整篇文章公式一多就容易漏，且和标准 LaTeX 写法不一致，维护成本高。用 hexo-filter-katex 后就不必再这样写。

综上，在 Hexo 里要稳定、省心地显示数学公式，推荐直接使用 **hexo-filter-katex** 在构建阶段完成渲染，并配好 `stylesheet_fragment` 与 `render_options`。
