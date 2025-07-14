# Phmate Makefile
# Default installation paths
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
DOCDIR ?= $(PREFIX)/share/doc/phmate
MANDIR ?= $(PREFIX)/share/man/man1
COMPLETIONDIR ?= $(PREFIX)/share/bash-completion/completions

# No build step needed for Bash scripts
all:
	@echo "Nothing to build. Use 'make install' to install Phmate."

install:
	@echo "Installing Phmate..."
	@install -d $(DESTDIR)$(BINDIR)
	@install -d $(DESTDIR)$(DOCDIR)
	@install -d $(DESTDIR)$(MANDIR)
	@install -d $(DESTDIR)$(COMPLETIONDIR)
	
	# Install the script
	@install -m 755 src/phmate.sh $(DESTDIR)$(BINDIR)/phmate
	
	# Install documentation
	@install -m 644 README.md $(DESTDIR)$(DOCDIR)/
	@install -m 644 CHANGELOG.md $(DESTDIR)$(DOCDIR)/
	@install -m 644 LICENSE $(DESTDIR)$(DOCDIR)/
	@install -m 644 docs/man/phmate.1 $(DESTDIR)$(MANDIR)/
	
	# Install bash completion
	@install -m 644 completion/bash/phmate $(DESTDIR)$(COMPLETIONDIR)/
	
	@echo "Installation complete!"

uninstall:
	@echo "Uninstalling Phmate..."
	@rm -f $(DESTDIR)$(BINDIR)/phmate
	@rm -f $(DESTDIR)$(MANDIR)/phmate.1
	@rm -f $(DESTDIR)$(COMPLETIONDIR)/phmate
	@rm -rf $(DESTDIR)$(DOCDIR)
	@echo "Uninstall complete!"

clean:
	@echo "Cleaning up build artifacts..."
	@rm -f *~
	@rm -f *.bak
	@rm -f *.log
	@rm -f *.tar.gz
	@rm -rf dist
	@rm -rf build
	@rm -rf __pycache__
	@echo "Clean complete!"

# For makepkg/pacman package building cleanup
pkgclean:
	@echo "Cleaning up package build artifacts..."
	@rm -rf src/phmate-*
	@rm -rf pkg
	@rm -f *.pkg.tar.zst
	@rm -f *.pkg.tar.xz
	@echo "Package clean complete!"

distclean: clean pkgclean
	@echo "Performing deep clean..."
	@rm -rf .venv
	@rm -rf .cache
	@echo "Deep clean complete!"

.PHONY: all install uninstall clean pkgclean distclean