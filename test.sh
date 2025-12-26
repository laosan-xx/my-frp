#!/bin/sh

# OpenWrt frp 包编译测试脚本
# 使用方法:
#   1. 在 OpenWrt SDK 环境中: ./test.sh compile
#   2. 检查 Makefile 语法: ./test.sh check
#   3. 检查文件完整性: ./test.sh verify

set -e

PKG_NAME="frp"
PKG_VERSION="0.65.0"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查必需文件是否存在
check_files() {
    info "检查必需文件..."
    local missing=0
    
    for file in Makefile files/frpc.config files/frpc.init files/frps.config files/frps.init; do
        if [ ! -f "$file" ]; then
            error "缺少文件: $file"
            missing=1
        else
            info "✓ 找到文件: $file"
        fi
    done
    
    if [ $missing -eq 1 ]; then
        error "文件检查失败"
        return 1
    fi
    
    info "所有必需文件存在"
    return 0
}

# 检查 Makefile 语法
check_makefile() {
    info "检查 Makefile 语法..."
    
    if ! make -n -f Makefile 2>&1 | head -20; then
        error "Makefile 语法检查失败"
        return 1
    fi
    
    info "Makefile 语法检查通过"
    return 0
}

# 验证文件完整性
verify_files() {
    info "验证文件完整性..."
    
    # 检查配置文件语法
    if command -v uci >/dev/null 2>&1; then
        info "检查 UCI 配置文件语法..."
        for config in files/frpc.config files/frps.config; do
            if [ -f "$config" ]; then
                # 基本语法检查
                if grep -q "^config " "$config"; then
                    info "✓ $config 格式正确"
                else
                    warn "$config 可能格式不正确"
                fi
            fi
        done
    fi
    
    # 检查 init 脚本
    for init in files/frpc.init files/frps.init; do
        if [ -f "$init" ]; then
            if head -1 "$init" | grep -q "#!/bin/sh"; then
                info "✓ $init 格式正确"
            else
                warn "$init 可能格式不正确"
            fi
        fi
    done
    
    info "文件完整性验证完成"
    return 0
}

# 编译测试（需要 OpenWrt SDK）
compile_test() {
    info "开始编译测试..."
    
    if [ -z "$TOPDIR" ] && [ ! -f "rules.mk" ]; then
        error "未检测到 OpenWrt 构建环境"
        error "请确保:"
        error "  1. 在 OpenWrt SDK 环境中运行此脚本"
        error "  2. 或者设置 TOPDIR 环境变量指向 OpenWrt 源码目录"
        error "  3. 或者使用 'make -f Makefile' 在 SDK 中编译"
        return 1
    fi
    
    info "检测到 OpenWrt 构建环境"
    
    # 尝试编译
    if make -f Makefile V=s 2>&1 | tee /tmp/frp_build.log; then
        info "编译成功！"
        info "编译日志保存在: /tmp/frp_build.log"
        return 0
    else
        error "编译失败，请查看日志: /tmp/frp_build.log"
        return 1
    fi
}

# 显示使用说明
usage() {
    echo "OpenWrt frp 包编译测试脚本"
    echo ""
    echo "使用方法:"
    echo "  $0 check      - 检查 Makefile 语法和文件完整性"
    echo "  $0 verify     - 验证所有配置文件"
    echo "  $0 compile    - 尝试编译包（需要 OpenWrt SDK）"
    echo "  $0 all        - 执行所有检查"
    echo ""
    echo "在 OpenWrt SDK 中编译:"
    echo "  make package/frp/compile V=s"
    echo "  make package/frp/install V=s"
}

# 主函数
main() {
    case "${1:-check}" in
        check)
            check_files && check_makefile
            ;;
        verify)
            check_files && verify_files
            ;;
        compile)
            compile_test
            ;;
        all)
            check_files && check_makefile && verify_files
            info ""
            warn "要执行编译测试，请运行: $0 compile"
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"
