#!/usr/bin/bash
#******************************************************************************
#
#            Copyright (C) 2020-2021, xxx, Ltd.
#
#******************************************************************************
#    File : auto_mount_udisk.sh
#    Auth : zhangcan
#    Date : 2020/3/31/
#    Desc : 挂载硬盘
#******************************************************************************
MOUNT_PATH="/opt/mount"

# 获取硬盘信息
function get_udisk_info()
{
    local i
    local udisk_list=($(fdisk -l |grep '^Disk /dev/sd[b-z]:' |awk -F: '{print $1}' |awk '{print $2}' |xargs echo))

    for i in ${udisk_list[@]}
    do
        fdisk -l |grep ^${i}[1-9] >/tmp/sdx_units.tmp
        local units=""
        while read line
        do
            #Windows格式
            local type=$(echo "${line}" |grep 'NTFS\|exFAT' |wc -l)
            if [[ ${type} -eq 1 ]]; then
                local unit=$(echo "${line}" |awk '{print $1}')
                UNITS_INFO_DICT[${unit}]='windows'
                if [[ -z "${units}" ]]; then
                    units="${unit}"
                else
                    units="${units} ${unit}"
                fi
            fi
            #Linux格式
            local type=$(echo "${line}" |grep 'Linux' |wc -l)
            if [[ ${type} -eq 1 ]]; then
                local unit=$(echo "${line}" |awk '{print $1}')
                UNITS_INFO_DICT[${unit}]='linux'
                if [[ -z "${units}" ]]; then
                    units="${unit}"
                else
                    units="${units} ${unit}"
                fi
            fi
        done </tmp/sdx_units.tmp

        # 保存硬盘信息
        if [[ -n "${units}" ]]; then
            local units_list=$(echo "${units}")
            UDISK_INFO_DICT[${i}]=${units_list[@]}
        fi
    done
}

# 获取挂载信息
function get_mount_info()
{
    local i
    local udisk_list=($(ls ${MOUNT_PATH} |xargs echo))

    for i in ${udisk_list[@]}
    do
        local path="${MOUNT_PATH}/${i}"
        local units_list=($(ls ${path} |xargs echo))
        if [[ ${#units_list[@]} -gt 0 ]]; then
            MOUNT_INFO_DICT[${i}]=${units_list[@]}
        else
            rm -rf ${path}
        fi
    done
}

# 判断硬盘是否存在
function is_exist_udisk()
{
    local v1="/dev/$1"
    local v2=$2
    local i

    for i in ${UDISK_INFO_DICT[${v1}][@]}
    do
        if [[ "${i}" == "${v2}" ]]; then
            return 1
        fi
    done

    return 0
}

# 检查并挂载硬盘
function check_mount_udisk()
{
    local i
    local j

    for i in ${!MOUNT_INFO_DICT[@]}
    do
        local units=""
        for j in ${MOUNT_INFO_DICT[$i][@]}
        do
            local path="${MOUNT_PATH}/${i}/${j}"
            local result=($(df -h ${path} |tail -n 1 |awk '{print $1,$NF}'))

            # 判断目录已挂载
            is_exist_udisk ${i} ${result[0]}
            if [[ $? -eq 0 ]] || [[ "${path}" != "${result[1]}" ]]; then
                umount ${path} >/dev/null 2>&1
                rm -rf ${path}
            else
                if [[ -z "${units}" ]]; then
                    units="/dev/${j}"
                else
                    units="${units} /dev/${j}"
                fi
            fi
        done

        # 删除空文件夹
        local path="${MOUNT_PATH}/${i}"
        if [[ -z "${units}" ]]; then
            rm -rf ${path}
        else
            local units_list=$(echo "${units}")
            EXIST_INFO_DICT[${i}]=${units_list[@]}
        fi
    done
}

# 判断硬盘是否已挂载
function is_mount_udisk()
{
    local v1="/dev/$1"
    local v2=$2
    local result=${EXIST_INFO_DICT[${v1}]}
    local i

    for i in ${result[@]}
    do
        if [[ "${i}" == "${v2}" ]]; then
            return 1
        fi
    done

    return 0
}

# 自动挂载硬盘
function auto_mount_udisk()
{
    local i
    local j

    for i in ${!UDISK_INFO_DICT[@]}
    do
        for j in ${UDISK_INFO_DICT[${i}][@]}
        do
            is_mount_udisk ${i} ${j}
            if [[ $? -eq 0 ]]; then
                local v1=$(echo ${i:5})
                local v2=$(echo ${j:5})
                local path="${MOUNT_PATH}/${v1}/${v2}"
                local mt=${UNITS_INFO_DICT[${j}][0]}
                if [[ "${mt}" == "windows" ]]; then
                    mkdir -p ${path}
                    ntfs-3g ${j} ${path} >/dev/null 2>&1
                fi
                if [[ "${mt}" == "linux" ]]; then
                    mkdir -p ${path}
                    mount ${j} ${path} >/dev/null 2>&1
                fi
            fi
        done
    done
}

# 主函数
function main()
{
    if [[ ! -d ${MOUNT_PATH} ]]; then
        mkdir -p ${MOUNT_PATH}
    fi

    # 定义保存临时数据字典
    declare -A MOUNT_INFO_DICT  #挂载信息字典，如：{'sdb':('sdb2', 'sdb3')}
    declare -A UDISK_INFO_DICT  #硬盘信息字典，如：{'/dev/sdb':('/dev/sdb2', '/dev/sdb3')}
    declare -A UNITS_INFO_DICT  #扇区信息字典，如：{'/dev/sdb2':'windows', '/dev/sdb3':'linux'}
    declare -A EXIST_INFO_DICT  #已挂载信息字典，如：{'sdb':('/dev/sdb2')}

    # 硬盘挂载
    get_udisk_info
    get_mount_info
    check_mount_udisk
    auto_mount_udisk
}

# 每秒检查一次
num=0
while true
do
    main
    sleep 1
    if [[ ${num} -lt 11 ]]; then
        let num++
    else
        num=0
        echo "" >/tmp/auto_mount_udisk.log
    fi
    time=$(date)
    echo "${time}" >>/tmp/auto_mount_udisk.log
done
