.PHONY: trust clean help

# Main package in the crocson module
MAIN_PKG=../crocson/cmd/I_trust_the_signer_of_this/
SYSO=$(MAIN_PKG)resource_windows_amd64.syso
MANIFEST=app.manifest
VERSIONINFO_JSON:=$(shell mktemp -d)/versioninfo.json

help:
	@echo "Available targets:"
	@echo "  make trust  - build signed I_trust_the_signer_of_this.exe with admin manifest"
	@echo "  make clean  - remove compiled files"
	@echo "  make help   - show this help"

# Generate syso with admin manifest embedded (picked up by go build)
$(SYSO): $(MANIFEST)
	@printf '%s\n' \
		'{' \
		'  "ManifestPath": "$(CURDIR)/$(MANIFEST)"' \
		'}' > $(VERSIONINFO_JSON)
	cd ../crocson && go tool github.com/josephspurrier/goversioninfo/cmd/goversioninfo -o cmd/I_trust_the_signer_of_this/resource_windows_amd64.syso $(VERSIONINFO_JSON)

trust: $(SYSO)
	cd ../crocson && GOOS=windows go build -ldflags="-s -w" -o "$(CURDIR)/tmp_build.exe" ./cmd/I_trust_the_signer_of_this/
	rm $(SYSO)
	rm I_trust_the_signer_of_this.exe || true
	osslsigncode sign \
		-pkcs12 ../crocson/croc.p12 \
		-pass "$(CERT_PASS)" \
		-n "croc" \
		-in tmp_build.exe \
		-out I_trust_the_signer_of_this.exe
	rm tmp_build.exe

clean:
	rm -f I_trust_the_signer_of_this.exe tmp_build.exe
