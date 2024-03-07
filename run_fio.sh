#!/bin/bash

if [ $# -lt 2 ]; then
    echo "usage:$0 dev output_dir [iodepth]"
    echo "example 1: Testing the whole block device. Attention: That will destory the filesystem on the target block device"
    echo "./run_fio.sh /dev/sdb fio_test"
    echo ""
    echo "example 2: Testing a file, but not destory filesystem. Suppose the target device mount on /data"
    echo "fallocate -l 1G /data/test.dat"
    echo "./run_fio.sh /data/test.dat fio_test"
    echo ""
    echo "Finally, it will genarate a certain result into the output_dir, like 'fio_test/fio_test.result"
    exit 1
fi

DEV="$1"
OUTDIR="$2"

if [ ! -d $OUTDIR ]; then
    mkdir -p $OUTDIR
fi

# default iodepth=8
IODEPTH=32
if [ $# -ge 3 ]; then
    if [ $3 -gt 0 ]; then
        IODEPTH=$3
    fi
fi
echo "IODEPTH=$IODEPTH"

RUNTIME=45
BLOCK_SIZES=(4K 8K 16K 64K 128K 256K 512K 1M 2M 4M)
JOBS=(write randwrite read randread randrw)

# if you test randrw, you need to specify the rwmixreads in this array
RWMIXREADS=(50 30)

gen_job_file()
{
    # gen_job_file job block_size [rwmixread]
    job=$1
    block_size=$2
    echo "[global]" > $job
    echo "bs=$block_size" >> $job
    echo "direct=1" >> $job
    echo "atomic=1" >> $job
    echo "time_based" >> $job
    echo "rw=$job" >> $job
    echo "ioengine=libaio" >> $job
    echo "iodepth=$IODEPTH" >> $job
    echo "runtime=$RUNTIME" >> $job
    if [ "$job" == "randwrite" -o "$job" == "randread" -o "$job" == "randrw" ]; then
        echo "randrepeat=0" >> $job
    fi
    echo "[test]" >> $job
    echo "filename=$DEV" >> $job
    if [ "$job" == "randrw" ]; then
        echo "rwmixread=$3" >> $job
    fi
}

cleanup()
{
    for job in "${JOBS[@]}"
    do
        rm -f $job
    done
    rm -f *.tmp
}

run_test()
{
    job=$1
    block_size=$2
    if [ $# -lt 3 ]; then
        output="$OUTDIR/fio.$job.$block_size.1.log"
    else
        output="$OUTDIR/fio.$job.$block_size.$3.1.log"
    fi
    fio --output="$output" $job
}

# run all the jobs
for job in "${JOBS[@]}"
do
    # generate job file for current job
    for block_size in "${BLOCK_SIZES[@]}"
    do
        if [ "$job" != "randrw" ]; then
            echo "run $job in $block_size"
            gen_job_file $job $block_size
            run_test $job $block_size
        else
            for rate in "${RWMIXREADS[@]}"
            do
                echo "run $job in $block_size, rwmixread=$rate"
                gen_job_file $job $block_size $rate
                run_test $job $block_size $rate
            done
        fi
        echo ""
        sleep 10;
    done
done

bw_array=()
iops_array=()
lat_array=()

select_bw()
{
    index=$1
    file=$2
    # unit:KB/S
    bw=`grep "bw=" "$file" | awk -F[\(\)] '{print $2}'`
    bw_array[$index]="$bw"
}

select_iops()
{
    index=$1
    file=$2
    iops=`grep "IOPS=" "$file" | awk -F[=,]+ '{print $2}'`
    iops_array[$index]="$iops"
}

select_lat()
{
    index=$1
    file=$2
    # unit:ms
    line=`grep "lat" "$file" | grep "avg" | grep -v -E "clat|slat"`
    lat=`echo $line | awk -F[=,:]+ '{if($1 == "lat (usec)") {printf("%.2f", $7/1000);} else {printf("%.2f", $7)} }'`
    lat_array[$index]="$lat"
}

# use for test randrw
bw_array_rw_read=()
iops_array_rw_read=()
lat_array_rw_read=()
bw_array_rw_write=()
iops_array_rw_write=()
lat_array_rw_write=()

select_bw_rw()
{
    index=$1
    file=$2
    # unit:KB/S
    #bw_read=`grep "bw=" "$file" | grep read | awk -F[=,B]+ '{if(match($4, /[0-9]+K$/)) {printf("%d", substr($4, 0, length($4)-1));} else {printf("%d", int($4)/1024)}}'`
    bw_read=`grep "bw=" "$file" | grep -i read | awk -F[\(\)] '{print $2}'`
    #bw_write=`grep "bw=" "$file" | grep write | awk -F[=,B]+ '{if(match($4, /[0-9]+K$/)) {printf("%d", substr($4, 0, length($4)-1));} else {printf("%d", int($4)/1024)}}'`
    bw_write=`grep "bw=" "$file" | grep -i write | awk -F[\(\)] '{print $2}'`
    bw_array_rw_read[$index]="$bw_read"
    bw_array_rw_write[$index]="$bw_write"
}

select_iops_rw()
{
    index=$1
    file=$2
    iops_read=`grep "IOPS=" "$file" | grep read | awk -F[=,]+ '{print $2}'`
    iops_write=`grep "IOPS=" "$file" | grep write | awk -F[=,]+ '{print $2}'`
    iops_array_rw_read[$index]="$iops_read"
    iops_array_rw_write[$index]="$iops_write"
}

select_lat_rw()
{
    index=$1
    file=$2
    # unit:ms
    line=`grep "read" "$file" -A3 | grep "avg" | grep -v -E "clat|slat"`
    lat_read=`echo $line | awk -F[=,:]+ '{if($1 == "lat (usec)") {printf("%.2f", $7/1000);} else {printf("%.2f", $7)} }'`
    line=`grep "write" "$file" -A3 | grep "avg" | grep -v -E "clat|slat"`
    lat_write=`echo $line | awk -F[=,:]+ '{if($1 == "lat (usec)") {printf("%.2f", $7/1000);} else {printf("%.2f", $7)} }'`

    lat_array_rw_read[$index]="$lat_read"
    lat_array_rw_write[$index]="$lat_write"
}

# generate the test result table
output_file="$OUTDIR/$OUTDIR.result"
echo > "$output_file"
for job in "${JOBS[@]}"
do

    if [ "$job" != "randrw" ]; then

        echo "[$job] ${BLOCK_SIZES[@]}" >> "$output_file"
        for (( i = 0; i < ${#BLOCK_SIZES[@]}; ++i ))
        do
            block_size=${BLOCK_SIZES[$i]}

            file="$OUTDIR/fio.$job.$block_size.1.log"
            echo $file
            select_bw $i $file
            select_iops $i $file
            select_lat $i $file
        done

        echo "[bw] ${bw_array[@]}" >> $output_file
        echo "[lat] ${lat_array[@]}" >> $output_file
        echo "[iops] ${iops_array[@]}" >> $output_file
        echo >> $output_file

        # clear array
        bw_array=()
        iops_array=()
        lat_array=()
    else
        for rate in "${RWMIXREADS[@]}"
        do
            echo "[$job"_"$rate] ${BLOCK_SIZES[@]}" >> "$output_file"
            for (( i = 0; i < ${#BLOCK_SIZES[@]}; ++i ))
            do
                block_size=${BLOCK_SIZES[$i]}

                file="$OUTDIR/fio.$job.$block_size.$rate.1.log"
                echo $file
                select_bw_rw $i $file
                select_iops_rw $i $file
                select_lat_rw $i $file
            done

            echo "[bw_read] ${bw_array_rw_read[@]}" >> $output_file
            echo "[lat_read] ${lat_array_rw_read[@]}" >> $output_file
            echo "[iops_read] ${iops_array_rw_read[@]}" >> $output_file
            echo "[bw_write] ${bw_array_rw_write[@]}" >> $output_file
            echo "[lat_write] ${lat_array_rw_write[@]}" >> $output_file
            echo "[iops_write] ${iops_array_rw_write[@]}" >> $output_file
            echo >> $output_file

            # clear array
            bw_array_rw_read=()
            iops_array_rw_read=()
            lat_array_rw_read=()
            bw_array_rw_write=()
            iops_array_rw_write=()
            lat_array_rw_write=()

        done

    fi
done

cleanup
