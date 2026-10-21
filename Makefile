TOP_DIR = ../..
include $(TOP_DIR)/tools/Makefile.common

DEPLOY_RUNTIME ?= /kb/runtime
TARGET ?= /kb/deployment

#
# Identify the CLI to the BV-BRC services. Every generated p3-* wrapper exports
# P3_CLIENT_PRODUCT, which P3ClientUA (p3_auth) turns into the User-Agent, so a
# request from these tools is distinguishable from any other Perl client in the
# tree -- in an access log, and in a Cloudflare block report.
#
# Doing it in the wrapper rather than in the scripts is what makes it hold for
# all of them: there is no module every p3-* script loads, and the HTTP clients
# that actually talk to the API live in p3_core, not here.
#
# The version is intentionally not specified in this repository -- stamping a
# release is a release-tooling job. Supply it at build time:
#
#	make P3_CLI_VERSION=1.2.3	=>	bvbrc-cli-perl/1.2.3
#	make				=>	bvbrc-cli-perl
#
P3_CLI_PRODUCT = bvbrc-cli-perl
P3_CLI_VERSION ?=

export P3_CLIENT_PRODUCT = $(P3_CLI_PRODUCT)$(if $(strip $(P3_CLI_VERSION)),/$(strip $(P3_CLI_VERSION)))
export WRAP_VARIABLES = P3_CLIENT_PRODUCT

SRC_PERL = $(wildcard scripts/*.pl)
BIN_PERL = $(addprefix $(BIN_DIR)/,$(basename $(notdir $(SRC_PERL))))
DEPLOY_PERL = $(addprefix $(TARGET)/bin/,$(basename $(notdir $(SRC_PERL))))

SRC_SERVICE_PERL = $(wildcard service-scripts/*.pl)
BIN_SERVICE_PERL = $(addprefix $(BIN_DIR)/,$(basename $(notdir $(SRC_SERVICE_PERL))))
DEPLOY_SERVICE_PERL = $(addprefix $(SERVICE_DIR)/bin/,$(basename $(notdir $(SRC_SERVICE_PERL))))

CLIENT_TESTS = $(wildcard t/client-tests/*.t)
SERVER_TESTS = $(wildcard t/server-tests/*.t)
PROD_TESTS = $(wildcard t/prod-tests/*.t)

STARMAN_WORKERS = 8
STARMAN_MAX_REQUESTS = 100

TPAGE_ARGS = --define kb_top=$(TARGET) --define kb_runtime=$(DEPLOY_RUNTIME) --define kb_service_name=$(SERVICE) \
	--define kb_service_port=$(SERVICE_PORT) --define kb_service_dir=$(SERVICE_DIR) \
	--define kb_sphinx_port=$(SPHINX_PORT) --define kb_sphinx_host=$(SPHINX_HOST) \
	--define kb_starman_workers=$(STARMAN_WORKERS) \
	--define kb_starman_max_requests=$(STARMAN_MAX_REQUESTS)

all: bin 

bin: $(BIN_PERL) $(BIN_SERVICE_PERL)

#
# P3_CLIENT_PRODUCT is baked into each wrapper when it is generated, so a change
# to it here has to force the wrappers to be rebuilt; otherwise an existing tree
# keeps announcing the old identity until someone empties bin/ by hand.
#
# This has to come after "all", or it would take over as make's default goal.
#
$(BIN_PERL) $(BIN_SERVICE_PERL): Makefile

deploy: deploy-all
deploy-all: deploy-client 
deploy-client: deploy-libs deploy-scripts deploy-docs

deploy-dir:
	if [ ! -d $(SERVICE_DIR) ] ; then mkdir $(SERVICE_DIR) ; fi
	if [ ! -d $(SERVICE_DIR)/webroot ] ; then mkdir $(SERVICE_DIR)/webroot ; fi
	if [ ! -d $(SERVICE_DIR)/bin ] ; then mkdir $(SERVICE_DIR)/bin ; fi
	if [ ! -d $(SERVICE_DIR)/sphinx ] ; then mkdir $(SERVICE_DIR)/sphinx ; fi

deploy-docs: 

test: test-client
	echo "running client and script tests"

# What does it mean to test a client. This is a test of a client
# library. If it is a client-server module, then it should be
# run against a running server. You can say that this also tests
# the server, and I agree. You can add a test-server dependancy
# to the test-client target if it makes sense to you. This test
# example assumes there is already a tested running server.
test-client:
	# run each client test
	for t in $(CLIENT_TESTS) ; do \
		if [ -f $$t ] ; then \
			$(DEPLOY_RUNTIME)/bin/perl $$t ; \
			if [ $$? -ne 0 ] ; then \
				exit 1 ; \
			fi \
		fi \
	done

test-server:
	# run each server test
	for t in $(SERVER_TESTS) ; do \
		if [ -f $$t ] ; then \
			echo Running $$t ; \
			$(DEPLOY_RUNTIME)/bin/perl $$t ; \
			if [ $$? -ne 0 ] ; then \
				exit 1 ; \
			fi \
		fi \
	done

test-prod-server:
	# run each prod test
	for t in $(PROD_TESTS) ; do \
		if [ -f $$t ] ; then \
			echo Running $$t ; \
			$(DEPLOY_RUNTIME)/bin/perl $$t ; \
			if [ $$? -ne 0 ] ; then \
				exit 1 ; \
			fi \
		fi \
	done

clean:
	ant clean

include $(TOP_DIR)/tools/Makefile.common.rules
