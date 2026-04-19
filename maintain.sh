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
        
    "theme")
        echo "更新Butterfly主题"
        npm update hexo-theme-butterfly
        echo "主题已更新"
        ;;
        
    "config")
        echo "编辑主题配置"
        if [ -f "_config.butterfly.yml" ]; then
            vim _config.butterfly.yml
        else
            echo "主题配置文件不存在"
        fi
        ;;
        
    "rss")
        echo "检查RSS文件"
        if [ -f "public/atom.xml" ]; then
            echo "RSS文件存在，大小: $(wc -c < public/atom.xml) 字节"
            echo "最后更新: $(stat -c %y public/atom.xml)"
        else
            echo "RSS文件不存在，重新生成..."
            npx hexo clean && npx hexo generate
        fi
        ;;
        
    "status")
        echo "=== 博客状态 ==="
        echo "文章数量: $(find source/_posts -name "*.md" | wc -l)"
        echo "主题: Butterfly"
        echo "RSS: 已启用 (atom.xml)"
        echo "最后修改: $(git log -1 --format="%cd" --date=short)"
        echo "Git状态:"
        git status --short
        ;;
        
        echo "Hexo博客维护脚本 (Butterfly主题)"
        echo "用法: $0 {new|serve|deploy|update|backup|theme|config|rss|status}"
        echo ""
        echo "命令说明:"
        echo "  new \"标题\"     创建新文章"
        echo "  serve          启动本地服务器"
        echo "  deploy         部署到GitHub Pages"
        echo "  update         更新博客(拉取代码+安装依赖)"
        echo "  backup         备份博客到GitHub"
        echo "  theme          更新Butterfly主题"
        echo "  config         编辑主题配置"
        echo "  rss            检查RSS文件状态"
        echo "  status         查看博客状态"
        exit 1
        ;;
esac