# Hexo博客维护指南

## 已完成的操作

1. ✅ 克隆了hexo-blog仓库到 `~/hexo-blog`
2. ✅ 安装了所有依赖 (Node.js, hexo等)
3. ✅ 创建了关于Hermes Agent的博客文章
4. ✅ 更新了部署配置为SSH方式
5. ✅ 部署到GitHub Pages: https://goodisok.github.io
6. ✅ 推送源代码到hexo-blog仓库
7. ✅ 创建了维护脚本 `maintain.sh`

## 博客文章详情

**标题**: Hermes Agent 完全指南：你的全能AI助手  
**文件**: `source/_posts/hermes-agent-complete-guide.md`  
**标签**: [AI, 工具, 自动化, 开发, 效率]  
**分类**: [技术工具]  
**URL**: https://goodisok.github.io/2026/04/19/hermes-agent-complete-guide/

## 维护命令

使用维护脚本简化操作：

```bash
# 进入博客目录
cd ~/hexo-blog

# 查看所有命令
./maintain.sh

# 创建新文章
./maintain.sh new "文章标题"

# 本地预览
./maintain.sh serve

# 部署到GitHub Pages
./maintain.sh deploy

# 更新博客(拉取最新代码)
./maintain.sh update

# 备份更改
./maintain.sh backup

# 查看状态
./maintain.sh status
```

## 手动命令参考

```bash
# 创建新文章
npx hexo new "文章标题"

# 生成静态文件
npx hexo clean
npx hexo generate

# 本地预览
npx hexo server

# 部署
npx hexo deploy

# Git操作
git add .
git commit -m "消息"
git push origin main
```

## 重要文件位置

- 博客目录: `~/hexo-blog/`
- 文章目录: `~/hexo-blog/source/_posts/`
- 配置文件: `~/hexo-blog/_config.yml`
- 维护脚本: `~/hexo-blog/maintain.sh`

## 验证部署

访问你的博客: https://goodisok.github.io

新文章应该出现在首页，或者直接访问:
https://goodisok.github.io/2026/04/19/hermes-agent-complete-guide/

## 后续维护建议

1. **定期备份**: 使用 `./maintain.sh backup`
2. **更新依赖**: 使用 `./maintain.sh update`
3. **本地测试**: 先使用 `./maintain.sh serve` 预览
4. **然后部署**: 使用 `./maintain.sh deploy` 发布

## 故障排除

如果遇到问题:

1. 检查Node.js版本: `node --version`
2. 检查hexo: `npx hexo version`
3. 清理缓存: `npx hexo clean`
4. 重新安装依赖: `rm -rf node_modules && npm install`

## 联系信息

- GitHub: goodisok
- 邮箱: lcgsmile@qq.com
- 博客: https://goodisok.github.io

---
*本文档由Hermes Agent自动生成*