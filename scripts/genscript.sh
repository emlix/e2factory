#!/bin/bash

function die() {
    echo "(genscript.sh) Error: $1"
    exit 1
}

set -e
test -n "$PREFIX" || die "PREFIX not set"
test -n "$BINDIR" || die "BINDIR not set"
test -n "$LIBDIR" || die "LIBDIR not set"
test -n "$LIBEXECDIR" || die "LIBEXECDIR not set"
test -n "$LOCALSTATEDIR" || die "LOCALSTATEDIR not set"
test -n "$SYSCONFDIR" || die "SYSCONFDIR not set"
test -n "$E2DATA" || die "E2DATA not set"
test -n "$TOOLDIR" || die "TOOLDIR not set"
test -n "$LUA_VERSION" || die "LUA_VERSION not set"
test -n "$ARCH" || die "ARCH not set"
test -n "$BINARY_STORE" || die "BINARY_STORE not set"
test -n "$E2_GROUP" || die "E2_GROUP not set"
test -n "$ENV_TOOL" || die "ENV_TOOL not set"
test -n "$CHROOT_TOOL" || die "CHROOT_TOOL not set"
test -n "$TAR_TOOL" || die "TAR_TOOL not set"
test -n "$CHOWN_TOOL" || die "CHOWN_TOOL not set"
test -n "$RM_TOOL" || die "RM_TOOL not set"
test -n "$DEFAULT_LOCAL_BRANCH" || die "DEFAULT_LOCAL_BRANCH not set"
test -n "$DEFAULT_LOCAL_TAG" || die "DEFAULT_LOCAL_TAG not set"
sed -e s,"@E2_E2DATA@","$E2DATA",g \
    -e s,"@LIBDIR@","$LIBDIR",g \
    -e s,"@LIBEXECDIR@","$LIBEXECDIR",g \
    -e s,"@BINDIR@","$BINDIR",g \
    -e s,"@LOCALSTATEDIR@","$LOCALSTATEDIR",g \
    -e s,"@SYSCONFDIR@","$SYSCONFDIR",g \
    -e s,"@TOOLDIR@","$TOOLDIR",g \
    -e s,"@LUA_VERSION@","$LUA_VERSION",g \
    -e s,"@ARCH@","$ARCH",g \
    -e s,"@BINARY_STORE@","$BINARY_STORE",g \
    -e s,"@E2_GROUP@","$E2_GROUP",g \
    -e s,"@SERVER_NAME@","$SERVER_NAME",g \
    -e s,"@SERVER_PORT@","$SERVER_PORT",g \
    -e s,"@ENV_TOOL@","$ENV_TOOL",g \
    -e s,"@CHROOT_TOOL@","$CHROOT_TOOL",g \
    -e s,"@TAR_TOOL@","$TAR_TOOL",g \
    -e s,"@CHOWN_TOOL@","$CHOWN_TOOL",g \
    -e s,"@RM_TOOL@","$RM_TOOL",g \
    -e s,"@DEFAULT_LOCAL_BRANCH@","$DEFAULT_LOCAL_BRANCH",g \
    -e s,"@DEFAULT_LOCAL_TAG@","$DEFAULT_LOCAL_TAG",g \
    -e s,"@E2_PREFIX@","$PREFIX",g $1 >$2 \
