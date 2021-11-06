#!/1/out/protobusybox/bin/ash
set -uex

export PATH=/1/out/tinycc/wrappers:/1/out/protobusybox/bin


echo 'Hi from stage 2!' | sed s/Hi/Hello/
mkdir -p /2/out /2/tmp
mkdir -p /dev; :>/dev/null


echo 'Preparing to build make twice over'
rm -rf /2/tmp/protognumake /2/tmp/gnumake

echo 'Building protognumake'
cp -ra /2/src/gnumake /2/tmp/protognumake
cd /2/tmp/protognumake
# FIXME this is part of stdlib, no idea how it's supposed to not clash
rm src/getopt.h
for f in src/getopt.c src/getopt1.c; do :> $f; done
for f in lib/fnmatch.c lib/glob.c lib/xmalloc.c lib/error.c; do :> $f; done
sed -i 's|/bin/sh|/1/out/protobusybox/bin/ash|' src/job.c
ash ./configure \
	--build x86_64-linux \
	--disable-posix-spawn \
	--disable-dependency-tracking \
	CONFIG_SHELL='/1/out/protobusybox/bin/ash' \
	SHELL='/1/out/protobusybox/bin/ash'
ash ./build.sh
./make --version

echo 'Building gnumake with protognumake'
cp -ra /2/src/gnumake /2/tmp/gnumake
cd /2/tmp/gnumake
sed -i 's|/bin/sh|/1/out/protobusybox/bin/ash|' src/job.c build-aux/install-sh
ash ./configure \
	--build x86_64-linux \
	--disable-posix-spawn \
	--disable-dependency-tracking \
	CONFIG_SHELL='/1/out/protobusybox/bin/ash' \
	SHELL='/1/out/protobusybox/bin/ash'
/2/tmp/protognumake/make
mkdir -p /2/out/gnumake/bin
cp make /2/out/gnumake/bin/gnumake


echo 'Building binutils'
rm -rf /2/tmp/binutils
cp -ra /2/src/binutils /2/tmp/
cd /2/tmp/binutils

mkdir fakes; export PATH=/2/tmp/binutils/fakes:$PATH
cp /1/out/protobusybox/bin/true fakes/makeinfo
sed -i 's|/bin/sh|/1/out/protobusybox/bin/ash|' \
	missing install-sh mkinstalldirs
export lt_cv_sys_max_cmd_len=32768

ash configure \
	CONFIG_SHELL=/1/out/protobusybox/bin/ash \
	SHELL=/1/out/protobusybox/bin/ash \
	CFLAGS='-D__LITTLE_ENDIAN__=1' \
	--host x86_64-linux --build x86_64-linux \
	--disable-bootstrap --disable-libquadmath \
	--prefix=/2/out/binutils/
/2/out/gnumake/bin/gnumake
/2/out/gnumake/bin/gnumake install

export PATH=/2/out/binutils/bin:$PATH


echo 'Building GNU GCC 4 (C only)'
rm -rf /2/tmp/gnugcc4
cp -ra /2/src/gnugcc4 /2/tmp/
cd /2/tmp/gnugcc4
sed -i 's|/bin/sh|/1/out/protobusybox/bin/ash|' \
	missing move-if-change mkdep mkinstalldirs symlink-tree \
	gcc/genmultilib */*.sh gcc/exec-tool.in \
	install-sh */install-sh
sed -i 's|^\(\s*\)sh |\1/1/out/protobusybox/bin/ash |' Makefile* */Makefile*
sed -i 's|/lib64/ld-linux-x86-64.so.2|/2/out/musl/lib/libc.so|' \
	gcc/config/i386/linux64.h
rm -rf /2/out/gnugcc4/sys-root; mkdir -p /2/out/gnugcc4/sys-root
ln -s /1/out/protomusl/lib /2/out/gnugcc4/sys-root/
ln -s /1/out/protomusl/include /2/out/gnugcc4/sys-root/
ash configure \
	CONFIG_SHELL='/1/out/protobusybox/bin/ash' \
	SHELL='/1/out/protobusybox/bin/ash' \
	--with-build-time-tools=/2/out/binutils/bin \
	--prefix=/2/out/gnugcc4 \
	--disable-bootstrap \
	--disable-decimal-float \
	--enable-languages=c \
	--disable-multilib \
	--disable-multiarch \
	--disable-libmudflap --disable-libsanitizer \
	--disable-libssp --disable-libmpx \
	--disable-libquadmath \
	--disable-libgomp \
	--with-sysroot=/2/out/gnugcc4/sys-root \
	--with-native-system-header-dir=/include \
	--host x86_64-linux --build x86_64-linux
