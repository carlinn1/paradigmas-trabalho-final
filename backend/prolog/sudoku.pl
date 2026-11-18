/*  sudoku.pl: Resolução e geração de puzzles de Sudoku em Prolog.

    Este é o "cérebro" do sistema. Todo o raciocínio sobre Sudoku acontece
    aqui; o Python apenas repassa os pedidos HTTP para estes predicados.

    REPRESENTAÇÃO
    -------------
    Um tabuleiro é uma lista com 9 linhas; cada linha é uma lista com 9
    inteiros. O número 0 representa uma casa vazia:

        [[5,3,0, 0,7,0, 0,0,0],
         [6,0,0, 1,9,5, 0,0,0],
         ...]

    Essa é exatamente a forma que o Python (via janus) envia e recebe: uma
    lista de listas do Python vira uma lista de listas do Prolog.

    A IDEIA CENTRAL: PROGRAMAÇÃO POR RESTRIÇÕES
    -------------------------------------------
    Em vez de escrever um algoritmo de busca "na mão" (backtracking com
    laços, como faríamos em Python ou C), usamos a biblioteca CLP(FD)
    (Constraint Logic Programming over Finite Domains). Nós apenas
    DECLARAMOS o que é um Sudoku válido:

        * cada casa contém um número entre 1 e 9;
        * os números de cada linha são todos diferentes;
        * os números de cada coluna são todos diferentes;
        * os números de cada bloco 3x3 são todos diferentes.

    O resolvedor de restrições se encarrega de encontrar valores que
    satisfazem tudo isso. Esse é o espírito do paradigma lógico/declarativo:
    descrevemos O QUE é uma solução, não COMO encontrá-la.

    COMO TESTAR NO TERMINAL
    -----------------------
        $ swipl backend/prolog/sudoku.pl
        ?- example_puzzle(P), solve(P, S), print_grid(S).
        ?- generate(medium, P), print_grid(P).
*/

% Um módulo define quais predicados são "públicos" (exportados). Os demais
% ficam privados ao arquivo. A notação nome/N indica o nome do predicado e
% sua aridade (número de argumentos): solve/2 recebe 2 argumentos.
:- module(sudoku,
          [ solve/2,             % +Puzzle, -Solution
            solve/3,             % +Variant, +Puzzle, -Solution
            count_solutions/3,   % +Puzzle, +Limit, -Count
            count_solutions/4,   % +Variant, +Puzzle, +Limit, -Count
            generate/2,          % +Difficulty, -Puzzle
            generate/3,          % +Variant, +Difficulty, -Puzzle
            hint/2,              % +Board, -Result
            hint/3,              % +Variant, +Board, -Result
            example_puzzle/1,    % -Puzzle
            print_grid/1         % +Grid
          ]).

% Convenção de documentação usada acima e abaixo:
%   +Arg  : argumento de entrada (deve chegar instanciado)
%   -Arg  : argumento de saída (o predicado vai instanciá-lo)
%   ?Arg  : pode ser entrada ou saída

:- use_module(library(clpfd)).    % restrições sobre inteiros: ins, #=, all_distinct...
:- use_module(library(lists)).    % append/2, nth0/3, sum_list/2...
:- use_module(library(apply)).    % maplist/2..N, foldl/4...
:- use_module(library(random)).   % random_permutation/2, random_member/2
:- use_module(library(solution_sequences)).  % limit/2


/* =========================================================================
   1. AS REGRAS DO SUDOKU (restrições)
   ========================================================================= */

%!  sudoku_constraints(+Variant, ?Rows) is det.
%
%   Impõe sobre Rows as regras do Sudoku para a variante escolhida:
%   - classic: linhas, colunas e blocos 3x3;
%   - diagonal: além das regras clássicas, as duas diagonais principais;
%   - anti_knight: além das regras clássicas, casas a um salto de cavalo
%     não podem repetir números.
sudoku_constraints(Rows) :-
    sudoku_constraints(classic, Rows).

sudoku_constraints(Variant, Rows) :-
    must_be(oneof([classic, diagonal, anti_knight]), Variant),
    length(Rows, 9),
    maplist(same_length(Rows), Rows),
    append(Rows, Cells),
    Cells ins 1..9,
    maplist(all_distinct, Rows),
    transpose(Rows, Columns),
    maplist(all_distinct, Columns),
    Rows = [R1, R2, R3, R4, R5, R6, R7, R8, R9],
    blocks(R1, R2, R3),
    blocks(R4, R5, R6),
    blocks(R7, R8, R9),
    variant_constraints(Variant, Rows).

