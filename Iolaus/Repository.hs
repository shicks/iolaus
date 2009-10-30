--  Copyright (C) 2009 David Roundy
--
--  This program is free software; you can redistribute it and/or modify
--  it under the terms of the GNU General Public License as published by
--  the Free Software Foundation; either version 2, or (at your option)
--  any later version.
--
--  This program is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU General Public License for more details.
--
--  You should have received a copy of the GNU General Public License
--  along with this program; see the file COPYING.  If not, write to
--  the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
--  Boston, MA 02110-1301, USA.
{-# LANGUAGE CPP #-}
#include "gadts.h"

module Iolaus.Repository
    ( add_heads, decapitate, push_heads,
      get_unrecorded_changes, get_recorded_and_unrecorded,
      get_unrecorded, Unrecorded(..), slurp_recorded, slurp_working ) where

import Control.Monad ( zipWithM_ )
import System.Directory ( removeFile )

import Iolaus.Diff ( diff )
import Iolaus.Patch ( Prim )
import Iolaus.Flags ( Flag )
import Iolaus.Ordered ( FL, unsafeCoerceS )
import Iolaus.SlurpDirectory ( Slurpy )
import Iolaus.Sealed ( Sealed(..), mapSealM, unseal )

import Git.Plumbing ( Hash, Commit, emptyCommit, heads, headNames, remoteHeads,
                      writetree, updateindex, updateref, sendPack )
import Git.Helpers ( touchedFiles, slurpTree, mergeCommits )
import Git.Dag ( parents, cauterizeHeads )

slurp_recorded :: [Flag] -> IO (Slurpy C(RecordedState))
slurp_recorded opts = do Sealed r <- heads >>= mergeCommits opts
                         slurpTree $ unsafeCoerceS r

slurp_working :: IO (Sealed Slurpy)
slurp_working =
    do touchedFiles >>= updateindex
       writetree >>= mapSealM slurpTree

data RecordedState = RecordedState

data Unrecorded =
    FORALL(x) Unrecorded (FL Prim C(RecordedState x)) (Slurpy C(x))

get_unrecorded :: [Flag] -> IO Unrecorded
get_unrecorded opts =
    do Sealed new <- slurp_working
       old <- slurp_recorded opts
       return $ Unrecorded (diff [] old new) new

get_recorded_and_unrecorded :: [Flag]
                            -> IO (Slurpy C(RecordedState), Unrecorded)
get_recorded_and_unrecorded opts =
    do Sealed new <- slurp_working
       old <- slurp_recorded opts
       return (old, Unrecorded (diff [] old new) new)

get_unrecorded_changes :: [Flag] -> IO (Sealed (FL Prim C(RecordedState)))
get_unrecorded_changes opts =
    do Sealed new <- slurp_working
       old <- slurp_recorded opts
       return $ Sealed $ diff [] old new

add_heads :: [Flag] -> [Sealed (Hash Commit)] -> IO ()
add_heads _ h =
    do hs <- heads
       case cauterizeHeads (h++hs) of
         hs' -> do zipWithM_ (\mm (Sealed hh) -> updateref mm hh) masters hs'
                   cleanup_all_but hs'

decapitate :: [Flag] -> [Sealed (Hash Commit)] -> IO ()
decapitate _ xs =
    do hs <- heads
       let pars = concatMap (unseal parents) xs
       case cauterizeHeads (filter (`notElem` xs) (hs++pars)) of
         hs' -> do zipWithM_ (\mm (Sealed hh) -> updateref mm hh) masters hs'
                   cleanup_all_but hs'

cleanup_all_but :: [Sealed (Hash Commit)] -> IO ()
cleanup_all_but hs =
    do hns <- headNames
       let rmhead x = removeFile (".git/"++x)
       mapM_ rmhead $ map snd $ filter ((`notElem` hs) . fst) hns

push_heads :: String -> [Sealed (Hash Commit)] -> IO ()
push_heads repo cs =
    do hs <- remoteHeads repo
       let newhs = cauterizeHeads (hs++cs)
           empties = take (length hs - length newhs) $
                     repeat $ Sealed emptyCommit
       sendPack repo (zip (newhs++empties) masters)

masters :: [String]
masters = "refs/heads/master" :
          map (\n -> "refs/heads/master"++show n) [1 :: Int ..]