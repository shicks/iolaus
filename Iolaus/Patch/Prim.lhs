%  Copyright (C) 2002-2003,2007 David Roundy
%
%  This program is free software; you can redistribute it and/or modify
%  it under the terms of the GNU General Public License as published by
%  the Free Software Foundation; either version 2, or (at your option)
%  any later version.
%
%  This program is distributed in the hope that it will be useful,
%  but WITHOUT ANY WARRANTY; without even the implied warranty of
%  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%  GNU General Public License for more details.
%
%  You should have received a copy of the GNU General Public License
%  along with this program; see the file COPYING.  If not, write to
%  the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
%  Boston, MA 02110-1301, USA.

\begin{code}
{-# OPTIONS_GHC -cpp -fglasgow-exts #-}
{-# LANGUAGE CPP #-}
-- , MagicHash, TypeOperators, GADTs, PatternGuards #-}

#include "gadts.h"

module Iolaus.Patch.Prim
       ( Prim(..), showPrim,
         DirPatchType(..), FilePatchType(..),
         CommuteFunction, Perhaps(..),
         is_identity,
         formatFileName,
         adddir, addfile,
         chunk, binary, move, rmdir, rmfile, chmod,
         is_addfile, is_chunk,
         is_adddir,
         canonize, try_to_shrink,
         subcommutes, sort_coalesceFL, join,
         splatter, splatterFL,
         try_shrinking_inverse,
         Effect(..)
       )
       where

import Control.Monad ( MonadPlus, msum, mzero, mplus )
#ifndef GADT_WITNESSES
import Data.Map ( elems, fromListWith, mapWithKey )
import Iolaus.Ordered ( mapFL )
#endif

import qualified Data.ByteString as B ( ByteString, concat )

import Iolaus.FileName ( FileName, fn2fp, fp2fn, norm_path,
                         movedirfilename, encode_white )
import Iolaus.RepoPath ( toFilePath )
import Iolaus.Ordered ( EqCheck(..), MyEq(..),
                       (:>)(..), (:\/:)(..), (:/\:)(..), FL(..), RL(..), (+>+),
                       concatFL, concatRL, mapFL_FL, mapRL_RL,
                       reverseFL, reverseRL, lengthFL, unsafeCoerceP )
import Iolaus.Patch.Patchy ( Invert(..), Commute(..) )
import Iolaus.Patch.Permutations () -- for Invert instance of FL
import Iolaus.Show
import Iolaus.Lcs2 ( nestedChanges )
import Iolaus.Colors ( colorOld, colorNew )
import Iolaus.Printer ( Doc, text, blueText, colorPS, ($$), (<+>), (<>) )
import Iolaus.IO ( ExecutableBit(IsExecutable, NotExecutable) )
#include "impossible.h"

data Prim C(x y) where
    Move :: !FileName -> !FileName -> Prim C(x y)
    DP :: !FileName -> !(DirPatchType C(x y)) -> Prim C(x y)
    FP :: !FileName -> !(FilePatchType C(x y)) -> Prim C(x y)
    Identity :: Prim C(x x)

data FilePatchType C(x y) = RmFile | AddFile
                          | Chmod ExecutableBit
                          | Chunk !B.ByteString !Int
                                  [B.ByteString] [B.ByteString]
                          | Binary B.ByteString B.ByteString
                            deriving (Eq,Ord)

data DirPatchType C(x y) = RmDir | AddDir
                           deriving (Eq,Ord)

instance MyEq FilePatchType where
    unsafeCompare a b = a == unsafeCoerceP b

instance MyEq DirPatchType where
    unsafeCompare a b = a == unsafeCoerceP b

is_identity :: Prim C(x y) -> EqCheck C(x y)
is_identity (FP _ (Chunk _ _ old new)) | old == new = unsafeCoerceP IsEq
is_identity (FP _ (Binary o n)) | o == n = unsafeCoerceP IsEq
is_identity (Move old new) | old == new = unsafeCoerceP IsEq
is_identity Identity = IsEq
is_identity _ = NotEq

is_addfile :: Prim C(x y) -> Bool
is_addfile (FP _ AddFile) = True
is_addfile _ = False

is_adddir :: Prim C(x y) -> Bool
is_adddir (DP _ AddDir) = True
is_adddir _ = False

is_chunk :: Prim C(x y) -> Bool
is_chunk (FP _ (Chunk _ _ _ _)) = True
is_chunk _ = False

addfile :: FilePath -> Prim C(x y)
rmfile :: FilePath -> Prim C(x y)
adddir :: FilePath -> Prim C(x y)
rmdir :: FilePath -> Prim C(x y)
move :: FilePath -> FilePath -> Prim C(x y)

addfile f = FP (n_fn f) AddFile
rmfile f = FP (n_fn f) RmFile
adddir d = DP (n_fn d) AddDir
rmdir d = DP (n_fn d) RmDir
move f f' = Move (n_fn f) (n_fn f')

chunk :: FilePath -> B.ByteString -> Int
      -> [B.ByteString] -> [B.ByteString] -> Prim C(x y)
chunk f c w o n = seq ccc (FP (n_fn f) ccc)
    where ccc = Chunk c w o n

binary :: FilePath -> B.ByteString -> B.ByteString -> Prim C(x y)
binary f o n = FP (n_fn f) (Binary o n)

chmod :: FilePath -> ExecutableBit -> Prim C(x y)
chmod f x = FP (n_fn f) (Chmod x)
\end{code}

\begin{code}
n_fn :: FilePath -> FileName
n_fn f = fp2fn $ "./"++(fn2fp $ norm_path $ fp2fn f)

instance Invert Prim where
    invert Identity = Identity
    invert (FP f RmFile)  = FP f AddFile
    invert (FP f AddFile)  = FP f RmFile
    invert (FP f (Chmod IsExecutable)) = FP f (Chmod NotExecutable)
    invert (FP f (Chmod NotExecutable)) = FP f (Chmod IsExecutable)
    invert (FP f (Chunk chs w old new))  = FP f $ Chunk chs w new old
    invert (FP f (Binary o n)) = FP f (Binary n o)
    invert (DP d RmDir) = DP d AddDir
    invert (DP d AddDir) = DP d RmDir
    invert (Move f f') = Move f' f
    identity = Identity
    sloppyIdentity Identity = IsEq
    sloppyIdentity _ = NotEq

\end{code}

\begin{code}
instance Show (Prim C(x y)) where
    showsPrec d (Move fn1 fn2) = showParen (d > app_prec) $ showString "Move " .
                                 showsPrec (app_prec + 1) fn1 . showString " " .
                                 showsPrec (app_prec + 1) fn2
    showsPrec d (DP fn dp) = showParen (d > app_prec) $ showString "DP " .
                             showsPrec (app_prec + 1) fn . showString " " .
                             showsPrec (app_prec + 1) dp
    showsPrec d (FP fn fp) = showParen (d > app_prec) $ showString "FP " .
                             showsPrec (app_prec + 1) fn . showString " " .
                             showsPrec (app_prec + 1) fp
    showsPrec _ Identity = showString "Identity"

instance Show2 Prim where
   showsPrec2 = showsPrec

instance Show (FilePatchType C(x y)) where
    showsPrec _ RmFile = showString "RmFile"
    showsPrec _ AddFile = showString "AddFile"
    showsPrec _ (Chmod IsExecutable) = showString "Chmod IsExecutable"
    showsPrec _ (Chmod NotExecutable) = showString "Chmod NotExecutable"
    showsPrec _ (Chunk _ _ _ _) = showString "Chunk not shown"
    showsPrec _ (Binary _ _) = showString "binary"

instance Show (DirPatchType C(x y)) where
    showsPrec _ RmDir = showString "RmDir"
    showsPrec _ AddDir = showString "AddDir"

formatFileName :: FileName -> Doc
formatFileName = blueText . encode_white . toFilePath

showPrim :: Prim C(a b) -> Doc
showPrim (FP f AddFile) = blueText "addfile" <+> formatFileName f
showPrim (FP f RmFile)  = blueText "rmfile" <+> formatFileName f
showPrim (FP f (Chmod IsExecutable)) = blueText "chmod +x" <+> formatFileName f
showPrim (FP f (Chmod NotExecutable)) = blueText "chmod -x" <+> formatFileName f
showPrim (FP f (Chunk _ word old new)) =
           blueText "chunk" <+> formatFileName f <+> text (show word) $$
              (colorPS colorOld $ B.concat old) <>
              (colorPS colorNew $ B.concat new)
showPrim (FP f (Binary _ _)) = blueText "binary" <+> formatFileName f
showPrim (DP d AddDir) = blueText "adddir" <+> formatFileName d
showPrim (DP d RmDir) = blueText "rmdir" <+> formatFileName d
showPrim (Move f f') =
    blueText "mv" <+> formatFileName f <+> formatFileName f'
showPrim Identity = blueText "{}"

try_to_shrink :: FL Prim C(x y) -> FL Prim C(x y)
try_to_shrink = mapPrimFL try_harder_to_shrink

mapPrimFL :: (FORALL(x y) FL Prim C(x y) -> FL Prim C(x y))
             -> FL Prim C(w z) -> FL Prim C(w z)
mapPrimFL f x =
#ifdef GADT_WITNESSES
                f x
#else 
-- an optimisation; break the list up into independent sublists
-- and apply f to each of them
     case mapM toSimple $ mapFL id x of
     Just sx -> foldr (+>+) NilFL $ elems $
                mapWithKey (\ k p -> f (fromSimples k (p NilFL))) $
                fromListWith (flip (.)) $
                map (\ (a,b) -> (a,(b:>:))) sx
     Nothing -> f x

data Simple C(x y) = SFP !(FilePatchType C(x y)) | SDP !(DirPatchType C(x y))
                   deriving ( Show )

toSimple :: Prim C(x y) -> Maybe (FileName, Simple C(x y))
toSimple (FP a b) = Just (a, SFP b)
toSimple (DP a AddDir) = Just (a, SDP AddDir)
toSimple (DP _ RmDir) = Nothing -- ordering is trickier with rmdir present
toSimple (Move _ _) = Nothing
toSimple Identity = Nothing

fromSimple :: FileName -> Simple C(x y) -> Prim C(x y)
fromSimple a (SFP b) = FP a b
fromSimple a (SDP b) = DP a b

fromSimples :: FileName -> FL Simple C(x y) -> FL Prim C(x y)
fromSimples a bs = mapFL_FL (fromSimple a) bs
#endif

try_harder_to_shrink :: FL Prim C(x y) -> FL Prim C(x y)
try_harder_to_shrink x = try_to_shrink2 $ maybe x id (try_shrinking_inverse x)

try_to_shrink2 :: FL Prim C(x y) -> FL Prim C(x y)
try_to_shrink2 psold =
    let ps = sort_coalesceFL psold
        ps_shrunk = shrink_a_bit ps
                    in
    if lengthFL ps_shrunk < lengthFL ps
    then try_to_shrink2 ps_shrunk
    else ps_shrunk

try_shrinking_inverse :: FL Prim C(x y) -> Maybe (FL Prim C(x y))
try_shrinking_inverse (x:>:y:>:z)
    | IsEq <- invert x =\/= y = Just z
    | otherwise = case try_shrinking_inverse (y:>:z) of
                  Nothing -> Nothing
                  Just yz' -> Just $ case try_shrinking_inverse (x:>:yz') of
                                     Nothing -> x:>:yz'
                                     Just xyz' -> xyz'
try_shrinking_inverse _ = Nothing

shrink_a_bit :: FL Prim C(x y) -> FL Prim C(x y)
shrink_a_bit NilFL = NilFL
shrink_a_bit (p:>:ps) =
    case try_one NilRL p ps of
    Nothing -> p :>: shrink_a_bit ps
    Just ps' -> ps'

try_one :: RL Prim C(w x) -> Prim C(x y) -> FL Prim C(y z)
        -> Maybe (FL Prim C(w z))
try_one _ _ NilFL = Nothing
try_one sofar p (p1:>:ps) =
    case join (p :> p1) of
    Just p' -> Just (reverseRL sofar +>+ p':>:NilFL +>+ ps)
    Nothing -> case commute (p :> p1) of
               Nothing -> Nothing
               Just (p1' :> p') -> try_one (p1':<:sofar) p' ps

-- | 'sort_coalesceFL' @ps@ joins as many patches in @ps@ as
--   possible, sorting the results according to the scheme defined
--   in 'comparePrim'
sort_coalesceFL :: FL Prim C(x y) -> FL Prim C(x y)
sort_coalesceFL = mapPrimFL sort_coalesceFL2

-- | The heart of "sort_coalesceFL"
sort_coalesceFL2 :: FL Prim C(x y) -> FL Prim C(x y)
sort_coalesceFL2 NilFL = NilFL
sort_coalesceFL2 (x:>:xs) | IsEq <- sloppyIdentity x = sort_coalesceFL2 xs
sort_coalesceFL2 (x:>:xs) | IsEq <- is_identity x = sort_coalesceFL2 xs
sort_coalesceFL2 (x:>:xs) = either id id $ push_coalesce_patch x $ sort_coalesceFL2 xs

-- | 'push_coalesce_patch' @new ps@ is almost like @new :>: ps@ except
--   as an alternative to consing, we first try to join @new@ with
--   the head of @ps@.  If this fails, we try again, using commutation
--   to push @new@ down the list until we find a place where either
--   (a) @new@ is @LT@ the next member of the list [see 'comparePrim']
--   (b) commutation fails or
--   (c) coalescing succeeds.
--   The basic principle is to join if we can and cons otherwise.
--
--   As an additional optimization, push_coalesce_patch outputs a Left
--   value if it wasn't able to shrink the patch sequence at all, and
--   a Right value if it was indeed able to shrink the patch sequence.
--   This avoids the O(N) calls to lengthFL that were in the older
--   code.
--
--   Also note that push_coalesce_patch is only ever used (and should
--   only ever be used) as an internal function in in
--   sort_coalesceFL2.
push_coalesce_patch :: Prim C(x y) -> FL Prim C(y z)
                    -> Either (FL Prim C(x z)) (FL Prim C(x z))
push_coalesce_patch new NilFL = Left (new:>:NilFL)
push_coalesce_patch new ps@(p:>:ps')
    = case join (new :> p) of
      Just new' | IsEq <- sloppyIdentity new' -> Right ps'
                | otherwise -> Right $ either id id $ push_coalesce_patch new' ps'
      Nothing -> if comparePrim new p == LT then Left (new:>:ps)
                            else case commute (new :> p) of
                                 Just (p' :> new') ->
                                     case push_coalesce_patch new' ps' of
                                     Right r -> Right $ either id id $
                                                push_coalesce_patch p' r
                                     Left r -> Left (p' :>: r)
                                 Nothing -> Left (new:>:ps)

is_in_directory :: FileName -> FileName -> Bool
is_in_directory d f = iid (fn2fp d) (fn2fp f)
    where iid (cd:cds) (cf:cfs)
              | cd /= cf = False
              | otherwise = iid cds cfs
          iid [] ('/':_) = True
          iid [] [] = True -- Count directory itself as being in directory...
          iid _ _ = False

data Perhaps a = Unknown | Failed | Succeeded a

instance  Monad Perhaps where
    (Succeeded x) >>= k =  k x
    Failed   >>= _      =  Failed
    Unknown  >>= _      =  Unknown
    Failed   >> _       =  Failed
    (Succeeded _) >> k  =  k
    Unknown  >> k       =  k
    return              =  Succeeded
    fail _              =  Unknown

instance  MonadPlus Perhaps where
    mzero                 = Unknown
    Unknown `mplus` ys    = ys
    Failed  `mplus` _     = Failed
    (Succeeded x) `mplus` _ = Succeeded x

toMaybe :: Perhaps a -> Maybe a
toMaybe (Succeeded x) = Just x
toMaybe _ = Nothing

toPerhaps :: Maybe a -> Perhaps a
toPerhaps (Just x) = Succeeded x
toPerhaps Nothing = Failed

clever_commute :: CommuteFunction -> CommuteFunction
clever_commute c (p2 :> p1) =
    case c (p2 :> p1) of
    Succeeded x -> Succeeded x
    Failed -> Failed
    Unknown -> case c (invert p1 :> invert p2) of
               Succeeded (p2' :> p1') -> Succeeded (invert p1' :> invert p2')
               Failed -> Failed
               Unknown -> Unknown
--clever_commute c (p1,p2) = c (p1,p2) `mplus`
--    (case c (invert p2,invert p1) of
--     Succeeded (p1', p2') -> Succeeded (invert p2', invert p1')
--     Failed -> Failed
--     Unknown -> Unknown)

speedy_commute :: CommuteFunction
speedy_commute (p2 :> p1) -- Deal with common case quickly!
    | p1_modifies /= Nothing && p2_modifies /= Nothing &&
      p1_modifies /= p2_modifies = Succeeded (unsafeCoerceP p1 :> unsafeCoerceP p2)
    | otherwise = Unknown
    where p1_modifies = is_filepatch p1
          p2_modifies = is_filepatch p2

everything_else_commute :: CommuteFunction
everything_else_commute x = eec x
    where
    eec :: CommuteFunction
    eec (p1 :> Identity) = Succeeded (Identity :> p1)
    eec (Identity :> p2) = Succeeded (p2 :> Identity)
    eec xx =
        msum [clever_commute commute_filedir xx]

instance Commute Prim where
    merge = elegant_merge
    commute x = toMaybe $ msum [speedy_commute x,
                                everything_else_commute x]
    -- Recurse on everything, these are potentially spoofed patches
    list_touched_files (Move f1 f2) = map toFilePath [f1, f2]
    list_touched_files (FP f _) = [toFilePath f]
    list_touched_files (DP d _) = [toFilePath d]
    list_touched_files Identity = []

is_filepatch :: Prim C(x y) -> Maybe FileName
is_filepatch (FP f _) = Just f
is_filepatch _ = Nothing
\end{code}

\begin{code}
is_superdir :: FileName -> FileName -> Bool
is_superdir d1 d2 = isd (fn2fp d1) (fn2fp d2)
    where isd s1 s2 =
              length s2 >= length s1 + 1 && take (length s1 + 1) s2 == s1 ++ "/"

commute_filedir :: CommuteFunction
commute_filedir (_ :> Move d d')
    | d `is_superdir` d' || d' `is_superdir` d
        = Failed -- nonsense, can't move dir to its subdirectory
commute_filedir (Move d d' :>_)
    | d `is_superdir` d' || d' `is_superdir` d
        = Failed -- nonsense, can't move dir to its subdirectory
commute_filedir (FP f2 p2 :> FP f1 p1) =
  if f1 /= f2 then Succeeded ( FP f1 (unsafeCoerceP p1) :> FP f2 (unsafeCoerceP p2) )
  else commuteFP f1 (p2 :> p1)
commute_filedir (DP d2 p2 :> DP d1 p1) =
  if (not $ is_in_directory d1 d2) && (not $ is_in_directory d2 d1) &&
     d1 /= d2
  then Succeeded ( DP d1 (unsafeCoerceP p1) :> DP d2 (unsafeCoerceP p2) )
  else Failed
commute_filedir (FP f fp :> DP d dp) =
    if not $ is_in_directory d f
    then Succeeded ( DP d (unsafeCoerceP dp) :> FP f (unsafeCoerceP fp) )
    else Failed
commute_filedir (FP f2 p2 :> Move d d')
    | d' `is_superdir` f2 = Failed -- nonsense
    | f2 == d' = Failed
    | (p2 == AddFile || p2 == RmFile) && d == f2 = Failed
    | otherwise = Succeeded (Move d d' :> FP (movedirfilename d d' f2) (unsafeCoerceP p2))
commute_filedir (DP d2 p2 :> Move d d')
    | d' `is_superdir` d2 = Failed -- nonsense
    | is_superdir d2 d' || is_superdir d2 d = Failed
    | {- (p2 == AddDir || p2 == RmDir) always true && -} d == d2 = Failed
    | d2 == d' = Failed
    | otherwise = Succeeded (Move d d' :> DP d2' (unsafeCoerceP p2))
    where d2' = movedirfilename d d' d2
commute_filedir (Move f f' :> Move d d')
    | d' `is_superdir` f' = Failed -- this is a nonsense case!
    | f `is_superdir` d = Failed -- this is another nonsense case!
    | f1' `is_superdir` d1' = Failed -- this is a nonsense case!
    | d1 `is_superdir` f1 = Failed -- this is another nonsense case!

    | d' `is_superdir` f = Failed -- yet another nonsense case...
    | f1' `is_superdir` d1 = Failed -- yet another nonsense case...
    | f `is_superdir` d' = Failed -- foobar nonsense case...
    | d1 `is_superdir` f1' = Failed -- foobar nonsense case...
    | f == d' || f' == d = Failed
    | f == d || f' == d' = Failed
    | d `is_superdir` f && f' `is_superdir` d' = Failed
    | f1 `is_superdir` d1 && d1' `is_superdir` f1' = Failed
    | otherwise = Succeeded (Move d1 d1' :> Move f1 f1')
    where d1 = movedirfilename f' f d
          d1' = movedirfilename f' f d'
          f1 = movedirfilename d d' f
          f1' = movedirfilename d d' f'

commute_filedir _ = Unknown

type CommuteFunction = FORALL(x y) (Prim :> Prim) C(x y)
                     -> Perhaps ((Prim :> Prim) C(x y))
subcommutes :: [(String, CommuteFunction)]
subcommutes =
    [("speedy_commute", speedy_commute),
     ("commute_filedir", clever_commute commute_filedir),
     ("commute_filepatches", clever_commute commute_filepatches),
     ("commute", toPerhaps . commute)
    ]

elegant_merge :: (Prim :\/: Prim) C(x y)
              -> Maybe ((Prim :/\: Prim) C(x y))
elegant_merge (p1 :\/: p2) =
    do p1':>ip2' <- commute (invert p2 :> p1)
       -- The following should be a redundant check
       p1o:>_ <- commute (p2 :> p1')
       IsEq <- return $ p1o =\/= p1
       return (invert ip2' :/\: p1')
\end{code}

It can sometimes be handy to have a canonical representation of a given
patch.  We achieve this by defining a canonical form for each patch type,
and a function ``{\tt canonize}'' which takes a patch and puts it into
canonical form.  This routine is used by the diff function to create an
optimal patch (based on an LCS algorithm) from a simple hunk describing the
old and new version of a file.
\begin{code}
canonize :: Prim C(x y) -> FL Prim C(x y)
canonize p | IsEq <- is_identity p = NilFL
canonize (FP f (Chunk c w old new)) = canonizeChunk f c w old new
canonize p = p :>: NilFL
\end{code}

A simpler, faster (and more generally useful) cousin of canonize is the
coalescing function.  This takes two sequential patches, and tries to turn
them into one patch.  This function is used to deal with ``split'' patches,
which are created when the commutation of a primitive patch can only be
represented by a composite patch.  In this case the resulting composite
patch must return to the original primitive patch when the commutation is
reversed, which a split patch accomplishes by trying to join its
contents each time it is commuted.

\begin{code}
-- | 'join' @p1 :> p2@ tries to combine @p1@ and @p2@ into a single
--   patch without intermediary changes.  For example, two hunk patches
--   modifying adjacent lines can be joined into a bigger hunk patch.
--   Or a patch which moves file A to file B can be joined with a
--   patch that moves file B into file C, yielding a patch that moves
--   file A to file C.
join :: (Prim :> Prim) C(x y) -> Maybe (Prim C(x y))
join (FP f2 _ :> FP f1 _) | f1 /= f2 = Nothing
join (p1 :> p2) | IsEq <- p2 =\/= invert p1 = Just Identity
join (FP _ p2 :> FP f1 p1) = coalesceFilePrim f1 (p2 :> p1) -- f1 = f2
join (Identity :> p) = Just p
join (p :> Identity) = Just p
join (Move b' a' :> Move a b) | a == a' = Just $ Move b' b
join (FP f AddFile :> Move a b) | f == a = Just $ FP b AddFile
join (DP f AddDir :> Move a b) | f == a = Just $ DP b AddDir
join (Move a b :> FP f RmFile) | b == f = Just $ FP a RmFile
join (Move a b :> DP f RmDir) | b == f = Just $ DP a RmDir
join _ = Nothing
\end{code}

\subsection{File patches}

A file patch is a patch which only modifies a single
file.  There are some rules which can be made about file patches in
general, which makes them a handy class.
For example, commutation of two filepatches is trivial if they modify
different files.  If they happen to
modify the same file, we'll have to check whether or not they commute.
\begin{code}
commute_filepatches :: CommuteFunction
commute_filepatches (FP f1 p1 :> FP f2 p2) | f1 == f2 = commuteFP f1 (p1 :> p2)
commute_filepatches _ = Unknown

commuteFP :: FileName -> (FilePatchType :> FilePatchType) C(x y)
          -> Perhaps ((Prim :> Prim) C(x y))
commuteFP _ (Chmod _ :> Chmod _) = Failed
commuteFP f (Chmod e :> x) = Succeeded (FP f (unsafeCoerceP x) :>
                                        FP f (Chmod e))
commuteFP f (x :> Chmod e) = Succeeded (FP f (Chmod e) :>
                                        FP f (unsafeCoerceP x))
commuteFP f (Chunk c w1 o1 n1 :> Chunk c2 w2 o2 n2)
    | c == c2 =
        toPerhaps $ commuteChunk f (Chunk c w1 o1 n1 :> Chunk c2 w2 o2 n2)
commuteFP _ (Binary _ _ :> _) = Failed
commuteFP _ (_ :> Binary _ _) = Failed
commuteFP _ _ = Unknown

splatterFL :: FL Prim C(x y) -> FL Prim C(x y)
splatterFL (a :>: b :>: c) = case splatter (a:>b) of
                               Just ab -> splatterFL (ab :>: c)
                               Nothing -> a :>: splatterFL (b:>:c)
splatterFL a = a

splatter :: (Prim :> Prim) C(x y) -> Maybe (Prim C(x y))
splatter (Identity :> a) = Just a
splatter (a :> Identity) = Just a
splatter (FP f (Chunk c1 w1 o1 n1) :> FP f' (Chunk c2 w2 o2 n2))
    | f /= f' = Nothing
    | c1 /= c2 = Nothing
    | (w2 >= w1 && w2 <= w1+ln1) || (w2 < w1 && w2 + lo2 >= w1) =
        Just $ FP f $ Chunk c1 (min w1 w2)
                               (take (w1-w2) o2++o1++drop (w1+ln1-w2) o2)
                               (take (w2-w1) n1++n2++drop (w2+lo2-w1) n1)
    | otherwise = Nothing
    where ln1 = length n1
          lo2 = length o2
splatter (FP f (Binary o n1) :> FP f' (Binary o1 n))
    | f == f' && n1 == o1 = Just (FP f (Binary o n))
splatter _ = Nothing


coalesceFilePrim :: FileName -> (FilePatchType :> FilePatchType) C(x y)
                  -> Maybe (Prim C(x y))
coalesceFilePrim f (Chunk c1 w1 o1 n1 :> Chunk c2 w2 o2 n2)
    | c1 == c2 = coalesceChunk f c1 w1 o1 n1 w2 o2 n2
coalesceFilePrim _ _ = Nothing

commuteChunk :: FileName -> (FilePatchType :> FilePatchType) C(x y)
             -> Maybe ((Prim :> Prim) C(x y))
commuteChunk f (Chunk c line1 old1 new1 :> Chunk _ line2 old2 new2)
  | seq f $ line1 + lengthnew1 < line2 =
      Just (FP f (Chunk c (line2 - lengthnew1 + lengthold1) old2 new2) :>
            FP f (Chunk c line1 old1 new1))
  | line2 + lengthold2 < line1 =
      Just (FP f (Chunk c line2 old2 new2) :>
            FP f (Chunk c (line1+ lengthnew2 - lengthold2) old1 new1))
  | line1 + lengthnew1 == line2 &&
    lengthold2 /= 0 && lengthold1 /= 0 && lengthnew2 /= 0 && lengthnew1 /= 0 =
      Just (FP f (Chunk c (line2 - lengthnew1 + lengthold1) old2 new2) :>
            FP f (Chunk c line1 old1 new1))
  | line2 + lengthold2 == line1 &&
    lengthold2 /= 0 && lengthold1 /= 0 && lengthnew2 /= 0 && lengthnew1 /= 0 =
      Just (FP f (Chunk c line2 old2 new2) :>
            FP f (Chunk c (line1 + lengthnew2 - lengthold2) old1 new1))
  | otherwise = Nothing
  where lengthnew1 = length new1
        lengthnew2 = length new2
        lengthold1 = length old1
        lengthold2 = length old2
commuteChunk _ _ = impossible

coalesceChunk :: FileName -> B.ByteString
             -> Int -> [B.ByteString] -> [B.ByteString]
             -> Int -> [B.ByteString] -> [B.ByteString]
             -> Maybe (Prim C(x y))
coalesceChunk f c line1 old1 new1 line2 old2 new2
    | line1 == line2 && lengthold1 < lengthnew2 =
        if take lengthold1 new2 /= old1
        then Nothing
        else case drop lengthold1 new2 of
        extranew -> Just (FP f (Chunk c line1 old2 (new1 ++ extranew)))
    | line1 == line2 && lengthold1 > lengthnew2 =
        if take lengthnew2 old1 /= new2
        then Nothing
        else case drop lengthnew2 old1 of
        extraold -> Just (FP f (Chunk c line1 (old2 ++ extraold) new1))
    | line1 == line2 = if new2 == old1 then Just (FP f (Chunk c line1 old2 new1))
                       else Nothing
    | line1 < line2 && lengthold1 >= line2 - line1 =
        case take (line2 - line1) old1 of
        extra-> coalesceChunk f c line1 old1 new1 line1 (extra ++ old2) (extra ++ new2)
    | line1 > line2 && lengthnew2 >= line1 - line2 =
        case take (line1 - line2) new2 of
        extra-> coalesceChunk f c line2 (extra ++ old1) (extra ++ new1) line2 old2 new2
    | otherwise = Nothing
    where lengthold1 = length old1
          lengthnew2 = length new2

canonizeChunk :: FileName -> B.ByteString -> Int
             -> [B.ByteString] -> [B.ByteString] -> FL Prim C(x y)
canonizeChunk f c w old new
    | null old || null new
        = FP f (Chunk c w old new) :>: NilFL
canonizeChunk f c w old new = make_chs $ nestedChanges old new
    where make_chs ((l,o,n):cs) = FP f (Chunk c (l+w) o n) :>: make_chs cs
          make_chs [] = unsafeCoerceP NilFL

instance MyEq Prim where
    unsafeCompare (Move a b) (Move c d) = a == c && b == d
    unsafeCompare (DP d1 p1) (DP d2 p2)
        = d1 == d2 && p1 `unsafeCompare` p2 
    unsafeCompare (FP f1 fp1) (FP f2 fp2)
        = f1 == f2 && fp1 `unsafeCompare` fp2
    unsafeCompare Identity Identity = True
    unsafeCompare _ _ = False

-- | 'comparePrim' @p1 p2@ is used to provide an arbitrary ordering between
--   @p1@ and @p2@.  Basically, identical patches are equal and
--   @Move < DP < FP < Identity@.
--   Everything else is compared in dictionary order of its arguments.
comparePrim :: Prim C(x y) -> Prim C(w z) -> Ordering
comparePrim (Move a b) (Move c d) = compare (a, b) (c, d)
comparePrim (Move _ _) _ = LT
comparePrim _ (Move _ _) = GT
comparePrim (DP d1 p1) (DP d2 p2) = compare (d1, p1) $ unsafeCoerceP (d2, p2)
comparePrim (DP _ _) _ = LT
comparePrim _ (DP _ _) = GT
comparePrim (FP f1 fp1) (FP f2 fp2) = compare (f1, fp1) $ unsafeCoerceP (f2, fp2)
comparePrim (FP _ _) _ = LT
comparePrim _ (FP _ _) = GT
comparePrim Identity Identity = EQ
\end{code}

\begin{code}

class Effect p where
    effect :: p C(x y) -> FL Prim C(x y)
    effect = reverseRL . effectRL
    effectRL :: p C(x y) -> RL Prim C(x y)
    effectRL = reverseFL . effect

instance Effect Prim where
    effect p | IsEq <- sloppyIdentity p = NilFL
             | otherwise = p :>: NilFL
    effectRL p | IsEq <- sloppyIdentity p = NilRL
               | otherwise = p :<: NilRL

instance Effect p => Effect (FL p) where
    effect p = concatFL $ mapFL_FL effect p
    effectRL p = concatRL $ mapRL_RL effectRL $ reverseFL p

instance Effect p => Effect (RL p) where
    effect p = concatFL $ mapFL_FL effect $ reverseRL p
    effectRL p = concatRL $ mapRL_RL effectRL p
\end{code}
