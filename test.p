.origin 0                        // start of program in PRU memory
.entrypoint START                // program entry point (for a debugger)

#include "cc1101.hp"

// number of loops in SPI delay loop
#define SPIDELAY 5

#define PRU0_R31_VEC_VALID 32    // allows notification of program completion
#define PRU_EVTOUT_0    3        // the event number that is sent back
#define PRU_EVTOUT_1	4	

// CC1101 pins
#define SCK r30.t2
#define MOSI r30.t1
#define MISO r31.t3
#define CS r30.t5
#define GD0 r31.t0

// maximum packet length
#define MAXLEN 0x07fe

// addresses of buffers
#define TX0 0x0000
#define TX1 0x0800
#define RX0 0x1000
#define RX1 0x1800

// when receiving a packet length which is
// longer than the maximum, we pretend that
// the length of the packet is this one:
#define SHORTPACKET 0x20

// number of elements in TX buffer
// when threshold is reached
#define TXTHRESHOLD 5
#define TXFIFOTHR 0x4e

// FIFOTHR to use when RXing the head of the packet
#define RXHEADFIFOTHR 0x40
// number of elements to receive as the head of the packet
#define RXHEAD 4

// number of elements in RX buffer
// when threshold is reached
#define RXTHRESHOLD 60
#define RXFIFOTHR 0x4e

// number of elements in FIFO
#define FIFOLEN 64	
	
// custom PKTCTRL0
#define PKTCTRL0 0x42

// values for IOCFG0
#define IOCFG0_RX 0x00
#define IOCFG0_CCA 0x09
#define IOCFG0_TX 0x02
#define IOCFG0_PACKET 0x06	
	
.macro delay40us
   MOV r0, 4000
LOOP:
   SUB r0, r0, 1
   QBNE LOOP, r0, 0
.endm

.macro delay100us
   MOV r0, 10000
LOOP:
   SUB r0, r0, 1
   QBNE LOOP, r0, 0
.endm

.macro delay1ms
   MOV r0, 100000
LOOP:
   SUB r0, r0, 1
   QBNE LOOP, r0, 0
.endm     

// delays for SPI
.macro delay
   MOV r0, SPIDELAY
LOOP:
   SUB r0, r0, 1
   QBNE LOOP, r0, 0
.endm

.macro longdelay
   MOV r0, 10*SPIDELAY
LOOP:
   SUB r0, r0, 1
   QBNE LOOP, r0, 0
.endm


/* clobbers r1 r2 r3 */
.macro writeReg
.mparam reg, val
   MOV r1.b3, reg
   MOV r1.b2, val
   MOV r3, 16
   JAL r29.w0, SHORTSPI
.endm

/* clobbers r3 */
.macro writeByte
   MOV r3, 8
LOOP:
   JAL r29.w2, SPICYCLE
   SUB r3, r3, 1
   QBNE LOOP, r3, 0
.endm

/* clobbers r1 r2 r3 */
.macro readReg
.mparam out, reg, regtype
   MOV r1.b3, reg | regtype
   MOV r1.b2, 0
   MOV r3, 16
   JAL r29.w0, SHORTSPI
   MOV out, r2.b0
.endm

/* clobbers r1 r2 r3 */
.macro cmdStrobe
.mparam strobe
   MOV r1.b3, strobe
   writeByte
.endm
   
