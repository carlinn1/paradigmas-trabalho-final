module View exposing (view)

{-| Camada de apresentação pura do Sudoku.

Recebe o `Model` imutável e devolve `Html Msg`. Nenhuma regra de negócio ou
efeito HTTP mora aqui.

-}

import Api exposing (Difficulty(..))
import Html exposing (Html, aside, button, div, footer, h1, header, input, label, main_, span, text)
import Html.Attributes exposing (attribute, checked, class, classList, disabled, type_, value)
import Html.Events exposing (onCheck, onClick)
import Set exposing (Set)
import Sudoku exposing (Board, Cell(..), Position, Variant(..))
import Types exposing (InputMode(..), Model, Msg(..), Status(..), isLoading)


view : Model -> Html Msg
view model =
    div
        [ class "app"
        , attribute "data-mode"
            (case model.mode of
                Numbers ->
                    "numbers"

                CornerMarks ->
                    "marks"
            )
        ]
        [ viewHeader model
        , main_ [ class "app-main" ]
            [ div [ class "app-container game" ]
                [ viewBoard model
                , aside [ class "side-panel" ]
                    [ span [ class "panel-label" ] [ text "Variante" ]
                    , viewVariantPicker model
                    , span [ class "panel-label" ] [ text "Dificuldade" ]
                    , viewDifficulty model
                    , div [ class "message-area" ] [ viewMessages model ]
                    , span [ class "panel-label" ] [ text "Números" ]
                    , viewNumberPad model
                    , span [ class "panel-label" ] [ text "Ajuda" ]
                    , viewActions model
                    ]
                ]
            ]
        , footer [ class "app-footer" ]
            [ text "Teclado: "
            , kbd [] [ text "1–9" ]
            , text " coloca, "
            , kbd [] [ text "setas" ]
            , text " movem, "
            , kbd [] [ text "⌫" ]
            , text " apaga, "
            , kbd [] [ text "N" ]
            , text " marcações, "
            , kbd [] [ text "Z" ]
            , text " desfaz."
            ]
        ]


viewHeader : Model -> Html Msg
viewHeader model =
    header [ class "app-header" ]
        [ div [ class "app-container app-header-content" ]
            [ h1 [ class "app-title" ] [ text "Sudoku" ]
            , span [ class "app-subtitle" ] [ text (Api.variantLabel model.variant) ]
            , div [ class "header-stats" ]
                [ span [ class "stat-pill", attribute "aria-label" "Tempo decorrido" ]
                    [ text (formatTime model.elapsedSeconds) ]
                , span [ class "stat-pill", attribute "aria-label" "Dicas usadas" ]
                    [ text ("Dicas: " ++ String.fromInt model.hintsUsed) ]
                ]
            , viewThemeToggle model
            ]
        ]


formatTime : Int -> String
formatTime totalSeconds =
    let
        minutes =
            totalSeconds // 60

        seconds =
            modBy 60 totalSeconds

        pad n =
            if n < 10 then
                "0" ++ String.fromInt n

            else
                String.fromInt n
    in
    pad minutes ++ ":" ++ pad seconds


viewThemeToggle : Model -> Html Msg
viewThemeToggle model =
    label [ class "theme-toggle", attribute "aria-label" "Alternar tema claro/escuro" ]
        [ input
            [ type_ "checkbox"
            , class "theme-controller"
            , value "dark"
            , checked model.darkTheme
            , onCheck ThemeToggled
            ]
            []
        , span [ class "swap-off" ] [ text "☀" ]
        , span [ class "swap-on" ] [ text "☾" ]
        ]


kbd : List (Html.Attribute msg) -> List (Html msg) -> Html msg
kbd =
    Html.node "kbd"


viewVariantPicker : Model -> Html Msg
viewVariantPicker model =
    let
        loading =
            isLoading model.status

        option variant =
            button
                [ class "difficulty-option"
                , classList [ ( "difficulty-option--active", variant == model.variant ) ]
                , disabled loading
                , onClick (NewGame variant model.difficulty)
                ]
                [ text (Api.variantLabel variant) ]
    in
    div [ class "difficulty-picker variant-picker" ]
        (List.map option [ Classic, Diagonal, AntiKnight ])


viewDifficulty : Model -> Html Msg
viewDifficulty model =
    let
        loading =
            isLoading model.status

        option difficulty =
            button
                [ class "difficulty-option"
                , classList [ ( "difficulty-option--active", difficulty == model.difficulty ) ]
                , disabled loading
                , onClick (NewGame model.variant difficulty)
                ]
                [ text (Api.difficultyLabel difficulty) ]
    in
    div [ class "difficulty-picker" ] (List.map option [ Easy, Medium, Hard ])


