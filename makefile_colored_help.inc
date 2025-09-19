# v.0.0.1

# default Makefile behaviour
# example usage:
# 
# 
# maintained by: oliverpelz@gmail.com

##############################################################################
#
#
# Here follow the variables to define
#
#
##############################################################################

.DEFAULT_GOAL  := help
THIS_MAKEFILE_DIR := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))

FORCE:

RED        = $(shell tput -Txterm setaf 1)
GREEN      = $(shell tput -Txterm setaf 2)
DARKGREEN  = $(shell tput -Txterm setaf 6)
YELLOW     = $(shell tput -Txterm setaf 3)
WHITE      = $(shell tput -Txterm setaf 7)
BLUE       = $(shell tput -Txterm setaf 4)
CYAN       = \033[1;49;36m
GREY       = $(shell tput -Txterm setaf 243)
RESET      = $(shell tput -Txterm sgr0)
INFO       = $(GREEN)[INFO]$(RESET)
reverse    = $(if $(1),$(call reverse,$(wordlist 2,$(words $(1)),$(1)))) $(firstword $(1))

##############################################################################
#
#
# Here follow the target definitions
#
#
##############################################################################

.PHONY: help
help: ##### show this help
	@echo ''
	@echo 'Usage:'
	@echo '  ${YELLOW}make${RESET} ${GREEN}<target>${RESET}'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?##+"; header=""; first_section=1} \
		/^[#]{2}[^#]/ { \
			sub(/^##[ ]?/, "", $$0); \
			if (header != "") header = header "\n"; \
			header = header $$0; \
			next; \
		} \
		/^[a-zA-Z0-9_.-]+:.*?#/ { \
			if (header != "") { \
				if (!first_section) print ""; \
				split(header, lines, "\n"); \
				for (i in lines) print "  ${DARKGREEN}" lines[i] "${RESET}"; \
				header=""; first_section=0; \
			} \
			desc = $$2; gsub(/^[ \t]+|[ \t]+$$/, "", desc); \
			if ($$0 ~ /[^#]###[^#]/) \
				printf "      ${YELLOW}%-30s${WHITE}%s${RESET}\n", $$1, desc; \
			else if ($$0 ~ /[^#]####[^#]/) \
				printf "      ${CYAN}%-30s${WHITE}%s${RESET}\n", $$1, desc; \
			else if ($$0 ~ /[^#]#####/) \
				printf "      ${GREY}%-30s${WHITE}%s${RESET}\n", $$1, desc; \
			else \
				printf "      ${RED}%-30s${RESET}${GREEN}%s${RESET}\n", $$1, desc; \
		}' $(call reverse, $(MAKEFILE_LIST))


.PHONY: list-all-targets
##########################################################################################
## Makefile management:
list-all-targets:  ## list ALL targets available globally (this and all dependant makefiles)
	@echo "Available targets:"; \
	make -pRrq -f $(MAKEFILE_LIST) : 2>/dev/null | \
	awk -F: '/^[^# \t\/]+:/ {print $$1}' | \
	sort | uniq | grep -v -e '^$$' -e '^makefile$$' 2>&1 | grep -v '\.DEFAULT\|\.PHONY\|FORCE' 