START:
	// r8 is current RX buffer. r9 is standby RX buffer
	MOV r8, RX0
	MOV r9, RX1
	
	// reset CC1101
	SET CS
	SET SCK
	CLR MOSI
	delay40us
	CLR CS
	delay40us
	SET CS
	delay40us
	CLR SCK
	CLR CS
	WBC MISO
	cmdStrobe CC1101_SRES
	delay
	WBC MISO
	SET CS
	longdelay

	// set default regs
	CLR CS

	// 100k GFSK 47.6kHz dev
	writeReg CC1101_FSCTRL1, 0x0C
	writeReg CC1101_FREQ2, 0x10
	writeReg CC1101_FREQ1, 0xB1
	writeReg CC1101_FREQ0, 0x3B
	writeReg CC1101_MDMCFG4, 0x5B
	writeReg CC1101_MDMCFG3, 0xF8
	writeReg CC1101_MDMCFG2, 0xf3 // MSK
	writeReg CC1101_DEVIATN, 0x07 
	writeReg CC1101_FOCCFG, 0x1D
	writeReg CC1101_BSCFG, 0x1C
	writeReg CC1101_AGCCTRL2, 0xC7
	writeReg CC1101_AGCCTRL1, 0x00
	writeReg CC1101_AGCCTRL0, 0xB2
	writeReg CC1101_WORCTRL, 0xFB
	writeReg CC1101_FREND1, 0xB6
	writeReg CC1101_FSCAL3, 0xEA
	writeReg CC1101_FSCAL2, 0x2A
	writeReg CC1101_FSCAL1, 0x00
	writeReg CC1101_FSCAL0, 0x1F
	writeReg CC1101_TEST0, 0x09

	// custom MCSM
	writeReg CC1101_MCSM1, 0x2f
	writeReg CC1101_MCSM0, 0x18
	// custom FIFOTHR
	writeReg CC1101_FIFOTHR, RXHEADFIFOTHR
	// custom PKTCTRL0
	writeReg CC1101_PKTCTRL0, PKTCTRL0
	// custom PKTCTRL1
   
	delay
	SET CS

	longdelay
	CLR CS
	// write PA table
	MOV r1, 0
	MOV r1.b3, CC1101_PATABLE | WRITE_BURST
	MOV r1.b2, 0xc0
	MOV r3, 8*9
	JAL r29.w0, SHORTSPI
	delay
	SET CS
	longdelay

   // calibrate PLL
   //CLR CS
   // set PLL lock status on GD0
   //writeReg CC1101_IOCFG0, 0x0A
   //cmdStrobe CC1101_SCAL
   //delay
   //SET CS
   //longdelay
   // wait for PLL lock
   //WBS GD0
   
	// go into RX mode
	CLR CS
	// set RX FIFO threshold on GD0
	writeReg CC1101_IOCFG0, IOCFG0_PACKET
	cmdStrobe CC1101_SRX
	delay
	SET CS
	longdelay

/*************************************************************
	RX CODE
*************************************************************/
DORX:
	// check if we are receiving something
	QBBC ENDRX, GD0
/*	// set RXFIFO to receive the head
	CLR CS
	writeReg CC1101_FIFOTHR, RXHEADFIFOTHR
	writeReg CC1101_IOCFG0, IOCFG0_RX
	SET CS
	longdelay
	// wait to receive the head
	WBS GD0
	*/
	// clear pktlen
	MOV r0.w0, 0
	SBBO r0.w0, r8, 0, 2
	// read pktlen into r6.w0 (first we read into *r8 + 2)
	// this could be improved to read directly into the register
	CLR CS
	MOV r4.b0, CC1101_RXFIFO
	MOV r4.b1, 2
	ADD r5, r8, 2
	JAL r29.w0, READBURST
	delay
	SET CS
	longdelay
	ADD r5, r8, 2
	LBBO r6.w0, r5, 0, 2
	MOV r11.w0, r6.w0
	// swap r6.w0 to little endian order
	MOV r0.b0, r6.b1
	MOV r6.b1, r6.b0
	MOV r6.b0, r0.b0
	MOV r6.w2, 2
	// pktlen is r6.w0
	// written is r6.w2
	// r11.w0 holds the pktlen as RX'd (big endian)
	// "fail" if pktlen is not within bounds
	MOV r0.w0, MAXLEN
	QBGE LENGTHOK, r6.w0, r0.w0
	MOV r6.w0, SHORTPACKET
	MOV r11.w0, 0
LENGTHOK:
	// write PKTLEN register and set RXFIFOTHR to normal RX value
	CLR CS
	writeReg CC1101_PKTLEN, r6.b0
	writeReg CC1101_FIFOTHR, RXFIFOTHR
	delay
	SET CS
	longdelay
RXLOOP:
	// check if less than 256 bytes remain
	SUB r0.w0, r6.w0, r6.w2
	QBNE MOREREMAINS, r0.b1, 0
	// less than 256 bytes remain
	// set fixed packet length
	// TODO: do this only once
	CLR CS
	writeReg CC1101_PKTCTRL0, PKTCTRL0 & ~0x03
	delay
	SET CS
	longdelay
