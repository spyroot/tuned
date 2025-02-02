NAME = tuned
# set to devel for nightly GIT snapshot
BUILD = release
# which config to use in mock-build target
MOCK_CONFIG = rhel-7-x86_64
# scratch-build for triggering Jenkins
SCRATCH_BUILD_TARGET = rhel-7.5-candidate
VERSION = $(shell awk '/^Version:/ {print $$2}' tuned.spec)
PRERELEASENUM = $(shell awk '/^\s*%global prereleasenum/ {print $$3}' tuned.spec)
ifneq ($(strip $(PRERELEASENUM)),)
	PRERELEASE = -rc.$(PRERELEASENUM)
endif
GIT_DATE = $(shell date +'%Y%m%d')
ifeq ($(BUILD), release)
	RPM_ARGS += --without snapshot
	MOCK_ARGS += --without=snapshot
	RPM_VERSION = $(NAME)-$(VERSION)-1
else
	RPM_ARGS += --with snapshot
	MOCK_ARGS += --with=snapshot
	GIT_SHORT_COMMIT = $(shell git rev-parse --short=8 --verify HEAD)
	GIT_SUFFIX = $(GIT_DATE)git$(GIT_SHORT_COMMIT)
	GIT_PSUFFIX = .$(GIT_SUFFIX)
	RPM_VERSION = $(NAME)-$(VERSION)-1$(GIT_PSUFFIX)
endif
UNITDIR_FALLBACK = /usr/lib/systemd/system
UNITDIR_DETECT = $(shell pkg-config systemd --variable systemdsystemunitdir || rpm --eval '%{_unitdir}' 2>/dev/null || echo $(UNITDIR_FALLBACK))
UNITDIR = $(UNITDIR_DETECT:%{_unitdir}=$(UNITDIR_FALLBACK))
TMPFILESDIR_FALLBACK = /usr/lib/tmpfiles.d
TMPFILESDIR_DETECT = $(shell pkg-config systemd --variable tmpfilesdir || rpm --eval '%{_tmpfilesdir}' 2>/dev/null || echo $(TMPFILESDIR_FALLBACK))
TMPFILESDIR = $(TMPFILESDIR_DETECT:%{_tmpfilesdir}=$(TMPFILESDIR_FALLBACK))
VERSIONED_NAME = $(NAME)-$(VERSION)$(PRERELEASE)$(GIT_PSUFFIX)

export SYSCONFDIR = /etc
export DATADIR = /usr/share
export DOCDIR = $(DATADIR)/doc/$(NAME)
PYTHON = /usr/bin/python3
PYLINT = pylint-3
ifeq ($(PYTHON),python2)
PYLINT = pylint-2
endif
SHEBANG_REWRITE_REGEX= '1s|^\#!/usr/bin/\<python3\>|\#!$(PYTHON)|'
PYTHON_SITELIB = $(shell $(PYTHON) -c 'from distutils.sysconfig import get_python_lib; print(get_python_lib());')
ifeq ($(PYTHON_SITELIB),)
$(error Failed to determine python library directory)
endif
KERNELINSTALLHOOKDIR = /usr/lib/kernel/install.d
TUNED_PROFILESDIR = /usr/lib/tuned
TUNED_RECOMMEND_DIR = $(TUNED_PROFILESDIR)/recommend.d
TUNED_USER_RECOMMEND_DIR = $(SYSCONFDIR)/tuned/recommend.d
BASH_COMPLETIONS = $(DATADIR)/bash-completion/completions

copy_executable = install -Dm 0755 $(1) $(2)
rewrite_shebang = sed -i -r -e $(SHEBANG_REWRITE_REGEX) $(1)
restore_timestamp = touch -r $(1) $(2)
install_python_script = $(call copy_executable,$(1),$(2)) \
	&& $(call rewrite_shebang,$(2)) && $(call restore_timestamp,$(1),$(2));

release-dir:
	mkdir -p $(VERSIONED_NAME)

release-cp: release-dir
	cp -a AUTHORS COPYING INSTALL README $(VERSIONED_NAME)

	cp -a tuned.py tuned.spec tuned.service tuned.tmpfiles Makefile tuned-adm.py \
		tuned-adm.bash dbus.conf recommend.conf tuned-main.conf 00_tuned \
		92-tuned.install bootcmdline modules.conf com.redhat.tuned.policy \
		tuned-gui.py tuned-gui.glade \
		tuned-gui.desktop $(VERSIONED_NAME)
	cp -a doc experiments libexec man profiles systemtap tuned contrib icons \
		tests $(VERSIONED_NAME)

