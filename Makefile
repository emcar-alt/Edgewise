.PHONY: build universal run install zip test icon clean

build:
	scripts/build.sh

universal:
	ARCHS="arm64 x86_64" scripts/build.sh

run: build
	-pkill -x Edgewise
	open build/Edgewise.app

install: build
	-pkill -x Edgewise
	rm -rf /Applications/Edgewise.app
	cp -R build/Edgewise.app /Applications/
	open /Applications/Edgewise.app

zip: universal
	cd build && ditto -c -k --keepParent Edgewise.app Edgewise-$$(cat ../VERSION).zip

test:
	scripts/test.sh

icon:
	swift scripts/make-icon.swift Resources

clean:
	rm -rf build