MOREREMAINS:
	// r7.w0 is bytes we still need to read
	SUB r7.w0, r6.w0, r6.w2
	// if less than a full RXFIFO buffer remains, exit this loop
	QBGE WAITENDRX, r7.w0, FIFOLEN-2 // -2 for 2 status bytes
	// wait for RXFIFO above threshold
	WBS GD0
	// read RXTHRESHOLD-1 bytes (-1 for silicon errata)
	CLR CS
	MOV r4.b0, CC1101_RXFIFO
	MOV r4.b1, RXTHRESHOLD-1
	MOV r5, r8
	ADD r5, r5, r6.w2
	ADD r6.w2, r6.w2, r4.b1
	JAL r29.w0, READBURST
	delay
	SET CS
	longdelay
	JMP RXLOOP
WAITENDRX:
	// wait for end of packet
	CLR CS
	writeReg CC1101_IOCFG0, IOCFG0_PACKET
	delay
	SET CS
	longdelay
	WBC GD0
	// r7.w0 is bytes we need to read
	SUB r7.w0, r6.w0, r6.w2
	// take into account 2 status bytes at the end of the packet
	ADD r7.w0, r7.w0, 2
	// read remaining bytes
	CLR CS
	MOV r4.b0, CC1101_RXFIFO
	MOV r4.b1, r7.b0
	MOV r5, r8
	ADD r5, r5, r6.w2
	JAL r29.w0, READBURST
	delay
	SET CS
	longdelay
	// set FIFOTHR, packet mode (infinite) and GD0 to its normal state
	CLR CS
	writeReg CC1101_PKTCTRL0, PKTCTRL0
	writeReg CC1101_IOCFG0, IOCFG0_RX
	writeReg CC1101_FIFOTHR, RXHEADFIFOTHR
	delay
	SET CS
	longdelay
	// finally write pktlen
	SBBO r11.w0, r8, 0, 2
	// notify C program
	MOV r31.b0, PRU0_R31_VEC_VALID | PRU_EVTOUT_1
	// swap RX buffer
	MOV r0, r8
	MOV r8, r9
	MOV r9, r0
ENDRX:

/****************************************************************
	TX CODE
*****************************************************************/
DOTX:   
	// check if something to send
	MOV r10, TX0
	LBBO r6.w0, r10, 0, 2
	QBNE PROCESSTX, r6.w0, 0
	MOV r10, TX1
	LBBO r6.w0, r10, 0, 2
	QBEQ ENDTX, r6.w0, 0
PROCESSTX:
	// r10 is address of buffer with data to TX
	CLR CS
	cmdStrobe CC1101_SFSTXON
	delay
	SET CS
	longdelay
	// check if FSTXON has been entered
	// (it is not entered if CCA is false)
	CLR CS
	readReg r4.b0, CC1101_MARCSTATE, CC1101_STATUS_REGISTER
	delay
	SET CS
	longdelay
	AND r4.b0, r4.b0, 0x1f
	// do not tx if radio still in RX
	QBEQ ENDTX, r4.b0, 0x0d
	// swap r6.w0 to little endian order
	MOV r0.b0, r6.b1
	MOV r6.b1, r6.b0
	MOV r6.b0, r0.b0
	// pktlen is r6.w0
	// check packet length
	MOV r0.w0, MAXLEN
	QBLT IGNOREPACKETTX, r6.w0, r0.w0
	// write PKTLEN register
	CLR CS
	writeReg CC1101_PKTLEN, r6.b0
	MIN r6.w2, r6.w0, CC1101_BUFFER_LEN
	// written is r6.w2
	// write first block
	MOV r4.b1, r6.b2
	MOV r4.b0, CC1101_TXFIFO
	MOV r5, r10
	JAL r29.w0, WRITEBURST
	delay
	SET CS
	longdelay
	/*
	// set GD0 to output CCA
	CLR CS
	writeReg CC1101_IOCFG0, IOCFG0_CCA
	delay
	SET CS
	longdelay
	// wait for CCA
	WBS GD0
	*/
	// set GD0 to output TX FIFO threshold
	CLR CS
	writeReg CC1101_FIFOTHR, TXFIFOTHR
	writeReg CC1101_IOCFG0, IOCFG0_TX
	// go into TX
	cmdStrobe CC1101_STX
	delay
	SET CS
	longdelay
	// TODO: check that TX mode has been entered
