OPTIMIZATION=-O0
build:
	cabal build all -j --ghc-options $(OPTIMIZATION)

.PHONY: test
test:
	cabal test -j --ghc-options $(OPTIMIZATION)

test-emulator:
	nix-build nix/emulator.nix -o result-emulator
	./result-emulator/bin/test-lifecycle

test-simulator:
	nix-build nix/simulator.nix -o result-simulator
	./result-simulator/bin/test-lifecycle-ios

haddock:
	cabal haddock all

haddock-hackage:
	cabal new-haddock all --haddock-for-hackage --haddock-option=--hyperlinked-source
	echo "the hackage ui doesn't accept the default format, use command instead"
	cabal upload -d --publish ./dist-newstyle/*-docs.tar.gz

ghcid: clean
	ghcid \
		--test="main" \
		--command="ghci" \
		test/Test
ghcid-app: clean
	ghcid \
		--main="main" \
		--command="ghci" \
		app/Main

ghci:
	ghci app/exe

etags:
	hasktags  -e ./src

clean:
	rm -fR dist dist-*
	find . -name '*.hi' -type f -delete
	find . -name '*.o' -type f -delete
	find . -name '*.dyn_hi' -type f -delete
	find . -name '*.dyn_o' -type f -delete
	find . -name 'autogen*' -type f -delete

.PHONY: test

sdist:
	nix-build .  # ad-hoc proof it builds
	cabal sdist

run:
	cabal run exe --ghc-options $(OPTIMIZATION) -- \

brittany_:
	$(shell set -x; for i in `fd hs`; do hlint --refactor --refactor-options=-i $$i; brittany --write-mode=inplace $$i; done)

hoogle:
	hoogle server --local -p 8080
