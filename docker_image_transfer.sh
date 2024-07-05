#!/bin/bash

# 显示帮助信息
show_help() {
    echo "Usage: $0 [--local] [--import-docker] [--import-containerd] [--keep-prefix <需保留的前缀>] [--new-repo <新镜像仓库>] [--config-file <配置文件路径>] <完整镜像名1> [<完整镜像名2> ...]"
    echo
    echo "参数："
    echo "  --local              选项参数，表示是否通过 docker save 和 docker load 命令在本地中转镜像文件"
    echo "  --import-docker      选项参数，表示是否通过 docker import 命令导入镜像文件"
    echo "  --import-containerd  选项参数，表示是否通过 containerd 相关命令导入镜像文件"
    echo "  --keep-prefix        选项参数，表示在解析镜像名时需要保留的前缀，可以输入多次"
    echo "  --new-repo           选项参数，表示新的镜像仓库地址"
    echo "  --config-file        选项参数，配置文件的路径"
    echo "  <完整镜像名>           必选参数，表示要处理的完整镜像名，可以输入多个"
    echo
    echo "环境变量："
    echo "  NEW_REPO             必须设置为新的镜像仓库地址，除非通过命令行参数提供"
    echo
    echo "配置文件："
    echo "  可以在脚本同目录下创建 .config 文件，包含 NEW_REPO=<新的镜像仓库>"
    echo
    echo "示例："
    echo "  $0 k8s.gcr.io/pause:3.2"
    echo "  $0 --local rancher/rancher:v2.8.3 nginx"
    echo "  $0 --keep-prefix rancher --keep-prefix myrepo rancher/rancher:v2.8.3"
    echo "  $0 --new-repo swr.cn-east-3.myhuaweicloud.com/yelijing18/ rancher/rancher:v2.8.3"
    echo "  $0 --config-file /path/to/config rancher/rancher:v2.8.3"
}

# 检查参数数量
if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# 初始化变量
DEFAULT_CONFIG_FILE="$(dirname "$0")/.config"
DEFAULT_TAG="latest"
LOCAL_FLAG=""
IMPORT_DOCKER_FLAG=""
IMPORT_CONTAINERD_FLAG=""
NEW_REPO=""
KEEP_PREFIXES=()
CONFIG_FILE="$DEFAULT_CONFIG_FILE"
IMAGES=()

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --local)
            LOCAL_FLAG="--local"
            shift
            ;;
        --import-docker)
            IMPORT_DOCKER_FLAG="--import-docker"
            shift
            ;;
        --import-containerd)
            IMPORT_CONTAINERD_FLAG="--import-containerd"
            shift
            ;;
        --keep-prefix)
            KEEP_PREFIXES+=("$2")
            shift 2
            ;;
        --new-repo)
            NEW_REPO=$2
            shift 2
            ;;
        --config-file)
            CONFIG_FILE=$2
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            IMAGES+=("$1")
            shift
            ;;
    esac
done

# 加载配置文件
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# 检查是否设置了NEW_REPO环境变量
if [[ -z "$NEW_REPO" ]]; then
    echo "错误：缺少新的镜像仓库地址。请通过命令行参数 --new-repo，环境变量 NEW_REPO 或配置文件提供。"
    show_help
    exit 1
fi

