# RapidGov

**Version:** 1.0.0  
**Language:** Clarity (Stacks blockchain)

A fast-track governance contract for emergency decision-making on the Stacks blockchain. Crises are reported by any participant, validated by a quorum of trusted oracles, and then opened for weighted community voting inside a compressed ~24-hour window. Proposals only become executable once they clear a supermajority threshold, ensuring legitimacy without sacrificing speed.

---

## Table of Contents

- [Overview](#overview)
- [How It Works](#how-it-works)
- [Roles](#roles)
- [Crisis Lifecycle](#crisis-lifecycle)
- [Proposal Lifecycle](#proposal-lifecycle)
- [Governance Parameters](#governance-parameters)
- [Public Functions](#public-functions)
- [Read-Only Functions](#read-only-functions)
- [Error Codes](#error-codes)
- [Constants Reference](#constants-reference)

---

## Overview

RapidGov is built around a two-stage process: **crisis validation** followed by **proposal voting**.

A crisis must first be confirmed by multiple trusted oracles before any governance action can be taken against it. This oracle gate prevents spam and ensures that compressed voting windows are only unlocked for legitimately verified emergencies. Once a crisis is verified, any participant may submit a proposal, which then goes to registered voters for a time-boxed weighted vote. A proposal must clear both a minimum participation threshold and a 66% supermajority to pass and become executable.

---

## How It Works

```
1. Anyone reports a crisis          → status: OPEN
2. Oracles submit verdicts
   └─ ≥ 2 confirmations             → status: VERIFIED
3. Anyone creates a proposal
   tied to the verified crisis
4. Registered voters cast weighted
   yes/no votes within 144 blocks (~24 hrs)
5. finalize-proposal is called
   └─ quorum met + ≥ 66% yes        → PASSED
   └─ otherwise                     → FAILED
6. execute-proposal is called       → EXECUTED
   └─ crisis is sealed              → CLOSED
```

---

## Roles

**Contract Owner** — The deploying principal. Manages oracle and voter registries. Cannot be changed after deployment.

**Oracles** — Trusted principals registered by the owner. They submit legitimacy verdicts on reported crises. A minimum of two confirmations are required to advance a crisis to `VERIFIED` status.

**Voters** — Registered principals with an assigned voting weight. Weight is set at registration and determines how much influence a voter's yes/no carries in a proposal.

**Reporters** — Any principal on the network. No registration required. Anyone may call `report-crisis` to flag an emergency for oracle review.

---

## Crisis Lifecycle

Crises progress through the following statuses:

| Status | Constant          | Value | Meaning                                               |
|--------|-------------------|-------|-------------------------------------------------------|
| Open   | `CRISIS-OPEN`     | `u1`  | Reported, awaiting oracle validation                  |
| Verified | `CRISIS-VERIFIED` | `u2` | Confirmed by oracles; proposals can now be created   |
| Rejected | `CRISIS-REJECTED` | `u3` | Not currently used; reserved for future logic        |
| Closed | `CRISIS-CLOSED`   | `u4`  | A proposal was executed; no further proposals allowed |

**Severity levels** (supplied by the reporter, informational):

| Value | Meaning  |
|-------|----------|
| `u1`  | Low      |
| `u2`  | Medium   |
| `u3`  | High     |
| `u4`  | Critical |

---

## Proposal Lifecycle

| Status   | Constant            | Value | Meaning                              |
|----------|---------------------|-------|--------------------------------------|
| Active   | `PROPOSAL-ACTIVE`   | `u1`  | Voting is open                       |
| Passed   | `PROPOSAL-PASSED`   | `u2`  | Quorum met and supermajority reached |
| Failed   | `PROPOSAL-FAILED`   | `u3`  | Quorum missed or threshold not met   |
| Executed | `PROPOSAL-EXECUTED` | `u4`  | Proposal carried out; crisis closed  |

A proposal passes if **both** conditions hold after the voting window closes:

1. `total-weight >= QUORUM` (minimum participation)
2. `yes-votes / total-weight >= 66%` (supermajority threshold)

---

## Governance Parameters

| Parameter                  | Value  | Description                                                  |
|----------------------------|--------|--------------------------------------------------------------|
| `VOTING-WINDOW`            | `u144` | Blocks a vote stays open (~24 hours at ~10 min/block)        |
| `MIN-ORACLE-CONFIRMATIONS` | `u2`   | Oracle confirmations needed to verify a crisis               |
| `QUORUM`                   | `u3`   | Minimum total vote-weight for a result to be valid           |
| `THRESHOLD`                | `u66`  | Percentage of yes-weight required for a proposal to pass     |

All parameters are hard-coded constants and cannot be changed without redeployment.

---

## Public Functions

### Oracle Management *(owner only)*

#### `register-oracle (oracle principal)`
Adds a principal to the trusted oracle registry. Fails if the oracle is already registered.

#### `remove-oracle (oracle principal)`
Revokes a principal's oracle status. Decrements the active oracle count.

---

### Voter Management *(owner only)*

#### `register-voter (voter principal) (weight uint)`
Enrolls a voter with a delegated voting weight. Weight must be greater than zero. Fails if the voter is already registered.

#### `remove-voter (voter principal)`
Removes a voter from the registry. Decrements the active voter count.

---

### Crisis Reporting *(open to all)*

#### `report-crisis (description string-utf8-500) (severity uint)`
Reports a new crisis for oracle review. Returns the assigned crisis ID. No registration required — any principal may call this. Severity must be between `u1` and `u4`.

---

### Oracle Crisis Validation *(oracles only)*

#### `verify-crisis (crisis-id uint) (legitimate bool)`
Submits an oracle verdict on a reported crisis. Passing `true` counts as a confirmation; `false` as a rejection. Each oracle may vote only once per crisis. Once `MIN-ORACLE-CONFIRMATIONS` confirmations accumulate the crisis status automatically advances to `CRISIS-VERIFIED`. Returns the resulting crisis status.

---

### Proposal Lifecycle *(open to all, except as noted)*

#### `create-proposal (crisis-id uint) (title string-utf8-100) (description string-utf8-1000)`
Creates an urgent governance proposal tied to a verified crisis. Voting opens immediately and runs for `VOTING-WINDOW` blocks. Fails if the crisis is not in `CRISIS-VERIFIED` status. Returns the new proposal ID.

#### `cast-vote (proposal-id uint) (support bool)`
Casts a weighted yes/no vote on an active proposal. The caller must be a registered voter. Each voter may vote only once per proposal. Fails if the voting window has closed. Passing `true` votes yes; `false` votes no.

#### `finalize-proposal (proposal-id uint)`
Resolves a proposal once its voting window has closed. Permissionless — any principal may call this. Computes whether quorum and the supermajority threshold are met and transitions the proposal to `PROPOSAL-PASSED` or `PROPOSAL-FAILED`. Returns the resulting status code.

#### `execute-proposal (proposal-id uint)`
Executes a passed proposal and seals the associated crisis (`CRISIS-CLOSED`). Permissionless. Fails if the proposal has not passed or has already been executed. In production this function would dispatch the on-chain action described by the proposal.

---

## Read-Only Functions

### Crisis Queries

| Function | Returns | Description |
|----------|---------|-------------|
| `get-crisis (crisis-id uint)` | `(optional crisis)` | Full crisis record |
| `get-oracle-crisis-vote (crisis-id uint) (oracle principal)` | `(optional vote)` | An oracle's verdict on a specific crisis |
| `get-next-crisis-id` | `uint` | Next crisis ID to be assigned |

### Proposal Queries

| Function | Returns | Description |
|----------|---------|-------------|
| `get-proposal (proposal-id uint)` | `(optional proposal)` | Full proposal record |
| `get-vote (proposal-id uint) (voter principal)` | `(optional vote)` | A voter's vote on a specific proposal |
| `get-next-proposal-id` | `uint` | Next proposal ID to be assigned |
| `get-proposal-result (proposal-id uint)` | `(response result err)` | Live vote tallies, yes%, status, and executed flag |
| `is-proposal-active (proposal-id uint)` | `bool` | Whether a proposal is active and within its voting window |
| `is-proposal-passed (proposal-id uint)` | `bool` | Whether a proposal has passed |

### Oracle & Voter Queries

| Function | Returns | Description |
|----------|---------|-------------|
| `get-oracle-info (oracle principal)` | `(optional oracle)` | Oracle record including confirmation tally |
| `get-voter-info (voter principal)` | `(optional voter)` | Voter record including assigned weight |
| `is-oracle (addr principal)` | `bool` | Whether a principal is a registered oracle |
| `is-voter (addr principal)` | `bool` | Whether a principal is a registered voter |
| `get-oracle-count` | `uint` | Total registered oracles |
| `get-voter-count` | `uint` | Total registered voters |

### Governance Parameter Queries

| Function | Returns | Description |
|----------|---------|-------------|
| `get-voting-window` | `uint` | Voting window duration in blocks |
| `get-min-oracle-confirmations` | `uint` | Confirmations needed to verify a crisis |
| `get-quorum` | `uint` | Minimum total vote-weight for validity |
| `get-threshold` | `uint` | Yes-vote percentage required to pass |
| `get-contract-owner` | `principal` | The deploying contract owner |

---

## Error Codes

| Code  | Constant                      | When it's thrown                                              |
|-------|-------------------------------|---------------------------------------------------------------|
| `u100`| `ERR-NOT-OWNER`               | Caller is not the contract owner                              |
| `u101`| `ERR-NOT-ORACLE`              | Caller is not a registered oracle                             |
| `u102`| `ERR-ALREADY-ORACLE`          | Target principal is already an oracle                         |
| `u103`| `ERR-CRISIS-NOT-FOUND`        | Crisis ID does not exist                                      |
| `u104`| `ERR-CRISIS-NOT-VERIFIED`     | Crisis has not been verified by oracles yet                   |
| `u105`| `ERR-CRISIS-CLOSED`           | Crisis is closed; oracle votes are no longer accepted         |
| `u106`| `ERR-ORACLE-ALREADY-VOTED`    | Oracle has already submitted a verdict for this crisis        |
| `u107`| `ERR-PROPOSAL-NOT-FOUND`      | Proposal ID does not exist                                    |
| `u108`| `ERR-PROPOSAL-NOT-ACTIVE`     | Proposal is not active or voting window has closed            |
| `u109`| `ERR-PROPOSAL-ALREADY-VOTED`  | Voter has already cast a vote on this proposal                |
| `u110`| `ERR-PROPOSAL-NOT-PASSED`     | Trying to execute a proposal that has not passed              |
| `u111`| `ERR-PROPOSAL-ALREADY-EXEC`   | Proposal has already been executed                            |
| `u112`| `ERR-NOT-VOTER`               | Caller is not a registered voter                              |
| `u113`| `ERR-ALREADY-VOTER`           | Target principal is already a registered voter                |
| `u114`| `ERR-INVALID-SEVERITY`        | Severity value is not between `u1` and `u4`                   |
| `u115`| `ERR-INVALID-WEIGHT`          | Voter weight must be greater than zero                        |
| `u116`| `ERR-VOTING-STILL-OPEN`       | Trying to finalise a proposal before its window has closed    |

---

## Constants Reference

```clarity
;; Governance Parameters
VOTING-WINDOW              u144   ;; ~24 hours at ~10 min/block
MIN-ORACLE-CONFIRMATIONS   u2     ;; confirmations to verify a crisis
QUORUM                     u3     ;; minimum total vote-weight
THRESHOLD                  u66    ;; % yes-votes required to pass

;; Crisis Status Flags
CRISIS-OPEN       u1
CRISIS-VERIFIED   u2
CRISIS-REJECTED   u3
CRISIS-CLOSED     u4

;; Proposal Status Flags
PROPOSAL-ACTIVE   u1
PROPOSAL-PASSED   u2
PROPOSAL-FAILED   u3
PROPOSAL-EXECUTED u4
```