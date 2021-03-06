-- | This module defines a type of native maps which
-- | require the keys to be strings.
-- |
-- | To maximize performance, native objects are not wrapped,
-- | and some native code is used even when it's not necessary.

module Data.StrMap
  ( StrMap
  , empty
  , isEmpty
  , size
  , singleton
  , insert
  , lookup
  , toUnfoldable
  , toAscUnfoldable
  , fromFoldable
  , fromFoldableWith
  , delete
  , pop
  , member
  , alter
  , update
  , mapWithKey
  , filterWithKey
  , filterKeys
  , filter
  , keys
  , values
  , union
  , unions
  , isSubmap
  , fold
  , foldMap
  , foldM
  , foldMaybe
  , all
  ) where

import Prelude

import Data.Foldable (class Foldable, foldl, foldr)
import Control.Monad.Eff (Eff, runPure, foreachE)
import Data.Array as A
import Data.Eq (class Eq1)
import Data.Function.Uncurried (Fn2, runFn2, Fn4, runFn4)
import Data.Maybe (Maybe(..), maybe, fromMaybe)
import Data.Monoid (class Monoid, mempty)
import Data.Traversable (class Traversable, traverse)
import Data.Tuple (Tuple(..), fst)
import Data.Unfoldable (class Unfoldable)

-- | `StrMap a` represents a map from `String`s to values of type `a`.
foreign import data StrMap :: Type -> Type

foreign import _fmapStrMap :: forall a b. Fn2 (StrMap a) (a -> b) (StrMap b)

instance functorStrMap :: Functor StrMap where
  map f m = runFn2 _fmapStrMap m f

foreign import _foldM :: forall a m z. (m -> (z -> m) -> m) -> (z -> String -> a -> m) -> m -> StrMap a -> m

