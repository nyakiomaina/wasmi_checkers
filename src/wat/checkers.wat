
(module
    (import "events" "piecemoved"
        (func $notify_piecemoved (param $fromX i32) (param $fromY i32) (param $toX i32) (param $toY i32)))
    (import "events" "piececrowned"
        (func $notify_piececrowned (param $pieceX i32) (param $pieceY i32)))

    (memory $mem 1)
    (global $currentTurn (mut i32) (i32.const 0))

    ;; checkerboard state bit flags:
    ;; 0 = Empty square
    ;; 1 = Black piece
    ;; 2 = Red piece
    ;; 4 = Crowned piece
    (global $BLACK i32 (i32.const 1))
    (global $RED i32 (i32.const 2))
    (global $CROWN i32 (i32.const 4))

    ;; map the checkboard into memory
    (func $indexForPosition (param $x i32) (param $y i32) (result i32)
        (i32.add
            (i32.mul
                (i32.const 8)
                (local.get $y)
            )
            (local.get $x)
        )
    )

    ;; offset = (x + y * 8) * 4
    ;; checkerboard as two-dimensional array visualized in linear memory
    ;; x and y represent coordinates (index, offset) in the array
    ;; 8 is the number of checkboard squares in a row
    ;; 4 is the byte length of a 32-bit integer
    (func $offsetForPosition (param $x i32) (param $y i32) (result i32)
        (i32.mul
            (call $indexForPosition (local.get $x) (local.get $y))
            (i32.const 4)
        )
    )

    ;; check if piece is crowned
    (func $isCrowned (param $piece i32) (result i32)
        (i32.eq
            (i32.and (local.get $piece) (global.get $CROWN))
            (global.get $CROWN)
        )
    )

    ;; check if piece has bit flag for red color
    (func $isRed (param $piece i32) (result i32)
        (i32.eq
            (i32.and (local.get $piece) (global.get $RED))
            (global.get $RED)
        )
    )

    ;; check if piece has bit flag for black color
    (func $isBlack (param $piece i32) (result i32)
        (i32.eq
            (i32.and (local.get $piece) (global.get $BLACK))
            (global.get $BLACK)
        )
    )

    ;; set the bit flag for crowning a piece
    (func $kingMe (param $piece i32) (result i32)
        (i32.or (local.get $piece) (global.get $CROWN))
    )

    ;; unset the bit flag for a crowned piece
    (func $dethrone (param $piece i32) (result i32)
        (i32.and (local.get $piece) (i32.const 3))
    )

    ;; place a piece on a square
    (func $setPiece (param $x i32) (param $y i32) (param $piece i32)
        (i32.store
            (call $offsetForPosition
                (local.get $x)
                (local.get $y)
            )
            (local.get $piece)
        )
    )

    ;; check state of a square, catch out of bounds errors
    (func $getPiece (param $x i32) (param $y i32) (result i32)
        (if (result i32)
            (block (result i32)
                (i32.and
                    (call $inRange
                        (i32.const 0)
                        (i32.const 7)
                        (local.get $x)
                    )
                    (call $inRange
                        (i32.const 0)
                        (i32.const 7)
                        (local.get $y)
                    )
                )
            )
            (then
                (i32.load
                    (call $offsetForPosition
                        (local.get $x)
                        (local.get $y)
                    )
                )
            )
            (else
                (unreachable)
            )
        )
    )

    ;; check row/square boundary
    (func $inRange (param $low i32) (param $high i32) (param $value i32) (result i32)
        (i32.and
            (i32.ge_s (local.get $value) (local.get $low))
            (i32.le_s (local.get $value) (local.get $high))
        )
    )

    ;; get the current turn owner
    (func $getTurnOwner (result i32)
        (global.get $currentTurn)
    )

    ;; change current turn owner
    (func $toggleTurnOwner
        (if (i32.eq (call $getTurnOwner) (i32.const 1))
            (then (call $setTurnOwner (i32.const 2)))
            (else (call $setTurnOwner (i32.const 1)))
        )
    )

    ;; set the current turn owner
    (func $setTurnOwner (param $piece i32)
        (global.set $currentTurn (local.get $piece))
    )

    ;; check who the current turn owner is
    (func $isPlayersTurn (param $player i32) (result i32)
        (i32.ge_s
            (i32.and (local.get $player) (call $getTurnOwner))
            (i32.const 0)
        )
    )

    ;; check if piece is eligible to be crowned
    (func $isCoronal (param $pieceY i32) (param $piece i32) (result i32)
        (i32.or
            (i32.and
                (i32.eq
                    (local.get $pieceY)
                    (i32.const 0)
                )
                (call $isBlack (local.get $piece))
            )
            (i32.and
                (i32.eq
                    (local.get $pieceY)
                    (i32.const 7)
                )
                (call $isRed (local.get $piece))
            )
        )
    )

    ;; do the crowning, notify host
    (func $coronation (param $x i32) (param $y i32)
        (local $piece i32)
        (local.set $piece (call $getPiece (local.get $x) (local.get $y)))
        (call $setPiece (local.get $x) (local.get $y) (call $kingMe (local.get $piece)))

        ;; emit event
        (call $notify_piececrowned (local.get $x) (local.get $y))
    )

    ;; check distance from the piece to the next desired location
    (func $distance (param $x i32) (param $y i32) (result i32)
        (i32.sub (local.get $x) (local.get $y))
    )

    ;; validate the current move
    (func $isValidMove (param $fromX i32) (param $fromY i32) (param $toX i32) (param $toY i32) (result i32)
        (local $player i32)
        (local $target i32)

        (local.set $player (call $getPiece (local.get $fromX) (local.get $fromY)))
        (local.set $target (call $getPiece (local.get $toX) (local.get $toY)))

        (if (result i32)
            (block (result i32)
                (i32.and
                    ;; check valid row
                    (call $validJumpDistance (local.get $fromY) (local.get $toY))
                    (i32.and
                        (call $isPlayersTurn (local.get $player))
                        ;; target must be unoccupied
                        (i32.eq (local.get $target) (i32.const 0))
                    )
                )
            )
            (then
                (i32.const 1)
            )
            (else
                (i32.const 0)
            )
        )
    )

    ;; validate jump distance: rules for 1 or 2 square jumps
    ;; logic evaluates whether result is a negative (signed or unsigned) integer
    (func $validJumpDistance (param $from i32) (param $to i32) (result i32)
        (local $d i32)
        (local.set $d
        (if (result i32)
            (i32.gt_s (local.get $to) (local.get $from))
            (then
                (call $distance (local.get $to) (local.get $from))
            )
            (else
                (call $distance (local.get $from) (local.get $to))
            ))
        )
        (i32.le_u
            (local.get $d)
            (i32.const 2)
        )
    )

    ;; to be run by the game host
    ;; validates the move and defers action to $do_move
    ;; @exported
    (func $move (param $fromX i32) (param $fromY i32) (param $toX i32) (param $toY i32) (result i32)
        (if (result i32)
            (block (result i32)
                (call $isValidMove (local.get $fromX) (local.get $fromY) (local.get $toX) (local.get $toY))
            )
            (then
                (call $do_move (local.get $fromX) (local.get $fromY) (local.get $toX) (local.get $toY))
            )
            (else
                (i32.const 0)
            )
        )
    )

    ;; sony guts of the move function
    (func $do_move (param $fromX i32) (param $fromY i32) (param $toX i32) (param $toY i32) (result i32)
        (local $currentPiece i32)
        (local.set $currentPiece (call $getPiece (local.get $fromX) (local.get $fromY)))

        (call $toggleTurnOwner)
        (call $setPiece (local.get $toX) (local.get $toY) (local.get $currentPiece))
        (call $setPiece (local.get $fromX) (local.get $fromY) (i32.const 0))
        (if (call $isCoronal (local.get $toY) (local.get $currentPiece))
            (then (call $coronation (local.get $toX) (local.get $toY))))
        (call $notify_piecemoved (local.get $fromX) (local.get $fromY) (local.get $toX) (local.get $toY))
        (i32.const 1)
    )

    ;; initialize checkerboard with pieces on their opening positions
    (func $initBoard
        ;; row 0, red pieces
        (call $setPiece (i32.const 1) (i32.const 0) (i32.const 2))
        (call $setPiece (i32.const 3) (i32.const 0) (i32.const 2))
        (call $setPiece (i32.const 5) (i32.const 0) (i32.const 2))
        (call $setPiece (i32.const 7) (i32.const 0) (i32.const 2))

        ;; row 1, red pieces
        (call $setPiece (i32.const 0) (i32.const 1) (i32.const 2))
        (call $setPiece (i32.const 2) (i32.const 1) (i32.const 2))
        (call $setPiece (i32.const 4) (i32.const 1) (i32.const 2))
        (call $setPiece (i32.const 6) (i32.const 1) (i32.const 2))

        ;; row 2, red pieces
        (call $setPiece (i32.const 1) (i32.const 2) (i32.const 2))
        (call $setPiece (i32.const 3) (i32.const 2) (i32.const 2))
        (call $setPiece (i32.const 5) (i32.const 2) (i32.const 2))
        (call $setPiece (i32.const 7) (i32.const 2) (i32.const 2))

        ;; row 3 and 4 are empty

        ;; row 5, black pieces
        (call $setPiece (i32.const 0) (i32.const 5) (i32.const 1))
        (call $setPiece (i32.const 2) (i32.const 5) (i32.const 1))
        (call $setPiece (i32.const 4) (i32.const 5) (i32.const 1))
        (call $setPiece (i32.const 6) (i32.const 5) (i32.const 1))

        ;; row 6, black pieces
        (call $setPiece (i32.const 1) (i32.const 6) (i32.const 1))
        (call $setPiece (i32.const 3) (i32.const 6) (i32.const 1))
        (call $setPiece (i32.const 5) (i32.const 6) (i32.const 1))
        (call $setPiece (i32.const 7) (i32.const 6) (i32.const 1))

        ;; row 7, black pieces
        (call $setPiece (i32.const 0) (i32.const 7) (i32.const 1))
        (call $setPiece (i32.const 2) (i32.const 7) (i32.const 1))
        (call $setPiece (i32.const 4) (i32.const 7) (i32.const 1))
        (call $setPiece (i32.const 6) (i32.const 7) (i32.const 1))

        ;; set first move to black
        (call $setTurnOwner (i32.const 1))
    )


    (export "getPiece" (func $getPiece))
    (export "isCrowned" (func $isCrowned))
    (export "initBoard" (func $initBoard))
    (export "getTurnOwner" (func $getTurnOwner))
    (export "move" (func $move))
    (export "memory" (memory $mem))
)
