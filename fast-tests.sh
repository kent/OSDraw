#!/bin/bash

# Run all tests except the slow invariant and symbolic tests
forge test --no-match-path "(OSDraw.invariant.t.sol|OSDraw.sym.t.sol|OSDraw.fuzz.t.sol)" "$@" 