-- | Fold the keys and values of a map
fold :: forall a z. (z -> String -> a -> z) -> z -> StrMap a -> z
fold = _foldM ((#))

-- | Fold the keys and values of a map, accumulating values using
-- | some `Monoid`.
foldMap :: forall a m. Monoid m => (String -> a -> m) -> StrMap a -> m
foldMap f = fold (\acc k v -> acc <> f k v) mempty

-- | Fold the keys and values of a map, accumulating values and effects in
-- | some `Monad`.
foldM :: forall a m z. Monad m => (z -> String -> a -> m z) -> z -> StrMap a -> m z
foldM f z = _foldM bind f (pure z)

instance foldableStrMap :: Foldable StrMap where
  foldl f = fold (\z _ -> f z)
  foldr f z m = foldr f z (values m)
  foldMap f = foldMap (const f)

instance traversableStrMap :: Traversable StrMap where
  traverse f ms = fold (\acc k v -> insert k <$> f v <*> acc) (pure empty) ms
  sequence = traverse id

-- Unfortunately the above are not short-circuitable (consider using purescript-machines)
-- so we need special cases:

foreign import _foldSCStrMap :: forall a z. Fn4 (StrMap a) z (z -> String -> a -> Maybe z) (forall b. b -> Maybe b -> b) z

-- | Fold the keys and values of a map.
-- |
-- | This function allows the folding function to terminate the fold early,
-- | using `Maybe`.
foldMaybe :: forall a z. (z -> String -> a -> Maybe z) -> z -> StrMap a -> z
foldMaybe f z m = runFn4 _foldSCStrMap m z f fromMaybe

-- | Test whether all key/value pairs in a `StrMap` satisfy a predicate.
foreign import all :: forall a. (String -> a -> Boolean) -> StrMap a -> Boolean

instance eqStrMap :: Eq a => Eq (StrMap a) where
  eq m1 m2 = (isSubmap m1 m2) && (isSubmap m2 m1)

instance eq1StrMap :: Eq1 StrMap where
  eq1 = eq

-- Internal use
toAscArray :: forall v. StrMap v -> Array (Tuple String v)
toAscArray = toAscUnfoldable

instance ordStrMap :: Ord a => Ord (StrMap a) where
  compare m1 m2 = compare (toAscArray m1) (toAscArray m2)

instance showStrMap :: Show a => Show (StrMap a) where
  show m = "(fromFoldable " <> show (toArray m) <> ")"

-- | An empty map
foreign import empty :: forall a. StrMap a

-- | Test whether one map contains all of the keys and values contained in another map
isSubmap :: forall a. Eq a => StrMap a -> StrMap a -> Boolean
isSubmap m1 m2 = all f m1 where
  f k v = runFn4 _lookup false ((==) v) k m2

-- | Test whether a map is empty
isEmpty :: forall a. StrMap a -> Boolean
isEmpty = all (\_ _ -> false)

-- | Calculate the number of key/value pairs in a map
foreign import size :: forall a. StrMap a -> Int

-- | Create a map with one key/value pair
singleton :: forall a. String -> a -> StrMap a
singleton k v = insert k v empty

foreign import _lookup :: forall a z. Fn4 z (a -> z) String (StrMap a) z

-- | Lookup the value for a key in a map
lookup :: forall a. String -> StrMap a -> Maybe a
lookup = runFn4 _lookup Nothing Just

-- | Test whether a `String` appears as a key in a map
member :: forall a. String -> StrMap a -> Boolean
member = runFn4 _lookup false (const true)

-- | Insert or replace a key/value pair in a map
foreign import insert :: forall a. String -> a -> StrMap a -> StrMap a

foreign import _unsafeDeleteStrMap :: forall a. Fn2 (StrMap a) String (StrMap a)

-- | Delete a key and value from a map
foreign import delete :: forall a. String -> StrMap a -> StrMap a

-- | Delete a key and value from a map, returning the value
-- | as well as the subsequent map
pop :: forall a. String -> StrMap a -> Maybe (Tuple a (StrMap a))
pop k m = lookup k m <#> \a -> Tuple a (delete k m)

-- | Insert, remove or update a value for a key in a map
alter :: forall a. (Maybe a -> Maybe a) -> String -> StrMap a -> StrMap a
alter f k m = case f (k `lookup` m) of
  Nothing -> delete k m
  Just v -> insert k v m

-- | Remove or update a value for a key in a map
update :: forall a. (a -> Maybe a) -> String -> StrMap a -> StrMap a
update f k m = alter (maybe Nothing f) k m

-- | Create a map from a foldable collection of key/value pairs
fromFoldable :: forall f a. Foldable f => f (Tuple String a) -> StrMap a
fromFoldable l = foldl (\m (Tuple k v) -> insert k v m) empty l

-- | Create a map from a foldable collection of key/value pairs, using the
-- | specified function to combine values for duplicate keys.
fromFoldableWith :: forall f a. Foldable f => (a -> a -> a) -> f (Tuple String a) -> StrMap a
fromFoldableWith f l = foldl (\m (Tuple k v) -> insert k (maybe v (f v) $ lookup k m) m) empty l

foreign import _collect :: forall a b . (String -> a -> b) -> StrMap a -> Array b

-- | Unfolds a map into a list of key/value pairs
toUnfoldable :: forall f a. Unfoldable f => StrMap a -> f (Tuple String a)
toUnfoldable = A.toUnfoldable <<< _collect Tuple

-- | Unfolds a map into a list of key/value pairs which is guaranteed to be
-- | sorted by key
toAscUnfoldable :: forall f a. Unfoldable f => StrMap a -> f (Tuple String a)
toAscUnfoldable = A.toUnfoldable <<< A.sortWith fst <<< _collect Tuple

-- Internal
toArray :: forall a. StrMap a -> Array (Tuple String a)
toArray = _collect Tuple

-- | Get an array of the keys in a map
foreign import keys :: forall a. StrMap a -> Array String

-- | Get a list of the values in a map
values :: forall a. StrMap a -> Array a
values = _collect (\_ v -> v)

-- | Compute the union of two maps, preferring the first map in the case of
-- | duplicate keys.
foreign import union :: forall a. StrMap a -> StrMap a -> StrMap a

-- | Compute the union of a collection of maps
unions :: forall f a. Foldable f => f (StrMap a) -> StrMap a
unions = foldl union empty

foreign import _mapWithKey :: forall a b. Fn2 (StrMap a) (String -> a -> b) (StrMap b)

-- | Apply a function of two arguments to each key/value pair, producing a new map
mapWithKey :: forall a b. (String -> a -> b) -> StrMap a -> StrMap b
mapWithKey f m = runFn2 _mapWithKey m f

foreign import _append :: forall a. (a -> a -> a) -> StrMap a -> StrMap a -> StrMap a

instance semigroupStrMap :: (Semigroup a) => Semigroup (StrMap a) where
  append m1 m2 = _append (<>) m1 m2

instance monoidStrMap :: (Semigroup a) => Monoid (StrMap a) where
  mempty = empty

foreign import _filterWithKey :: forall a. Fn2 (StrMap a) (String -> a -> Boolean) (StrMap a)

-- | Filter out those key/value pairs of a map for which a predicate
-- | fails to hold.
filterWithKey :: forall a. (String -> a -> Boolean) -> StrMap a -> StrMap a
filterWithKey predicate m = runFn2 _filterWithKey m predicate

-- | Filter out those key/value pairs of a map for which a predicate
-- | on the key fails to hold.
filterKeys :: (String -> Boolean) -> StrMap ~> StrMap
filterKeys predicate = filterWithKey $ const <<< predicate

-- | Filter out those key/value pairs of a map for which a predicate
-- | on the value fails to hold.
filter :: forall a. (a -> Boolean) -> StrMap a -> StrMap a
filter predicate = filterWithKey $ const predicate
