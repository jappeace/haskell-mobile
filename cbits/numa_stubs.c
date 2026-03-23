// Stub implementations for libnuma functions.
// Android doesn't have libnuma, but GHC's RTS references these symbols
// when statically linked. The RTS checks numa_available() at init time
// and disables NUMA if it returns -1.
#include <stddef.h>

int numa_available(void) { return -1; }  // NUMA not available
long mbind(void *a, unsigned long b, int c, const unsigned long *d,
           unsigned long e, unsigned f) { return -1; }
void numa_bitmask_free(void *bitmask) { (void)bitmask; }
void *numa_get_mems_allowed(void) { return NULL; }
int numa_num_configured_nodes(void) { return 1; }
int numa_run_on_node(int node) { (void)node; return -1; }
