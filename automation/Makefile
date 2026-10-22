SHELL := /usr/bin/env bash

AUTOMATION_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
GITOPS_NS ?= openshift-gitops

.PHONY: help bootstrap status verify teardown

help:
	@printf '%s\n' \
	  '  make bootstrap   Deploy the lab through OpenShift GitOps (clusters without an RHDP order)' \
	  '  make status      Show sync and health of the lab Applications' \
	  '  make verify      PASS/FAIL readiness checks for class' \
	  '  make teardown    Delete the lab Applications and everything they created'

bootstrap:
	domain=$$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}') && \
	  test -n "$$domain" && \
	  sed "s|DEPLOYER_DOMAIN|$$domain|" $(AUTOMATION_DIR)/bootstrap.yaml | oc apply -f -

status:
	oc -n $(GITOPS_NS) get applications.argoproj.io -l demo.redhat.com/application=field-content

verify:
	GITOPS_NS=$(GITOPS_NS) bash $(AUTOMATION_DIR)/verify.sh

teardown:
	oc delete -f $(AUTOMATION_DIR)/bootstrap.yaml --ignore-not-found --wait=true
