%  Copyright (C) 2003-2004 David Roundy
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
{-# LANGUAGE CPP, PatternGuards #-}

module Iolaus.Commands.Changes ( changes ) where

import Data.List ( nub, delete, (\\), intersect )
import Data.Maybe ( isJust, fromJust, catMaybes, maybeToList )

import Iolaus.Command ( Command(..), nodefaults )
import Iolaus.Arguments ( Flag(MaxC, Reverse, Graph), changes_format,
                          commit_format, max_count,
                          possibly_remote_repo_dir, working_repo_dir,
                          only_to_files,
                          match_several_or_range, all_interactive,
                          show_autogenerated )
import Iolaus.Sealed ( Sealed, unseal )
import Iolaus.Printer ( putDocLn )
import Iolaus.Colors ( Color, resetCode, colorCode, rainbow )

import Git.LocateRepo ( amInRepository )
import Git.Plumbing ( Hash, Commit, heads, RevListOption(MaxCount, TopoOrder) )
import Git.Helpers ( revListHeadsHashes, showCommit )
import Git.Dag ( cauterizeHeads, parents )

changes_description :: String
changes_description =
    "Gives a changelog-style summary of the repository history."

changes_help :: String
changes_help =
 "Changes gives a changelog-style summary of the repository history,\n"++
 "with options for altering how the patches are selected and displayed.\n"

changes :: Command
changes = Command {command_name = "changes",
                   command_help = changes_help,
                   command_description = changes_description,
                   command_extra_args = -1,
                   command_extra_arg_help = ["[FILE or DIRECTORY]..."],
                   command_get_arg_possibilities = return [],
                   command_command = changes_cmd,
                   command_prereq = amInRepository,
                   command_argdefaults = nodefaults,
                   command_advanced_options = [],
                   command_basic_options = [match_several_or_range,
                                            only_to_files]++changes_format++
                                           commit_format++
                                           [max_count,
                                            show_autogenerated,
                                            possibly_remote_repo_dir,
                                            working_repo_dir,
                                            all_interactive]}

changes_cmd :: [Flag] -> [String] -> IO ()
changes_cmd opts _ | Graph `elem` opts = heads >>= putGraph opts
changes_cmd opts _ =
    do cs <- revListHeadsHashes flags
       mapM_ (showC `unseal`) $ filt cs
    where flags = [MaxCount n | MaxC n <- opts]++[TopoOrder]
          showC c = do showCommit opts c >>= putDocLn
                       putStrLn ""
          filt = if Reverse `elem` opts then reverse else id

data Spot = AtHome { homeIs :: Maybe (Sealed (Hash Commit)),
                     overlapping :: [Sealed (Hash Commit)] }
          | Away { homeIs :: Maybe (Sealed (Hash Commit)),
                   overlapping :: [Sealed (Hash Commit)] }
            deriving ( Show )

data GraphState = GS { allSpots :: [Spot],
                       colors :: [(Sealed (Hash Commit), Color)] }
                  deriving ( Show )

delo :: Sealed (Hash Commit) -> Spot -> Spot
delo h s = s { overlapping = delete h $ overlapping s }
addo :: Sealed (Hash Commit) -> Spot -> Spot
addo h s | Just h == homeIs s = AtHome (Just h) (overlapping s)
         | otherwise = s { overlapping = h : delete h (overlapping s) }

evolveSpots :: [Spot] -> [Spot]
evolveSpots [] = []
evolveSpots [x] = [x]
evolveSpots (a:b)
    | Just h <- homeIs a,
      h `elem` overlapping a =
          evolveSpots (AtHome (homeIs a) (delete h $ overlapping a) : b)
evolveSpots (a:b:c)
    | [] <- overlapping a,
      o:_ <- overlapping b,
      Just o `notElem` map homeIs (b:c) = addo o a : evolveSpots (delo o b : c)
    | o:_ <- overlapping a,
      Just o `elem` map homeIs (b:c) = case evolveSpots (b:c) of
                                         b':c' -> delo o a : addo o b' : c'
                                         [] -> error "sagdsdg"
evolveSpots (a:c) = a : evolveSpots c

data G a = G (GraphState -> IO (GraphState, a))
instance Monad G where
    G a >>= f = G $ \s -> do (s',x) <- a s
                             case f x of
                               G b -> b s'
    G a >> G b = G $ \s -> do (s',_) <- a s
                              b s'
    fail e = G $ const $ fail e
    return a = G $ \s -> return (s,a)

runG :: G () -> IO ()
runG (G f) = do f (GS [] []); return ()

io :: IO a -> G a
io f = G $ \s -> do x <- f
                    return (s,x)

putGenS :: Maybe (Sealed (Hash Commit)) -> String
        -> GraphState -> IO (GraphState, ())
putGenS mn l s = do let newspots = evolveSpots (allSpots s)
                    putStrLn (mkpref (allSpots s) newspots++"  "++l)
                    --putStrLn $ "    mn is : "++show mn
                    --putStrLn $ "    lines are: "++unwords
                    --             (map (show  . homeIs) $ allSpots s)
                    --putStrLn $ "    spots are: "++show (allSpots s)
                    return (s { allSpots = newspots },())
    where draw h c = maybe [c] (\cc -> colorCode cc++c:resetCode) $
                     lookup h (colors s)
          mkpref (a : c ) (a' : c')
              | homeIs a == mn && isJust mn = draw (fromJust $ homeIs a) '*' ++
                                              betw (a:c) (a':c')
          mkpref (a@(AtHome (Just h)  _) : c )
                 (a'@(AtHome (Just h') _) : c')
              | h == h' = draw h '|' ++ betw (a:c) (a':c')
          mkpref (a : b : c )
                 (a'@(AtHome (Just h) _) : b': c') =
                 draw h '.' ++ betw (a:b:c) (a':b':c')
          mkpref (a : c )
                 (a' : c') =
                 case overlapping a `intersect` overlapping a' of
                   o:_ -> draw o 'I' ++ betw (a:c) (a':c')
                   [] -> ' ' : betw (a:c) (a':c')
          mkpref [] [] = ""
          mkpref _ _ = "XXX"
          betw (a : b : c )
               (a' : b': c')
              | Just h <- homeIs a',
                h `elem` overlapping b && h `notElem` overlapping b' =
                  draw h '/' ++ mkpref (b:c) (b':c')
              | Just h <- homeIs b',
                h `elem` overlapping a && h `notElem` overlapping a' =
                  draw (fromJust $ homeIs b') '\\' ++ mkpref (b:c) (b':c')
              | o:_ <- overlapping a `intersect` overlapping b' =
                    draw o '\\' ++ mkpref (b:c) (b':c')
              | o:_ <-  overlapping a' `intersect` overlapping b =
                    draw o '/' ++ mkpref (b:c) (b':c')
              | otherwise = ' ' : mkpref (b:c) (b':c')
          betw a a' = mkpref (drop 1 a) (drop 1 a')

putS :: String -> G ()
putS s | '\n' `elem` s = mapM_ putS $ lines s
putS l = G $ putGenS Nothing l

getParents :: G [Sealed (Hash Commit)]
getParents = G $ \s -> return (s, catMaybes $ map homeIs $ allSpots s)

node :: Sealed (Hash Commit) -> [Sealed (Hash Commit)] -> String -> G ()
node n ps name = G addit
    where addit s | not $ null $ concatMap overlapping $ allSpots s =
                      do (s',_) <- putGenS Nothing "" s
                         addit s'
          addit s = do let s0 = if Just n `elem` map homeIs (allSpots s)
                                then s
                                else s { allSpots = allSpots s ++
                                                    [Away (Just n) []] }
                       (s',_) <- putGenS (Just n) name s0
                       let oldps = catMaybes $ map homeIs $ allSpots s'
                           newps = nub (concatMap treeit $ oldps++[n]++ps)
                           treeit x | x == n = ps
                                    | otherwise = [x]
                           newspots = zipWith mixspot
                                      (map (maybeToList . homeIs) (allSpots s')++
                                       repeat [])
                                      (map Just newps++
                                       take (length oldps-length newps)
                                            (repeat Nothing))
                           mixspot :: [Sealed (Hash Commit)]
                                   -> Maybe (Sealed (Hash Commit))
                                   -> Spot
                           mixspot os (Just nn)
                               | nn `elem` os = AtHome (Just nn) (delete nn os)
                           mixspot os nn
                               | n `elem` os = mixspot (reverse ps++delete n os) nn
                           mixspot mo Nothing = Away Nothing mo
                           mixspot mo (Just nn) = Away (Just nn) mo
                           cs = filter ((`elem` newps) . fst) $ colors s'
                           unused = filter (`notElem` map snd cs) rainbow
                           choices =
                               case lookup n (colors s') of
                                 Just cn -> cn : delete cn unused
                                 Nothing -> unused
                           cs' = zip (newps \\ oldps) choices ++ cs
                       --putStrLn ("newterms are "++show newterms)
                       return (GS newspots cs',())


putGraph :: [Flag] -> [Sealed (Hash Commit)] -> IO ()
putGraph opts hs0 = runG $ putGr opts hs0

putGr :: [Flag] -> [Sealed (Hash Commit)] -> G ()
putGr opts hs0 =
    do ps <- getParents
       case cauterizeHeads (ps++hs0) of
         [] -> return ()
         h:xs -> do let hs = filter (`elem` hs0) xs
                    pict <- io $ showCommit opts `unseal` h
                    let n:body = lines $ show pict
                    node h (parents `unseal` h) n
                    mapM_ putS body
                    putGr opts hs
\end{code}

\subsection{iolaus changes}

\options{changes}

\haskell{changes_help}
