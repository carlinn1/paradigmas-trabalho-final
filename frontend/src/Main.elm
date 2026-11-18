module Main exposing (main)

{-| Orquestração da aplicação Sudoku (Arquitetura Elm: init, update, subscriptions).

Os tipos compartilhados vivem em `Types`, a lógica pura de tabuleiro em
`Sudoku`, a comunicação HTTP em `Api` e o HTML em `View`.

-}

import Api exposing (Difficulty(..))
import Browser
import Browser.Events
import Json.Decode as Decode exposing (Decoder)
import Sudoku exposing (Board, Cell(..), Position, Variant(..))
import Time
import Types exposing (Flags, InputMode(..), Model, Msg(..), Status(..))
import View


main : Program Flags Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = View.view
        , subscriptions = subscriptions
        }


init : Flags -> ( Model, Cmd Msg )
init flags =
    ( { board = Sudoku.empty
      , history = []
      , selected = Nothing
      , variant = Classic
      , difficulty = Medium
      , mode = Numbers
      , darkTheme = flags.darkTheme
      , status = Loading
      , elapsedSeconds = 0
      , hintsUsed = 0
      }
    , Api.generate Classic Medium GotPuzzle
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NewGame variant difficulty ->
            ( { model
                | variant = variant
                , difficulty = difficulty
                , history = []
                , status = Loading
                , elapsedSeconds = 0
                , hintsUsed = 0
              }
            , Api.generate variant difficulty GotPuzzle
            )

        GotPuzzle (Ok board) ->
            ( { model
                | board = board
                , history = []
                , selected = Nothing
                , status = Ready
                , elapsedSeconds = 0
                , hintsUsed = 0
              }
            , Cmd.none
            )

        GotPuzzle (Err error) ->
            ( { model | status = Failed error }, Cmd.none )

        CellClicked position ->
            ( { model | selected = Just position }, Cmd.none )

        NumberPressed n ->
            case model.mode of
                Numbers ->
                    ( applyBoardChange (placeNumber model.variant (Guess n) n) model, Cmd.none )

                CornerMarks ->
                    ( applyBoardChange (\position -> Sudoku.toggleMark position n) model, Cmd.none )

        ErasePressed ->
            ( applyBoardChange (\position -> Sudoku.setCell position Empty) model, Cmd.none )

        UndoPressed ->
            case model.history of
                previous :: older ->
                    ( { model | board = previous, history = older }, Cmd.none )

                [] ->
                    ( model, Cmd.none )

        ModeToggled ->
            let
                newMode =
                    case model.mode of
                        Numbers ->
                            CornerMarks

                        CornerMarks ->
                            Numbers
            in
            ( { model | mode = newMode }, Cmd.none )

        ThemeToggled dark ->
            ( { model | darkTheme = dark }, Cmd.none )

        MoveSelection dRow dCol ->
            let
                move ( row, col ) =
                    ( modBy 9 (row + dRow), modBy 9 (col + dCol) )
            in
            ( { model | selected = Just (Maybe.withDefault ( 0, 0 ) (Maybe.map move model.selected)) }
            , Cmd.none
            )

        HintRequested ->
            ( { model | status = Loading }
            , Api.hint model.variant model.board GotHint
            )

        GotHint (Ok { row, col, value }) ->
            let
                nextBoard =
                    placeNumber model.variant (Revealed value) value ( row, col ) model.board
            in
            ( { model
                | board = nextBoard
                , history = pushHistory model.board nextBoard model.history
                , selected = Just ( row, col )
                , status = Ready
                , hintsUsed = model.hintsUsed + 1
              }
            , Cmd.none
            )

        GotHint (Err error) ->
            ( { model | status = Failed error }, Cmd.none )

        SolveRequested ->
            ( { model | status = Loading }
            , Api.solve model.variant (Sudoku.clearGuesses model.board) GotSolution
            )

        GotSolution (Ok solution) ->
            let
                nextBoard =
                    Sudoku.revealSolution solution model.board
            in
            ( { model
                | board = nextBoard
                , history = pushHistory model.board nextBoard model.history
                , status = Ready
              }
            , Cmd.none
            )

        GotSolution (Err error) ->
            ( { model | status = Failed error }, Cmd.none )

        ResetRequested ->
            let
                nextBoard =
                    Sudoku.clearGuesses model.board
            in
            ( { model
                | board = nextBoard
                , history = pushHistory model.board nextBoard model.history
                , status = Ready
              }
            , Cmd.none
            )

        ErrorDismissed ->
            ( { model | status = Ready }, Cmd.none )

        Tick _ ->
            if model.status == Ready && not (Sudoku.isComplete model.variant model.board) then
                ( { model | elapsedSeconds = model.elapsedSeconds + 1 }, Cmd.none )

            else
                ( model, Cmd.none )


pushHistory : Board -> Board -> List Board -> List Board
pushHistory previous next history =
    if previous == next then
        history

    else
        previous :: history


applyBoardChange : (Position -> Board -> Board) -> Model -> Model
applyBoardChange change model =
    case model.selected of
        Just position ->
            let
                nextBoard =
                    change position model.board
            in
            { model
                | board = nextBoard
                , history = pushHistory model.board nextBoard model.history
            }

        Nothing ->
            model


placeNumber : Variant -> Cell -> Int -> Position -> Board -> Board
placeNumber variant cell n position board =
    if Sudoku.isGiven (Sudoku.cellAt position board) then
        board

    else
        board
            |> Sudoku.setCell position cell
            |> Sudoku.removeMarkFromPeers variant position n



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ Browser.Events.onKeyDown keyDecoder
        , Time.every 1000 Tick
        ]


keyDecoder : Decoder Msg
keyDecoder =
    Decode.field "key" Decode.string
        |> Decode.andThen keyToMsg


keyToMsg : String -> Decoder Msg
keyToMsg key =
    case key of
        "ArrowUp" ->
            Decode.succeed (MoveSelection -1 0)

        "ArrowDown" ->
            Decode.succeed (MoveSelection 1 0)

        "ArrowLeft" ->
            Decode.succeed (MoveSelection 0 -1)

        "ArrowRight" ->
            Decode.succeed (MoveSelection 0 1)

        "Backspace" ->
            Decode.succeed ErasePressed

        "Delete" ->
            Decode.succeed ErasePressed

        "n" ->
            Decode.succeed ModeToggled

        "N" ->
            Decode.succeed ModeToggled

        "z" ->
            Decode.succeed UndoPressed

        "Z" ->
            Decode.succeed UndoPressed

        _ ->
            case String.toInt key of
                Just n ->
                    if n >= 1 && n <= 9 then
                        Decode.succeed (NumberPressed n)

                    else
                        Decode.succeed ErasePressed

                Nothing ->
                    Decode.fail "tecla ignorada"
