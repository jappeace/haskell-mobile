#ifndef HASKELL_MOBILE_H
#define HASKELL_MOBILE_H

/* GHC RTS initialization (call before any Haskell function) */
void hs_init(int *argc, char **argv[]);

/* Haskell FFI exports */
void haskellInit(void);
char *haskellGreet(const char *name);

#endif /* HASKELL_MOBILE_H */
