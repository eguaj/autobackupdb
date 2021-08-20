
CONTENT_DIRS = var/backupdb

.PHONY: deb
deb: .build/DEBIAN .build/var/backupdb/backupdb.sh
	( cd .build && find $(CONTENT_DIRS) -type f -exec md5sum {} \; ) > .build/DEBIAN/md5sums
	fakeroot dpkg-deb --build .build ..

.build/DEBIAN: .build
	cp -aR DEBIAN/. .build/DEBIAN/

.build/var/backupdb/backupdb.sh: ../backupdb.sh .build/var/backupdb
	install -m 0750 $< $@
	# cp -a $< $@

.build/var/backupdb: .build/var
	mkdir -p -m 0750 $@

.build/var: .build
	mkdir -p $@

.build:
	mkdir -p $@

.PHONY: clean
clean:
	rm -Rf .build

