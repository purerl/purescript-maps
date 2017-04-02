-module(data_strMap_unsafe@foreign).
-export([unsafeIndex/2]).

unsafeIndex(M,K) -> maps:get(K, M).
