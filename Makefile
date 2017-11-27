WCF_FILES = $(shell find files_wcf -type f)

all: be.bastelstu.wcf.nodePush.tar

be.bastelstu.wcf.nodePush.tar: files_wcf.tar *.xml LICENSE language/*.xml
	tar cvf be.bastelstu.wcf.nodePush.tar --numeric-owner --exclude-vcs -- $^

files_wcf.tar: $(WCF_FILES)
	tar cvf files_wcf.tar --numeric-owner --exclude-vcs --transform='s,files_wcf/,,' -- $^

clean:
	-rm -f files_wcf.tar

distclean: clean
	-rm -f be.bastelstu.wcf.nodePush.tar

.PHONY: distclean clean
