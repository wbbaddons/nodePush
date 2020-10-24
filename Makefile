WCF_FILES = $(shell find files_wcf -type f)
TS_FILES = $(shell find ts/ -type f |sed 's/ts$$/js/g;s!^ts/!files_wcf/js/!')

all: be.bastelstu.wcf.nodePush.tar

be.bastelstu.wcf.nodePush.tar: files_wcf.tar *.xml LICENSE language/*.xml
	tar cvf $@ --numeric-owner --exclude-vcs -- $^

files_wcf.tar: $(WCF_FILES) $(TS_FILES)
	tar cvf files_wcf.tar --numeric-owner --exclude-vcs --transform='s,files_wcf/,,' -- $^

%.tar:
	tar cvf $@ --numeric-owner --exclude-vcs -C $* -- $(^:$*/%=%)

files_wcf/js/%.js files_wcf/js/%.js.map: ts/%.ts tsconfig.json
	yarn run tsc

clean:
	-find files_wcf/js/ -iname '*.js' -delete
	-find files_wcf/js/ -iname '*.js.map' -delete
	-rm -f files_wcf.tar

distclean: clean
	-rm -f be.bastelstu.wcf.nodePush.tar

.PHONY: distclean clean
