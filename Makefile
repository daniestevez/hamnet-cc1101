all: hamnet-cc1101 hamnet-cc1101.bin BB-HAMNET-CC1101-00A0.dtbo

clean:
	rm -f *.bin *.o *.dtbo hamnet-cc1101

hamnet-cc1101: crc32.c main.c
	gcc -Wall -O2 crc32.c main.c -o $@ -lpthread -lprussdrv

%.bin : %.p
	pasm -b $<

%.dtbo : %.dts
	dtc -O dtb -o $@ -b 0 -@ $<	
