PREFIX = /usr/local
BINDIR = $(PREFIX)/bin
SCRIPT = dan
TARGET = dan
.PHONY = install uninstall

dan: $(SOURCE)
	echo "bash scripts, can't compile."

install: $(TARGET)
	@echo "Installing $(SCRIPT) to $(BINDIR)/$(TARGET)"
	mkdir -p $(BINDIR)
	rm -f $(BINDIR)/$(TARGET)
	cp -f $(SCRIPT) $(BINDIR)/$(TARGET)
	chmod 755 $(BINDIR)/$(TARGET)
	@echo "Installation complete."

uninstall:
	@echo "Removing $(BINDIR)/$(TARGET)"
	rm -f $(BINDIR)/$(TARGET)
	@echo "Removation complete."
