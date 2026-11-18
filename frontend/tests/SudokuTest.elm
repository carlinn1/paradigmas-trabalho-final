module SudokuTest exposing (suite)

import Expect
import Set
import Sudoku exposing (Cell(..), Variant(..))
import Test exposing (Test, describe, test)


sampleBoard : Sudoku.Board
sampleBoard =
    Sudoku.fromLists
        [ [ 5, 3, 0, 0, 7, 0, 0, 0, 0 ]
        , [ 6, 0, 0, 1, 9, 5, 0, 0, 0 ]
        , [ 0, 9, 8, 0, 0, 0, 0, 6, 0 ]
        , [ 8, 0, 0, 0, 6, 0, 0, 0, 3 ]
        , [ 4, 0, 0, 8, 0, 3, 0, 0, 1 ]
        , [ 7, 0, 0, 0, 2, 0, 0, 0, 6 ]
        , [ 0, 6, 0, 0, 0, 0, 2, 8, 0 ]
        , [ 0, 0, 0, 4, 1, 9, 0, 0, 5 ]
        , [ 0, 0, 0, 0, 8, 0, 0, 7, 9 ]
        ]


suite : Test
suite =
    describe "Sudoku domain"
        [ describe "peers and variants"
            [ test "Classic does not treat main diagonal across boxes as peers" <|
                \_ ->
                    Sudoku.peers Classic ( 0, 0 ) ( 4, 4 )
                        |> Expect.equal False
            , test "Diagonal treats main diagonal and anti-diagonal cells as peers" <|
                \_ ->
                    ( Sudoku.peers Diagonal ( 0, 0 ) ( 4, 4 )
                    , Sudoku.peers Diagonal ( 0, 8 ) ( 4, 4 )
                    )
                        |> Expect.equal ( True, True )
            , test "AntiKnight treats knight-move cells as peers" <|
                \_ ->
                    ( Sudoku.peers AntiKnight ( 0, 1 ) ( 1, 3 )
                    , Sudoku.peers AntiKnight ( 0, 1 ) ( 2, 2 )
                    )
                        |> Expect.equal ( True, True )
            ]
        , describe "conflicts"
            [ test "detects row/column conflicts in Classic" <|
                \_ ->
                    Sudoku.empty
                        |> Sudoku.setCell ( 0, 0 ) (Guess 5)
                        |> Sudoku.setCell ( 0, 4 ) (Guess 5)
                        |> Sudoku.conflicts Classic
                        |> Expect.equal (Set.fromList [ ( 0, 0 ), ( 0, 4 ) ])
            , test "detects diagonal conflict only in Diagonal variant" <|
                \_ ->
                    let
                        board =
                            Sudoku.empty
                                |> Sudoku.setCell ( 0, 0 ) (Guess 5)
                                |> Sudoku.setCell ( 4, 4 ) (Guess 5)
                    in
                    ( Set.isEmpty (Sudoku.conflicts Classic board)
                    , Sudoku.conflicts Diagonal board
                    )
                        |> Expect.equal ( True, Set.fromList [ ( 0, 0 ), ( 4, 4 ) ] )
            , test "detects knight-move conflict only in AntiKnight variant" <|
                \_ ->
                    let
                        board =
                            Sudoku.empty
                                |> Sudoku.setCell ( 0, 1 ) (Guess 5)
                                |> Sudoku.setCell ( 1, 3 ) (Guess 5)
                    in
                    ( Set.isEmpty (Sudoku.conflicts Classic board)
                    , Sudoku.conflicts AntiKnight board
                    )
                        |> Expect.equal ( True, Set.fromList [ ( 0, 1 ), ( 1, 3 ) ] )
            ]
        , describe "board mutations"
            [ test "setCell protects Given clues" <|
                \_ ->
                    sampleBoard
                        |> Sudoku.setCell ( 0, 0 ) (Guess 9)
                        |> Sudoku.cellAt ( 0, 0 )
                        |> Expect.equal (Given 5)
            , test "toggleMark adds and removes marks cleanly" <|
                \_ ->
                    Sudoku.empty
                        |> Sudoku.toggleMark ( 0, 0 ) 4
                        |> Sudoku.toggleMark ( 0, 0 ) 7
                        |> Sudoku.toggleMark ( 0, 0 ) 4
                        |> Sudoku.cellAt ( 0, 0 )
                        |> Expect.equal (Marks (Set.singleton 7))
            , test "removeMarkFromPeers clears marks on variant peers" <|
                \_ ->
                    Sudoku.empty
                        |> Sudoku.toggleMark ( 4, 4 ) 5
                        |> Sudoku.removeMarkFromPeers Diagonal ( 0, 0 ) 5
                        |> Sudoku.cellAt ( 4, 4 )
                        |> Expect.equal Empty
            , test "clearGuesses preserves Given and clears user guesses" <|
                \_ ->
                    sampleBoard
                        |> Sudoku.setCell ( 0, 2 ) (Guess 4)
                        |> Sudoku.clearGuesses
                        |> Sudoku.cellAt ( 0, 2 )
                        |> Expect.equal Empty
            ]
        ]
