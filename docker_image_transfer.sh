#!/bin/bash

# 显示帮助信息
show_help() {
    echo "Usage: $0 [--local] [--import-docker] [--import-containerd] <完整镜像名> <新镜像仓库>"
    echo
    echo "参数："
    echo "  --local              选项参数，表示是否通过 docker save 和 docker load 命令在本地中转镜像文件"
    echo "  --import-docker      选项参数，表示是否通过 docker import 命令导入镜像文件"
    echo "  --import-containerd  选项参数，表示是否通过 containerd 相关命令导入镜像文件"
    echo "  <完整镜像名>           必选参数，表示要处理的完整镜像名"
    echo "  <新镜像仓库>           必选参数，表示新的镜像仓库"
    echo
    echo "示例："
    echo "  $0 k8s.gcr.io/pause:3.2 swr.cn-east-3.myhuaweicloud.com/yelijing18/"
    echo "  $0 --local rancher/rancher:v2.8.3 swr.cn-east-3.myhuaweicloud.com/yelijing18/"
    echo "  $0 nginx swr.cn-east-3.myhuaweicloud.com/yelijing18/"
}

# 检查参数数量
if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
    exit 0
fi

DEFAULT_TAG="latest"
LOCAL_FLAG=""
IMPORT_DOCKER_FLAG=""
IMPORT_CONTAINERD_FLAG=""
FULL_IMAGE=""
NEW_REPO=""

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
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            if [[ -z "$FULL_IMAGE" ]]; then
                FULL_IMAGE=$1
            elif [[ -z "$NEW_REPO" ]]; then
                NEW_REPO=$1
            else
                echo "错误：未知参数 $1"
                show_help
                exit 1
            fi
            shift
            ;;
    esac
done

# 检查必要参数
if [[ -z "$FULL_IMAGE" || -z "$NEW_REPO" ]]; then
    echo "错误：缺少必要参数。"
    show_help
    exit 1
fi

# 解析镜像名称和标签
if [[ "$FULL_IMAGE" == *":"* ]]; then
    IMAGE_NAME=$(echo "$FULL_IMAGE" | cut -d':' -f1)
    TAG=$(echo "$FULL_IMAGE" | cut -d':' -f2)
else
    IMAGE_NAME="$FULL_IMAGE"
    TAG="$DEFAULT_TAG"
fi

# 解析原始镜像仓库和镜像名
if [[ "$IMAGE_NAME" == *"/"* ]]; then
    ORIGINAL_REPO=$(echo "$IMAGE_NAME" | rev | cut -d'/' -f2- | rev)/
    IMAGE_NAME=$(echo "$IMAGE_NAME" | rev | cut -d'/' -f1 | rev)
else
    ORIGINAL_REPO=""
fi

# 文件名
FILE_NAME="${IMAGE_NAME}-${TAG}.tar"

# 打印Docker命令
echo "docker pull ${ORIGINAL_REPO}${IMAGE_NAME}:${TAG}"
if [[ "$LOCAL_FLAG" == "--local" ]]; then
    echo "docker save -o ${FILE_NAME} ${ORIGINAL_REPO}${IMAGE_NAME}:${TAG}"
    echo "docker rmi ${ORIGINAL_REPO}${IMAGE_NAME}:${TAG}"
    echo "# 请通过合适的方式传输镜像文件" 
    echo "docker load < ${FILE_NAME}"
fi
echo "docker tag ${ORIGINAL_REPO}${IMAGE_NAME}:${TAG} ${NEW_REPO}${IMAGE_NAME}:${TAG}"
echo "docker push ${NEW_REPO}${IMAGE_NAME}:${TAG}"
echo "docker rmi ${NEW_REPO}${IMAGE_NAME}:${TAG}"
echo "docker rmi ${ORIGINAL_REPO}${IMAGE_NAME}:${TAG}"
if [[ "$IMPORT_DOCKER_FLAG" == "--import-docker" ]]; then
    echo "# 请确保镜像已配置为公开或正确配置了拉取密钥"
    echo "docker pull ${NEW_REPO}${IMAGE_NAME}:${TAG}"
    echo "docker tag ${NEW_REPO}${IMAGE_NAME}:${TAG} ${ORIGINAL_REPO}${IMAGE_NAME}:${TAG}"
    echo "docker rmi ${NEW_REPO}${IMAGE_NAME}:${TAG}"
fi
if [[ "$IMPORT_CONTAINERD_FLAG" == "--import-containerd" ]]; then
    echo "# 请确保镜像已配置为公开或正确配置了拉取密钥"
    echo "ctr i pull ${NEW_REPO}${IMAGE_NAME}:${TAG}"
    echo "ctr i tag ${NEW_REPO}${IMAGE_NAME}:${TAG} ${ORIGINAL_REPO}${IMAGE_NAME}:${TAG}"
    echo "ctr i del ${NEW_REPO}${IMAGE_NAME}:${TAG}"
fi