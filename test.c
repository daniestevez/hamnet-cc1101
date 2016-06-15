#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <prussdrv.h>
#include <pruss_intc_mapping.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <linux/if.h>
#include <linux/if_tun.h>
#include <arpa/inet.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <pthread.h>
#include <unistd.h>

#include "crc32.h"

#define PRU_NUM	0

#define TX0 0x0000
#define TX1 0x0800
#define RX0 0x1000
#define RX1 0x1800

volatile uint16_t *rx_len[2];
volatile uint8_t *rx_data[2];

int tap0_fd;

void *receive_thread (void *arg) {
  uint8_t buffer[1600];
  uint16_t len;
  int i;
  crc_t crc;

  while (1) {
    prussdrv_pru_wait_event(PRU_EVTOUT_1);

    for (i = 0; i < 2; i++) {
      if ((len = ntohs(*rx_len[i]))) {
	memcpy(buffer, (void *) rx_data[i], len - 2); // 2 for length
	*rx_len[i] = 0;
	crc = crc_init();
	crc = crc_update(crc, (void *) buffer, len - 2 - 4); // 2 for length, 4 for crc32
	crc = crc_finalize(crc);
	if (crc == ntohl(*(uint32_t *) (buffer + len - 2 - 4))) {
	  write(tap0_fd, buffer, len - 2 - 4);
	}
      }
    }

    // for some reason we have to use PRU1_ARM_INTERRUPT
    // instead of PRU0_ARM_INTERRUPT
    // see https://groups.google.com/forum/#!topic/beagleboard/e-Nqdngv9mo
    prussdrv_pru_clear_event(PRU_EVTOUT_1, PRU1_ARM_INTERRUPT);
  }
}

int main (void) {
  volatile void *pru0_dataram = NULL;
  volatile uint16_t *tx_len[2];
  volatile uint8_t *tx_data[2];

  struct ifreq ifr;
  char buffer[1600];
  int nread;
  crc_t crc;
  int i;

  pthread_t rx_thread;
  
  if(getuid()!=0){
    printf("You must run this program as root. Exiting.\n");
    exit(EXIT_FAILURE);
  }
  // Initialize structure used by prussdrv_pruintc_intc
  // PRUSS_INTC_INITDATA is found in pruss_intc_mapping.h
  tpruss_intc_initdata pruss_intc_initdata = PRUSS_INTC_INITDATA;
  
  // Allocate and initialize memory
  prussdrv_init();
  prussdrv_open(PRU_EVTOUT_0);
  prussdrv_open(PRU_EVTOUT_1);
  
  // Map PRU's interrupts
  prussdrv_pruintc_init(&pruss_intc_initdata);

  prussdrv_map_prumem(PRUSS0_PRU0_DATARAM, (void **) &pru0_dataram);
  tx_len[0] = (volatile uint16_t *) ((char *) pru0_dataram + TX0);
  tx_len[1] = (volatile uint16_t *) ((char *) pru0_dataram + TX1);
  tx_data[0] = (volatile uint8_t *) ((char *) pru0_dataram + TX0 + 2);
  tx_data[1] = (volatile uint8_t *) ((char *) pru0_dataram + TX1 + 2);
  rx_len[0] = (volatile uint16_t *) ((char *) pru0_dataram + RX0);
  rx_len[1] = (volatile uint16_t *) ((char *) pru0_dataram + RX1);
  rx_data[0] = (volatile uint8_t *) ((char *) pru0_dataram + RX0 + 2);
  rx_data[1] = (volatile uint8_t *) ((char *) pru0_dataram + RX1 + 2);
  
  
  memset((void *) pru0_dataram, 0, 0x2000);
  
  // Load and execute the PRU program on the PRU
  prussdrv_exec_program(PRU_NUM, "./test.bin");

  if ((tap0_fd = open("/dev/net/tun", O_RDWR)) < 0) {
    perror("Unable to open /dev/net/tun");
    exit(1);
  }
  memset(&ifr, 0, sizeof(ifr));
  ifr.ifr_flags = IFF_TAP | IFF_NO_PI;
  if (ioctl(tap0_fd, TUNSETIFF, (void *) &ifr) < 0) {
    perror("Unable to do ioctl(..., TUNSETIF)");
    exit(1);
  }

  if(pthread_create(&rx_thread, NULL, &receive_thread, NULL)){
    perror("Failed to create thread");
  }

  while (1) {
    nread = read(tap0_fd, buffer, sizeof(buffer));
    if (nread < 0) {
      perror("Failed to read from TAP FD");
      exit(1);
    }

    // append crc32
    crc = crc_init();
    crc = crc_update(crc, (void *) buffer, nread);
    crc = crc_finalize(crc);
    *(uint32_t *) (buffer + nread) = htonl(crc);

    for (i = 0; 1; i = (i+1) % 2) {
      if (!*tx_len[i]) {
	memcpy((void *) tx_data[i], buffer, nread + 4); // 4 for crc32
	*tx_len[i] = htons(nread + 2 + 4); // 2 for length and 4 for crc32
	break;
      }
    }
  }

  // Wait for event completion from PRU,4 returns the PRU_EVTOUT_0 number
  int n = prussdrv_pru_wait_event(PRU_EVTOUT_0);
  printf("EBB PRU program completed, event number %d.\n", n);
  
  // Disable PRU and close memory mappings
  prussdrv_pru_disable(PRU_NUM);
  prussdrv_exit();
  return EXIT_SUCCESS;
}