TXLOOP:
	// check if we have written all
	QBEQ TXLOOPEND, r6.w0, r6.w2
	// r7.w0 is bytes that remain to be written
	SUB r7.w0, r6.w0, r6.w2
	// wait for threshold below level
	WBC GD0
	CLR CS
	// at most TXTHRESHOLD - 1 bytes are filled in TX FIFO
	MIN r4.b1, r7.w0, CC1101_BUFFER_LEN - TXTHRESHOLD + 1
	MOV r4.b0, CC1101_TXFIFO
	MOV r5, r10
	ADD r5, r5, r6.w2
	ADD r6.w2, r6.w2, r4.b1
	JAL r29.w0, WRITEBURST
	delay
	SET CS
	longdelay
	JMP TXLOOP
TXLOOPEND:
	CLR CS
	// set fixed packet length
	writeReg CC1101_PKTCTRL0, PKTCTRL0 & ~0x03
	// wait for end of packet
	writeReg CC1101_IOCFG0, IOCFG0_PACKET
	delay
	SET CS
	longdelay
	WBS GD0
	WBC GD0
	CLR CS
	// set infinite packet length
	writeReg CC1101_PKTCTRL0, PKTCTRL0
	writeReg CC1101_FIFOTHR, RXHEADFIFOTHR
	writeReg CC1101_IOCFG0, IOCFG0_RX
	delay
	SET CS
	longdelay
IGNOREPACKETTX:
	// clear packet-in-use indicator
	MOV r0.w0, 0
	SBBO r0.w0, r10, 0, 2
ENDTX:
	JMP DORX

END:                             // notify the calling app that finished
   MOV R31.b0, PRU0_R31_VEC_VALID | PRU_EVTOUT_0
   HALT                     // halt the pru program

/* perform a writeBurstReg
r4.b0 -> reg
r4.b1 -> len
r5 -> address
clobbers: r0 r1 r2 r3
assumes jal on r29.w0
*/
WRITEBURST:
   OR r1.b3, r4.b0, WRITE_BURST
   writeByte   
 WRITEBURSTLOOP:
   LBBO r1.b3, r5, 0, 1
   MOV r3, 8
   writeByte
   ADD r5, r5, 1
   SUB r4.b1, r4.b1, 1
   QBNE WRITEBURSTLOOP, r4.b1, 0
	JMP r29.w0

/* perform a readBurstReg
r4.b0 -> reg
r4.b1 -> len
r5 -> address
clobbers: r0 r1 r2 r3
assumes jal on r29.w0
*/
READBURST:
	OR r1.b3, r4.b0, READ_BURST
	writeByte
	MOV r1, 0
READBURSTLOOP:
	//   LBBO r1.b3, r5, 0, 1
	MOV r3, 8
	writeByte
	SBBO r2.b0, r5, 0, 1
	ADD r5, r5, 1
	SUB r4.b1, r4.b1, 1
	QBNE READBURSTLOOP, r4.b1, 0
	JMP r29.w0

/* perform a "short SPI transaction" (max 4 bytes)
r1 -> tx
r2 -> rx
r3 -> length in bits
clobbers: r0
assumes jal on r29.w0
*/
SHORTSPI:
   CLR CS
SHORTSPILOOP:
   JAL r29.w2, SPICYCLE
   SUB r3, r3, 1
   QBNE SHORTSPILOOP, r3, 0
   JMP r29.w0
   
/* perform a SPI cycle transition
r1.t31 -> tx bit (r1 gets shifted left after tx)
r2.t0 -> rx bit (r2 gets shifted left before rx)
assumes jal on r29.w2
clobbers: r0 */
SPICYCLE:
   QBBC MOSILOW, r1.t31
   SET MOSI
   QBA SPICYCLECONT
MOSILOW:
   CLR MOSI
SPICYCLECONT:
   LSL r1, r1, 1
   // delay low
   delay
   SET SCK
   LSL r2, r2, 1
   QBBC MISOLOW, MISO
   OR r2, r2, 0x1
MISOLOW:
   // delay high
   delay
   CLR SCK
   JMP r29.w2

   