variant_constraints(classic, _Rows).
variant_constraints(diagonal, Rows) :-
    main_diagonal(Rows, 0, MainDiag),
    anti_diagonal(Rows, 8, AntiDiag),
    all_distinct(MainDiag),
    all_distinct(AntiDiag).
variant_constraints(anti_knight, Rows) :-
    knight_constraints(Rows, Rows, 0).

main_diagonal([], _, []).
main_diagonal([Row | Rows], I, [Cell | Cells]) :-
    nth0(I, Row, Cell),
    I1 is I + 1,
    main_diagonal(Rows, I1, Cells).

anti_diagonal([], _, []).
anti_diagonal([Row | Rows], I, [Cell | Cells]) :-
    nth0(I, Row, Cell),
    I1 is I - 1,
    anti_diagonal(Rows, I1, Cells).

knight_constraints([], _, _).
knight_constraints([Row | Rows], AllRows, R) :-
    knight_row_constraints(Row, AllRows, R, 0),
    R1 is R + 1,
    knight_constraints(Rows, AllRows, R1).

knight_row_constraints([], _, _, _).
knight_row_constraints([Cell | Cells], AllRows, R, C) :-
    knight_offsets(Offsets),
    apply_knight_offsets(Offsets, Cell, AllRows, R, C),
    C1 is C + 1,
    knight_row_constraints(Cells, AllRows, R, C1).

knight_offsets([1-2, 1-(-2), 2-1, 2-(-1)]).

apply_knight_offsets([], _, _, _, _).
apply_knight_offsets([DR-DC | Rest], Cell, AllRows, R, C) :-
    R2 is R + DR,
    C2 is C + DC,
    (   R2 >= 0, R2 < 9, C2 >= 0, C2 < 9
    ->  nth0(R2, AllRows, TargetRow),
        nth0(C2, TargetRow, TargetCell),
        Cell #\= TargetCell
    ;   true
    ),
    apply_knight_offsets(Rest, Cell, AllRows, R, C).

%!  blocks(?RowA, ?RowB, ?RowC) is det.
%
%   Recebe três linhas consecutivas e impõe all_distinct em cada um dos três
%   blocos 3x3 formados por elas. Funciona por recursão: consome as 3
%   primeiras colunas de cada linha, e chama a si mesmo com o resto.
blocks([], [], []).                       % caso base: linhas consumidas
blocks([A1, A2, A3 | As],
       [B1, B2, B3 | Bs],
       [C1, C2, C3 | Cs]) :-
    % A notação [X, Y | Resto] separa os primeiros elementos da cauda.
    all_distinct([A1, A2, A3, B1, B2, B3, C1, C2, C3]),
    blocks(As, Bs, Cs).


/* =========================================================================
   2. CONVERSÃO ENTRE "0 = vazio" E VARIÁVEIS LÓGICAS
   ========================================================================= */

%!  grid_vars(+Grid, -Vars) is det.
%
%   Troca cada 0 do tabuleiro por uma variável lógica nova (livre), e
%   mantém os demais números. Exemplo:
%
%       ?- grid_vars([[5,0,3]], V).
%       V = [[5, _A, 3]].
%
%   Usamos maplist/3 duas vezes, aninhado: o de fora percorre as linhas, e
%   `maplist(cell_var)` (uma "aplicação parcial") percorre as casas.
grid_vars(Grid, Vars) :-
    maplist(maplist(cell_var), Grid, Vars).

%   cell_var(+Number, -Var)
%   O "!" (corte / cut) impede que o Prolog tente a segunda cláusula quando
%   a primeira já casou. Sem ele, cell_var(0, X) também poderia responder
%   X = 0 no backtracking, o que estaria errado.
cell_var(0, _Fresh) :- !.
cell_var(N, N).


/* =========================================================================
   3. RESOLVER
   ========================================================================= */

%!  solve(+Puzzle, -Solution) is semidet.
%!  solve(+Variant, +Puzzle, -Solution) is semidet.
%
%   Solution é uma solução de Puzzle na variante especificada. Falha se o
%   puzzle não tiver solução.
solve(Puzzle, Solution) :-
    solve(classic, Puzzle, Solution).