# 检查必要参数
if [[ ${#IMAGES[@]} -eq 0 ]]; then
    echo "错误：缺少必要参数。"
    show_help
    exit 1
fi

# 解析镜像名称和标签
parse_image() {
    local full_image=$1
    if [[ "$full_image" == *":"* ]]; then
        IMAGE_NAME=$(echo "$full_image" | cut -d':' -f1)
        TAG=$(echo "$full_image" | cut -d':' -f2)
    else
        IMAGE_NAME="$full_image"
        TAG="$DEFAULT_TAG"
    fi

    if [[ "$IMAGE_NAME" == *"/"* ]]; then
        for prefix in "${KEEP_PREFIXES[@]}"; do
            if [[ "$IMAGE_NAME" == "$prefix"* ]]; then
                ORIGINAL_REPO=""
                return
            fi
        done
        ORIGINAL_REPO=$(echo "$IMAGE_NAME" | rev | cut -d'/' -f2- | rev)/
        IMAGE_NAME=$(echo "$IMAGE_NAME" | rev | cut -d'/' -f1 | rev)
    else
        ORIGINAL_REPO=""
    fi
}

echo "# 拉取镜像："
for FULL_IMAGE in "${IMAGES[@]}"; do
    parse_image "$FULL_IMAGE"
    echo "docker pull ${ORIGINAL_REPO}${IMAGE_NAME}:${TAG}"
done
echo

if [[ "$LOCAL_FLAG" == "--local" ]]; then
    echo "# 导出到本地文件并删除本地镜像："
    for FULL_IMAGE in "${IMAGES[@]}"; do
        parse_image "$FULL_IMAGE"
        FILE_NAME="${IMAGE_NAME##*/}-${TAG}.tar"
        echo "docker save -o ${FILE_NAME} ${ORIGINAL_REPO}${IMAGE_NAME}:${TAG}"
        echo "docker rmi ${ORIGINAL_REPO}${IMAGE_NAME}:${TAG}"
    done
    echo
    echo "# 请通过合适的方式传输镜像文件"
    echo
    echo "# 从本地文件导入镜像"
    for FULL_IMAGE in "${IMAGES[@]}"; do
        parse_image "$FULL_IMAGE"
        FILE_NAME="${IMAGE_NAME##*/}-${TAG}.tar"
        echo "docker load < ${FILE_NAME}"
    done
    echo
fi

echo "# 重命名镜像、推送并删除本地镜像："
for FULL_IMAGE in "${IMAGES[@]}"; do
    parse_image "$FULL_IMAGE"
    echo "docker tag ${ORIGINAL_REPO}${IMAGE_NAME}:${TAG} ${NEW_REPO}${IMAGE_NAME}:${TAG}"
    echo "docker push ${NEW_REPO}${IMAGE_NAME}:${TAG}"
    echo "docker rmi ${NEW_REPO}${IMAGE_NAME}:${TAG}"
    echo "docker rmi ${ORIGINAL_REPO}${IMAGE_NAME}:${TAG}"
done
echo

if [[ "$IMPORT_DOCKER_FLAG" == "--import-docker" ]]; then
    echo "# 请确保镜像已配置为公开或正确配置了拉取密钥"
    echo
    echo "# 拉取镜像并还原标签"
    for FULL_IMAGE in "${IMAGES[@]}"; do
        parse_image "$FULL_IMAGE"
        echo "docker pull ${NEW_REPO}${IMAGE_NAME}:${TAG}"
        echo "docker tag ${NEW_REPO}${IMAGE_NAME}:${TAG} ${ORIGINAL_REPO}${IMAGE_NAME}:${TAG}"
        echo "docker rmi ${NEW_REPO}${IMAGE_NAME}:${TAG}"
    done
    echo
fi

if [[ "$IMPORT_CONTAINERD_FLAG" == "--import-containerd" ]]; then
    echo "# 请确保镜像已配置为公开或正确配置了拉取密钥"
    echo
    echo "# 拉取镜像并还原标签"
    for FULL_IMAGE in "${IMAGES[@]}"; do
        parse_image "$FULL_IMAGE"
        echo "ctr i pull ${NEW_REPO}${IMAGE_NAME}:${TAG}"
        echo "ctr i tag ${NEW_REPO}${IMAGE_NAME}:${TAG} ${ORIGINAL_REPO}${IMAGE_NAME}:${TAG}"
        echo "ctr i del ${NEW_REPO}${IMAGE_NAME}:${TAG}"
    done
    echo
fi