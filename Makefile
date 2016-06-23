all: test test.bin BB-HAMNET-CC1101-00A0.dtbo

clean:
	rm *.bin *.o *.dtbo test

test: crc32.c test.c
	gcc -Wall -O2 crc32.c test.c -o test -lpthread -lprussdrv

%.bin : %.p
	pasm -b $<

%.dtbo : %.dts
	dtc -O dtb -o $@ -b 0 -@ $<	