solve(Variant, Puzzle, Solution) :-
    grid_vars(Puzzle, Solution),
    sudoku_constraints(Variant, Solution),
    append(Solution, Cells),
    labeling([ff], Cells),
    !.

%!  count_solutions(+Puzzle, +Limit, -Count) is det.
%!  count_solutions(+Variant, +Puzzle, +Limit, -Count) is det.
%
%   Count é o número de soluções de Puzzle na variante, contando no máximo
%   até Limit.
count_solutions(Puzzle, Limit, Count) :-
    count_solutions(classic, Puzzle, Limit, Count).

count_solutions(Variant, Puzzle, Limit, Count) :-
    grid_vars(Puzzle, Rows),
    append(Rows, Cells),
    findall(x,
            limit(Limit, ( sudoku_constraints(Variant, Rows),
                           labeling([ff], Cells) )),
            Found),
    length(Found, Count).

unique_solution(Variant, Puzzle) :-
    count_solutions(Variant, Puzzle, 2, 1).


/* =========================================================================
   4. GERADOR
   =========================================================================

   Algoritmo em duas etapas:

   (a) Gerar um tabuleiro COMPLETO e aleatório. Usamos o mesmo modelo de
       restrições, mas com uma rotina de labeling que testa os valores em
       ordem aleatória. Assim, cada execução produz uma grade diferente.

   (b) "Cavar buracos": percorremos as 81 casas em ordem aleatória e
       tentamos apagar cada uma. Se o puzzle continua com solução única,
       a remoção é mantida; caso contrário, devolvemos o número. Paramos
       quando o número de pistas (casas preenchidas) chega ao alvo da
       dificuldade escolhida.

   Essa estratégia gulosa nem sempre consegue chegar a poucas pistas (o
   mínimo teórico é 17), mas para ~24 ou mais funciona bem e é rápida.
*/

%!  difficulty_clues(?Difficulty, ?Clues) is nondet.
%
%   Fatos: quantas pistas deixar em cada nível. Ajuste à vontade!
difficulty_clues(easy,   40).
difficulty_clues(medium, 32).
difficulty_clues(hard,   26).

%!  generate(+Difficulty, -Puzzle) is det.
%!  generate(+Variant, +Difficulty, -Puzzle) is det.
generate(Difficulty, Puzzle) :-
    generate(classic, Difficulty, Puzzle).

generate(Variant, Difficulty, Puzzle) :-
    must_be(oneof([classic, diagonal, anti_knight]), Variant),
    must_be(oneof([easy, medium, hard]), Difficulty),
    difficulty_clues(Difficulty, Target),
    random_full_grid(Variant, Full),
    numlist(0, 80, Indexes),
    random_permutation(Indexes, Order),
    append(Full, FlatFull),
    dig_holes(Order, Variant, Target, FlatFull, FlatPuzzle),
    rows_of_9(FlatPuzzle, Puzzle),
    !.

%!  random_full_grid(+Variant, -Grid) is det.
random_full_grid(Variant, Rows) :-
    length(Rows, 9),
    sudoku_constraints(Variant, Rows),
    append(Rows, Cells),
    random_labeling(Cells),
    !.

%!  random_labeling(+Vars) is nondet.
%
%   Versão caseira de label/1 que tenta os valores de cada variável em ordem
%   aleatória. Graças à propagação do CLP(FD), raramente precisa voltar
%   atrás (backtrack) em um tabuleiro vazio.
random_labeling([]).
random_labeling([Var | Vars]) :-
    % Construção "Se -> Então ; Senão" do Prolog.
    (   integer(Var)
    ->  true                              % já foi determinada pela propagação
    ;   fd_dom(Var, Domain),              % ex.: Domain = 1..3\/7..9

        % Enumera os valores do domínio numa lista comum, ex.: [1,2,3,7,8,9].
        findall(V, (V in Domain, indomain(V)), Values),
        random_permutation(Values, Shuffled),

        % member/2 é um PONTO DE ESCOLHA: se mais adiante alguma restrição
        % falhar, o Prolog volta aqui e tenta o próximo valor da lista.
        member(Var, Shuffled)
    ),
    random_labeling(Vars).

