;; title: RapidGov
;; version: 1.0.0
;; summary: Urgent decision protocol with compressed voting windows and oracle-verified crisis legitimacy validation
;; description:
;;   RapidGov is a fast-track governance contract designed to handle emergencies on the Stacks blockchain.
;;   Crises are reported by any participant, validated by a quorum of trusted oracles, and then opened
;;   for community voting inside a compressed window (~24 hours at Stacks block times). Proposals only
;;   become executable once they clear a supermajority threshold, ensuring legitimacy without sacrificing speed.

;; ============================================================
;;  CONSTANTS
;; ============================================================

(define-constant CONTRACT-OWNER tx-sender)

;; -- Error codes --
(define-constant ERR-NOT-OWNER              (err u100))
(define-constant ERR-NOT-ORACLE             (err u101))
(define-constant ERR-ALREADY-ORACLE         (err u102))
(define-constant ERR-CRISIS-NOT-FOUND       (err u103))
(define-constant ERR-CRISIS-NOT-VERIFIED    (err u104))
(define-constant ERR-CRISIS-CLOSED          (err u105))
(define-constant ERR-ORACLE-ALREADY-VOTED   (err u106))
(define-constant ERR-PROPOSAL-NOT-FOUND     (err u107))
(define-constant ERR-PROPOSAL-NOT-ACTIVE    (err u108))
(define-constant ERR-PROPOSAL-ALREADY-VOTED (err u109))
(define-constant ERR-PROPOSAL-NOT-PASSED    (err u110))
(define-constant ERR-PROPOSAL-ALREADY-EXEC  (err u111))
(define-constant ERR-NOT-VOTER              (err u112))
(define-constant ERR-ALREADY-VOTER          (err u113))
(define-constant ERR-INVALID-SEVERITY       (err u114))
(define-constant ERR-INVALID-WEIGHT         (err u115))
(define-constant ERR-VOTING-STILL-OPEN      (err u116))

;; -- Governance parameters --
;; Compressed voting window: 144 Stacks blocks (~24 hours at ~10 min/block)
(define-constant VOTING-WINDOW              u144)
;; Number of oracle confirmations required to validate a crisis
(define-constant MIN-ORACLE-CONFIRMATIONS   u2)
;; Minimum total vote-weight required for a result to be valid
(define-constant QUORUM                     u3)
;; Yes-vote percentage (out of 100) required to pass a proposal
(define-constant THRESHOLD                  u66)

;; -- Crisis status flags --
(define-constant CRISIS-OPEN       u1)
(define-constant CRISIS-VERIFIED   u2)
(define-constant CRISIS-REJECTED   u3)
(define-constant CRISIS-CLOSED     u4)

;; -- Proposal status flags --
(define-constant PROPOSAL-ACTIVE   u1)
(define-constant PROPOSAL-PASSED   u2)
(define-constant PROPOSAL-FAILED   u3)
(define-constant PROPOSAL-EXECUTED u4)

;; ============================================================
;;  DATA VARS
;; ============================================================

(define-data-var next-crisis-id   uint u1)
(define-data-var next-proposal-id uint u1)
(define-data-var oracle-count     uint u0)
(define-data-var voter-count      uint u0)

;; ============================================================
;;  DATA MAPS
;; ============================================================

;; Trusted oracle registry
(define-map oracles
  principal
  {
    registered:       bool,
    verified-crises:  uint   ;; running tally of confirmed crises
  }
)

;; Voter registry with delegated voting weight
(define-map voters
  principal
  { weight: uint }
)

;; Crisis registry
(define-map crises
  uint  ;; crisis-id
  {
    description:          (string-utf8 500),
    severity:             uint,      ;; 1=low 2=medium 3=high 4=critical
    reporter:             principal,
    oracle-confirmations: uint,
    oracle-rejections:    uint,
    created-at:           uint,
    status:               uint       ;; see CRISIS-* constants
  }
)

;; Prevents the same oracle from voting twice on the same crisis
(define-map oracle-crisis-votes
  { crisis-id: uint, oracle: principal }
  { verified: bool }
)

;; Proposal registry
(define-map proposals
  uint  ;; proposal-id
  {
    crisis-id:    uint,
    title:        (string-utf8 100),
    description:  (string-utf8 1000),
    proposer:     principal,
    vote-start:   uint,
    vote-end:     uint,
    yes-votes:    uint,
    no-votes:     uint,
    total-weight: uint,
    status:       uint,   ;; see PROPOSAL-* constants
    executed:     bool
  }
)

