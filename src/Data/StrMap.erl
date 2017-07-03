-module(data_strMap@foreign).
-export(['_fmapStrMap'/0, '_foldM'/4, '_foldSCStrMap'/0, all/2, empty/0, size/1, '_lookup'/0, '_collect'/2, keys/1, '_mapWithKey'/0, '_filterWithKey'/0, insert/3, delete/2, '_unsafeDeleteStrMap'/0, union/2, '_append'/3]).

'_fmapStrMap'() -> fun (M,F) -> maps:map(fun (_K,V) -> F(V) end, M) end.
'_foldM'(Bind,F,Mz,M) ->
  G = fun (K, V) -> fun (Z) -> ((F(Z))(K))(V) end end,
  FoldF = fun (K, V, Acc) -> (Bind(Acc))(G(K, V)) end,
  maps:fold(FoldF, Mz, M).

'_foldSCStrMap'() -> fun (M,Z,F,FromMaybe) ->
  FoldF = fun (K, V, {Acc, Abort}) ->
    case Abort of
      abort -> {Acc, abort};
      _ -> begin
        MaybeR = ((F(Acc))(K))(V),
        case (FromMaybe(abort_fold))(MaybeR) of
          abort_fold -> {Acc, abort};
          X -> {X, continue}
        end
      end
    end
  end,
  maps:fold(FoldF, {Z, continue}, M) end.

all(F, M) -> maps:fold(fun (K, V, A) -> A and (F(K))(V) end, true, M).
empty() -> #{}.

% TODO: This will change to int https://github.com/purescript/purescript-maps/pull/88
size(M) -> float(maps:size(M)).
'_lookup'() ->
  fun (Nothing, Just, K, M) ->
    case maps:find(K, M) of
      {ok, V} -> Just(V);
      _ -> Nothing
    end
  end.

% Reverse to preserve "natural ordering" consistent with keys etc.
'_collect'(F,M) -> array:from_list(lists:reverse(maps:fold(fun (K,V,Acc) -> [ (F(K))(V) | Acc ] end, [], M))).
keys(M) -> array:from_list(maps:keys(M)).

'_mapWithKey'() -> fun (M,F) -> maps:map(fun (K, V) -> (F(K))(V) end, M) end.

'_filterWithKey'() -> fun (M,F) -> maps:filter(fun (K, V) -> (F(K))(V) end, M) end.

insert(K,V,M) -> maps:put(K,V,M).

delete(K,M) -> maps:remove(K,M).
'_unsafeDeleteStrMap'() -> fun (M,K) -> maps:remove(K,M) end.
union(M1,M2) -> maps:merge(M2,M1).

'_append'(Append, M1, M2) ->
  maps:fold(fun (K1, V1, M) ->
    maps:update_with(K1, fun (V2) ->
      (Append(V1))(V2)
    end, V1, M)
  end, M2, M1).