%!  dig_holes(+Order, +Variant, +Target, +Flat0, -Flat) is det.
dig_holes([], _Variant, _Target, Flat, Flat).
dig_holes([Index | Rest], Variant, Target, Flat0, Flat) :-
    clue_count(Flat0, Clues),
    (   Clues =< Target
    ->  Flat = Flat0
    ;   replace_nth0(Index, Flat0, 0, Candidate),
        rows_of_9(Candidate, CandidateRows),
        (   unique_solution(Variant, CandidateRows)
        ->  Next = Candidate
        ;   Next = Flat0
        ),
        dig_holes(Rest, Variant, Target, Next, Flat)
    ).

%   clue_count(+Flat, -N): quantas casas diferentes de 0.
%   include/3 filtra uma lista (como `filter` em outras linguagens).
%   `\==` significa "não idêntico a".
clue_count(Flat, N) :-
    include(\==(0), Flat, Clues),
    length(Clues, N).

%   replace_nth0(+Index, +List, +Elem, -NewList)
%   NewList é List com o elemento na posição Index trocado por Elem.
%   nth0/4 é versátil: "remove" o elemento de uma posição e nos devolve
%   o resto; chamando de novo com o novo elemento, ele é "inserido".
replace_nth0(Index, List, Elem, NewList) :-
    nth0(Index, List, _Old, Rest),
    nth0(Index, NewList, Elem, Rest).

%   rows_of_9(?Flat, ?Rows): converte entre a lista achatada e 9 linhas.
rows_of_9([], []).
rows_of_9(Flat, [Row | Rows]) :-
    length(Row, 9),
    append(Row, Rest, Flat),   % Flat = Row ++ Rest
    rows_of_9(Rest, Rows).


/* =========================================================================
   5. DICA
   ========================================================================= */

%!  hint(+Board, -Result) is det.
%!  hint(+Variant, +Board, -Result) is det.
%
%   Escolhe a casa vazia mais restrita (menor domínio restante no CLP(FD),
%   heurística MRV / first-fail) e retorna [Row, Col, Value] com base na
%   solução da variante escolhida.
hint(Board, Result) :-
    hint(classic, Board, Result).

hint(Variant, Board, Result) :-
    (   solve(Variant, Board, Solution)
    ->  empty_positions(Board, Empty),
        (   Empty == []
        ->  Result = complete
        ;   best_hint_cell(Variant, Board, Empty, Row-Col),
            nth0(Row, Solution, SolutionRow),
            nth0(Col, SolutionRow, Value),
            Result = [Row, Col, Value]
        )
    ;   Result = unsolvable
    ).

best_hint_cell(Variant, Board, Empty, BestPos) :-
    grid_vars(Board, PropRows),
    sudoku_constraints(Variant, PropRows),
    findall(Size-(R-C),
            ( member(R-C, Empty),
              nth0(R, PropRows, Row),
              nth0(C, Row, Var),
              ( integer(Var) -> Size = 1 ; fd_size(Var, Size) )
            ),
            Scored),
    keysort(Scored, [MinSize-_ | _]),
    findall(Pos, member(MinSize-Pos, Scored), BestCells),
    random_member(BestPos, BestCells).

%   empty_positions(+Board, -Positions): todas as posições Row-Col com 0.
%   findall/3 com um objetivo composto: nth0/3 enumera, por backtracking,
%   cada linha e, dentro dela, cada casa que contém 0.
empty_positions(Board, Positions) :-
    findall(R-C,
            ( nth0(R, Board, Row),
              nth0(C, Row, 0) ),
            Positions).


/* =========================================================================
   6. UTILITÁRIOS PARA USO NO TERMINAL
   ========================================================================= */

%   Um puzzle clássico (da Wikipedia) para experimentar.
example_puzzle([[5,3,0, 0,7,0, 0,0,0],
                [6,0,0, 1,9,5, 0,0,0],
                [0,9,8, 0,0,0, 0,6,0],
                [8,0,0, 0,6,0, 0,0,3],
                [4,0,0, 8,0,3, 0,0,1],
                [7,0,0, 0,2,0, 0,0,6],
                [0,6,0, 0,0,0, 2,8,0],
                [0,0,0, 4,1,9, 0,0,5],
                [0,0,0, 0,8,0, 0,7,9]]).

%   print_grid(+Grid): imprime o tabuleiro de forma legível.
%   forall(Cond, Ação) executa Ação para cada solução de Cond.
print_grid(Grid) :-
    forall(member(Row, Grid),
           ( maplist(format_cell, Row), nl )).

format_cell(0) :- !, write(' .').
format_cell(N) :- format(' ~w', [N]).
