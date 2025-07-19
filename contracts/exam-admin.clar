;; Exam Administration Contract
;; Manages certification test delivery and scheduling

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-EXAM-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-REGISTERED (err u102))
(define-constant ERR-EXAM-FULL (err u103))
(define-constant ERR-INVALID-DATE (err u104))
(define-constant ERR-EXAM-COMPLETED (err u105))

;; Data Variables
(define-data-var next-exam-id uint u1)
(define-data-var next-registration-id uint u1)

;; Data Maps
(define-map exams
  { exam-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    max-participants: uint,
    current-participants: uint,
    exam-date: uint,
    duration-minutes: uint,
    passing-score: uint,
    is-active: bool,
    created-by: principal
  }
)

(define-map exam-registrations
  { registration-id: uint }
  {
    exam-id: uint,
    participant: principal,
    registration-date: uint,
    status: (string-ascii 20),
    score: (optional uint),
    completed-at: (optional uint)
  }
)

(define-map participant-exams
  { participant: principal, exam-id: uint }
  { registration-id: uint, attempts: uint }
)

;; Read-only functions
(define-read-only (get-exam (exam-id uint))
  (map-get? exams { exam-id: exam-id })
)

(define-read-only (get-registration (registration-id uint))
  (map-get? exam-registrations { registration-id: registration-id })
)

(define-read-only (get-participant-exam-info (participant principal) (exam-id uint))
  (map-get? participant-exams { participant: participant, exam-id: exam-id })
)

(define-read-only (is-exam-available (exam-id uint))
  (match (map-get? exams { exam-id: exam-id })
    exam-data (and
      (get is-active exam-data)
      (< (get current-participants exam-data) (get max-participants exam-data))
      (> (get exam-date exam-data) block-height)
    )
    false
  )
)

;; Public functions
(define-public (create-exam
  (title (string-ascii 100))
  (description (string-ascii 500))
  (max-participants uint)
  (exam-date uint)
  (duration-minutes uint)
  (passing-score uint)
)
  (let ((exam-id (var-get next-exam-id)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> exam-date block-height) ERR-INVALID-DATE)
    (asserts! (and (> passing-score u0) (<= passing-score u100)) ERR-INVALID-DATE)

    (map-set exams
      { exam-id: exam-id }
      {
        title: title,
        description: description,
        max-participants: max-participants,
        current-participants: u0,
        exam-date: exam-date,
        duration-minutes: duration-minutes,
        passing-score: passing-score,
        is-active: true,
        created-by: tx-sender
      }
    )

    (var-set next-exam-id (+ exam-id u1))
    (ok exam-id)
  )
)

(define-public (register-for-exam (exam-id uint))
  (let (
    (registration-id (var-get next-registration-id))
    (exam-data (unwrap! (map-get? exams { exam-id: exam-id }) ERR-EXAM-NOT-FOUND))
  )
    (asserts! (is-exam-available exam-id) ERR-EXAM-FULL)
    (asserts! (is-none (map-get? participant-exams { participant: tx-sender, exam-id: exam-id })) ERR-ALREADY-REGISTERED)

    (map-set exam-registrations
      { registration-id: registration-id }
      {
        exam-id: exam-id,
        participant: tx-sender,
        registration-date: block-height,
        status: "registered",
        score: none,
        completed-at: none
      }
    )

    (map-set participant-exams
      { participant: tx-sender, exam-id: exam-id }
      { registration-id: registration-id, attempts: u1 }
    )

    (map-set exams
      { exam-id: exam-id }
      (merge exam-data { current-participants: (+ (get current-participants exam-data) u1) })
    )

    (var-set next-registration-id (+ registration-id u1))
    (ok registration-id)
  )
)

(define-public (submit-exam-score (registration-id uint) (score uint))
  (let ((registration-data (unwrap! (map-get? exam-registrations { registration-id: registration-id }) ERR-EXAM-NOT-FOUND)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status registration-data) "registered") ERR-EXAM-COMPLETED)
    (asserts! (<= score u100) ERR-INVALID-DATE)

    (map-set exam-registrations
      { registration-id: registration-id }
      (merge registration-data {
        score: (some score),
        status: "completed",
        completed-at: (some block-height)
      })
    )

    (ok true)
  )
)

(define-public (deactivate-exam (exam-id uint))
  (let ((exam-data (unwrap! (map-get? exams { exam-id: exam-id }) ERR-EXAM-NOT-FOUND)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set exams
      { exam-id: exam-id }
      (merge exam-data { is-active: false })
    )

    (ok true)
  )
)
