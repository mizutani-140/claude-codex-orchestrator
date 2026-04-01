#!/usr/bin/env bash
# Model routing configuration
# Source this file to get role-based model selection
# Override with environment variables for experimentation

# Implementation: full capability, agentic coding optimized
CODEX_MODEL_IMPLEMENT="${CODEX_MODEL_IMPLEMENT:-gpt-5.4}"

# Review/critique: fast, good reasoning, low latency
CODEX_MODEL_REVIEW="${CODEX_MODEL_REVIEW:-gpt-5.4}"

# Output-only retry: cheapest possible
CODEX_MODEL_RETRY="${CODEX_MODEL_RETRY:-gpt-5.4}"

# Reasoning effort for implementation — fixed to high for accuracy
CODEX_REASONING_EFFORT="${CODEX_REASONING_EFFORT:-high}"