archive: clean release-cp
	tar czf $(VERSIONED_NAME).tar.gz $(VERSIONED_NAME)

rpm-build-dir:
	mkdir rpm-build-dir

srpm: archive rpm-build-dir
	rpmbuild --define "_sourcedir `pwd`/rpm-build-dir" --define "_srcrpmdir `pwd`/rpm-build-dir" \
		--define "_specdir `pwd`/rpm-build-dir" --nodeps $(RPM_ARGS) -ts $(VERSIONED_NAME).tar.gz

rpm: archive rpm-build-dir
	rpmbuild --define "_sourcedir `pwd`/rpm-build-dir" --define "_srcrpmdir `pwd`/rpm-build-dir" \
		--define "_specdir `pwd`/rpm-build-dir" --nodeps $(RPM_ARGS) -tb $(VERSIONED_NAME).tar.gz

clean-mock-result-dir:
	rm -f mock-result-dir/*

mock-result-dir:
	mkdir mock-result-dir

# delete RPM files older than cca. one week if total space occupied is more than 5 MB
tidy-mock-result-dir: mock-result-dir
	if [ `du -bs mock-result-dir | tail -n 1 | cut -f1` -gt 5000000 ]; then \
		rm -f `find mock-result-dir -name '*.rpm' -mtime +7`; \
	fi

mock-build: srpm
	mock -r $(MOCK_CONFIG) $(MOCK_ARGS) --resultdir=`pwd`/mock-result-dir `ls rpm-build-dir/*$(RPM_VERSION).*.src.rpm | head -n 1`&& \
	rm -f mock-result-dir/*.log

mock-devel-build: srpm
	mock -r $(MOCK_CONFIG) --with=snapshot \
		--define "git_short_commit `if [ -n \"$(GIT_SHORT_COMMIT)\" ]; then echo $(GIT_SHORT_COMMIT); else git rev-parse --short=8 --verify HEAD; fi`" \
		--resultdir=`pwd`/mock-result-dir `ls rpm-build-dir/*$(RPM_VERSION).*.src.rpm | head -n 1` && \
	rm -f mock-result-dir/*.log

createrepo: mock-devel-build
	createrepo mock-result-dir

# scratch build to triggering Jenkins
scratch-build: mock-devel-build
	brew build --scratch --nowait $(SCRATCH_BUILD_TARGET) `ls mock-result-dir/*$(GIT_DATE)git*.*.src.rpm | head -n 1`

nightly: tidy-mock-result-dir createrepo scratch-build
	rsync -ave ssh --delete --progress mock-result-dir/ jskarvad@fedorapeople.org:/home/fedora/jskarvad/public_html/tuned/devel/repo/

html:
	$(MAKE) -C doc/manual

install-html:
	$(MAKE) -C doc/manual install

clean-html:
	$(MAKE) -C doc/manual clean


install-dirs:
	mkdir -p $(DESTDIR)$(PYTHON_SITELIB)
	mkdir -p $(DESTDIR)$(TUNED_PROFILESDIR)
	mkdir -p $(DESTDIR)/var/lib/tuned
	mkdir -p $(DESTDIR)/var/log/tuned
	mkdir -p $(DESTDIR)/run/tuned
	mkdir -p $(DESTDIR)$(DOCDIR)
	mkdir -p $(DESTDIR)$(SYSCONFDIR)
	mkdir -p $(DESTDIR)$(TUNED_RECOMMEND_DIR)
	mkdir -p $(DESTDIR)$(TUNED_USER_RECOMMEND_DIR)

install: install-dirs
	# library
	cp -a tuned $(DESTDIR)$(PYTHON_SITELIB)

	# binaries
	$(call install_python_script,tuned.py,$(DESTDIR)/usr/sbin/tuned)
	$(call install_python_script,tuned-adm.py,$(DESTDIR)/usr/sbin/tuned-adm)
	$(call install_python_script,tuned-gui.py,$(DESTDIR)/usr/sbin/tuned-gui)

	$(foreach file, diskdevstat netdevstat scomes, \
		install -Dpm 0755 systemtap/$(file) $(DESTDIR)/usr/sbin/$(notdir $(file));)
	$(call install_python_script, \
		systemtap/varnetload, $(DESTDIR)/usr/sbin/varnetload)

	# glade
	install -Dpm 0644 tuned-gui.glade $(DESTDIR)$(DATADIR)/tuned/ui/tuned-gui.glade

	# tools
	$(call install_python_script, \
		 experiments/powertop2tuned.py, $(DESTDIR)/usr/bin/powertop2tuned)

	# configuration files
	install -Dpm 0644 tuned-main.conf $(DESTDIR)$(SYSCONFDIR)/tuned/tuned-main.conf
	# None profile in the moment, autodetection will be used
	echo -n > $(DESTDIR)$(SYSCONFDIR)/tuned/active_profile
	echo -n > $(DESTDIR)$(SYSCONFDIR)/tuned/profile_mode
	echo -n > $(DESTDIR)$(SYSCONFDIR)/tuned/post_loaded_profile
	install -Dpm 0644 bootcmdline $(DESTDIR)$(SYSCONFDIR)/tuned/bootcmdline
	install -Dpm 0644 modules.conf $(DESTDIR)$(SYSCONFDIR)/modprobe.d/tuned.conf

	# profiles & system config
	cp -a profiles/* $(DESTDIR)$(TUNED_PROFILESDIR)/
	mv $(DESTDIR)$(TUNED_PROFILESDIR)/realtime/realtime-variables.conf \
		$(DESTDIR)$(SYSCONFDIR)/tuned/realtime-variables.conf
	mv $(DESTDIR)$(TUNED_PROFILESDIR)/realtime-virtual-guest/realtime-virtual-guest-variables.conf \
		$(DESTDIR)$(SYSCONFDIR)/tuned/realtime-virtual-guest-variables.conf
	mv $(DESTDIR)$(TUNED_PROFILESDIR)/realtime-virtual-host/realtime-virtual-host-variables.conf \
		$(DESTDIR)$(SYSCONFDIR)/tuned/realtime-virtual-host-variables.conf
	mv $(DESTDIR)$(TUNED_PROFILESDIR)/cpu-partitioning/cpu-partitioning-variables.conf \
		$(DESTDIR)$(SYSCONFDIR)/tuned/cpu-partitioning-variables.conf
	mv $(DESTDIR)$(TUNED_PROFILESDIR)/cpu-partitioning-powersave/cpu-partitioning-powersave-variables.conf \
		$(DESTDIR)$(SYSCONFDIR)/tuned/cpu-partitioning-powersave-variables.conf
	install -pm 0644 recommend.conf $(DESTDIR)$(TUNED_RECOMMEND_DIR)/50-tuned.conf

	# bash completion
	install -Dpm 0644 tuned-adm.bash $(DESTDIR)$(BASH_COMPLETIONS)/tuned-adm

	# runtime directory
	install -Dpm 0644 tuned.tmpfiles $(DESTDIR)$(TMPFILESDIR)/tuned.conf

	# systemd units
	install -Dpm 0644 tuned.service $(DESTDIR)$(UNITDIR)/tuned.service

	# dbus configuration
	install -Dpm 0644 dbus.conf $(DESTDIR)$(SYSCONFDIR)/dbus-1/system.d/com.redhat.tuned.conf

	# grub template
	install -Dpm 0755 00_tuned $(DESTDIR)$(SYSCONFDIR)/grub.d/00_tuned

	# kernel install hook
	install -Dpm 0755 92-tuned.install $(DESTDIR)$(KERNELINSTALLHOOKDIR)/92-tuned.install

	# polkit configuration
	install -Dpm 0644 com.redhat.tuned.policy $(DESTDIR)$(DATADIR)/polkit-1/actions/com.redhat.tuned.policy

	# manual pages
	$(foreach man_section, 5 7 8, $(foreach file, $(wildcard man/*.$(man_section)), \
		install -Dpm 0644 $(file) $(DESTDIR)$(DATADIR)/man/man$(man_section)/$(notdir $(file));))

	# documentation
	cp -a doc/README* $(DESTDIR)$(DOCDIR)
	cp -a doc/*.txt $(DESTDIR)$(DOCDIR)
	cp AUTHORS COPYING README $(DESTDIR)$(DOCDIR)

	# libexec scripts
	$(foreach file, $(wildcard libexec/*), \
		$(call install_python_script, \
			$(file), $(DESTDIR)/usr/libexec/tuned/$(notdir $(file))))

	# icon
	install -Dpm 0644 icons/tuned.svg $(DESTDIR)$(DATADIR)/icons/hicolor/scalable/apps/tuned.svg

	# desktop file
	install -dD $(DESTDIR)$(DATADIR)/applications

desktop:
	desktop-file-install --dir=$(DESTDIR)$(DATADIR)/applications tuned-gui.desktop

clean: clean-html
	find -name "*.pyc" | xargs rm -f
	rm -rf $(VERSIONED_NAME) rpm-build-dir

test:
	$(PYTHON) -B -m unittest discover tests/unit

lint:
	$(PYLINT) -E -f parseable tuned *.py tests/unit

.PHONY: clean archive srpm tag test lint
