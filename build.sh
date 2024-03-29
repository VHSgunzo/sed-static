#!/bin/bash
set -e
export MAKEFLAGS="-j$(nproc)"

# WITH_UPX=1
# NO_SYS_MUSL=1

sed_version="latest"
musl_version="latest"

platform="$(uname -s)"
platform_arch="$(uname -m)"

[ "$sed_version" == "latest" ] && \
  sed_version="$(curl -s https://ftp.gnu.org/gnu/sed/|tac|\
                       grep -om1 'sed-.*\.tar\.xz'|cut -d'>' -f2|sed 's|sed-||g;s|.tar.xz||g')"

[ "$musl_version" == "latest" ] && \
  musl_version="$(curl -s https://www.musl-libc.org/releases/|tac|grep -v 'latest'|\
                  grep -om1 'musl-.*\.tar\.gz'|cut -d'>' -f2|sed 's|musl-||g;s|.tar.gz||g')"

if [ -d build ]
    then
        echo "= removing previous build directory"
        rm -rf build
fi

if [ -d release ]
    then
        echo "= removing previous release directory"
        rm -rf release
fi

# create build and release directory
mkdir build
mkdir release
pushd build

# download tarballs
echo "= downloading sed v${sed_version}"
curl -LO https://ftp.gnu.org/gnu/sed/sed-${sed_version}.tar.gz

echo "= extracting sed"
tar -xf sed-${sed_version}.tar.gz

if [ "$platform" == "Linux" ]
    then
        echo "= setting CC to musl-gcc"
        if [[ ! -x "$(which musl-gcc 2>/dev/null)" || "$NO_SYS_MUSL" == 1 ]]
            then
                echo "= downloading musl v${musl_version}"
                curl -LO https://www.musl-libc.org/releases/musl-${musl_version}.tar.gz

                echo "= extracting musl"
                tar -xf musl-${musl_version}.tar.gz

                echo "= building musl"
                working_dir="$(pwd)"

                install_dir="${working_dir}/musl-install"

                pushd musl-${musl_version}
                env CFLAGS="$CFLAGS -Os -ffunction-sections -fdata-sections" LDFLAGS='-Wl,--gc-sections' ./configure --prefix="${install_dir}"
                make install
                popd # musl-${musl-version}
                export CC="${working_dir}/musl-install/bin/musl-gcc"
            else
                export CC="$(which musl-gcc 2>/dev/null)"
        fi
        export CFLAGS="-static"
        export LDFLAGS='--static'
    else
        echo "= WARNING: your platform does not support static binaries."
        echo "= (This is mainly due to non-static libc availability.)"
fi

echo "= building sed"
pushd sed-${sed_version}
env CFLAGS="$CFLAGS -g -O2 -Os -ffunction-sections -fdata-sections" LDFLAGS="$LDFLAGS -Wl,--gc-sections" ./configure
make
popd # sed-${sed_version}

popd # build

shopt -s extglob

echo "= extracting sed binary"
cp build/sed-${sed_version}/sed/sed release 2>/dev/null

echo "= striptease"
for file in release/*
  do
      strip -s -R .comment -R .gnu.version --strip-unneeded "$file" 2>/dev/null
done

if [[ "$WITH_UPX" == 1 && -x "$(which upx 2>/dev/null)" ]]
    then
        echo "= upx compressing"
        for file in release/*
          do
              upx -9 --best "$file" 2>/dev/null
        done
fi

echo "= create release tar.xz"
tar --xz -acf sed-static-v${sed_version}-${platform_arch}.tar.xz release

if [ "$NO_CLEANUP" != 1 ]
    then
        echo "= cleanup"
        rm -rf release build
fi

echo "= sed v${sed_version} done"