viewMessages : Model -> Html Msg
viewMessages model =
    case model.status of
        Failed error ->
            div [ class "message message--error" ]
                [ span [] [ text error ]
                , button [ class "message-close", onClick ErrorDismissed ] [ text "✕" ]
                ]

        Loading ->
            div [ class "message message--loading" ]
                [ span [ class "spinner" ] []
                , span [] [ text "O Prolog está pensando..." ]
                ]

        Ready ->
            if Sudoku.isComplete model.variant model.board then
                div [ class "message message--success" ]
                    [ text (completionMessage model) ]

            else
                text ""


completionMessage : Model -> String
completionMessage model =
    let
        revealed =
            Sudoku.positions
                |> List.any (\pos -> Sudoku.isRevealed (Sudoku.cellAt pos model.board))
    in
    if revealed then
        "Resolvido em " ++ formatTime model.elapsedSeconds ++ " (com ajuda do Prolog)."

    else
        "Parabéns! Resolvido em " ++ formatTime model.elapsedSeconds ++ "!"


viewBoard : Model -> Html Msg
viewBoard model =
    let
        conflicts =
            Sudoku.conflicts model.variant model.board
    in
    div
        [ class "board"
        , classList [ ( "board--solved", Sudoku.isComplete model.variant model.board ) ]
        ]
        (List.map (viewCell model conflicts) Sudoku.positions)


viewCell : Model -> Set Position -> Position -> Html Msg
viewCell model conflicts (( row, col ) as position) =
    let
        cell =
            Sudoku.cellAt position model.board

        value =
            Sudoku.valueOf cell

        isRelated =
            case model.selected of
                Just sel ->
                    Sudoku.peers model.variant sel position

                Nothing ->
                    False

        isDiagonal =
            model.variant == Diagonal && Sudoku.isDiagonalCell position

        selectedValue =
            model.selected
                |> Maybe.andThen (\sel -> Sudoku.valueOf (Sudoku.cellAt sel model.board))
    in
    button
        [ class "cell"
        , classList
            [ ( "cell--selected", model.selected == Just position )
            , ( "cell--related", isRelated )
            , ( "cell--diagonal", isDiagonal )
            , ( "cell--same-value", value /= Nothing && value == selectedValue )
            , ( "cell--conflict", Set.member position conflicts )
            , ( "cell--given", Sudoku.isGiven cell )
            , ( "cell--guess", Sudoku.isGuess cell )
            , ( "cell--revealed", Sudoku.isRevealed cell )
            ]
        , attribute "aria-label"
            ("Linha " ++ String.fromInt (row + 1) ++ ", coluna " ++ String.fromInt (col + 1))
        , onClick (CellClicked position)
        ]
        [ case cell of
            Marks marks ->
                viewCornerMarks selectedValue marks

            _ ->
                span [ class "cell-value" ]
                    [ text (Maybe.map String.fromInt value |> Maybe.withDefault "") ]
        ]


viewCornerMarks : Maybe Int -> Set Int -> Html Msg
viewCornerMarks selectedValue marks =
    let
        viewMark n =
            span
                [ class "corner-mark"
                , classList [ ( "corner-mark--highlight", Just n == selectedValue ) ]
                ]
                [ text (String.fromInt n) ]
    in
    div [ class "corner-marks" ] (List.map viewMark (Set.toList marks))


viewNumberPad : Model -> Html Msg
viewNumberPad model =
    let
        marking =
            model.mode == CornerMarks

        noSelection =
            model.selected == Nothing

        numberKey n =
            button
                [ class "number-key"
                , disabled noSelection
                , onClick (NumberPressed n)
                ]
                [ text (String.fromInt n) ]
    in
    div [ class "number-pad" ]
        (List.map numberKey (List.range 1 9)
            ++ [ button [ class "erase-key", disabled noSelection, onClick ErasePressed ] [ text "⌫" ]
               , button
                    [ class "mode-toggle"
                    , classList [ ( "mode-toggle--on", marking ) ]
                    , onClick ModeToggled
                    ]
                    [ text
                        (if marking then
                            "✎ Marcando"

                         else
                            "✎ Marcar"
                        )
                    ]
               ]
        )


viewActions : Model -> Html Msg
viewActions model =
    let
        loading =
            isLoading model.status

        nothingToReveal =
            loading || Sudoku.isComplete model.variant model.board
    in
    div [ class "actions" ]
        [ button [ class "action-button action-button--undo", disabled (loading || List.isEmpty model.history), onClick UndoPressed ] [ text "Desfazer" ]
        , button [ class "action-button action-button--hint", disabled nothingToReveal, onClick HintRequested ] [ text "Dica" ]
        , button [ class "action-button action-button--solve", disabled nothingToReveal, onClick SolveRequested ] [ text "Resolver" ]
        , button [ class "action-button action-button--reset", disabled loading, onClick ResetRequested ] [ text "Limpar" ]
        ]
