# Build stamp binary (libqpdf-based PDF banner stamper)
# Requires: app-text/qpdf (provides libqpdf headers + pkg-config)

CXX      ?= g++
CXXFLAGS ?= -O2 -Wall -Wextra -std=c++17
PKG       = libqpdf

PKG_CFLAGS := $(shell pkg-config --cflags $(PKG))
PKG_LIBS   := $(shell pkg-config --libs   $(PKG))

stamp: stamp.cpp
	$(CXX) $(CXXFLAGS) $(PKG_CFLAGS) -o $@ $< $(PKG_LIBS)

clean:
	rm -f stamp

.PHONY: clean
