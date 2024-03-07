usage:./run_fio.sh dev output_dir [iodepth]
example 1: Testing the whole block device. Attention: That will destroy the filesystem on the target block device
./run_fio.sh /dev/sdb fio_test

example 2: Testing a file, but not destory filesystem. Suppose the target device mount on /data
fallocate -l 1G /data/test.dat
./run_fio.sh /data/test.dat fio_test

Finally, it will genarate a certain result into the output_dir, like 'fio_test/fio_test.result'
