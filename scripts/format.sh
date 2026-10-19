#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift format format --in-place --recursive Package.swift Sources Tests
