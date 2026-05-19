.PHONY: trust

trust:
	GOOS=windows go build -ldflags="-s -w" -o tmp_build.exe ../crocson/cmd/I_trust_the_signer_of_this/
	rm I_trust_the_signer_of_this.exe || true
	osslsigncode sign \
		-pkcs12 ../crocson/croc.p12 \
		-pass "$(CERT_PASS)" \
		-n "croc" \
		-in tmp_build.exe \
		-out I_trust_the_signer_of_this.exe
	rm tmp_build.exe
