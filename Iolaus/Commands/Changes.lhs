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

import Iolaus.Command ( Command(..), nodefaults )
import Iolaus.Arguments ( Flag, changes_format, commit_format, max_count,
                          possibly_remote_repo_dir, working_repo_dir,
                          only_to_files,
                          match_several_or_range, all_interactive )
import Iolaus.Graph ( putGraph )

import Git.LocateRepo ( amInRepository )
import Git.Plumbing ( heads )

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
                                            possibly_remote_repo_dir,
                                            working_repo_dir,
                                            all_interactive]}

changes_cmd :: [Flag] -> [String] -> IO ()
changes_cmd opts _ = heads >>= putGraph opts (const True)
\end{code}
