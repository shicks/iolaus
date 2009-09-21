-- Copyright (C) 2009 David Roundy
--
-- This program is free software; you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation; either version 2, or (at your option)
-- any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program; see the file COPYING.  If not, write to
-- the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
-- Boston, MA 02110-1301, USA.

{-# LANGUAGE CPP #-}

module Main (main) where

import System.IO ( hSetBinaryMode)
import System.IO ( stdin, stdout )
import System.Environment ( getArgs )
import Control.Exception ( Exception( AssertionFailed ), handleJust )

import Arcs.RunCommand ( run_the_command )
import Arcs.Flags ( ArcsFlag(Verbose) )
import Arcs.Help ( help_cmd, list_available_commands, print_version )
import Arcs.SignalHandler ( withSignalsHandled )
import Arcs.Global ( with_atexit )
#include "impossible.h"

assertions :: Control.Exception.Exception -> Maybe String
assertions (AssertionFailed s) = Just s
assertions _ = Nothing

main :: IO ()
main = with_atexit $ withSignalsHandled $
  handleJust assertions bug $ do
  argv <- getArgs
  case argv of
    -- User called "arcs" without arguments.
    []                  -> print_version >> help_cmd [] []
    -- User called "arcs --foo" for some special foo.
    ["-h"]              -> help_cmd [] []
    ["--help"]          -> help_cmd [] []
    ["--overview"]      -> help_cmd [Verbose] []
    ["--commands"]      -> list_available_commands
    ["-v"]              -> putStrLn "arcs"
    ["--version"]       -> putStrLn "arcs"
    ["--exact-version"] -> do
              putStrLn $ "arcs compiled on "++__DATE__++", at "++__TIME__
              putStrLn "context"
    -- User called a normal arcs command, "arcs foo [args]".
    _ -> do
      hSetBinaryMode stdin True
      hSetBinaryMode stdout True
      run_the_command (head argv) (tail argv)
{-

module Main where

import Control.Monad ( when )
import System.Environment ( getArgs )

import Git.Plumbing ( lsfiles, writetree, updateindex, updateref,
                      diffAllFiles, diffFiles,
                      commitTree, headhash )
import Git.Helpers ( testIndex )

import Arcs.RunCommand ()

commit :: String -> IO ()
commit message =
    do fs <- lsfiles
       updateindex fs
       testIndex
       t <- writetree
       putStrLn ("write-tree gives "++show t)
       par <- headhash
       com <- commitTree t [par] message
       putStrLn ("commit-tree gives "++ com)
       updateref "refs/heads/master" com

whatsnew :: [FilePath] -> IO ()
whatsnew [] = diffAllFiles >>= putStr
whatsnew fs = diffFiles fs >>= putStr

main :: IO ()
main = do x <- getArgs
          when ("wh" `elem` x) $ whatsnew $ filter (/= "wh") x
          when ("commit" `elem` x) $ commit $ unwords $
               filter (`notElem` ["commit","-m"]) x
          when ("add" `elem` x) $ updateindex $ filter (/= "add") x
-}