;; Prevents the same voter from voting twice on the same proposal
(define-map proposal-votes
  { proposal-id: uint, voter: principal }
  { support: bool, weight: uint }
)

;; ============================================================
;;  PRIVATE HELPERS
;; ============================================================

(define-private (is-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

(define-private (is-registered-oracle (addr principal))
  (match (map-get? oracles addr)
    oracle-data (get registered oracle-data)
    false
  )
)

(define-private (is-registered-voter (addr principal))
  (is-some (map-get? voters addr))
)

(define-private (get-voter-weight (addr principal))
  (match (map-get? voters addr)
    voter-data (get weight voter-data)
    u0
  )
)

;; Safe integer percentage: (numerator * 100) / denominator
(define-private (calculate-percentage (numerator uint) (denominator uint))
  (if (is-eq denominator u0)
    u0
    (/ (* numerator u100) denominator)
  )
)

;; ============================================================
;;  PUBLIC FUNCTIONS - ORACLE MANAGEMENT
;; ============================================================

;; Register a new trusted oracle (owner only)
(define-public (register-oracle (oracle principal))
  (begin
    (asserts! (is-owner) ERR-NOT-OWNER)
    (asserts! (not (is-registered-oracle oracle)) ERR-ALREADY-ORACLE)
    (map-set oracles oracle { registered: true, verified-crises: u0 })
    (var-set oracle-count (+ (var-get oracle-count) u1))
    (ok true)
  )
)

;; Revoke an oracle's trusted status (owner only)
(define-public (remove-oracle (oracle principal))
  (let
    (
      (oracle-data (unwrap! (map-get? oracles oracle) ERR-NOT-ORACLE))
    )
    (asserts! (is-owner) ERR-NOT-OWNER)
    (asserts! (get registered oracle-data) ERR-NOT-ORACLE)
    (map-set oracles oracle (merge oracle-data { registered: false }))
    (var-set oracle-count (- (var-get oracle-count) u1))
    (ok true)
  )
)

;; ============================================================
;;  PUBLIC FUNCTIONS - VOTER MANAGEMENT
;; ============================================================

;; Enroll a new voter with a given voting weight (owner only)
(define-public (register-voter (voter principal) (weight uint))
  (begin
    (asserts! (is-owner) ERR-NOT-OWNER)
    (asserts! (not (is-registered-voter voter)) ERR-ALREADY-VOTER)
    (asserts! (> weight u0) ERR-INVALID-WEIGHT)
    (map-set voters voter { weight: weight })
    (var-set voter-count (+ (var-get voter-count) u1))
    (ok true)
  )
)

;; Remove a voter from the registry (owner only)
(define-public (remove-voter (voter principal))
  (begin
    (asserts! (is-owner) ERR-NOT-OWNER)
    (asserts! (is-registered-voter voter) ERR-NOT-VOTER)
    (map-delete voters voter)
    (var-set voter-count (- (var-get voter-count) u1))
    (ok true)
  )
)

;; ============================================================
;;  PUBLIC FUNCTIONS - CRISIS REPORTING
;; ============================================================

;; Any participant may report a crisis for oracle review.
;; severity: 1=low, 2=medium, 3=high, 4=critical
(define-public (report-crisis
    (description (string-utf8 500))
    (severity    uint)
  )
  (let
    (
      (crisis-id (var-get next-crisis-id))
    )
    (asserts! (and (>= severity u1) (<= severity u4)) ERR-INVALID-SEVERITY)
    (map-set crises crisis-id
      {
        description:          description,
        severity:             severity,
        reporter:             tx-sender,
        oracle-confirmations: u0,
        oracle-rejections:    u0,
        created-at:           stacks-block-height,
        status:               CRISIS-OPEN
      }
    )
    (var-set next-crisis-id (+ crisis-id u1))
    (ok crisis-id)
  )
)

;; ============================================================
;;  PUBLIC FUNCTIONS - ORACLE CRISIS VALIDATION
;; ============================================================

;; A trusted oracle submits a legitimacy verdict for a reported crisis.
;; Passing `legitimate: true` counts as a confirmation; `false` as a rejection.
;; Once MIN-ORACLE-CONFIRMATIONS confirmations are accumulated the crisis
;; status automatically advances to CRISIS-VERIFIED, unlocking proposals.
(define-public (verify-crisis (crisis-id uint) (legitimate bool))
  (let
    (
      (crisis         (unwrap! (map-get? crises crisis-id) ERR-CRISIS-NOT-FOUND))
      (vote-key       { crisis-id: crisis-id, oracle: tx-sender })
      (oracle-data    (unwrap! (map-get? oracles tx-sender) ERR-NOT-ORACLE))
    )
    (asserts! (get registered oracle-data) ERR-NOT-ORACLE)
    (asserts! (is-eq (get status crisis) CRISIS-OPEN) ERR-CRISIS-CLOSED)
    (asserts! (is-none (map-get? oracle-crisis-votes vote-key)) ERR-ORACLE-ALREADY-VOTED)

    ;; Record oracle's verdict
    (map-set oracle-crisis-votes vote-key { verified: legitimate })

    (if legitimate
      (let
        (
          (new-confirmations (+ (get oracle-confirmations crisis) u1))
          (new-status
            (if (>= new-confirmations MIN-ORACLE-CONFIRMATIONS)
              CRISIS-VERIFIED
              CRISIS-OPEN
            )
          )
        )
        ;; Increment oracle's lifetime confirmation tally
        (map-set oracles tx-sender
          (merge oracle-data { verified-crises: (+ (get verified-crises oracle-data) u1) })
        )
        ;; Update crisis with new confirmation count (and possibly verified status)
        (map-set crises crisis-id
          (merge crisis { oracle-confirmations: new-confirmations, status: new-status })
        )
        (ok new-status)
      )
      ;; Oracle rejected: increment rejection count, status stays OPEN
      (let
        (
          (new-rejections (+ (get oracle-rejections crisis) u1))
        )
        (map-set crises crisis-id
          (merge crisis { oracle-rejections: new-rejections })
        )
        (ok CRISIS-OPEN)
      )
    )
  )
)

;; ============================================================
;;  PUBLIC FUNCTIONS - PROPOSAL LIFECYCLE
;; ============================================================

;; Create an urgent proposal tied to a verified crisis.
;; Voting opens immediately and closes after VOTING-WINDOW blocks.
(define-public (create-proposal
    (crisis-id   uint)
    (title       (string-utf8 100))
    (description (string-utf8 1000))
  )
  (let
    (
      (crisis      (unwrap! (map-get? crises crisis-id) ERR-CRISIS-NOT-FOUND))
      (proposal-id (var-get next-proposal-id))
    )
    (asserts! (is-eq (get status crisis) CRISIS-VERIFIED) ERR-CRISIS-NOT-VERIFIED)
    (map-set proposals proposal-id
      {
        crisis-id:    crisis-id,
        title:        title,
        description:  description,
        proposer:     tx-sender,
        vote-start:   stacks-block-height,
        vote-end:     (+ stacks-block-height VOTING-WINDOW),
        yes-votes:    u0,
        no-votes:     u0,
        total-weight: u0,
        status:       PROPOSAL-ACTIVE,
        executed:     false
      }
    )
    (var-set next-proposal-id (+ proposal-id u1))
    (ok proposal-id)
  )
)

;; Registered voter casts a yes/no vote on an active proposal.
(define-public (cast-vote (proposal-id uint) (support bool))
  (let
    (
      (proposal   (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
      (voter-data (unwrap! (map-get? voters tx-sender) ERR-NOT-VOTER))
      (vote-key   { proposal-id: proposal-id, voter: tx-sender })
      (weight     (get weight voter-data))
    )
    (asserts! (is-eq (get status proposal) PROPOSAL-ACTIVE) ERR-PROPOSAL-NOT-ACTIVE)
    (asserts! (<= stacks-block-height (get vote-end proposal)) ERR-PROPOSAL-NOT-ACTIVE)
    (asserts! (is-none (map-get? proposal-votes vote-key)) ERR-PROPOSAL-ALREADY-VOTED)

    ;; Record the vote
    (map-set proposal-votes vote-key { support: support, weight: weight })

    ;; Tally into the proposal
    (if support
      (map-set proposals proposal-id
        (merge proposal {
          yes-votes:    (+ (get yes-votes proposal) weight),
          total-weight: (+ (get total-weight proposal) weight)
        })
      )
      (map-set proposals proposal-id
        (merge proposal {
          no-votes:     (+ (get no-votes proposal) weight),
          total-weight: (+ (get total-weight proposal) weight)
        })
      )
    )
    (ok true)
  )
)

;; Finalise a proposal once its voting window has closed.
;; Returns the resolved status: PROPOSAL-PASSED or PROPOSAL-FAILED.
(define-public (finalize-proposal (proposal-id uint))
  (let
    (
      (proposal     (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
      (yes-votes    (get yes-votes proposal))
      (total-weight (get total-weight proposal))
      (yes-pct      (calculate-percentage yes-votes total-weight))
    )
    (asserts! (is-eq (get status proposal) PROPOSAL-ACTIVE) ERR-PROPOSAL-NOT-ACTIVE)
    (asserts! (> stacks-block-height (get vote-end proposal)) ERR-VOTING-STILL-OPEN)

    (if (and (>= total-weight QUORUM) (>= yes-pct THRESHOLD))
      (begin
        (map-set proposals proposal-id (merge proposal { status: PROPOSAL-PASSED }))
        (ok PROPOSAL-PASSED)
      )
      (begin
        (map-set proposals proposal-id (merge proposal { status: PROPOSAL-FAILED }))
        (ok PROPOSAL-FAILED)
      )
    )
  )
)

;; Execute a passed proposal and close the associated crisis.
;; Only callable after the proposal has been finalised as PASSED.
(define-public (execute-proposal (proposal-id uint))
  (let
    (
      (proposal  (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
      (crisis-id (get crisis-id proposal))
    )
    (asserts! (is-eq (get status proposal) PROPOSAL-PASSED) ERR-PROPOSAL-NOT-PASSED)
    (asserts! (not (get executed proposal)) ERR-PROPOSAL-ALREADY-EXEC)

    ;; Mark proposal as executed
    (map-set proposals proposal-id
      (merge proposal { executed: true, status: PROPOSAL-EXECUTED })
    )
    ;; Seal the crisis so no further proposals can be opened against it
    (match (map-get? crises crisis-id)
      crisis-data
        (map-set crises crisis-id (merge crisis-data { status: CRISIS-CLOSED }))
      false
    )
    (ok true)
  )
)

;; ============================================================
;;  READ-ONLY FUNCTIONS
;; ============================================================

;; -- Crisis queries --

(define-read-only (get-crisis (crisis-id uint))
  (map-get? crises crisis-id)
)

(define-read-only (get-oracle-crisis-vote (crisis-id uint) (oracle principal))
  (map-get? oracle-crisis-votes { crisis-id: crisis-id, oracle: oracle })
)

(define-read-only (get-next-crisis-id)
  (var-get next-crisis-id)
)

;; -- Proposal queries --

(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals proposal-id)
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
  (map-get? proposal-votes { proposal-id: proposal-id, voter: voter })
)

(define-read-only (get-next-proposal-id)
  (var-get next-proposal-id)
)

;; Returns live result metrics for a proposal
(define-read-only (get-proposal-result (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal
      (ok {
        yes-votes:    (get yes-votes proposal),
        no-votes:     (get no-votes proposal),
        total-weight: (get total-weight proposal),
        yes-pct:      (calculate-percentage
                        (get yes-votes proposal)
                        (get total-weight proposal)
                      ),
        status:       (get status proposal),
        executed:     (get executed proposal)
      })
    ERR-PROPOSAL-NOT-FOUND
  )
)

(define-read-only (is-proposal-active (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal
      (and
        (is-eq (get status proposal) PROPOSAL-ACTIVE)
        (<= stacks-block-height (get vote-end proposal))
      )
    false
  )
)

(define-read-only (is-proposal-passed (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal (is-eq (get status proposal) PROPOSAL-PASSED)
    false
  )
)

;; -- Oracle / voter queries --

(define-read-only (get-oracle-info (oracle principal))
  (map-get? oracles oracle)
)

(define-read-only (get-voter-info (voter principal))
  (map-get? voters voter)
)

(define-read-only (is-oracle (addr principal))
  (is-registered-oracle addr)
)

(define-read-only (is-voter (addr principal))
  (is-registered-voter addr)
)

(define-read-only (get-oracle-count)
  (var-get oracle-count)
)

(define-read-only (get-voter-count)
  (var-get voter-count)
)

;; -- Governance parameter queries --

(define-read-only (get-voting-window)
  VOTING-WINDOW
)

(define-read-only (get-min-oracle-confirmations)
  MIN-ORACLE-CONFIRMATIONS
)

(define-read-only (get-quorum)
  QUORUM
)

(define-read-only (get-threshold)
  THRESHOLD
)

(define-read-only (get-contract-owner)
  CONTRACT-OWNER
)
