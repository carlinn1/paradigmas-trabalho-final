module Api exposing
    ( Difficulty(..)
    , Hint
    , difficultyLabel
    , generate
    , hint
    , solve
    , variantLabel
    )

{-| Comunicação com o backend (FastAPI + Prolog).

Em Elm, uma requisição HTTP não "acontece" quando chamamos uma função. As
funções deste módulo devolvem um `Cmd msg`: uma DESCRIÇÃO do efeito que
queremos. Quem executa o efeito é o runtime do Elm; quando a resposta chega,
ele chama nosso `update` com a mensagem que indicamos (por exemplo,
`GotPuzzle resultado`). É assim que o Elm mantém todas as funções puras.

As URLs começam com `/api/...`. Em desenvolvimento, o Vite repassa essas
requisições para o backend em <http://localhost:8000> (veja vite.config.js).

-}

import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Sudoku exposing (Board, Variant(..))


type Difficulty
    = Easy
    | Medium
    | Hard


difficultyLabel : Difficulty -> String
difficultyLabel difficulty =
    case difficulty of
        Easy ->
            "Fácil"

        Medium ->
            "Médio"

        Hard ->
            "Difícil"


{-| Nome usado pela API (e pelo Prolog: são os átomos easy/medium/hard).
-}
difficultyToString : Difficulty -> String
difficultyToString difficulty =
    case difficulty of
        Easy ->
            "easy"

        Medium ->
            "medium"

        Hard ->
            "hard"


variantLabel : Variant -> String
variantLabel variant =
    case variant of
        Classic ->
            "Clássico"

        Diagonal ->
            "Diagonal (X)"

        AntiKnight ->
            "Anti-Cavalo"


variantToString : Variant -> String
variantToString variant =
    case variant of
        Classic ->
            "classic"

        Diagonal ->
            "diagonal"

        AntiKnight ->
            "anti_knight"


{-| Um _record_ (registro): um conjunto de campos com nome. O `type alias`
também cria automaticamente uma função construtora `Hint : Int -> Int -> Int
-> Hint`, que usamos no decoder abaixo.
-}
type alias Hint =
    { row : Int
    , col : Int
    , value : Int
    }



-- REQUISIÇÕES
--
-- Todas recebem uma função `toMsg` que diz como embrulhar o resultado numa
-- mensagem. `Result String a` é: ou `Ok valor`, ou `Err mensagemDeErro`.


generate : Variant -> Difficulty -> (Result String Board -> msg) -> Cmd msg
generate variant difficulty toMsg =
    Http.post
        { url = "/api/generate"
        , body =
            Http.jsonBody
                (Encode.object
                    [ ( "variant", Encode.string (variantToString variant) )
                    , ( "difficulty", Encode.string (difficultyToString difficulty) )
                    ]
                )
        , expect = expectJson toMsg boardDecoder
        }


solve : Variant -> Board -> (Result String Board -> msg) -> Cmd msg
solve variant board toMsg =
    Http.post
        { url = "/api/solve"
        , body = Http.jsonBody (encodeBoardRequest variant board)
        , expect = expectJson toMsg boardDecoder
        }


hint : Variant -> Board -> (Result String Hint -> msg) -> Cmd msg
hint variant board toMsg =
    Http.post
        { url = "/api/hint"
        , body = Http.jsonBody (encodeBoardRequest variant board)
        , expect = expectJson toMsg hintDecoder
        }



-- JSON
--
-- Elm não converte JSON em valores "magicamente". Escrevemos DECODERS, que
-- descrevem a forma esperada do JSON. Se o JSON vier diferente, a decodificação
-- falha com uma mensagem de erro, em vez de gerar um valor inválido.


{-| Envia `{"variant": "...", "board": [[5,3,0,...], ...]}`.
-}
encodeBoardRequest : Variant -> Board -> Encode.Value
encodeBoardRequest variant board =
    Encode.object
        [ ( "variant", Encode.string (variantToString variant) )
        , ( "board", Encode.list (Encode.list Encode.int) (Sudoku.toLists board) )
        ]


{-| Lê `{"board": [[...], ...]}`. Decoders se combinam como peças de Lego:
`Decode.list (Decode.list Decode.int)` é "uma lista de listas de inteiros".
-}
boardDecoder : Decoder Board
boardDecoder =
    Decode.field "board" (Decode.list (Decode.list Decode.int))
        |> Decode.map Sudoku.fromLists


{-| `Decode.map3` junta três decoders e passa os três resultados para a
função `Hint` (o construtor do record).
-}
hintDecoder : Decoder Hint
hintDecoder =
    Decode.map3 Hint
        (Decode.field "row" Decode.int)
        (Decode.field "col" Decode.int)
        (Decode.field "value" Decode.int)



-- TRATAMENTO DE ERROS
--
-- `Http.expectJson` já existe, mas quando o servidor responde com erro (ex.:
-- 422) ele descarta o corpo da resposta. Nosso backend manda uma mensagem útil
-- em `{"detail": "..."}`, então escrevemos nossa própria versão, que olha o
-- corpo e devolve sempre um `Result String a` com mensagens em português.


expectJson : (Result String a -> msg) -> Decoder a -> Http.Expect msg
expectJson toMsg decoder =
    Http.expectStringResponse toMsg <|
        \response ->
            case response of
                Http.GoodStatus_ _ body ->
                    Decode.decodeString decoder body
                        |> Result.mapError (\_ -> "Resposta inesperada do servidor.")

                Http.BadStatus_ metadata body ->
                    Err (errorDetail metadata.statusCode body)

                Http.BadUrl_ url ->
                    Err ("URL inválida: " ++ url)

                Http.Timeout_ ->
                    Err "O servidor demorou demais para responder."

                Http.NetworkError_ ->
                    Err "Não foi possível falar com o servidor. O backend está rodando?"


{-| Tenta extrair o campo `detail` (quando ele é uma string). Se não der,
monta uma mensagem genérica com o código HTTP.
-}
errorDetail : Int -> String -> String
errorDetail status body =
    case Decode.decodeString (Decode.field "detail" Decode.string) body of
        Ok detail ->
            detail

        Err _ ->
            "Erro no servidor (código " ++ String.fromInt status ++ ")."
