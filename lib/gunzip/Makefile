all:
	mkdir -p gen bin
	node tools/gencrctable.js > gen/crctable.asm
	java -jar tools/glass.jar -I gen -I lib/neonlib/src src/COM.asm bin/gunzip.com gen/gunzip.sym

dist: all
	rm -f bin/gunzip.zip
	zip -j bin/gunzip.zip bin/gunzip.com README.md CHANGES.md LICENSE

run: all
	openmsx -machine Panasonic_FS-A1GT -ext ide -script openmsx.tcl

run2: all
	openmsx -machine Philips_NMS_8245 -ext ide -script openmsx.tcl
