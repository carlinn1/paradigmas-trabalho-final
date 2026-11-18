module Types exposing
    ( Flags
    , InputMode(..)
    , Model
    , Msg(..)
    , Status(..)
    , isLoading
    )

{-| Tipos centrais da aplicação Elm (Model, Msg, Status e InputMode).

Separar estes tipos em um módulo próprio evita dependências circulares
entre `Main` (orquestração) e `View` (interface) e garante que estados
inválidos não possam ser representados.

-}

import Api exposing (Difficulty)
import Sudoku exposing (Board, Position, Variant)
import Time


type alias Flags =
    { darkTheme : Bool
    }


{-| Estado da comunicação com o backend Prolog.

Substitui o par `loading : Bool` + `error : Maybe String`: assim não é
possível estar carregando e exibindo um erro antigo ao mesmo tempo.

-}
type Status
    = Loading
    | Ready
    | Failed String


type InputMode
    = Numbers
    | CornerMarks


type alias Model =
    { board : Board
    , history : List Board
    , selected : Maybe Position
    , variant : Variant
    , difficulty : Difficulty
    , mode : InputMode
    , darkTheme : Bool
    , status : Status
    , elapsedSeconds : Int
    , hintsUsed : Int
    }


type Msg
    = NewGame Variant Difficulty
    | GotPuzzle (Result String Board)
    | CellClicked Position
    | NumberPressed Int
    | ErasePressed
    | UndoPressed
    | ModeToggled
    | ThemeToggled Bool
    | MoveSelection Int Int
    | HintRequested
    | GotHint (Result String Api.Hint)
    | SolveRequested
    | GotSolution (Result String Board)
    | ResetRequested
    | ErrorDismissed
    | Tick Time.Posix


isLoading : Status -> Bool
isLoading status =
    case status of
        Loading ->
            True

        _ ->
            False
