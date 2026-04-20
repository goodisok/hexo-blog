#!/bin/bash
cd /home/dministrator/hexo-blog
export NODE_OPTIONS="--max-old-space-size=4096"
echo "Starting hexo generate with increased memory..."
timeout 120 npx hexo generate 2>&1 | tee /tmp/hexo_simple.log
echo "Exit code: $?"
ls -la public/ 2>/dev/null | head -5