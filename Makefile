# Builds the KMS presenter NIF and the touchscreen reader into priv/.
# Driven by elixir_make; Nerves provides CC, CFLAGS and ERL_EI_INCLUDE_DIR.

PREFIX = $(MIX_APP_PATH)/priv
ERL_CFLAGS ?= -I$(ERL_EI_INCLUDE_DIR)
CFLAGS ?= -O2
CFLAGS += -Wall -Wextra

all: $(PREFIX) $(PREFIX)/drm_nif.so $(PREFIX)/evtouch

$(PREFIX):
	mkdir -p $@

$(PREFIX)/drm_nif.so: c_src/drm_nif.c
	$(CC) $(filter-out -pie,$(CFLAGS)) $(ERL_CFLAGS) -fPIC -shared -o $@ $<

$(PREFIX)/evtouch: c_src/evtouch.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f $(PREFIX)/drm_nif.so $(PREFIX)/evtouch

.PHONY: all clean