/2/out/gnumake/bin/gnumake
/2/out/gnumake/bin/gnumake install

export PATH=/2/out/gnugcc4/bin:$PATH


echo 'Building musl with gcc'
rm -rf /2/tmp/musl
cp -ra /2/src/musl /2/tmp/
cd /2/tmp/musl
sed -i 's|/bin/sh|/1/out/protobusybox/bin/ash|' \
	tools/*.sh \
# Hardcode /usr/bin/env sh instead of /bin/sh for popen and system calls.
# At least one hardcode less and env is dumber than sh =(
# TODO: build and bundle an env with musl at this step?
sed -i 's|/bin/sh|/usr/bin/env|' src/stdio/popen.c src/process/system.c
sed -i 's|"sh", "-c"|"/usr/bin/env", "sh", "-c"|' \
	src/stdio/popen.c src/process/system.c
mkdir -p /2/out/musl/bin
ash ./configure --target x86_64-linux --prefix=/2/out/musl
/2/out/gnumake/bin/gnumake
/2/out/gnumake/bin/gnumake install
ln -sfn /2/out/musl/lib /2/out/gnugcc4/sys-root/lib
ln -sfn /2/out/musl/include /2/out/gnugcc4/sys-root/include

/2/out/gnugcc4/bin/gcc /1/src/hello.c -o /2/tmp/hello
/2/tmp/hello || hello_retcode=$?
[ $hello_retcode == 42 ]


echo 'Installing kernel headers'
rm -rf /2/tmp/linux
cp -ra /2/src/linux /2/tmp/
cd /2/tmp/linux
/2/out/gnumake/bin/gnumake \
	CONFIG_SHELL=/1/out/protobusybox/bin/ash CC=gcc HOSTCC=gcc ARCH=x86_64 \
	headers
mkdir -p /2/out/linux/
cp -rv usr/include /2/out/linux/
find /2/out/linux/include -name '.*' -delete
rm /2/out/linux/include/Makefile


echo 'Building a more complete busybox'
rm -rf /2/tmp/busybox
cp -ra /2/src/busybox /2/tmp/
cd /2/tmp/busybox
BUSYBOX_FLAGS='CONFIG_SHELL=/1/out/protobusybox/bin/ash'
BUSYBOX_FLAGS="$BUSYBOX_FLAGS CC=gcc HOSTCC=gcc"
BUSYBOX_FLAGS="$BUSYBOX_FLAGS CFLAGS=-I/2/out/linux/include"
echo -e '#!/1/out/protobusybox/bin/ash\nprintf 9999' > scripts/gcc-version.sh
sed -i 's|/bin/sh|/1/out/protobusybox/bin/ash|' \
	applets/busybox.mkscripts \
	applets/usage_compressed \
	applets/install.sh \
	scripts/*.sh \
	scripts/mkconfigs scripts/embedded_scripts scripts/trylink
/2/out/gnumake/bin/gnumake $BUSYBOX_FLAGS defconfig
echo CONFIG_INSTALL_NO_USR=y >> .config
/2/out/gnumake/bin/gnumake $BUSYBOX_FLAGS busybox busybox.links
sed -i 's|^/usr/s\?bin/|/bin/|' busybox.links
rm -rf /2/out/busybox; mkdir -p /2/out/busybox
/2/out/gnumake/bin/gnumake $BUSYBOX_FLAGS install \
	CONFIG_PREFIX=/2/out/busybox/


echo 'Rebuilding musl with /usr/bin/env hardcoded instead of /bin/sh (big sigh)'
rm -rf /3/tmp/musl
cp -ra /2/src/musl /3/tmp/
cd /3/tmp/musl
sed -i 's|/bin/sh|/2/out/busybox/bin/ash|' tools/*.sh
mkdir -p /3/out/musl/bin
ash ./configure --target x86_64-linux --prefix=/3/out/musl
/2/out/gnumake/bin/gnumake
/2/out/gnumake/bin/gnumake install


echo 'Cleaning up stage 2'
rm -rf /2/tmp /dev /tmp
echo '--- stage 2 cutoff point ---'
exec /3/src/stage3.sh
exit 99
