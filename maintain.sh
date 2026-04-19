#!/bin/bash
# Hexo博客维护脚本
# 保存为: ~/hexo-blog/maintain.sh

set -e

HEXO_DIR="$HOME/hexo-blog"
cd "$HEXO_DIR"

case "$1" in
    "new")
        if [ -z "$2" ]; then
            echo "用法: $0 new \"文章标题\""
            exit 1
        fi
        echo "创建新文章: $2"
        npx hexo new "$2"
        ;;
        
    "serve")
        echo "启动本地服务器 (端口: 4000)"
        npx hexo clean
        npx hexo generate
        npx hexo server
        ;;
        
    "deploy")
        echo "部署到GitHub Pages"
        npx hexo clean
        npx hexo generate
        npx hexo deploy
        ;;
        
    "update")
        echo "更新博客"
        git pull origin main
        npm install
        ;;
        
    "backup")
        echo "备份博客"
        git add .
        git commit -m "备份: $(date '+%Y-%m-%d %H:%M:%S')"
        git push origin main
        ;;
        
    "status")
        echo "=== 博客状态 ==="
        echo "文章数量: $(find source/_posts -name "*.md" | wc -l)"
        echo "最后修改: $(git log -1 --format="%cd" --date=short)"
        echo "Git状态:"
        git status --short
        ;;
        
    *)
        echo "Hexo博客维护脚本"
        echo "用法: $0 {new|serve|deploy|update|backup|status}"
        echo ""
        echo "命令说明:"
        echo "  new \"标题\"     创建新文章"
        echo "  serve          启动本地服务器"
        echo "  deploy         部署到GitHub Pages"
        echo "  update         更新博客(拉取代码+安装依赖)"
        echo "  backup         备份博客到GitHub"
        echo "  status         查看博客状态"
        exit 1
        ;;
esac